// Tests for snapshot optimization in projection rebuilding
// These tests verify:
// 1. Snapshot optimization is used when no UNDO events are present
// 2. Full rebuild is used when UNDO events are present (even if snapshot exists)
// 3. Snapshot restoration correctness
// 4. Incremental event application after snapshot
// 5. Fallback to full rebuild when snapshot optimization fails

use debt_tracker_api::config::Config;
use debt_tracker_api::domain::DomainEvent;
use debt_tracker_api::handlers::sync::{post_sync_events, SyncEventRequest};
use debt_tracker_api::permissions::WalletRole;
use debt_tracker_api::services::projections::Projections;
use debt_tracker_api::websocket;
use debt_tracker_api::AppState;
use serde_json::json;
use sqlx::{PgPool, Row};
use std::sync::Arc;
use uuid::Uuid;

mod test_helpers;
use test_helpers::*;

#[tokio::test]
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
            wallet_context_extension(wallet_id, WalletRole::Owner),
            auth_user_extension(user_id, None),
            axum::Json(sync_requests_to_domain_events(
                vec![event],
                wallet_id,
                user_id,
            )),
        )
        .await;
    }

    // Verify snapshot was created (at event 10)
    let snapshot_count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM projection_snapshots WHERE wallet_id = $1")
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
            wallet_context_extension(wallet_id, WalletRole::Owner),
            auth_user_extension(user_id, None),
            axum::Json(sync_requests_to_domain_events(
                vec![event],
                wallet_id,
                user_id,
            )),
        )
        .await;
    }

    // Check state before rebuild
    let name_before: String =
        sqlx::query_scalar("SELECT name FROM contacts_projection WHERE id = $1 AND wallet_id = $2")
            .bind(contact_id)
            .bind(wallet_id)
            .fetch_one(&pool)
            .await
            .unwrap();
    println!("Name before rebuild: {}", name_before);

    // Check event count
    let event_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM events WHERE wallet_id = $1")
        .bind(wallet_id)
        .fetch_one(&pool)
        .await
        .unwrap();
    println!("Event count: {}", event_count);

    // 3. Rebuild projections - should use snapshot optimization (no UNDO events)
    let _ = Projections::rebuild_projections_from_events(&app_state, wallet_id).await;

    // 4. Verify final state is correct (should have name "Contact 12" from last update)
    let final_name: String =
        sqlx::query_scalar("SELECT name FROM contacts_projection WHERE id = $1 AND wallet_id = $2")
            .bind(contact_id)
            .bind(wallet_id)
            .fetch_one(&pool)
            .await
            .unwrap();
    println!("Name after rebuild: {}", final_name);
    assert_eq!(
        final_name, "Contact 12",
        "Final state should reflect all events including those after snapshot"
    );
}

#[tokio::test]
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
            wallet_context_extension(wallet_id, WalletRole::Owner),
            auth_user_extension(user_id, None),
            axum::Json(sync_requests_to_domain_events(
                vec![event],
                wallet_id,
                user_id,
            )),
        )
        .await;
    }

    // Verify snapshot was created
    let snapshot_count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM projection_snapshots WHERE wallet_id = $1")
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
        wallet_context_extension(wallet_id, WalletRole::Owner),
        auth_user_extension(user_id, None),
        axum::Json(sync_requests_to_domain_events(
            vec![undo_event],
            wallet_id,
            user_id,
        )),
    )
    .await;

    // 3. Rebuild projections - should use FULL rebuild (undone event is before all snapshots)
    let _ = Projections::rebuild_projections_from_events(&app_state, wallet_id).await;

    // 4. Verify state is correct (event 6 was undone, so should have name from event 5 or later)
    let final_name: String =
        sqlx::query_scalar("SELECT name FROM contacts_projection WHERE id = $1 AND wallet_id = $2")
            .bind(contact_id)
            .bind(wallet_id)
            .fetch_one(&pool)
            .await
            .unwrap();
    // Event 6 was undone, so name should be from event 5 or a later event that wasn't undone
    assert!(final_name != "Contact 6", "Event 6 should be undone");
}

#[tokio::test]
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
            wallet_context_extension(wallet_id, WalletRole::Owner),
            auth_user_extension(user_id, None),
            axum::Json(sync_requests_to_domain_events(
                vec![event],
                wallet_id,
                user_id,
            )),
        )
        .await;
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
    let snapshot_name = contacts
        .as_array()
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
            wallet_context_extension(wallet_id, WalletRole::Owner),
            auth_user_extension(user_id, None),
            axum::Json(sync_requests_to_domain_events(
                vec![event],
                wallet_id,
                user_id,
            )),
        )
        .await;
    }

    // 3. Rebuild - should restore from snapshot and apply events after
    let _ = Projections::rebuild_projections_from_events(&app_state, wallet_id).await;

    // 4. Verify final state (should be "After Snapshot 11" from last event)
    let final_name: String =
        sqlx::query_scalar("SELECT name FROM contacts_projection WHERE id = $1 AND wallet_id = $2")
            .bind(contact_id)
            .bind(wallet_id)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(
        final_name, "After Snapshot 11",
        "Final state should reflect snapshot + events after"
    );
}

#[tokio::test]
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
            wallet_context_extension(wallet_id, WalletRole::Owner),
            auth_user_extension(user_id, None),
            axum::Json(sync_requests_to_domain_events(
                vec![event],
                wallet_id,
                user_id,
            )),
        )
        .await;
    }

    // Verify no snapshot exists
    let snapshot_count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM projection_snapshots WHERE wallet_id = $1")
            .bind(wallet_id)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(snapshot_count, 0, "No snapshot should exist yet");

    // 2. Rebuild - should fallback to full rebuild (no snapshot available)
    let _ = Projections::rebuild_projections_from_events(&app_state, wallet_id).await;

    // 3. Verify state is correct (full rebuild should work)
    let final_name: String =
        sqlx::query_scalar("SELECT name FROM contacts_projection WHERE id = $1 AND wallet_id = $2")
            .bind(contact_id)
            .bind(wallet_id)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(
        final_name, "Contact 4",
        "Full rebuild should produce correct state"
    );
}

#[tokio::test]
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
            wallet_context_extension(wallet_id, WalletRole::Owner),
            auth_user_extension(user_id, None),
            axum::Json(sync_requests_to_domain_events(
                vec![event],
                wallet_id,
                user_id,
            )),
        )
        .await;
    }

    // Verify snapshot was created
    let snapshot_count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM projection_snapshots WHERE wallet_id = $1")
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
            wallet_context_extension(wallet_id, WalletRole::Owner),
            auth_user_extension(user_id, None),
            axum::Json(sync_requests_to_domain_events(
                vec![event],
                wallet_id,
                user_id,
            )),
        )
        .await;
    }

    // 3. Rebuild - should use snapshot optimization
    let _ = Projections::rebuild_projections_from_events(&app_state, wallet_id).await;

    // 4. Verify transaction count is correct (should have 12 transactions)
    let transaction_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM transactions_projection WHERE contact_id = $1 AND wallet_id = $2 AND is_deleted = false"
    )
    .bind(contact_id)
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        transaction_count, 12,
        "Should have all 12 transactions after snapshot optimization"
    );
}

// Phase 2 Batch Processing Tests
// These tests verify that the batch processing optimization correctly handles
// large wallets by processing events in configurable batch sizes

#[tokio::test]
async fn test_batch_processing_with_small_batch_size() {
    let pool = setup_test_db().await;
    let user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    add_user_to_wallet(&pool, user_id, wallet_id, "owner").await;

    // Create config with small batch size (5 events per batch)
    let mut config = Config::from_env().unwrap();
    config.event_rebuild_batch_size = 5;
    let config = Arc::new(config);

    let broadcast_tx = websocket::create_broadcast_channel();
    let app_state = AppState {
        db_pool: Arc::new(pool.clone()),
        config: config.clone(),
        broadcast_tx: broadcast_tx.clone(),
        rate_limiter: debt_tracker_api::middleware::rate_limit::RateLimiter::new(100, 60),
    };

    let contact_id = Uuid::new_v4();

    // Create 15 events (3 batches of 5 each with batch size 5)
    for i in 0..15 {
        let event = SyncEventRequest {
            id: Uuid::new_v4().to_string(),
            aggregate_type: "contact".to_string(),
            aggregate_id: contact_id.to_string(),
            event_type: if i == 0 { "CREATED" } else { "UPDATED" }.to_string(),
            event_data: json!({
                "name": format!("Batch Contact {}", i),
                "timestamp": chrono::Utc::now().to_rfc3339()
            }),
            timestamp: chrono::Utc::now().to_rfc3339(),
            version: 1,
        };

        let _ = post_sync_events(
            axum::extract::State(app_state.clone()),
            wallet_context_extension(wallet_id, WalletRole::Owner),
            auth_user_extension(user_id, None),
            axum::Json(sync_requests_to_domain_events(
                vec![event],
                wallet_id,
                user_id,
            )),
        )
        .await;
    }

    // Verify all 15 events were created
    let event_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM events WHERE wallet_id = $1")
        .bind(wallet_id)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(event_count, 15, "Should have 15 events");

    // Clear projections to force full rebuild with batch processing
    sqlx::query("DELETE FROM transactions_projection WHERE wallet_id = $1")
        .bind(wallet_id)
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query("DELETE FROM contacts_projection WHERE wallet_id = $1")
        .bind(wallet_id)
        .execute(&pool)
        .await
        .unwrap();

    // Rebuild - should use batch processing (no snapshots, batch size 5)
    let rebuild_result = Projections::rebuild_projections_from_events(&app_state, wallet_id).await;
    assert!(
        rebuild_result.is_ok(),
        "Rebuild should succeed with batch processing"
    );

    // Verify final state is correct (should have last contact name)
    let final_name: String =
        sqlx::query_scalar("SELECT name FROM contacts_projection WHERE id = $1 AND wallet_id = $2")
            .bind(contact_id)
            .bind(wallet_id)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(
        final_name, "Batch Contact 14",
        "Final state should reflect all 15 events processed in batches"
    );
}

#[tokio::test]
async fn test_batch_processing_with_large_batch_size() {
    let pool = setup_test_db().await;
    let user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    add_user_to_wallet(&pool, user_id, wallet_id, "owner").await;

    // Create config with large batch size (1000 events per batch)
    let mut config = Config::from_env().unwrap();
    config.event_rebuild_batch_size = 1000;
    let config = Arc::new(config);

    let broadcast_tx = websocket::create_broadcast_channel();
    let app_state = AppState {
        db_pool: Arc::new(pool.clone()),
        config: config.clone(),
        broadcast_tx: broadcast_tx.clone(),
        rate_limiter: debt_tracker_api::middleware::rate_limit::RateLimiter::new(100, 60),
    };

    let contact_id = Uuid::new_v4();

    // Create 25 events (should fit in 1 batch with batch size 1000)
    for i in 0..25 {
        let event = SyncEventRequest {
            id: Uuid::new_v4().to_string(),
            aggregate_type: "contact".to_string(),
            aggregate_id: contact_id.to_string(),
            event_type: if i == 0 { "CREATED" } else { "UPDATED" }.to_string(),
            event_data: json!({
                "name": format!("Large Batch {}", i),
                "timestamp": chrono::Utc::now().to_rfc3339()
            }),
            timestamp: chrono::Utc::now().to_rfc3339(),
            version: 1,
        };

        let _ = post_sync_events(
            axum::extract::State(app_state.clone()),
            wallet_context_extension(wallet_id, WalletRole::Owner),
            auth_user_extension(user_id, None),
            axum::Json(sync_requests_to_domain_events(
                vec![event],
                wallet_id,
                user_id,
            )),
        )
        .await;
    }

    // Clear projections to force full rebuild
    sqlx::query("DELETE FROM transactions_projection WHERE wallet_id = $1")
        .bind(wallet_id)
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query("DELETE FROM contacts_projection WHERE wallet_id = $1")
        .bind(wallet_id)
        .execute(&pool)
        .await
        .unwrap();

    // Rebuild - should process all events in single batch
    let rebuild_result = Projections::rebuild_projections_from_events(&app_state, wallet_id).await;
    assert!(rebuild_result.is_ok(), "Rebuild should succeed");

    // Verify final state
    let final_name: String =
        sqlx::query_scalar("SELECT name FROM contacts_projection WHERE id = $1 AND wallet_id = $2")
            .bind(contact_id)
            .bind(wallet_id)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(
        final_name, "Large Batch 24",
        "Final state should reflect all 25 events"
    );
}

#[tokio::test]
async fn test_batch_processing_with_transactions() {
    let pool = setup_test_db().await;
    let user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    add_user_to_wallet(&pool, user_id, wallet_id, "owner").await;

    // Create config with small batch size to test batching
    let mut config = Config::from_env().unwrap();
    config.event_rebuild_batch_size = 3;
    let config = Arc::new(config);

    let broadcast_tx = websocket::create_broadcast_channel();
    let app_state = AppState {
        db_pool: Arc::new(pool.clone()),
        config: config.clone(),
        broadcast_tx: broadcast_tx.clone(),
        rate_limiter: debt_tracker_api::middleware::rate_limit::RateLimiter::new(100, 60),
    };

    let contact_id = Uuid::new_v4();

    // First, create a contact via event
    let contact_event = SyncEventRequest {
        id: Uuid::new_v4().to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: contact_id.to_string(),
        event_type: "CREATED".to_string(),
        event_data: json!({
            "name": "Test Contact",
            "timestamp": chrono::Utc::now().to_rfc3339()
        }),
        timestamp: chrono::Utc::now().to_rfc3339(),
        version: 1,
    };

    let _ = post_sync_events(
        axum::extract::State(app_state.clone()),
        wallet_context_extension(wallet_id, WalletRole::Owner),
        auth_user_extension(user_id, None),
        axum::Json(sync_requests_to_domain_events(
            vec![contact_event],
            wallet_id,
            user_id,
        )),
    )
    .await;

    // Create 10 transaction events (multiple batches of 3)
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
                "amount": (i + 1) as i64 * 100,
                "currency": "USD",
                "transaction_date": chrono::Utc::now().format("%Y-%m-%d").to_string(),
                "timestamp": chrono::Utc::now().to_rfc3339()
            }),
            timestamp: chrono::Utc::now().to_rfc3339(),
            version: 1,
        };

        let _ = post_sync_events(
            axum::extract::State(app_state.clone()),
            wallet_context_extension(wallet_id, WalletRole::Owner),
            auth_user_extension(user_id, None),
            axum::Json(sync_requests_to_domain_events(
                vec![event],
                wallet_id,
                user_id,
            )),
        )
        .await;
    }

    // Clear projections to force batch processing rebuild
    sqlx::query("DELETE FROM transactions_projection WHERE wallet_id = $1")
        .bind(wallet_id)
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query("DELETE FROM contacts_projection WHERE wallet_id = $1")
        .bind(wallet_id)
        .execute(&pool)
        .await
        .unwrap();

    // Rebuild with batch processing
    let rebuild_result = Projections::rebuild_projections_from_events(&app_state, wallet_id).await;
    assert!(rebuild_result.is_ok(), "Rebuild should succeed");

    // Verify all transactions were created (should have 10 transactions)
    let transaction_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM transactions_projection WHERE contact_id = $1 AND wallet_id = $2 AND is_deleted = false"
    )
    .bind(contact_id)
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        transaction_count, 10,
        "Should have all 10 transactions after batch processing"
    );
}

#[tokio::test]
async fn test_batch_processing_with_undo_events() {
    let pool = setup_test_db().await;
    let user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    add_user_to_wallet(&pool, user_id, wallet_id, "owner").await;

    // Create config with small batch size
    let mut config = Config::from_env().unwrap();
    config.event_rebuild_batch_size = 3;
    let config = Arc::new(config);

    let broadcast_tx = websocket::create_broadcast_channel();
    let app_state = AppState {
        db_pool: Arc::new(pool.clone()),
        config: config.clone(),
        broadcast_tx: broadcast_tx.clone(),
        rate_limiter: debt_tracker_api::middleware::rate_limit::RateLimiter::new(100, 60),
    };

    let contact_id = Uuid::new_v4();
    let mut event_ids = Vec::new();

    // Create 8 events and track their IDs
    for i in 0..8 {
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
            wallet_context_extension(wallet_id, WalletRole::Owner),
            auth_user_extension(user_id, None),
            axum::Json(sync_requests_to_domain_events(
                vec![event],
                wallet_id,
                user_id,
            )),
        )
        .await;
    }

    // Create UNDO event for event 3 (index 2)
    let undo_event = SyncEventRequest {
        id: Uuid::new_v4().to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: contact_id.to_string(),
        event_type: "UNDO".to_string(),
        event_data: json!({
            "undone_event_id": event_ids[2],
            "timestamp": chrono::Utc::now().to_rfc3339()
        }),
        timestamp: chrono::Utc::now().to_rfc3339(),
        version: 1,
    };

    let _ = post_sync_events(
        axum::extract::State(app_state.clone()),
        wallet_context_extension(wallet_id, WalletRole::Owner),
        auth_user_extension(user_id, None),
        axum::Json(sync_requests_to_domain_events(
            vec![undo_event],
            wallet_id,
            user_id,
        )),
    )
    .await;

    // Clear projections to force batch processing rebuild
    sqlx::query("DELETE FROM transactions_projection WHERE wallet_id = $1")
        .bind(wallet_id)
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query("DELETE FROM contacts_projection WHERE wallet_id = $1")
        .bind(wallet_id)
        .execute(&pool)
        .await
        .unwrap();

    // Rebuild - should handle UNDO events correctly even with batch processing
    let rebuild_result = Projections::rebuild_projections_from_events(&app_state, wallet_id).await;
    assert!(
        rebuild_result.is_ok(),
        "Rebuild should succeed with UNDO events"
    );

    // Verify final state (event 2 was undone, so name should not be "Contact 2")
    let final_name: String =
        sqlx::query_scalar("SELECT name FROM contacts_projection WHERE id = $1 AND wallet_id = $2")
            .bind(contact_id)
            .bind(wallet_id)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_ne!(
        final_name, "Contact 2",
        "Undone event 2 should not be reflected in final state"
    );
}

#[tokio::test]
async fn test_batch_processing_empty_wallet() {
    let pool = setup_test_db().await;
    let user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Empty Wallet").await;
    add_user_to_wallet(&pool, user_id, wallet_id, "owner").await;

    let mut config = Config::from_env().unwrap();
    config.event_rebuild_batch_size = 5;
    let config = Arc::new(config);

    let broadcast_tx = websocket::create_broadcast_channel();
    let app_state = AppState {
        db_pool: Arc::new(pool.clone()),
        config: config.clone(),
        broadcast_tx: broadcast_tx.clone(),
        rate_limiter: debt_tracker_api::middleware::rate_limit::RateLimiter::new(100, 60),
    };

    // Rebuild on empty wallet - should succeed without errors
    let rebuild_result = Projections::rebuild_projections_from_events(&app_state, wallet_id).await;
    assert!(
        rebuild_result.is_ok(),
        "Rebuild should succeed on empty wallet"
    );

    // Verify no projections were created
    let contact_count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM contacts_projection WHERE wallet_id = $1")
            .bind(wallet_id)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(contact_count, 0, "Should have no contacts in empty wallet");
}

#[tokio::test]
async fn test_batch_processing_with_permission_events() {
    let pool = setup_test_db().await;
    let user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Wallet with Permissions").await;
    add_user_to_wallet(&pool, user_id, wallet_id, "owner").await;

    // Create a second user to add to the wallet
    let user2_id = create_test_user(&pool).await;

    let mut config = Config::from_env().unwrap();
    config.event_rebuild_batch_size = 5;
    let config = Arc::new(config);

    let broadcast_tx = websocket::create_broadcast_channel();
    let app_state = AppState {
        db_pool: Arc::new(pool.clone()),
        config: config.clone(),
        broadcast_tx: broadcast_tx.clone(),
        rate_limiter: debt_tracker_api::middleware::rate_limit::RateLimiter::new(100, 60),
    };

    // Create 10 permission events (WALLET_USER_ADDED events for the same user multiple times with role changes)
    for i in 0..10 {
        let event = SyncEventRequest {
            id: Uuid::new_v4().to_string(),
            aggregate_type: "permission".to_string(),
            aggregate_id: user2_id.to_string(),
            event_type: if i == 0 {
                "WALLET_USER_ADDED"
            } else {
                "WALLET_USER_ROLE_CHANGED"
            }
            .to_string(),
            event_data: json!({
                "user_id": user2_id.to_string(),
                "role": if i < 5 { "member" } else { "admin" },
                "timestamp": chrono::Utc::now().to_rfc3339()
            }),
            timestamp: chrono::Utc::now().to_rfc3339(),
            version: 1,
        };

        let _ = post_sync_events(
            axum::extract::State(app_state.clone()),
            wallet_context_extension(wallet_id, WalletRole::Owner),
            auth_user_extension(user_id, None),
            axum::Json(sync_requests_to_domain_events(
                vec![event],
                wallet_id,
                user_id,
            )),
        )
        .await;
    }

    // Verify all 10 permission events were created
    let event_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM events WHERE wallet_id = $1 AND aggregate_type = 'permission'",
    )
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(event_count, 10, "Should have 10 permission events");

    // Verify user was added to wallet_users
    let user_in_wallet: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM wallet_users WHERE wallet_id = $1 AND user_id = $2)",
    )
    .bind(wallet_id)
    .bind(user2_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(user_in_wallet, "User2 should be in wallet_users after sync");

    // Check the role after sync (should be 'admin' from the last WALLET_USER_ROLE_CHANGED)
    let role_after_sync: String =
        sqlx::query_scalar("SELECT role FROM wallet_users WHERE wallet_id = $1 AND user_id = $2")
            .bind(wallet_id)
            .bind(user2_id)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(
        role_after_sync, "admin",
        "Final role should be admin after all events"
    );

    // Clear wallet_users for this user to test rebuild
    sqlx::query("DELETE FROM wallet_users WHERE wallet_id = $1 AND user_id = $2")
        .bind(wallet_id)
        .bind(user2_id)
        .execute(&pool)
        .await
        .unwrap();

    // Verify user is no longer in wallet_users
    let user_removed: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM wallet_users WHERE wallet_id = $1 AND user_id = $2)",
    )
    .bind(wallet_id)
    .bind(user2_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(!user_removed, "User should be removed from wallet_users");

    // Rebuild - should reapply all permission events
    let rebuild_result = Projections::rebuild_projections_from_events(&app_state, wallet_id).await;
    assert!(
        rebuild_result.is_ok(),
        "Rebuild should succeed with permission events"
    );

    // Verify user is back in wallet_users
    let user_restored: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM wallet_users WHERE wallet_id = $1 AND user_id = $2)",
    )
    .bind(wallet_id)
    .bind(user2_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(
        user_restored,
        "User should be restored to wallet_users after rebuild"
    );

    // Verify final role is correct (should be 'admin' from last role change event)
    let role_after_rebuild: String =
        sqlx::query_scalar("SELECT role FROM wallet_users WHERE wallet_id = $1 AND user_id = $2")
            .bind(wallet_id)
            .bind(user2_id)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(
        role_after_rebuild, "admin",
        "Final role should still be admin after rebuild from batch processing"
    );
}

#[tokio::test]
async fn test_permission_events_with_undo() {
    let pool = setup_test_db().await;
    let user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Wallet with Permission UNDO").await;
    add_user_to_wallet(&pool, user_id, wallet_id, "owner").await;

    let user2_id = create_test_user(&pool).await;
    let user3_id = create_test_user(&pool).await;

    let config = Arc::new(Config::from_env().unwrap());
    let broadcast_tx = websocket::create_broadcast_channel();
    let app_state = AppState {
        db_pool: Arc::new(pool.clone()),
        config: config.clone(),
        broadcast_tx: broadcast_tx.clone(),
        rate_limiter: debt_tracker_api::middleware::rate_limit::RateLimiter::new(100, 60),
    };

    // Create WALLET_USER_ADDED event for user2
    let user2_add_event = SyncEventRequest {
        id: Uuid::new_v4().to_string(),
        aggregate_type: "permission".to_string(),
        aggregate_id: user2_id.to_string(),
        event_type: "WALLET_USER_ADDED".to_string(),
        event_data: json!({
            "user_id": user2_id.to_string(),
            "role": "member",
            "timestamp": chrono::Utc::now().to_rfc3339()
        }),
        timestamp: chrono::Utc::now().to_rfc3339(),
        version: 1,
    };

    let _ = post_sync_events(
        axum::extract::State(app_state.clone()),
        wallet_context_extension(wallet_id, WalletRole::Owner),
        auth_user_extension(user_id, None),
        axum::Json(sync_requests_to_domain_events(
            vec![user2_add_event.clone()],
            wallet_id,
            user_id,
        )),
    )
    .await;

    // Create WALLET_USER_ADDED event for user3
    let user3_add_event = SyncEventRequest {
        id: Uuid::new_v4().to_string(),
        aggregate_type: "permission".to_string(),
        aggregate_id: user3_id.to_string(),
        event_type: "WALLET_USER_ADDED".to_string(),
        event_data: json!({
            "user_id": user3_id.to_string(),
            "role": "member",
            "timestamp": chrono::Utc::now().to_rfc3339()
        }),
        timestamp: chrono::Utc::now().to_rfc3339(),
        version: 1,
    };

    let _ = post_sync_events(
        axum::extract::State(app_state.clone()),
        wallet_context_extension(wallet_id, WalletRole::Owner),
        auth_user_extension(user_id, None),
        axum::Json(sync_requests_to_domain_events(
            vec![user3_add_event.clone()],
            wallet_id,
            user_id,
        )),
    )
    .await;

    // Verify both users are in wallet
    let count_before: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM wallet_users WHERE wallet_id = $1")
            .bind(wallet_id)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(
        count_before, 3,
        "Should have 3 users (owner + user2 + user3)"
    );

    // Create a contact and then UNDO it (to test UNDO with permission events present)
    let contact_create = SyncEventRequest {
        id: Uuid::new_v4().to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: Uuid::new_v4().to_string(),
        event_type: "CREATED".to_string(),
        event_data: json!({
            "name": "Test Contact"
        }),
        timestamp: chrono::Utc::now().to_rfc3339(),
        version: 1,
    };

    let contact_id = contact_create.id.clone();

    let _ = post_sync_events(
        axum::extract::State(app_state.clone()),
        wallet_context_extension(wallet_id, WalletRole::Owner),
        auth_user_extension(user_id, None),
        axum::Json(sync_requests_to_domain_events(
            vec![contact_create],
            wallet_id,
            user_id,
        )),
    )
    .await;

    // Create UNDO event to undo the contact
    let undo_event = SyncEventRequest {
        id: Uuid::new_v4().to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: Uuid::new_v4().to_string(),
        event_type: "UNDO".to_string(),
        event_data: json!({
            "undone_event_id": contact_id
        }),
        timestamp: chrono::Utc::now().to_rfc3339(),
        version: 1,
    };

    let _ = post_sync_events(
        axum::extract::State(app_state.clone()),
        wallet_context_extension(wallet_id, WalletRole::Owner),
        auth_user_extension(user_id, None),
        axum::Json(sync_requests_to_domain_events(
            vec![undo_event],
            wallet_id,
            user_id,
        )),
    )
    .await;

    // Rebuild to apply UNDO
    let rebuild_result = Projections::rebuild_projections_from_events(&app_state, wallet_id).await;
    assert!(
        rebuild_result.is_ok(),
        "Rebuild should succeed with UNDO event"
    );

    // Verify permission events are still intact after UNDO and rebuild
    let user2_exists: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM wallet_users WHERE wallet_id = $1 AND user_id = $2)",
    )
    .bind(wallet_id)
    .bind(user2_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(
        user2_exists,
        "User2 should still be in wallet after UNDO of contact"
    );

    // Verify user3 is still in wallet
    let user3_exists: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM wallet_users WHERE wallet_id = $1 AND user_id = $2)",
    )
    .bind(wallet_id)
    .bind(user3_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(
        user3_exists,
        "User3 should still be in wallet after UNDO of contact"
    );

    // Verify final count is still 3 (all permission events preserved)
    let count_after: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM wallet_users WHERE wallet_id = $1")
            .bind(wallet_id)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(
        count_after, 3,
        "Should have 3 users after UNDO (permission events preserved)"
    );
}

#[tokio::test]
async fn test_permission_events_with_snapshot() {
    let pool = setup_test_db().await;
    let user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Wallet with Permission Snapshot").await;
    add_user_to_wallet(&pool, user_id, wallet_id, "owner").await;

    let config = Arc::new(Config::from_env().unwrap());
    let broadcast_tx = websocket::create_broadcast_channel();
    let app_state = AppState {
        db_pool: Arc::new(pool.clone()),
        config: config.clone(),
        broadcast_tx: broadcast_tx.clone(),
        rate_limiter: debt_tracker_api::middleware::rate_limit::RateLimiter::new(100, 60),
    };

    // Create 15 contacts to trigger snapshot creation
    for i in 0..15 {
        let contact_id = Uuid::new_v4();
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
            wallet_context_extension(wallet_id, WalletRole::Owner),
            auth_user_extension(user_id, None),
            axum::Json(sync_requests_to_domain_events(
                vec![event],
                wallet_id,
                user_id,
            )),
        )
        .await;
    }

    // Verify snapshot was created
    let snapshot_count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM projection_snapshots WHERE wallet_id = $1")
            .bind(wallet_id)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert!(snapshot_count > 0, "Snapshot should be created");

    // Create 5 permission events after snapshot
    let new_users = vec![
        create_test_user(&pool).await,
        create_test_user(&pool).await,
        create_test_user(&pool).await,
        create_test_user(&pool).await,
        create_test_user(&pool).await,
    ];

    for new_user_id in &new_users {
        let event = SyncEventRequest {
            id: Uuid::new_v4().to_string(),
            aggregate_type: "permission".to_string(),
            aggregate_id: new_user_id.to_string(),
            event_type: "WALLET_USER_ADDED".to_string(),
            event_data: json!({
                "user_id": new_user_id.to_string(),
                "role": "member",
                "timestamp": chrono::Utc::now().to_rfc3339()
            }),
            timestamp: chrono::Utc::now().to_rfc3339(),
            version: 1,
        };

        let _ = post_sync_events(
            axum::extract::State(app_state.clone()),
            wallet_context_extension(wallet_id, WalletRole::Owner),
            auth_user_extension(user_id, None),
            axum::Json(sync_requests_to_domain_events(
                vec![event],
                wallet_id,
                user_id,
            )),
        )
        .await;
    }

    // Verify all new users are in wallet_users
    let user_count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM wallet_users WHERE wallet_id = $1")
            .bind(wallet_id)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(user_count, 6, "Should have 6 users (1 owner + 5 new)");

    // Clear wallet_users (except owner) to test rebuild with snapshot
    sqlx::query("DELETE FROM wallet_users WHERE wallet_id = $1 AND user_id != $2")
        .bind(wallet_id)
        .bind(user_id)
        .execute(&pool)
        .await
        .unwrap();

    // Rebuild - should use snapshot + apply permission events after snapshot
    let rebuild_result = Projections::rebuild_projections_from_events(&app_state, wallet_id).await;
    assert!(
        rebuild_result.is_ok(),
        "Rebuild should succeed with snapshot"
    );

    // Verify all users are restored
    let restored_count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM wallet_users WHERE wallet_id = $1")
            .bind(wallet_id)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(
        restored_count, 6,
        "All users should be restored after rebuild with snapshot"
    );
}
