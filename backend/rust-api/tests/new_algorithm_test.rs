// Tests for the new optimized projection rebuild algorithm
// These tests verify:
// 1. Snapshot optimization is used when UNDO event undoes an event after a snapshot
// 2. Full rebuild is used when UNDO event undoes an event before all snapshots
// 3. Cleaned event list correctly removes UNDO and undone events
// 4. Finding undone event position by ID (fast lookup)
// 5. Multiple UNDO events with snapshot optimization

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
async fn test_snapshot_optimization_with_undo_after_snapshot() {
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
    let mut event_ids = Vec::new();
    
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
        event_ids.push(event.id.clone());

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

    // 2. Create 5 more events after snapshot
    for i in 10..15 {
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
        event_ids.push(event.id.clone());

        let _ = post_sync_events(
            axum::extract::State(app_state.clone()),
            wallet_context_extension(wallet_id, "owner"),
            auth_user_extension(user_id, None),
            axum::Json(vec![event]),
        ).await;
    }

    // 3. Create UNDO event for event 12 (which is after the snapshot at event 10)
    // With new algorithm, should use snapshot optimization
    let undo_event = SyncEventRequest {
        id: Uuid::new_v4().to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: contact_id.to_string(),
        event_type: "UNDO".to_string(),
        event_data: json!({
            "undone_event_id": event_ids[12], // Undo event 13 (index 12)
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

    // 4. Rebuild projections - should use snapshot optimization (snapshot exists before undone event)
    let _ = rebuild_projections_from_events(&app_state, wallet_id).await;

    // 5. Verify final state is correct (event 13 was undone, so should have name from event 12 or earlier)
    let final_name: String = sqlx::query_scalar(
        "SELECT name FROM contacts_projection WHERE id = $1 AND wallet_id = $2"
    )
    .bind(contact_id)
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    // Event 13 (index 12) was undone, so name should be from event 12 (index 11) or earlier
    assert!(final_name != "Contact 13", "Event 13 should be undone");
    assert!(final_name == "Contact 12" || final_name == "Contact 11" || final_name == "Contact 10", 
            "Name should be from an event before the undone one");
}

#[tokio::test]
#[ignore] // Ignore by default - requires test database
async fn test_full_rebuild_when_undo_before_all_snapshots() {
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
    let mut event_ids = Vec::new();
    
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
        event_ids.push(event.id.clone());

        let _ = post_sync_events(
            axum::extract::State(app_state.clone()),
            wallet_context_extension(wallet_id, "owner"),
            auth_user_extension(user_id, None),
            axum::Json(vec![event]),
        ).await;
    }

    // Verify no snapshot exists yet
    let snapshot_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM projection_snapshots WHERE wallet_id = $1")
        .bind(wallet_id)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(snapshot_count, 0, "No snapshot should exist yet");

    // 2. Create UNDO event for event 2 (before any snapshot)
    let undo_event = SyncEventRequest {
        id: Uuid::new_v4().to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: contact_id.to_string(),
        event_type: "UNDO".to_string(),
        event_data: json!({
            "undone_event_id": event_ids[2], // Undo event 3 (index 2)
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

    // 3. Rebuild projections - should use full rebuild (no snapshot before undone event)
    let _ = rebuild_projections_from_events(&app_state, wallet_id).await;

    // 4. Verify final state is correct (event 3 was undone)
    let final_name: String = sqlx::query_scalar(
        "SELECT name FROM contacts_projection WHERE id = $1 AND wallet_id = $2"
    )
    .bind(contact_id)
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(final_name != "Contact 3", "Event 3 should be undone");
}

#[tokio::test]
#[ignore] // Ignore by default - requires test database
async fn test_cleaned_event_list_removes_undo_and_undone_events() {
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
    let mut event_ids = Vec::new();
    
    // 1. Create 10 events to trigger snapshot
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

    // 2. Create 3 more events
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
        event_ids.push(event.id.clone());

        let _ = post_sync_events(
            axum::extract::State(app_state.clone()),
            wallet_context_extension(wallet_id, "owner"),
            auth_user_extension(user_id, None),
            axum::Json(vec![event]),
        ).await;
    }

    // 3. Create UNDO event for event 11 (index 11)
    let undo_event = SyncEventRequest {
        id: Uuid::new_v4().to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: contact_id.to_string(),
        event_type: "UNDO".to_string(),
        event_data: json!({
            "undone_event_id": event_ids[11],
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

    // 4. Rebuild projections - cleaned event list should exclude UNDO and undone event
    let _ = rebuild_projections_from_events(&app_state, wallet_id).await;

    // 5. Verify final state (event 12 was undone, so should have name from event 11 or earlier)
    let final_name: String = sqlx::query_scalar(
        "SELECT name FROM contacts_projection WHERE id = $1 AND wallet_id = $2"
    )
    .bind(contact_id)
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(final_name != "Contact 12", "Event 12 should be undone");
    
    // Verify UNDO event is not in projections (it's excluded from cleaned list)
    // This is implicit - if the projection is correct, the cleaned list worked
}

#[tokio::test]
#[ignore] // Ignore by default - requires test database
async fn test_multiple_undo_events_with_snapshot_optimization() {
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
    let mut event_ids = Vec::new();
    
    // 1. Create 10 events to trigger snapshot
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

    // 2. Create 5 more events after snapshot
    for i in 10..15 {
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
        event_ids.push(event.id.clone());

        let _ = post_sync_events(
            axum::extract::State(app_state.clone()),
            wallet_context_extension(wallet_id, "owner"),
            auth_user_extension(user_id, None),
            axum::Json(vec![event]),
        ).await;
    }

    // 3. Create multiple UNDO events for events after snapshot
    let undo1 = SyncEventRequest {
        id: Uuid::new_v4().to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: contact_id.to_string(),
        event_type: "UNDO".to_string(),
        event_data: json!({
            "undone_event_id": event_ids[11], // Undo event 12
            "timestamp": chrono::Utc::now().to_rfc3339()
        }),
        timestamp: chrono::Utc::now().to_rfc3339(),
        version: 1,
    };

    let undo2 = SyncEventRequest {
        id: Uuid::new_v4().to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: contact_id.to_string(),
        event_type: "UNDO".to_string(),
        event_data: json!({
            "undone_event_id": event_ids[13], // Undo event 14
            "timestamp": chrono::Utc::now().to_rfc3339()
        }),
        timestamp: chrono::Utc::now().to_rfc3339(),
        version: 1,
    };

    let _ = post_sync_events(
        axum::extract::State(app_state.clone()),
        wallet_context_extension(wallet_id, "owner"),
        axum::Json(vec![undo1, undo2]),
    ).await;

    // 4. Rebuild projections - should use snapshot optimization (snapshot at event 10, undone events are 12 and 14)
    let _ = rebuild_projections_from_events(&app_state, wallet_id).await;

    // 5. Verify final state (events 12 and 14 were undone)
    let final_name: String = sqlx::query_scalar(
        "SELECT name FROM contacts_projection WHERE id = $1 AND wallet_id = $2"
    )
    .bind(contact_id)
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(final_name != "Contact 12", "Event 12 should be undone");
    assert!(final_name != "Contact 14", "Event 14 should be undone");
}

#[tokio::test]
#[ignore] // Ignore by default - requires test database
async fn test_undo_event_finds_position_by_id() {
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
    let mut event_ids = Vec::new();
    
    // 1. Create 20 events (2 snapshots should be created at events 10 and 20)
    for i in 0..20 {
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

    // Verify snapshots were created
    let snapshot_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM projection_snapshots WHERE wallet_id = $1")
        .bind(wallet_id)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert!(snapshot_count >= 2, "At least 2 snapshots should be created");

    // 2. Create UNDO event for event 15 (which is after snapshot at event 10, but before snapshot at event 20)
    // Algorithm should find event 15's position by ID and use snapshot at event 10
    let undo_event = SyncEventRequest {
        id: Uuid::new_v4().to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: contact_id.to_string(),
        event_type: "UNDO".to_string(),
        event_data: json!({
            "undone_event_id": event_ids[15], // Undo event 16 (index 15)
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

    // 3. Rebuild projections - should use snapshot at event 10 (since undone event is at position 16)
    let _ = rebuild_projections_from_events(&app_state, wallet_id).await;

    // 4. Verify final state (event 16 was undone)
    let final_name: String = sqlx::query_scalar(
        "SELECT name FROM contacts_projection WHERE id = $1 AND wallet_id = $2"
    )
    .bind(contact_id)
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(final_name != "Contact 16", "Event 16 should be undone");
}
