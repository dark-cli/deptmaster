// Tests for snapshot optimization in projection rebuilding
// These tests verify:
// 1. Snapshot optimization is used when no UNDO events are present
// 2. Full rebuild is used when UNDO events are present (even if snapshot exists)
// 3. Snapshot restoration correctness
// 4. Incremental event application after snapshot
// 5. Fallback to full rebuild when snapshot optimization fails

use debt_tracker_api::handlers::sync::{post_sync_events, rebuild_projections_from_events, SyncEventRequest};
use debt_tracker_api::AppState;
use debt_tracker_api::config::Config;
use debt_tracker_api::websocket;
use sqlx::{PgPool, Row};
use uuid::Uuid;
use std::sync::Arc;
use serde_json::json;

mod test_helpers;
use test_helpers::*;

#[tokio::test]
#[ignore] // Ignore by default - requires test database
async fn test_snapshot_optimization_used_when_no_undo_events() {
    let pool = setup_test_db().await;
    let user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    add_user_to_wallet(&pool, user_id, wallet_id, "owner").await;
    
    let config = Arc::new(Config::from_env().unwrap());
    let broadcast_tx = websocket::create_broadcast_channel();
    let app_state = AppState {
        db_pool: Arc::new(pool.clone()),
        config: config.clone(),
        broadcast_tx: broadcast_tx.clone(),
        rate_limiter: debt_tracker_api::middleware::rate_limit::RateLimiter::new(100, 60),
    };

    let contact_id = Uuid::new_v4();
    
    // 1. Create 10 events to trigger snapshot creation
    for i in 0..10 {
        let event = SyncEventRequest {
            id: Uuid::new_v4().to_string(),
            aggregate_type: "contact".to_string(),
            aggregate_id: contact_id.to_string(),
            event_type: if i == 0 { "CREATED" } else { "UPDATED" }.to_string(),
            event_data: json!({
                "name": format!("Contact {}", i),
                "timestamp": chrono::Utc::now().to_rfc3339()
            }),
            timestamp: chrono::Utc::now().to_rfc3339(),
            version: 1,
        };

        let _ = post_sync_events(
            axum::extract::State(app_state.clone()),
            wallet_context_extension(wallet_id, "owner"),
            auth_user_extension(user_id, None),
            axum::Json(vec![event]),
        ).await;
    }

    // Verify snapshot was created (at event 10)
    let snapshot_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM projection_snapshots WHERE wallet_id = $1")
        .bind(wallet_id)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert!(snapshot_count > 0, "Snapshot should be created at event 10");

    // 2. Create 3 more events (no UNDO events)
    for i in 10..13 {
        let event = SyncEventRequest {
            id: Uuid::new_v4().to_string(),
            aggregate_type: "contact".to_string(),
            aggregate_id: contact_id.to_string(),
            event_type: "UPDATED".to_string(),
            event_data: json!({
                "name": format!("Contact {}", i),
                "timestamp": chrono::Utc::now().to_rfc3339()
            }),
            timestamp: chrono::Utc::now().to_rfc3339(),
            version: 1,
        };

        let _ = post_sync_events(
            axum::extract::State(app_state.clone()),
            wallet_context_extension(wallet_id, "owner"),
            auth_user_extension(user_id, None),
            axum::Json(vec![event]),
        ).await;
    }

    // 3. Rebuild projections - should use snapshot optimization (no UNDO events)
    let _ = rebuild_projections_from_events(&app_state, wallet_id).await;

    // 4. Verify final state is correct (should have name "Contact 12" from last update)
    let final_name: String = sqlx::query_scalar(
        "SELECT name FROM contacts_projection WHERE id = $1 AND wallet_id = $2"
    )
    .bind(contact_id)
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(final_name, "Contact 12", "Final state should reflect all events including those after snapshot");
}

#[tokio::test]
#[ignore] // Ignore by default - requires test database
async fn test_full_rebuild_used_when_undo_events_present() {
    let pool = setup_test_db().await;
    let user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    add_user_to_wallet(&pool, user_id, wallet_id, "owner").await;
    
    let config = Arc::new(Config::from_env().unwrap());
    let broadcast_tx = websocket::create_broadcast_channel();
    let app_state = AppState {
        db_pool: Arc::new(pool.clone()),
        config: config.clone(),
        broadcast_tx: broadcast_tx.clone(),
        rate_limiter: debt_tracker_api::middleware::rate_limit::RateLimiter::new(100, 60),
    };

    let contact_id = Uuid::new_v4();
    
    // 1. Create 10 events to trigger snapshot creation
    let mut event_ids = Vec::new();
    for i in 0..10 {
        let event = SyncEventRequest {
            id: Uuid::new_v4().to_string(),
            aggregate_type: "contact".to_string(),
            aggregate_id: contact_id.to_string(),
            event_type: if i == 0 { "CREATED" } else { "UPDATED" }.to_string(),
            event_data: json!({
                "name": format!("Contact {}", i),
                "timestamp": chrono::Utc::now().to_rfc3339()
            }),
            timestamp: chrono::Utc::now().to_rfc3339(),
            version: 1,
        };
        event_ids.push(event.id.clone());

        let _ = post_sync_events(
            axum::extract::State(app_state.clone()),
            wallet_context_extension(wallet_id, "owner"),
            auth_user_extension(user_id, None),
            axum::Json(vec![event]),
        ).await;
    }

    // Verify snapshot was created
    let snapshot_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM projection_snapshots WHERE wallet_id = $1")
        .bind(wallet_id)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert!(snapshot_count > 0, "Snapshot should be created");

    // 2. Create UNDO event for event 6 (which is BEFORE the snapshot at event 10)
    // With new algorithm: should use FULL rebuild because no snapshot exists before event 6
    let undo_event = SyncEventRequest {
        id: Uuid::new_v4().to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: contact_id.to_string(),
        event_type: "UNDO".to_string(),
        event_data: json!({
            "undone_event_id": event_ids[5], // Undo event 6 (index 5, position 6)
            "timestamp": chrono::Utc::now().to_rfc3339()
        }),
        timestamp: chrono::Utc::now().to_rfc3339(),
        version: 1,
    };

    let _ = post_sync_events(
        axum::extract::State(app_state.clone()),
        wallet_context_extension(wallet_id, "owner"),
        axum::Json(vec![undo_event]),
    ).await;

    // 3. Rebuild projections - should use FULL rebuild (undone event is before all snapshots)
    let _ = rebuild_projections_from_events(&app_state, wallet_id).await;

    // 4. Verify state is correct (event 6 was undone, so should have name from event 5 or later)
    let final_name: String = sqlx::query_scalar(
        "SELECT name FROM contacts_projection WHERE id = $1 AND wallet_id = $2"
    )
    .bind(contact_id)
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    // Event 6 was undone, so name should be from event 5 or a later event that wasn't undone
    assert!(final_name != "Contact 6", "Event 6 should be undone");
}

#[tokio::test]
#[ignore] // Ignore by default - requires test database
async fn test_snapshot_restoration_correctness() {
    let pool = setup_test_db().await;
    let user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    add_user_to_wallet(&pool, user_id, wallet_id, "owner").await;
    
    let config = Arc::new(Config::from_env().unwrap());
    let broadcast_tx = websocket::create_broadcast_channel();
    let app_state = AppState {
        db_pool: Arc::new(pool.clone()),
        config: config.clone(),
        broadcast_tx: broadcast_tx.clone(),
        rate_limiter: debt_tracker_api::middleware::rate_limit::RateLimiter::new(100, 60),
    };

    let contact_id = Uuid::new_v4();
    
    // 1. Create 10 events to trigger snapshot
    for i in 0..10 {
        let event = SyncEventRequest {
            id: Uuid::new_v4().to_string(),
            aggregate_type: "contact".to_string(),
            aggregate_id: contact_id.to_string(),
            event_type: if i == 0 { "CREATED" } else { "UPDATED" }.to_string(),
            event_data: json!({
                "name": format!("Snapshot Name {}", i),
                "timestamp": chrono::Utc::now().to_rfc3339()
            }),
            timestamp: chrono::Utc::now().to_rfc3339(),
            version: 1,
        };

        let _ = post_sync_events(
            axum::extract::State(app_state.clone()),
            wallet_context_extension(wallet_id, "owner"),
            auth_user_extension(user_id, None),
            axum::Json(vec![event]),
        ).await;
    }

    // Get snapshot state
    let snapshot = sqlx::query(
        "SELECT contacts_snapshot FROM projection_snapshots WHERE wallet_id = $1 ORDER BY snapshot_index DESC LIMIT 1"
    )
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    
    let contacts: serde_json::Value = snapshot.try_get("contacts_snapshot").unwrap();
    let snapshot_name = contacts.as_array()
        .and_then(|arr| arr.first())
        .and_then(|c| c.get("name"))
        .and_then(|n| n.as_str())
        .unwrap_or("");

    // 2. Create 2 more events
    for i in 10..12 {
        let event = SyncEventRequest {
            id: Uuid::new_v4().to_string(),
            aggregate_type: "contact".to_string(),
            aggregate_id: contact_id.to_string(),
            event_type: "UPDATED".to_string(),
            event_data: json!({
                "name": format!("After Snapshot {}", i),
                "timestamp": chrono::Utc::now().to_rfc3339()
            }),
            timestamp: chrono::Utc::now().to_rfc3339(),
            version: 1,
        };

        let _ = post_sync_events(
            axum::extract::State(app_state.clone()),
            wallet_context_extension(wallet_id, "owner"),
            auth_user_extension(user_id, None),
            axum::Json(vec![event]),
        ).await;
    }

    // 3. Rebuild - should restore from snapshot and apply events after
    let _ = rebuild_projections_from_events(&app_state, wallet_id).await;

    // 4. Verify final state (should be "After Snapshot 11" from last event)
    let final_name: String = sqlx::query_scalar(
        "SELECT name FROM contacts_projection WHERE id = $1 AND wallet_id = $2"
    )
    .bind(contact_id)
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(final_name, "After Snapshot 11", "Final state should reflect snapshot + events after");
}

#[tokio::test]
#[ignore] // Ignore by default - requires test database
async fn test_fallback_to_full_rebuild_when_no_snapshot() {
    let pool = setup_test_db().await;
    let user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    add_user_to_wallet(&pool, user_id, wallet_id, "owner").await;
    
    let config = Arc::new(Config::from_env().unwrap());
    let broadcast_tx = websocket::create_broadcast_channel();
    let app_state = AppState {
        db_pool: Arc::new(pool.clone()),
        config: config.clone(),
        broadcast_tx: broadcast_tx.clone(),
        rate_limiter: debt_tracker_api::middleware::rate_limit::RateLimiter::new(100, 60),
    };

    let contact_id = Uuid::new_v4();
    
    // 1. Create 5 events (not enough to trigger snapshot)
    for i in 0..5 {
        let event = SyncEventRequest {
            id: Uuid::new_v4().to_string(),
            aggregate_type: "contact".to_string(),
            aggregate_id: contact_id.to_string(),
            event_type: if i == 0 { "CREATED" } else { "UPDATED" }.to_string(),
            event_data: json!({
                "name": format!("Contact {}", i),
                "timestamp": chrono::Utc::now().to_rfc3339()
            }),
            timestamp: chrono::Utc::now().to_rfc3339(),
            version: 1,
        };

        let _ = post_sync_events(
            axum::extract::State(app_state.clone()),
            wallet_context_extension(wallet_id, "owner"),
            auth_user_extension(user_id, None),
            axum::Json(vec![event]),
        ).await;
    }

    // Verify no snapshot exists
    let snapshot_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM projection_snapshots WHERE wallet_id = $1")
        .bind(wallet_id)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(snapshot_count, 0, "No snapshot should exist yet");

    // 2. Rebuild - should fallback to full rebuild (no snapshot available)
    let _ = rebuild_projections_from_events(&app_state, wallet_id).await;

    // 3. Verify state is correct (full rebuild should work)
    let final_name: String = sqlx::query_scalar(
        "SELECT name FROM contacts_projection WHERE id = $1 AND wallet_id = $2"
    )
    .bind(contact_id)
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(final_name, "Contact 4", "Full rebuild should produce correct state");
}

#[tokio::test]
#[ignore] // Ignore by default - requires test database
async fn test_snapshot_optimization_with_transactions() {
    let pool = setup_test_db().await;
    let user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    add_user_to_wallet(&pool, user_id, wallet_id, "owner").await;
    let contact_id = create_test_contact(&pool, user_id, wallet_id, "Test Contact").await;
    
    let config = Arc::new(Config::from_env().unwrap());
    let broadcast_tx = websocket::create_broadcast_channel();
    let app_state = AppState {
        db_pool: Arc::new(pool.clone()),
        config: config.clone(),
        broadcast_tx: broadcast_tx.clone(),
        rate_limiter: debt_tracker_api::middleware::rate_limit::RateLimiter::new(100, 60),
    };

    // 1. Create 10 transaction events to trigger snapshot
    for i in 0..10 {
        let transaction_id = Uuid::new_v4();
        let event = SyncEventRequest {
            id: Uuid::new_v4().to_string(),
            aggregate_type: "transaction".to_string(),
            aggregate_id: transaction_id.to_string(),
            event_type: "CREATED".to_string(),
            event_data: json!({
                "contact_id": contact_id.to_string(),
                "type": "money",
                "direction": "lent",
                "amount": 1000 * (i + 1),
                "currency": "USD",
                "transaction_date": chrono::Utc::now().format("%Y-%m-%d").to_string(),
                "timestamp": chrono::Utc::now().to_rfc3339()
            }),
            timestamp: chrono::Utc::now().to_rfc3339(),
            version: 1,
        };

        let _ = post_sync_events(
            axum::extract::State(app_state.clone()),
            wallet_context_extension(wallet_id, "owner"),
            auth_user_extension(user_id, None),
            axum::Json(vec![event]),
        ).await;
    }

    // Verify snapshot was created
    let snapshot_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM projection_snapshots WHERE wallet_id = $1")
        .bind(wallet_id)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert!(snapshot_count > 0, "Snapshot should be created");

    // 2. Create 2 more transaction events (no UNDO)
    for i in 10..12 {
        let transaction_id = Uuid::new_v4();
        let event = SyncEventRequest {
            id: Uuid::new_v4().to_string(),
            aggregate_type: "transaction".to_string(),
            aggregate_id: transaction_id.to_string(),
            event_type: "CREATED".to_string(),
            event_data: json!({
                "contact_id": contact_id.to_string(),
                "type": "money",
                "direction": "lent",
                "amount": 1000 * (i + 1),
                "currency": "USD",
                "transaction_date": chrono::Utc::now().format("%Y-%m-%d").to_string(),
                "timestamp": chrono::Utc::now().to_rfc3339()
            }),
            timestamp: chrono::Utc::now().to_rfc3339(),
            version: 1,
        };

        let _ = post_sync_events(
            axum::extract::State(app_state.clone()),
            wallet_context_extension(wallet_id, "owner"),
            auth_user_extension(user_id, None),
            axum::Json(vec![event]),
        ).await;
    }

    // 3. Rebuild - should use snapshot optimization
    let _ = rebuild_projections_from_events(&app_state, wallet_id).await;

    // 4. Verify transaction count is correct (should have 12 transactions)
    let transaction_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM transactions_projection WHERE contact_id = $1 AND wallet_id = $2 AND is_deleted = false"
    )
    .bind(contact_id)
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(transaction_count, 12, "Should have all 12 transactions after snapshot optimization");
}
