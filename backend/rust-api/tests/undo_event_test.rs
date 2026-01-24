use debt_tracker_api::handlers::sync::{post_sync_events, SyncEventRequest};
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
async fn test_undo_event_validation() {
    let pool = setup_test_db().await;
    let _user_id = create_test_user(&pool).await;
    
    let config = Arc::new(Config::from_env().unwrap());
    let broadcast_tx = websocket::create_broadcast_channel();
    let app_state = AppState {
        db_pool: Arc::new(pool.clone()),
        config: config.clone(),
        broadcast_tx: broadcast_tx.clone(),
    };

    // Test 1: UNDO event without 'undone_event_id' should be rejected
    let invalid_undo = SyncEventRequest {
        id: Uuid::new_v4().to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: Uuid::new_v4().to_string(),
        event_type: "UNDO".to_string(),
        event_data: json!({}), // Missing undone_event_id
        timestamp: chrono::Utc::now().to_rfc3339(),
        version: 1,
    };

    let result = post_sync_events(
        axum::extract::State(app_state.clone()),
        axum::Json(vec![invalid_undo.clone()]),
    ).await;

    // Should be rejected (validation error) - validation happens before insert, so it goes to conflicts
    let response = result.unwrap().0;
    assert!(response.conflicts.contains(&invalid_undo.id), "Invalid UNDO event should be in conflicts");

    // Test 2: UNDO event with invalid UUID in 'undone_event_id' should be rejected
    let invalid_uuid_undo = SyncEventRequest {
        id: Uuid::new_v4().to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: Uuid::new_v4().to_string(),
        event_type: "UNDO".to_string(),
        event_data: json!({
            "undone_event_id": "not-a-valid-uuid"
        }),
        timestamp: chrono::Utc::now().to_rfc3339(),
        version: 1,
    };

    let result = post_sync_events(
        axum::extract::State(app_state.clone()),
        axum::Json(vec![invalid_uuid_undo.clone()]),
    ).await;

    // Should be rejected (validation error)
    let response = result.unwrap().0;
    assert!(response.conflicts.contains(&invalid_uuid_undo.id), "Invalid UUID UNDO event should be in conflicts");

    // Test 3: UNDO event with valid structure should be accepted
    let original_event_id = Uuid::new_v4();
    let valid_undo = SyncEventRequest {
        id: Uuid::new_v4().to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: Uuid::new_v4().to_string(),
        event_type: "UNDO".to_string(),
        event_data: json!({
            "undone_event_id": original_event_id.to_string()
        }),
        timestamp: chrono::Utc::now().to_rfc3339(),
        version: 1,
    };

    let result = post_sync_events(
        axum::extract::State(app_state),
        axum::Json(vec![valid_undo.clone()]),
    ).await;

    // Should be accepted (even if undone event doesn't exist - validation only checks structure)
    let response = result.unwrap().0;
    assert!(response.accepted.contains(&valid_undo.id), "Valid UNDO event structure should be accepted");
}

#[tokio::test]
#[ignore] // Ignore by default - requires test database
async fn test_undo_event_skips_undone_event_in_projections() {
    let pool = setup_test_db().await;
    let _user_id = create_test_user(&pool).await;
    
    let config = Arc::new(Config::from_env().unwrap());
    let broadcast_tx = websocket::create_broadcast_channel();
    let app_state = AppState {
        db_pool: Arc::new(pool.clone()),
        config: config.clone(),
        broadcast_tx: broadcast_tx.clone(),
    };

    let contact_id = Uuid::new_v4();
    
    // 1. Create a contact via CREATED event
    let created_event = SyncEventRequest {
        id: Uuid::new_v4().to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: contact_id.to_string(),
        event_type: "CREATED".to_string(),
        event_data: json!({
            "name": "Original Name",
            "timestamp": chrono::Utc::now().to_rfc3339()
        }),
        timestamp: chrono::Utc::now().to_rfc3339(),
        version: 1,
    };

    let _ = post_sync_events(
        axum::extract::State(app_state.clone()),
        axum::Json(vec![created_event.clone()]),
    ).await;

    // 2. Update the contact via UPDATED event
    let updated_event = SyncEventRequest {
        id: Uuid::new_v4().to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: contact_id.to_string(),
        event_type: "UPDATED".to_string(),
        event_data: json!({
            "name": "Updated Name",
            "timestamp": chrono::Utc::now().to_rfc3339()
        }),
        timestamp: chrono::Utc::now().to_rfc3339(),
        version: 1,
    };

    let _ = post_sync_events(
        axum::extract::State(app_state.clone()),
        axum::Json(vec![updated_event.clone()]),
    ).await;

    // Verify update was applied
    let name_after_update: String = sqlx::query_scalar(
        "SELECT name FROM contacts_projection WHERE id = $1"
    )
    .bind(contact_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(name_after_update, "Updated Name");

    // 3. Create UNDO event for the UPDATE
    let undo_event = SyncEventRequest {
        id: Uuid::new_v4().to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: contact_id.to_string(),
        event_type: "UNDO".to_string(),
        event_data: json!({
            "undone_event_id": updated_event.id,
            "timestamp": chrono::Utc::now().to_rfc3339()
        }),
        timestamp: chrono::Utc::now().to_rfc3339(),
        version: 1,
    };

    let _ = post_sync_events(
        axum::extract::State(app_state.clone()),
        axum::Json(vec![undo_event.clone()]),
    ).await;

    // Rebuild projections to apply UNDO
    let _ = debt_tracker_api::handlers::sync::rebuild_projections_from_events(&app_state).await;

    // 4. Verify projection shows original contact data (update was undone)
    let name_after_undo: String = sqlx::query_scalar(
        "SELECT name FROM contacts_projection WHERE id = $1"
    )
    .bind(contact_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(name_after_undo, "Original Name");
}

#[tokio::test]
#[ignore] // Ignore by default - requires test database
async fn test_undo_event_syncs_correctly() {
    let pool = setup_test_db().await;
    let _user_id = create_test_user(&pool).await;
    
    let config = Arc::new(Config::from_env().unwrap());
    let broadcast_tx = websocket::create_broadcast_channel();
    let app_state = AppState {
        db_pool: Arc::new(pool.clone()),
        config: config.clone(),
        broadcast_tx: broadcast_tx.clone(),
    };

    let contact_id = Uuid::new_v4();
    
    // 1. Create original event
    let original_event = SyncEventRequest {
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
        axum::Json(vec![original_event.clone()]),
    ).await;

    // 2. Client creates UNDO event and syncs to server
    let undo_event = SyncEventRequest {
        id: Uuid::new_v4().to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: contact_id.to_string(),
        event_type: "UNDO".to_string(),
        event_data: json!({
            "undone_event_id": original_event.id,
            "timestamp": chrono::Utc::now().to_rfc3339()
        }),
        timestamp: chrono::Utc::now().to_rfc3339(),
        version: 1,
    };

    // 3. Server accepts UNDO event
    let result = post_sync_events(
        axum::extract::State(app_state.clone()),
        axum::Json(vec![undo_event.clone()]),
    ).await;

    assert!(result.is_ok());
    let response = result.unwrap().0;
    assert!(response.accepted.contains(&undo_event.id), "UNDO event should be accepted");

    // 4. Verify UNDO event is in database
    let undo_exists: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM events WHERE event_id = $1 AND event_type = 'UNDO')"
    )
    .bind(Uuid::parse_str(&undo_event.id).unwrap())
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(undo_exists, "UNDO event should be stored in database");

    // 5. Rebuild projections - undone event should be skipped
    let _ = debt_tracker_api::handlers::sync::rebuild_projections_from_events(&app_state).await;

    // Verify contact doesn't exist (original event was undone)
    let contact_exists: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM contacts_projection WHERE id = $1)"
    )
    .bind(contact_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(!contact_exists, "Contact should not exist after UNDO");
}

#[tokio::test]
#[ignore] // Ignore by default - requires test database
async fn test_undo_event_creates_snapshot() {
    let pool = setup_test_db().await;
    let _user_id = create_test_user(&pool).await;
    
    let config = Arc::new(Config::from_env().unwrap());
    let broadcast_tx = websocket::create_broadcast_channel();
    let app_state = AppState {
        db_pool: Arc::new(pool.clone()),
        config: config.clone(),
        broadcast_tx: broadcast_tx.clone(),
    };

    // 1. Create some events (not reaching snapshot interval of 10)
    let contact_id = Uuid::new_v4();
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
            axum::Json(vec![event]),
        ).await;
    }

    // Verify no snapshot exists yet (we have 5 events, not 10)
    let snapshot_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM projection_snapshots")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(snapshot_count, 0);

    // 2. Create UNDO event
    let undo_event = SyncEventRequest {
        id: Uuid::new_v4().to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: contact_id.to_string(),
        event_type: "UNDO".to_string(),
        event_data: json!({
            "undone_event_id": Uuid::new_v4().to_string(), // Reference a previous event
            "timestamp": chrono::Utc::now().to_rfc3339()
        }),
        timestamp: chrono::Utc::now().to_rfc3339(),
        version: 1,
    };

    let _ = post_sync_events(
        axum::extract::State(app_state.clone()),
        axum::Json(vec![undo_event]),
    ).await;

    // 3. Verify snapshot was created after UNDO event
    let snapshot_count_after: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM projection_snapshots")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert!(snapshot_count_after > 0, "Snapshot should be created after UNDO event");

    // 4. Verify snapshot contains correct state
    let snapshot = sqlx::query(
        "SELECT contacts_snapshot, transactions_snapshot FROM projection_snapshots ORDER BY snapshot_index DESC LIMIT 1"
    )
    .fetch_one(&pool)
    .await
    .unwrap();

    let contacts: serde_json::Value = snapshot.try_get("contacts_snapshot").unwrap();
    assert!(contacts.is_array());
}

#[tokio::test]
#[ignore] // Ignore by default - requires test database
async fn test_event_validation_rejects_invalid_undo() {
    let pool = setup_test_db().await;
    let _user_id = create_test_user(&pool).await;
    
    let config = Arc::new(Config::from_env().unwrap());
    let broadcast_tx = websocket::create_broadcast_channel();
    let app_state = AppState {
        db_pool: Arc::new(pool.clone()),
        config: config.clone(),
        broadcast_tx: broadcast_tx.clone(),
    };

    // 1. UNDO event without 'undone_event_id' is rejected
    let no_undone_id = SyncEventRequest {
        id: Uuid::new_v4().to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: Uuid::new_v4().to_string(),
        event_type: "UNDO".to_string(),
        event_data: json!({}), // Missing undone_event_id
        timestamp: chrono::Utc::now().to_rfc3339(),
        version: 1,
    };

    let result = post_sync_events(
        axum::extract::State(app_state.clone()),
        axum::Json(vec![no_undone_id.clone()]),
    ).await;
    let response = result.unwrap().0;
    assert!(response.conflicts.contains(&no_undone_id.id), "UNDO without undone_event_id should be rejected");

    // 2. UNDO event with invalid UUID in 'undone_event_id' is rejected
    let invalid_uuid = SyncEventRequest {
        id: Uuid::new_v4().to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: Uuid::new_v4().to_string(),
        event_type: "UNDO".to_string(),
        event_data: json!({
            "undone_event_id": "not-a-uuid"
        }),
        timestamp: chrono::Utc::now().to_rfc3339(),
        version: 1,
    };

    let result = post_sync_events(
        axum::extract::State(app_state.clone()),
        axum::Json(vec![invalid_uuid.clone()]),
    ).await;
    let response = result.unwrap().0;
    assert!(response.conflicts.contains(&invalid_uuid.id), "UNDO with invalid UUID should be rejected");

    // 3. UNDO event with non-existent 'undone_event_id' is still accepted (validation only checks structure)
    let valid_structure = SyncEventRequest {
        id: Uuid::new_v4().to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: Uuid::new_v4().to_string(),
        event_type: "UNDO".to_string(),
        event_data: json!({
            "undone_event_id": Uuid::new_v4().to_string() // Valid UUID format, but doesn't exist
        }),
        timestamp: chrono::Utc::now().to_rfc3339(),
        version: 1,
    };

    let result = post_sync_events(
        axum::extract::State(app_state),
        axum::Json(vec![valid_structure.clone()]),
    ).await;
    let response = result.unwrap().0;
    assert!(response.accepted.contains(&valid_structure.id), "UNDO with valid structure should be accepted even if undone event doesn't exist");
}

#[tokio::test]
#[ignore] // Ignore by default - requires test database
async fn test_multiple_undo_events() {
    let pool = setup_test_db().await;
    let _user_id = create_test_user(&pool).await;
    
    let config = Arc::new(Config::from_env().unwrap());
    let broadcast_tx = websocket::create_broadcast_channel();
    let app_state = AppState {
        db_pool: Arc::new(pool.clone()),
        config: config.clone(),
        broadcast_tx: broadcast_tx.clone(),
    };

    let contact_id = Uuid::new_v4();
    
    // 1. Create multiple events
    let event1 = SyncEventRequest {
        id: Uuid::new_v4().to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: contact_id.to_string(),
        event_type: "CREATED".to_string(),
        event_data: json!({
            "name": "Original",
            "timestamp": chrono::Utc::now().to_rfc3339()
        }),
        timestamp: chrono::Utc::now().to_rfc3339(),
        version: 1,
    };

    let event2 = SyncEventRequest {
        id: Uuid::new_v4().to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: contact_id.to_string(),
        event_type: "UPDATED".to_string(),
        event_data: json!({
            "name": "First Update",
            "timestamp": chrono::Utc::now().to_rfc3339()
        }),
        timestamp: chrono::Utc::now().to_rfc3339(),
        version: 1,
    };

    let event3 = SyncEventRequest {
        id: Uuid::new_v4().to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: contact_id.to_string(),
        event_type: "UPDATED".to_string(),
        event_data: json!({
            "name": "Second Update",
            "timestamp": chrono::Utc::now().to_rfc3339()
        }),
        timestamp: chrono::Utc::now().to_rfc3339(),
        version: 1,
    };

    let _ = post_sync_events(
        axum::extract::State(app_state.clone()),
        axum::Json(vec![event1.clone(), event2.clone(), event3.clone()]),
    ).await;

    // 2. Create multiple UNDO events for different original events
    let undo1 = SyncEventRequest {
        id: Uuid::new_v4().to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: contact_id.to_string(),
        event_type: "UNDO".to_string(),
        event_data: json!({
            "undone_event_id": event2.id,
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
            "undone_event_id": event3.id,
            "timestamp": chrono::Utc::now().to_rfc3339()
        }),
        timestamp: chrono::Utc::now().to_rfc3339(),
        version: 1,
    };

    let _ = post_sync_events(
        axum::extract::State(app_state.clone()),
        axum::Json(vec![undo1.clone(), undo2.clone()]),
    ).await;

    // 3. Rebuild projections - all undone events should be skipped
    let _ = debt_tracker_api::handlers::sync::rebuild_projections_from_events(&app_state).await;

    // 4. Verify state is correct (should have original name, both updates undone)
    let name: String = sqlx::query_scalar(
        "SELECT name FROM contacts_projection WHERE id = $1"
    )
    .bind(contact_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(name, "Original", "Both updates should be undone, leaving original name");
}

#[tokio::test]
#[ignore] // Ignore by default - requires test database
async fn test_undo_event_with_snapshot_rebuild() {
    let pool = setup_test_db().await;
    let _user_id = create_test_user(&pool).await;
    
    let config = Arc::new(Config::from_env().unwrap());
    let broadcast_tx = websocket::create_broadcast_channel();
    let app_state = AppState {
        db_pool: Arc::new(pool.clone()),
        config: config.clone(),
        broadcast_tx: broadcast_tx.clone(),
    };

    let contact_id = Uuid::new_v4();
    
    // 1. Create events to trigger snapshot (every 10 events)
    let mut events_to_undo: Vec<String> = Vec::new();
    for i in 0..15 {
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
        
        if i < 5 {
            events_to_undo.push(event.id.clone());
        }

        let _ = post_sync_events(
            axum::extract::State(app_state.clone()),
            axum::Json(vec![event]),
        ).await;
    }

    // Verify snapshot was created (at event 10)
    let snapshot_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM projection_snapshots")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert!(snapshot_count > 0, "Snapshot should be created at event 10");

    // 2. Create UNDO event for an event before latest snapshot (event 3)
    let undo_event = SyncEventRequest {
        id: Uuid::new_v4().to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: contact_id.to_string(),
        event_type: "UNDO".to_string(),
        event_data: json!({
            "undone_event_id": events_to_undo[2], // Undo event 3
            "timestamp": chrono::Utc::now().to_rfc3339()
        }),
        timestamp: chrono::Utc::now().to_rfc3339(),
        version: 1,
    };

    let _ = post_sync_events(
        axum::extract::State(app_state.clone()),
        axum::Json(vec![undo_event]),
    ).await;

    // 3. Rebuild projections - should use snapshot and filter undone events
    let _ = debt_tracker_api::handlers::sync::rebuild_projections_from_events(&app_state).await;

    // 4. Verify rebuild filtered out undone events correctly
    // The contact should exist with a name from events after the undone one
    let contact_exists: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM contacts_projection WHERE id = $1)"
    )
    .bind(contact_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(contact_exists, "Contact should exist after rebuild");
}
