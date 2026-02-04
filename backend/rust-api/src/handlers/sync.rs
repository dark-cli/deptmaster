use axum::{
    extract::{Query, State, Extension},
    http::StatusCode,
    response::Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use crate::AppState;
use crate::websocket;
use crate::services::projection_snapshot_service;
use crate::middleware::wallet_context::WalletContext;
use sha2::{Sha256, Digest};

/// Calculate total debt (sum of all contact balances) at current time for a wallet
async fn calculate_total_debt(state: &AppState, wallet_id: uuid::Uuid) -> i64 {
    sqlx::query_scalar::<_, i64>(
        r#"
        SELECT COALESCE(SUM(
            CASE 
                WHEN t.direction = 'lent' THEN t.amount
                WHEN t.direction = 'owed' THEN -t.amount
                ELSE 0
            END
        )::BIGINT, 0)
        FROM contacts_projection c
        LEFT JOIN transactions_projection t ON t.contact_id = c.id AND t.is_deleted = false AND t.wallet_id = $1
        WHERE c.is_deleted = false AND c.wallet_id = $1
        "#
    )
    .bind(wallet_id)
    .fetch_one(&*state.db_pool)
    .await
    .unwrap_or(0)
}

#[derive(Serialize)]
pub struct SyncHashResponse {
    pub hash: String,
    pub event_count: i64,
    pub last_event_timestamp: Option<chrono::NaiveDateTime>,
}

/// Get hash of all events for sync comparison
pub async fn get_sync_hash(
    State(state): State<AppState>,
    Extension(wallet_context): Extension<WalletContext>,
) -> Result<Json<SyncHashResponse>, (StatusCode, Json<serde_json::Value>)> {
    let wallet_id = wallet_context.wallet_id;
    
    // Get all events for this wallet ordered by timestamp
    let events = sqlx::query(
        r#"
        SELECT event_id, aggregate_type, aggregate_id, event_type, created_at
        FROM events
        WHERE wallet_id = $1
        ORDER BY created_at ASC
        "#
    )
    .bind(wallet_id)
    .fetch_all(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching events for hash: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to fetch events"})),
        )
    })?;

    // Calculate hash from event IDs and timestamps
    let mut hasher = Sha256::new();
    for row in &events {
        let event_id: uuid::Uuid = row.get("event_id");
        let created_at: chrono::NaiveDateTime = row.get("created_at");
        hasher.update(event_id.to_string().as_bytes());
        hasher.update(created_at.to_string().as_bytes());
    }
    let hash = format!("{:x}", hasher.finalize());

    let last_event_timestamp = events.last().map(|row| row.get::<chrono::NaiveDateTime, _>("created_at"));

    Ok(Json(SyncHashResponse {
        hash,
        event_count: events.len() as i64,
        last_event_timestamp,
    }))
}

#[derive(Deserialize)]
pub struct SyncEventsQuery {
    since: Option<String>, // ISO timestamp
}

#[derive(Serialize)]
pub struct SyncEvent {
    pub id: String,
    pub aggregate_type: String,
    pub aggregate_id: String,
    pub event_type: String,
    pub event_data: serde_json::Value,
    pub timestamp: String,
    pub version: i32,
}

/// Get events since a timestamp
pub async fn get_sync_events(
    Query(params): Query<SyncEventsQuery>,
    State(state): State<AppState>,
    Extension(wallet_context): Extension<WalletContext>,
) -> Result<Json<Vec<SyncEvent>>, (StatusCode, Json<serde_json::Value>)> {
    let wallet_id = wallet_context.wallet_id;
    
    let since_timestamp = params.since.and_then(|s| {
        chrono::DateTime::parse_from_rfc3339(&s)
            .ok()
            .map(|dt| dt.naive_utc())
    });

    let query = if let Some(since) = since_timestamp {
        sqlx::query(
            r#"
            SELECT event_id, aggregate_type, aggregate_id, event_type, event_data, created_at, event_version
            FROM events
            WHERE wallet_id = $1 AND created_at > $2
            ORDER BY created_at ASC
            "#
        )
        .bind(wallet_id)
        .bind(since)
    } else {
        sqlx::query(
            r#"
            SELECT event_id, aggregate_type, aggregate_id, event_type, event_data, created_at, event_version
            FROM events
            WHERE wallet_id = $1
            ORDER BY created_at ASC
            "#
        )
        .bind(wallet_id)
    };

    let events = query
        .fetch_all(&*state.db_pool)
        .await
        .map_err(|e| {
            tracing::error!("Error fetching events: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to fetch events"})),
            )
        })?;

    let sync_events: Vec<SyncEvent> = events
        .iter()
        .map(|row| {
            SyncEvent {
                id: row.get::<uuid::Uuid, _>("event_id").to_string(),
                aggregate_type: row.get("aggregate_type"),
                aggregate_id: row.get::<uuid::Uuid, _>("aggregate_id").to_string(),
                event_type: row.get("event_type"),
                event_data: row.get("event_data"),
                timestamp: {
                    let naive_dt: chrono::NaiveDateTime = row.get("created_at");
                    chrono::DateTime::<chrono::Utc>::from_naive_utc_and_offset(naive_dt, chrono::Utc).to_rfc3339()
                },
                version: row.get("event_version"),
            }
        })
        .collect();

    Ok(Json(sync_events))
}

#[derive(Deserialize, Clone)]
pub struct SyncEventRequest {
    pub id: String,
    pub aggregate_type: String,
    pub aggregate_id: String,
    pub event_type: String,
    pub event_data: serde_json::Value,
    pub timestamp: String,
    pub version: i32,
}

#[derive(Serialize)]
pub struct SyncEventsResponse {
    pub accepted: Vec<String>,
    pub conflicts: Vec<String>,
}

/// Validate event structure and data
/// Returns error message if validation fails, None if valid
fn validate_event(event: &SyncEventRequest) -> Option<String> {
    // Validate event_type
    let allowed_event_types = ["CREATED", "UPDATED", "DELETED", "UNDO"];
    if !allowed_event_types.contains(&event.event_type.as_str()) {
        return Some(format!(
            "Invalid event_type: '{}'. Allowed values: CREATED, UPDATED, DELETED, UNDO",
            event.event_type
        ));
    }

    // Validate aggregate_type
    let allowed_aggregate_types = ["contact", "transaction"];
    if !allowed_aggregate_types.contains(&event.aggregate_type.as_str()) {
        return Some(format!(
            "Invalid aggregate_type: '{}'. Allowed values: contact, transaction",
            event.aggregate_type
        ));
    }

    // Validate event_data structure based on event_type and aggregate_type
    match event.event_type.as_str() {
        "UNDO" => {
            // UNDO events must have undone_event_id
            if !event.event_data.get("undone_event_id").and_then(|v| v.as_str()).is_some() {
                return Some("UNDO events must have 'undone_event_id' in event_data".to_string());
            }
            // Validate undone_event_id is a valid UUID string
            if let Some(undone_id) = event.event_data.get("undone_event_id").and_then(|v| v.as_str()) {
                if uuid::Uuid::parse_str(undone_id).is_err() {
                    return Some("UNDO event 'undone_event_id' must be a valid UUID".to_string());
                }
            }
            // Note: 5-second validation is done in post_sync_events after we can query the undone event
        }
        "CREATED" | "UPDATED" => {
            match event.aggregate_type.as_str() {
                "contact" => {
                    // CREATED contact must have name
                    if event.event_type == "CREATED" {
                        if !event.event_data.get("name").and_then(|v| v.as_str()).is_some() {
                            return Some("CREATED contact events must have 'name' in event_data".to_string());
                        }
                    }
                    // Optional fields: username, phone, email, notes (no validation needed)
                }
                "transaction" => {
                    // CREATED/UPDATED transaction must have required fields
                    if event.event_data.get("amount").and_then(|v| v.as_i64()).is_none() {
                        return Some("Transaction events must have 'amount' in event_data".to_string());
                    }
                    if !event.event_data.get("direction").and_then(|v| v.as_str()).is_some() {
                        return Some("Transaction events must have 'direction' in event_data".to_string());
                    }
                    if let Some(direction) = event.event_data.get("direction").and_then(|v| v.as_str()) {
                        if direction != "lent" && direction != "owed" {
                            return Some("Transaction 'direction' must be 'lent' or 'owed'".to_string());
                        }
                    }
                    if event.event_type == "CREATED" {
                        if !event.event_data.get("contact_id").and_then(|v| v.as_str()).is_some() {
                            return Some("CREATED transaction events must have 'contact_id' in event_data".to_string());
                        }
                        // Validate contact_id is a valid UUID
                        if let Some(contact_id) = event.event_data.get("contact_id").and_then(|v| v.as_str()) {
                            if uuid::Uuid::parse_str(contact_id).is_err() {
                                return Some("Transaction 'contact_id' must be a valid UUID".to_string());
                            }
                        }
                    }
                    // Optional fields: type, currency, description, transaction_date, due_date (no validation needed)
                }
                _ => {}
            }
        }
        "DELETED" => {
            // DELETED events have no specific requirements (may have comment)
        }
        _ => {}
    }

    None // Validation passed
}

/// Accept events from client and insert them
pub async fn post_sync_events(
    State(state): State<AppState>,
    axum::extract::Extension(wallet_context): axum::extract::Extension<WalletContext>,
    Json(events): Json<Vec<SyncEventRequest>>,
) -> Result<Json<SyncEventsResponse>, (StatusCode, Json<serde_json::Value>)> {
    let wallet_id = wallet_context.wallet_id;
    let mut accepted = Vec::new();
    let mut conflicts = Vec::new();

    // Get user ID
    let user_id = sqlx::query_scalar::<_, uuid::Uuid>(
        "SELECT id FROM users_projection LIMIT 1"
    )
    .fetch_optional(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching user: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    let user_id = user_id.ok_or_else(|| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "No user found"})),
        )
    })?;

    for event in events {
        let event_id = uuid::Uuid::parse_str(&event.id).map_err(|e| {
            (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({"error": format!("Invalid event ID: {}", e)})),
            )
        })?;

        let aggregate_id = uuid::Uuid::parse_str(&event.aggregate_id).map_err(|e| {
            (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({"error": format!("Invalid aggregate ID: {}", e)})),
            )
        })?;

        let timestamp = chrono::DateTime::parse_from_rfc3339(&event.timestamp)
            .map_err(|e| {
                (
                    StatusCode::BAD_REQUEST,
                    Json(serde_json::json!({"error": format!("Invalid timestamp: {}", e)})),
                )
            })?
            .naive_utc();

        // Validate event structure and data
        if let Some(validation_error) = validate_event(&event) {
            let event_id_clone = event.id.clone();
            conflicts.push(event.id);
            tracing::warn!("Event validation failed for {}: {}", event_id_clone, validation_error);
            continue;
        }

        // Special validation for UNDO events: check 5-second window
        // The 5 seconds should be between when the original event was created and when the UNDO event is created
        if event.event_type == "UNDO" {
            if let Some(undone_event_id_str) = event.event_data.get("undone_event_id").and_then(|v| v.as_str()) {
                if let Ok(undone_event_uuid) = uuid::Uuid::parse_str(undone_event_id_str) {
                    // Query the undone event to get its creation timestamp (must be in same wallet)
                    let undone_event = sqlx::query(
                        "SELECT created_at FROM events WHERE event_id = $1 AND wallet_id = $2"
                    )
                    .bind(undone_event_uuid)
                    .bind(wallet_id)
                    .fetch_optional(&*state.db_pool)
                    .await
                    .map_err(|e| {
                        tracing::error!("Error querying undone event: {:?}", e);
                        (
                            StatusCode::INTERNAL_SERVER_ERROR,
                            Json(serde_json::json!({"error": "Database error"})),
                        )
                    })?;

                    if let Some(undone_row) = undone_event {
                        let undone_created_at: chrono::NaiveDateTime = undone_row.get("created_at");
                        let undo_event_created_at = timestamp;
                        
                        // Calculate time difference
                        let time_diff = undo_event_created_at.signed_duration_since(undone_created_at);
                        
                        // Check if more than 5 seconds have passed
                        if time_diff.num_seconds() > 5 {
                            conflicts.push(event.id);
                            tracing::warn!(
                                "UNDO event rejected: original event is too old ({} seconds old, max 5 seconds)",
                                time_diff.num_seconds()
                            );
                            continue;
                        }
                    } else {
                        // Undone event doesn't exist - this is a conflict
                        conflicts.push(event.id);
                        tracing::warn!("UNDO event rejected: undone event {} does not exist", undone_event_id_str);
                        continue;
                    }
                }
            }
        }

        // Check if event already exists (idempotency) - must be in same wallet
        let exists = sqlx::query_scalar::<_, bool>(
            "SELECT EXISTS(SELECT 1 FROM events WHERE event_id = $1 AND wallet_id = $2)"
        )
        .bind(event_id)
        .bind(wallet_id)
        .fetch_one(&*state.db_pool)
        .await
        .map_err(|e| {
            tracing::error!("Error checking event existence: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Database error"})),
            )
        })?;

        if exists {
            // Event already exists - check if it's the same
            let existing = sqlx::query(
                "SELECT event_data, created_at FROM events WHERE event_id = $1 AND wallet_id = $2"
            )
            .bind(event_id)
            .bind(wallet_id)
            .fetch_optional(&*state.db_pool)
            .await
            .map_err(|e| {
                tracing::error!("Error fetching existing event: {:?}", e);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(serde_json::json!({"error": "Database error"})),
                )
            })?;

            if let Some(row) = existing {
                let existing_data: serde_json::Value = row.get("event_data");
                if existing_data != event.event_data {
                    // Conflict: same ID but different data
                    conflicts.push(event.id);
                    continue;
                }
            }
            // Same event - accept it
            accepted.push(event.id);
            continue;
        }

        // Validate wallet_id in event_data matches request wallet_id
        if let Some(event_wallet_id_str) = event.event_data.get("wallet_id").and_then(|v| v.as_str()) {
            if let Ok(event_wallet_id) = uuid::Uuid::parse_str(event_wallet_id_str) {
                if event_wallet_id != wallet_id {
                    conflicts.push(event.id);
                    tracing::warn!("Event wallet_id mismatch: event has {}, request has {}", event_wallet_id, wallet_id);
                    continue;
                }
            }
        } else {
            // If wallet_id is missing from event_data, add it
            // This handles legacy events that don't have wallet_id
        }
        
        // Insert event first (without total_debt - we'll add it after execution)
        let insert_result = sqlx::query(
            r#"
            INSERT INTO events (event_id, user_id, wallet_id, aggregate_type, aggregate_id, event_type, event_version, event_data, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
            ON CONFLICT (event_id) DO NOTHING
            RETURNING event_id
            "#
        )
        .bind(event_id)
        .bind(user_id)
        .bind(wallet_id)
        .bind(&event.aggregate_type)
        .bind(aggregate_id)
        .bind(&event.event_type)
        .bind(event.version)
        .bind(&event.event_data)
        .bind(timestamp)
        .fetch_optional(&*state.db_pool)
        .await;

        match insert_result {
            Ok(Some(_)) => {
                // Event inserted successfully - now apply it and calculate total_debt
                accepted.push(event.id.clone());
                
                // Apply this single event to projections
                if let Err(e) = apply_single_event_to_projections(&state, &event, aggregate_id, user_id, wallet_id, timestamp).await {
                    tracing::error!("Error applying event to projections: {:?}", e);
                    // Continue anyway - event is inserted
                }
                
                // If this is an UNDO event, trigger a full rebuild to ensure consistency (wallet-scoped)
                if event.event_type == "UNDO" {
                    tracing::info!("UNDO event processed, triggering full projection rebuild for wallet {}", wallet_id);
                    if let Err(e) = rebuild_projections_from_events(&state, wallet_id).await {
                        tracing::error!("Error rebuilding projections after UNDO: {:?}", e);
                    }
                }
                
                // Calculate total_debt AFTER this event is applied
                let total_debt_after = calculate_total_debt(&state, wallet_id).await;
                
                // Update this event with total_debt (so event log shows correct running total)
                let update_result = sqlx::query(
                    r#"
                    UPDATE events
                    SET event_data = jsonb_set(COALESCE(event_data, '{}'::jsonb), '{total_debt}', $1::jsonb)
                    WHERE event_id = $2 AND wallet_id = $3
                    "#
                )
                .bind(serde_json::json!(total_debt_after))
                .bind(event_id)
                .bind(wallet_id)
                .execute(&*state.db_pool)
                .await;
                match &update_result {
                    Ok(result) if result.rows_affected() == 0 => {
                        tracing::warn!(
                            "Failed to set total_debt on event {} (0 rows updated); event log may show stale total",
                            event_id
                        );
                    }
                    Err(e) => {
                        tracing::error!("Error updating total_debt on event {}: {:?}", event_id, e);
                    }
                    _ => {}
                }
                
                // Save snapshot if needed (every 10 events or after UNDO)
                if let Ok(Some(event_db_id)) = sqlx::query_scalar::<_, Option<i64>>(
                    "SELECT id FROM events WHERE event_id = $1 AND wallet_id = $2"
                )
                .bind(event_id)
                .bind(wallet_id)
                .fetch_optional(&*state.db_pool)
                .await {
                    if let Some(db_id) = event_db_id {
                        let event_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM events")
                            .fetch_one(&*state.db_pool)
                            .await
                            .unwrap_or(0);
                        
                        let should_save = crate::services::projection_snapshot_service::should_create_snapshot(event_count) 
                            || event.event_type == "UNDO";
                        
                        if should_save {
                            // Create snapshot JSON from current projections
                            if let Ok(snapshot_json) = create_snapshot_json(&state, wallet_id).await {
                                let _ = crate::services::projection_snapshot_service::save_snapshot(
                                    &*state.db_pool,
                                    db_id,
                                    event_count,
                                    snapshot_json.0,
                                    snapshot_json.1,
                                    wallet_id,
                                ).await;
                            }
                        }
                    }
                }
            }
            Ok(None) => {
                // Conflict (duplicate)
                conflicts.push(event.id);
            }
            Err(e) => {
                tracing::error!("Error inserting event: {:?}", e);
                conflicts.push(event.id);
            }
        }
    }

    // Broadcast WebSocket message when events are synced (so other clients get notified immediately)
    if !accepted.is_empty() {
        websocket::broadcast_change(
            &state.broadcast_tx,
            "events_synced",
            &serde_json::json!({
                "accepted_count": accepted.len(),
                "conflicts_count": conflicts.len()
            }).to_string(),
        );
    }

    Ok(Json(SyncEventsResponse {
        accepted,
        conflicts,
    }))
}

/// Rebuild projections from all events in the database for a specific wallet
/// Implements the optimized algorithm:
/// 1. Create projection after any new event
/// 2. Stack of snapshots (push after every 10 events or after UNDO event)
/// 3. If UNDO event: find undone event position, find snapshot before it, create cleaned event list
/// 4. Pass cleaned event list + snapshot to builder
/// 5. Builder creates new snapshot, make it current projection, save to stack
pub async fn rebuild_projections_from_events(state: &AppState, wallet_id: uuid::Uuid) -> Result<(), sqlx::Error> {
    tracing::info!("Rebuilding projections from events for wallet {}...", wallet_id);
    
    // Get user ID (for this wallet, get the first user who has access)
    let user_id = sqlx::query_scalar::<_, uuid::Uuid>(
        "SELECT user_id FROM wallet_users WHERE wallet_id = $1 LIMIT 1"
    )
    .bind(wallet_id)
    .fetch_one(&*state.db_pool)
    .await?;

    // Get all events for this wallet ordered by timestamp (chronological order)
    let events = sqlx::query(
        r#"
        SELECT event_id, aggregate_type, aggregate_id, event_type, event_data, created_at, id
        FROM events
        WHERE wallet_id = $1
        ORDER BY created_at ASC
        "#
    )
    .bind(wallet_id)
    .fetch_all(&*state.db_pool)
    .await?;

    // Get event count and last event info
    let event_count = events.len() as i64;
    let last_event_uuid = events.last().map(|row| row.get::<uuid::Uuid, _>("event_id"));
    let last_event_db_id = events.last().and_then(|row| row.get::<Option<i64>, _>("id"));

    // Build a map of event_id (UUID) -> position (1-based index) for fast lookup
    let mut event_id_to_position: std::collections::HashMap<uuid::Uuid, i64> = std::collections::HashMap::new();
    for (index, row) in events.iter().enumerate() {
        let event_id: uuid::Uuid = row.get("event_id");
        event_id_to_position.insert(event_id, (index + 1) as i64);
    }

    // Check for UNDO events
    let has_undo_events = events.iter().any(|row| {
        let event_type: String = row.get("event_type");
        event_type == "UNDO"
    });

    let used_snapshot = if has_undo_events {
        // Step 3: If UNDO event exists, find undone event positions
        let mut undone_event_positions = Vec::new();
        let mut undone_event_ids = std::collections::HashSet::new();
        
        for row in &events {
            let event_type: String = row.get("event_type");
            if event_type == "UNDO" {
                let event_data: serde_json::Value = row.get("event_data");
                if let Some(undone_id_str) = event_data.get("undone_event_id").and_then(|v| v.as_str()) {
                    if let Ok(undone_id) = uuid::Uuid::parse_str(undone_id_str) {
                        undone_event_ids.insert(undone_id);
                        // Find the undone event's position using the map (fast lookup by ID)
                        if let Some(position) = event_id_to_position.get(&undone_id) {
                            undone_event_positions.push(*position);
                        }
                    }
                }
            }
        }

        // Find the minimum undone event position (earliest undone event)
        let min_undone_position = undone_event_positions.iter().min().copied();

        // Step 4: Search snapshot stack for snapshot with event_count < undone_event_count (wallet-scoped)
        let snapshot = if let Some(target_count) = min_undone_position {
            projection_snapshot_service::get_snapshot_before_event_count(
                &*state.db_pool,
                target_count,
                wallet_id,
            ).await.ok().flatten()
        } else {
            None
        };

        // Step 5: Create cleaned event list (remove UNDO and undone events)
        let cleaned_events: Vec<_> = events.iter()
            .filter(|row| {
                let event_id: uuid::Uuid = row.get("event_id");
                let event_type: String = row.get("event_type");
                
                // Skip UNDO events
                if event_type == "UNDO" {
                    return false;
                }
                
                // Skip undone events
                if undone_event_ids.contains(&event_id) {
                    return false;
                }
                
                true
            })
            .map(|row| row as &sqlx::postgres::PgRow)
            .collect();

        // Step 6: Use snapshot if found, otherwise use full cleaned event list
        if let Some(snapshot) = snapshot {
            // Restore from snapshot (pass undone_event_ids to filter them out)
            if restore_projections_from_snapshot(state, &snapshot, user_id, wallet_id, &undone_event_ids).await.is_ok() {
                // Get events after the snapshot (from cleaned events)
                let snapshot_last_db_id = snapshot.last_event_id;
                let events_after_snapshot: Vec<_> = cleaned_events.iter()
                    .filter(|row| {
                        let event_db_id: Option<i64> = row.get("id");
                        event_db_id.map_or(false, |id| id > snapshot_last_db_id)
                    })
                    .copied()
                    .collect();

                if !events_after_snapshot.is_empty() {
                    // Apply cleaned events after snapshot
                    let mut empty_undone_set = std::collections::HashSet::new();
                    if apply_events_to_projections(state, &events_after_snapshot, user_id, wallet_id, &mut empty_undone_set).await.is_ok() {
                        tracing::info!("Used snapshot optimization with UNDO: {} events after snapshot", events_after_snapshot.len());
                        true
                    } else {
                        false
                    }
                } else {
                    // No events after snapshot, snapshot is current
                    true
                }
            } else {
                false
            }
        } else {
            // No suitable snapshot found, rebuild from scratch with cleaned events
            false
        }
    } else {
        // No UNDO events - use snapshot optimization if available
        if let Some(last_id) = last_event_db_id {
            if let Ok(Some(snapshot)) = projection_snapshot_service::get_snapshot_before_event(
                &*state.db_pool,
                last_id,
                wallet_id,
            ).await {
                // Get events after the snapshot
                let snapshot_last_db_id = snapshot.last_event_id;
                let events_after_snapshot: Vec<_> = events.iter()
                    .filter(|row| {
                        let event_db_id: Option<i64> = row.get("id");
                        event_db_id.map_or(false, |id| id > snapshot_last_db_id)
                    })
                    .map(|row| row as &sqlx::postgres::PgRow)
                    .collect();

                if !events_after_snapshot.is_empty() {
                    // Collect undone event IDs from all events (even if no UNDO in current set, 
                    // snapshot might contain items undone by previous UNDO events)
                        let mut undone_event_ids = std::collections::HashSet::new();
                    for row in &events {
                            let event_type: String = row.get("event_type");
                            if event_type == "UNDO" {
                                let event_data: serde_json::Value = row.get("event_data");
                                if let Some(undone_id_str) = event_data.get("undone_event_id").and_then(|v| v.as_str()) {
                                    if let Ok(undone_id) = uuid::Uuid::parse_str(undone_id_str) {
                                        undone_event_ids.insert(undone_id);
                                    }
                                }
                            }
                        }
                    
                    // Restore projections from snapshot (filter out undone events)
                    if restore_projections_from_snapshot(state, &snapshot, user_id, wallet_id, &undone_event_ids).await.is_ok() {
                        // Apply events after snapshot
                        let mut empty_undone_set = std::collections::HashSet::new();
                        if apply_events_to_projections(state, &events_after_snapshot, user_id, wallet_id, &mut empty_undone_set).await.is_ok() {
                            tracing::info!("Used snapshot for optimization: {} events after snapshot", events_after_snapshot.len());
                            true
                        } else {
                            false
                        }
                    } else {
                        false
                    }
                } else {
                    // No new events, snapshot is current - just restore it
                    // Still need to check for undone events in case snapshot contains undone items
                    let mut undone_event_ids = std::collections::HashSet::new();
                    for row in &events {
                        let event_type: String = row.get("event_type");
                        if event_type == "UNDO" {
                            let event_data: serde_json::Value = row.get("event_data");
                            if let Some(undone_id_str) = event_data.get("undone_event_id").and_then(|v| v.as_str()) {
                                if let Ok(undone_id) = uuid::Uuid::parse_str(undone_id_str) {
                                    undone_event_ids.insert(undone_id);
                                }
                            }
                        }
                    }
                    restore_projections_from_snapshot(state, &snapshot, user_id, wallet_id, &undone_event_ids).await.is_ok()
            }
        } else {
            false
        }
    } else {
        false
        }
    };

    // If snapshot optimization failed or not used, do full rebuild
    if !used_snapshot {
        // Clear existing projections for this wallet (delete transactions first due to foreign key constraints)
        sqlx::query("DELETE FROM transactions_projection WHERE wallet_id = $1")
            .bind(wallet_id)
            .execute(&*state.db_pool)
            .await?;
        
        sqlx::query("DELETE FROM contacts_projection WHERE wallet_id = $1")
            .bind(wallet_id)
            .execute(&*state.db_pool)
            .await?;

        // Collect undone event IDs if UNDO events exist
        let mut undone_event_ids: std::collections::HashSet<uuid::Uuid> = std::collections::HashSet::new();
        if has_undo_events {
        for row in &events {
            let event_type: String = row.get("event_type");
            if event_type == "UNDO" {
                let event_data: serde_json::Value = row.get("event_data");
                if let Some(undone_id_str) = event_data.get("undone_event_id").and_then(|v| v.as_str()) {
                    if let Ok(undone_id) = uuid::Uuid::parse_str(undone_id_str) {
                        undone_event_ids.insert(undone_id);
                    }
                    }
                }
            }
        }

        // Use cleaned events if UNDO events exist, otherwise use all events
        let events_to_process: Vec<_> = if has_undo_events {
            tracing::info!("Filtering events: found {} undone event IDs", undone_event_ids.len());
            let filtered: Vec<_> = events.iter()
                .filter(|row| {
                    let event_id: uuid::Uuid = row.get("event_id");
                    let event_type: String = row.get("event_type");
                    
                    // Skip UNDO events
                    if event_type == "UNDO" {
                        return false;
                    }
                    
                    // Skip undone events
                    if undone_event_ids.contains(&event_id) {
                        tracing::info!("Skipping undone event: {}", event_id);
                        return false;
    }

                    true
                })
                .map(|row| row as &sqlx::postgres::PgRow)
                .collect();
            tracing::info!("After filtering: {} events to process (from {} total)", filtered.len(), events.len());
            filtered
        } else {
            events.iter().map(|row| row as &sqlx::postgres::PgRow).collect()
        };

        // Process events to rebuild projections
        apply_events_to_projections(state, &events_to_process, user_id, wallet_id, &mut undone_event_ids).await?;
    }

    // Step 7: Save snapshot after rebuild if needed (every 10 events or after UNDO)
    if let Some(last_uuid) = last_event_uuid {
        if let Ok(Some(last_event_db_id)) = sqlx::query_scalar::<_, Option<i64>>(
            "SELECT id FROM events WHERE event_id = $1"
        )
        .bind(last_uuid)
        .fetch_optional(&*state.db_pool)
        .await {
            if let Some(db_id) = last_event_db_id {
                let should_save = crate::services::projection_snapshot_service::should_create_snapshot(event_count) 
                    || has_undo_events;
                
                if should_save {
                    if let Ok(snapshot_json) = create_snapshot_json(state, wallet_id).await {
                        let _ = crate::services::projection_snapshot_service::save_snapshot(
                            &*state.db_pool,
                            db_id,
                            event_count,
                            snapshot_json.0,
                            snapshot_json.1,
                            wallet_id,
                        ).await;
                    }
                }
            }
        }
    }

    tracing::info!("Projections rebuilt successfully");
    Ok(())
}

/// Create snapshot JSON from current projections for a wallet
/// Returns (contacts_json, transactions_json)
async fn create_snapshot_json(state: &AppState, wallet_id: uuid::Uuid) -> Result<(serde_json::Value, serde_json::Value), sqlx::Error> {
    // Get all contacts for this wallet
    let contacts = sqlx::query(
        r#"
        SELECT id, user_id, name, username, phone, email, notes, is_deleted, created_at, updated_at
        FROM contacts_projection
        WHERE wallet_id = $1 AND is_deleted = false
        ORDER BY created_at
        "#
    )
    .bind(wallet_id)
    .fetch_all(&*state.db_pool)
    .await?;

    let contacts_json: Vec<serde_json::Value> = contacts
        .iter()
        .map(|row| {
            serde_json::json!({
                "id": row.get::<uuid::Uuid, _>("id").to_string(),
                "name": row.get::<String, _>("name"),
                "username": row.get::<Option<String>, _>("username"),
                "phone": row.get::<Option<String>, _>("phone"),
                "email": row.get::<Option<String>, _>("email"),
                "notes": row.get::<Option<String>, _>("notes"),
                "created_at": row.get::<chrono::NaiveDateTime, _>("created_at").to_string(),
                "updated_at": row.get::<chrono::NaiveDateTime, _>("updated_at").to_string(),
            })
        })
        .collect();

    // Get all transactions for this wallet
    let transactions = sqlx::query(
        r#"
        SELECT id, user_id, contact_id, type, direction, amount, currency, description, 
               transaction_date, due_date, is_deleted, created_at, updated_at
        FROM transactions_projection
        WHERE wallet_id = $1 AND is_deleted = false
        ORDER BY created_at
        "#
    )
    .bind(wallet_id)
    .fetch_all(&*state.db_pool)
    .await?;

    let transactions_json: Vec<serde_json::Value> = transactions
        .iter()
        .map(|row| {
            serde_json::json!({
                "id": row.get::<uuid::Uuid, _>("id").to_string(),
                "contact_id": row.get::<uuid::Uuid, _>("contact_id").to_string(),
                "type": row.get::<String, _>("type"),
                "direction": row.get::<String, _>("direction"),
                "amount": row.get::<i64, _>("amount"),
                "currency": row.get::<Option<String>, _>("currency"),
                "description": row.get::<Option<String>, _>("description"),
                "transaction_date": row.get::<chrono::NaiveDate, _>("transaction_date").to_string(),
                "due_date": row.get::<Option<chrono::NaiveDate>, _>("due_date")
                    .map(|d| d.to_string()),
                "created_at": row.get::<chrono::NaiveDateTime, _>("created_at").to_string(),
                "updated_at": row.get::<chrono::NaiveDateTime, _>("updated_at").to_string(),
            })
        })
        .collect();

    Ok((serde_json::json!(contacts_json), serde_json::json!(transactions_json)))
}

/// Restore projections from snapshot JSON
/// undone_event_ids: Set of event IDs that were undone - transactions/contacts created by these events should be excluded
async fn restore_projections_from_snapshot(
    state: &AppState,
    snapshot: &projection_snapshot_service::ProjectionSnapshot,
    user_id: uuid::Uuid,
    wallet_id: uuid::Uuid,
    undone_event_ids: &std::collections::HashSet<uuid::Uuid>,
) -> Result<(), sqlx::Error> {
    // Clear existing projections for this wallet
    sqlx::query("DELETE FROM transactions_projection WHERE wallet_id = $1")
        .bind(wallet_id)
        .execute(&*state.db_pool)
        .await?;
    
    sqlx::query("DELETE FROM contacts_projection WHERE wallet_id = $1")
        .bind(wallet_id)
        .execute(&*state.db_pool)
        .await?;

    // Get all undone aggregate IDs (transactions/contacts that were created by undone events)
    let mut undone_transaction_ids = std::collections::HashSet::new();
    let mut undone_contact_ids = std::collections::HashSet::new();
    
    if !undone_event_ids.is_empty() {
        // Find all transactions/contacts created by undone events
        let undone_event_ids_vec: Vec<uuid::Uuid> = undone_event_ids.iter().copied().collect();
        let undone_aggregates = sqlx::query(
            r#"
            SELECT aggregate_type, aggregate_id
            FROM events
            WHERE event_id = ANY($1) AND event_type = 'CREATED'
            "#
        )
        .bind(&undone_event_ids_vec[..])
        .fetch_all(&*state.db_pool)
        .await?;
        
        for row in undone_aggregates {
            let aggregate_type: String = row.get("aggregate_type");
            let aggregate_id: uuid::Uuid = row.get("aggregate_id");
            match aggregate_type.as_str() {
                "transaction" => {
                    undone_transaction_ids.insert(aggregate_id);
                }
                "contact" => {
                    undone_contact_ids.insert(aggregate_id);
                }
                _ => {}
            }
        }
    }

    // Restore contacts from snapshot (excluding undone ones)
    if let Some(contacts_array) = snapshot.contacts_snapshot.as_array() {
        for contact_json in contacts_array {
            let id_str = contact_json.get("id").and_then(|v| v.as_str()).unwrap_or("");
            if let Ok(contact_id) = uuid::Uuid::parse_str(id_str) {
                // Skip if this contact was undone
                if undone_contact_ids.contains(&contact_id) {
                    continue;
                }
                let name = contact_json.get("name").and_then(|v| v.as_str()).unwrap_or("");
                let username = contact_json.get("username").and_then(|v| v.as_str());
                let phone = contact_json.get("phone").and_then(|v| v.as_str());
                let email = contact_json.get("email").and_then(|v| v.as_str());
                let notes = contact_json.get("notes").and_then(|v| v.as_str());
                let created_at_str = contact_json.get("created_at").and_then(|v| v.as_str()).unwrap_or("");
                let updated_at_str = contact_json.get("updated_at").and_then(|v| v.as_str()).unwrap_or("");
                
                let created_at = chrono::NaiveDateTime::parse_from_str(created_at_str, "%Y-%m-%d %H:%M:%S%.f")
                    .unwrap_or_else(|_| chrono::Utc::now().naive_utc());
                let updated_at = chrono::NaiveDateTime::parse_from_str(updated_at_str, "%Y-%m-%d %H:%M:%S%.f")
                    .unwrap_or(created_at);

                sqlx::query(
                    r#"
                    INSERT INTO contacts_projection 
                    (id, user_id, wallet_id, name, username, phone, email, notes, is_deleted, created_at, updated_at, last_event_id)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, false, $9, $10, 0)
                    "#
                )
                .bind(contact_id)
                .bind(user_id)
                .bind(wallet_id)
                .bind(name)
                .bind(username)
                .bind(phone)
                .bind(email)
                .bind(notes)
                .bind(created_at)
                .bind(updated_at)
                .execute(&*state.db_pool)
                .await?;
            }
        }
    }

    // Restore transactions from snapshot (excluding undone ones)
    if let Some(transactions_array) = snapshot.transactions_snapshot.as_array() {
        for transaction_json in transactions_array {
            let id_str = transaction_json.get("id").and_then(|v| v.as_str()).unwrap_or("");
            if let Ok(transaction_id) = uuid::Uuid::parse_str(id_str) {
                // Skip if this transaction was undone
                if undone_transaction_ids.contains(&transaction_id) {
                    continue;
                }
                
                let contact_id_str = transaction_json.get("contact_id").and_then(|v| v.as_str()).unwrap_or("");
                if let Ok(contact_id) = uuid::Uuid::parse_str(contact_id_str) {
                    let tx_type = transaction_json.get("type").and_then(|v| v.as_str()).unwrap_or("money");
                    let direction = transaction_json.get("direction").and_then(|v| v.as_str()).unwrap_or("lent");
                    let amount = transaction_json.get("amount").and_then(|v| v.as_i64()).unwrap_or(0);
                    let currency = transaction_json.get("currency").and_then(|v| v.as_str()).unwrap_or("USD");
                    let description = transaction_json.get("description").and_then(|v| v.as_str());
                    let transaction_date_str = transaction_json.get("transaction_date").and_then(|v| v.as_str()).unwrap_or("");
                    let due_date_str = transaction_json.get("due_date").and_then(|v| v.as_str());
                    let created_at_str = transaction_json.get("created_at").and_then(|v| v.as_str()).unwrap_or("");
                    let updated_at_str = transaction_json.get("updated_at").and_then(|v| v.as_str()).unwrap_or("");
                    
                    let transaction_date = if !transaction_date_str.is_empty() {
                        chrono::NaiveDate::parse_from_str(transaction_date_str, "%Y-%m-%d").ok()
                    } else {
                        None
                    };
                    
                    let due_date = due_date_str.and_then(|d| {
                        chrono::NaiveDate::parse_from_str(d, "%Y-%m-%d").ok()
                    });
                    
                    let created_at = chrono::NaiveDateTime::parse_from_str(created_at_str, "%Y-%m-%d %H:%M:%S%.f")
                        .unwrap_or_else(|_| chrono::Utc::now().naive_utc());
                    let updated_at = chrono::NaiveDateTime::parse_from_str(updated_at_str, "%Y-%m-%d %H:%M:%S%.f")
                        .unwrap_or(created_at);

                    if let Some(txn_date) = transaction_date {
                        sqlx::query(
                            r#"
                            INSERT INTO transactions_projection 
                            (id, user_id, wallet_id, contact_id, type, direction, amount, currency, description, transaction_date, due_date, is_deleted, created_at, updated_at, last_event_id)
                            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, false, $12, $13, 0)
                            "#
                        )
                        .bind(transaction_id)
                        .bind(user_id)
                        .bind(wallet_id)
                        .bind(contact_id)
                        .bind(tx_type)
                        .bind(direction)
                        .bind(amount)
                        .bind(currency)
                        .bind(description)
                        .bind(txn_date)
                        .bind(due_date)
                        .bind(created_at)
                        .bind(updated_at)
                        .execute(&*state.db_pool)
                        .await?;
                    }
                }
            }
        }
    }

    Ok(())
}

/// Apply events to projections (helper function for both full rebuild and snapshot-based rebuild)
async fn apply_events_to_projections(
    state: &AppState,
    events: &[&sqlx::postgres::PgRow],
    user_id: uuid::Uuid,
    wallet_id: uuid::Uuid,
    undone_event_ids: &mut std::collections::HashSet<uuid::Uuid>,
) -> Result<(), sqlx::Error> {
    // First pass: collect UNDO events if not already collected
    if undone_event_ids.is_empty() {
        for row in events.iter() {
            let event_type: String = row.get("event_type");
            if event_type == "UNDO" {
                let event_data: serde_json::Value = row.get("event_data");
                if let Some(undone_id_str) = event_data.get("undone_event_id").and_then(|v| v.as_str()) {
                    if let Ok(undone_id) = uuid::Uuid::parse_str(undone_id_str) {
                        undone_event_ids.insert(undone_id);
                    }
                }
            }
        }
    }

    // Second pass: apply events (skipping UNDO events and undone events)
    for row in events {
        let event_id: uuid::Uuid = row.get("event_id");
        let aggregate_type: String = row.get("aggregate_type");
        let aggregate_id: uuid::Uuid = row.get("aggregate_id");
        let event_type: String = row.get("event_type");
        let event_data: serde_json::Value = row.get("event_data");
        let created_at: chrono::NaiveDateTime = row.get("created_at");

        // Skip UNDO events (they don't modify projections directly)
        if event_type == "UNDO" {
            continue;
        }

        // Skip events that have been undone
        if undone_event_ids.contains(&event_id) {
            continue;
        }

        // Apply event (same logic as full rebuild)
        if aggregate_type == "contact" {
            match event_type.as_str() {
                "CREATED" => {
                    let name = event_data.get("name").and_then(|v| v.as_str()).unwrap_or("");
                    let username = event_data.get("username").and_then(|v| v.as_str());
                    let phone = event_data.get("phone").and_then(|v| v.as_str());
                    let email = event_data.get("email").and_then(|v| v.as_str());
                    let notes = event_data.get("notes").and_then(|v| v.as_str());

                    sqlx::query(
                        r#"
                        INSERT INTO contacts_projection 
                        (id, user_id, wallet_id, name, username, phone, email, notes, is_deleted, created_at, updated_at, last_event_id)
                        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, false, $9, $9, 0)
                        ON CONFLICT (id) DO UPDATE SET
                            name = EXCLUDED.name,
                            username = EXCLUDED.username,
                            phone = EXCLUDED.phone,
                            email = EXCLUDED.email,
                            notes = EXCLUDED.notes,
                            updated_at = EXCLUDED.updated_at
                        "#
                    )
                    .bind(aggregate_id)
                    .bind(user_id)
                    .bind(wallet_id)
                    .bind(name)
                    .bind(username)
                    .bind(phone)
                    .bind(email)
                    .bind(notes)
                    .bind(created_at)
                    .execute(&*state.db_pool)
                    .await?;
                }
                "UPDATED" => {
                    let current = sqlx::query(
                        "SELECT name, username, phone, email, notes FROM contacts_projection WHERE id = $1 AND wallet_id = $2"
                    )
                    .bind(aggregate_id)
                    .bind(wallet_id)
                    .fetch_optional(&*state.db_pool)
                    .await?;

                    if let Some(current_row) = current {
                        let current_name: String = current_row.get("name");
                        let current_username: Option<String> = current_row.get("username");
                        let current_phone: Option<String> = current_row.get("phone");
                        let current_email: Option<String> = current_row.get("email");
                        let current_notes: Option<String> = current_row.get("notes");

                        let name = event_data.get("name").and_then(|v| v.as_str()).unwrap_or(&current_name);
                        let username = event_data.get("username").and_then(|v| v.as_str()).or(current_username.as_deref());
                        let phone = event_data.get("phone").and_then(|v| v.as_str()).or(current_phone.as_deref());
                        let email = event_data.get("email").and_then(|v| v.as_str()).or(current_email.as_deref());
                        let notes = event_data.get("notes").and_then(|v| v.as_str()).or(current_notes.as_deref());

                        sqlx::query(
                            r#"
                            UPDATE contacts_projection SET
                                name = $2,
                                username = $3,
                                phone = $4,
                                email = $5,
                                notes = $6,
                                updated_at = $7
                            WHERE id = $1 AND wallet_id = $8
                            "#
                        )
                        .bind(aggregate_id)
                        .bind(wallet_id)
                        .bind(name)
                        .bind(username)
                        .bind(phone)
                        .bind(email)
                        .bind(notes)
                        .bind(created_at)
                        .execute(&*state.db_pool)
                        .await?;
                    }
                }
                "DELETED" => {
                    // Mark contact as deleted
                    sqlx::query(
                        "UPDATE contacts_projection SET is_deleted = true, updated_at = $2 WHERE id = $1 AND wallet_id = $3"
                    )
                    .bind(aggregate_id)
                    .bind(created_at)
                    .bind(wallet_id)
                    .execute(&*state.db_pool)
                    .await?;
                    
                    // Also delete all transactions that reference this deleted contact
                    // This ensures data consistency: deleted contacts don't leave orphaned transactions
                    let deleted_transactions = sqlx::query(
                        "UPDATE transactions_projection SET is_deleted = true, updated_at = $1 WHERE contact_id = $2 AND wallet_id = $3 AND is_deleted = false"
                    )
                    .bind(created_at)
                    .bind(aggregate_id)
                    .bind(wallet_id)
                    .execute(&*state.db_pool)
                    .await?;
                    
                    if deleted_transactions.rows_affected() > 0 {
                        tracing::info!("Deleted {} transaction(s) for deleted contact {}", deleted_transactions.rows_affected(), aggregate_id);
                    }
                }
                _ => {}
            }
        } else if aggregate_type == "transaction" {
            match event_type.as_str() {
                "CREATED" | "TRANSACTION_CREATED" => {
                    let contact_id_str = event_data.get("contact_id").and_then(|v| v.as_str()).unwrap_or("");
                    let contact_id = uuid::Uuid::parse_str(contact_id_str).ok();
                    
                    // Only create transaction if contact exists and is not deleted
                    // If contact was deleted, its transactions should also be ignored/deleted
                    if let Some(cid) = contact_id {
                        // Check if contact exists and is not deleted
                        let contact_exists = sqlx::query_scalar::<_, bool>(
                            "SELECT EXISTS(SELECT 1 FROM contacts_projection WHERE id = $1 AND wallet_id = $2 AND is_deleted = false)"
                        )
                        .bind(cid)
                        .bind(wallet_id)
                        .fetch_one(&*state.db_pool)
                        .await?;
                        
                        if !contact_exists {
                            tracing::warn!("Skipping transaction creation for deleted contact {}", cid);
                            continue;
                        }
                        let tx_type = event_data.get("type").and_then(|v| v.as_str()).unwrap_or("money");
                        let direction = event_data.get("direction").and_then(|v| v.as_str()).unwrap_or("lent");
                        let amount = event_data.get("amount").and_then(|v| v.as_i64()).unwrap_or(0);
                        let currency = event_data.get("currency").and_then(|v| v.as_str()).unwrap_or("USD");
                        let description = event_data.get("description").and_then(|v| v.as_str());
                        let transaction_date_str = event_data.get("transaction_date").and_then(|v| v.as_str()).unwrap_or("");
                        let due_date_str = event_data.get("due_date").and_then(|v| v.as_str());
                        
                        let transaction_date = if !transaction_date_str.is_empty() {
                            chrono::NaiveDate::parse_from_str(transaction_date_str, "%Y-%m-%d").ok()
                        } else {
                            Some(created_at.date())
                        };
                        
                        let due_date = due_date_str.and_then(|d| {
                            chrono::NaiveDate::parse_from_str(d, "%Y-%m-%d").ok()
                        });

                        if let Some(txn_date) = transaction_date {
                            sqlx::query(
                                r#"
                                INSERT INTO transactions_projection 
                                (id, user_id, wallet_id, contact_id, type, direction, amount, currency, description, transaction_date, due_date, is_deleted, created_at, updated_at, last_event_id)
                                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, false, $12, $12, 0)
                                ON CONFLICT (id) DO UPDATE SET
                                    contact_id = EXCLUDED.contact_id,
                                    type = EXCLUDED.type,
                                    direction = EXCLUDED.direction,
                                    amount = EXCLUDED.amount,
                                    currency = EXCLUDED.currency,
                                    description = EXCLUDED.description,
                                    transaction_date = EXCLUDED.transaction_date,
                                    due_date = EXCLUDED.due_date,
                                    updated_at = EXCLUDED.updated_at
                                "#
                            )
                            .bind(aggregate_id)
                            .bind(user_id)
                            .bind(wallet_id)
                            .bind(cid)
                            .bind(tx_type)
                            .bind(direction)
                            .bind(amount)
                            .bind(currency)
                            .bind(description)
                            .bind(txn_date)
                            .bind(due_date)
                            .bind(created_at)
                            .execute(&*state.db_pool)
                            .await?;
                        }
                    }
                }
                "UPDATED" => {
                    let current = sqlx::query(
                        "SELECT contact_id, type, direction, amount, currency, description, transaction_date, due_date FROM transactions_projection WHERE id = $1 AND wallet_id = $2"
                    )
                    .bind(aggregate_id)
                    .bind(wallet_id)
                    .fetch_optional(&*state.db_pool)
                    .await?;

                    if let Some(current_row) = current {
                        let current_contact_id: uuid::Uuid = current_row.get("contact_id");
                        let current_type: String = current_row.get("type");
                        let current_direction: String = current_row.get("direction");
                        let current_amount: i64 = current_row.get("amount");
                        let current_currency: String = current_row.get("currency");
                        let current_description: Option<String> = current_row.get("description");
                        let current_transaction_date: chrono::NaiveDate = current_row.get("transaction_date");
                        let current_due_date: Option<chrono::NaiveDate> = current_row.get("due_date");

                        let contact_id_str = event_data.get("contact_id").and_then(|v| v.as_str());
                        let contact_id = contact_id_str
                            .and_then(|s| uuid::Uuid::parse_str(s).ok())
                            .unwrap_or(current_contact_id);
                        
                        let tx_type = event_data.get("type").and_then(|v| v.as_str()).unwrap_or(&current_type);
                        let direction = event_data.get("direction").and_then(|v| v.as_str()).unwrap_or(&current_direction);
                        let amount = event_data.get("amount").and_then(|v| v.as_i64()).unwrap_or(current_amount);
                        let currency = event_data.get("currency").and_then(|v| v.as_str()).unwrap_or(&current_currency);
                        let description = event_data.get("description").and_then(|v| v.as_str()).or(current_description.as_deref());
                        
                        let transaction_date_str = event_data.get("transaction_date").and_then(|v| v.as_str());
                        let transaction_date = transaction_date_str
                            .and_then(|d| chrono::NaiveDate::parse_from_str(d, "%Y-%m-%d").ok())
                            .unwrap_or(current_transaction_date);
                        
                        let due_date_str = event_data.get("due_date").and_then(|v| v.as_str());
                        let due_date = due_date_str
                            .and_then(|d| chrono::NaiveDate::parse_from_str(d, "%Y-%m-%d").ok())
                            .or(current_due_date);

                        sqlx::query(
                            r#"
                            UPDATE transactions_projection SET
                                contact_id = $2,
                                type = $3,
                                direction = $4,
                                amount = $5,
                                currency = $6,
                                description = $7,
                                transaction_date = $8,
                                due_date = $9,
                                updated_at = $10
                            WHERE id = $1 AND wallet_id = $11
                            "#
                        )
                        .bind(aggregate_id)
                        .bind(wallet_id)
                        .bind(contact_id)
                        .bind(tx_type)
                        .bind(direction)
                        .bind(amount)
                        .bind(currency)
                        .bind(description)
                        .bind(transaction_date)
                        .bind(due_date)
                        .bind(created_at)
                        .execute(&*state.db_pool)
                        .await?;
                    }
                }
                "DELETED" => {
                    sqlx::query(
                        "UPDATE transactions_projection SET is_deleted = true, updated_at = $2 WHERE id = $1 AND wallet_id = $3"
                    )
                    .bind(aggregate_id)
                    .bind(created_at)
                    .bind(wallet_id)
                    .execute(&*state.db_pool)
                    .await?;
                }
                _ => {}
            }
        }
    }

    Ok(())
}

/// Apply a single event to projections (for incremental updates during sync)
async fn apply_single_event_to_projections(
    state: &AppState,
    event: &SyncEventRequest,
    aggregate_id: uuid::Uuid,
    user_id: uuid::Uuid,
    wallet_id: uuid::Uuid,
    created_at: chrono::NaiveDateTime,
) -> Result<(), sqlx::Error> {
    // UNDO events need to remove the undone event's effects from projections
    if event.event_type == "UNDO" {
        let event_data = &event.event_data;
        if let Some(undone_id_str) = event_data.get("undone_event_id").and_then(|v| v.as_str()) {
            if let Ok(undone_event_id) = uuid::Uuid::parse_str(undone_id_str) {
                // Find the undone event to determine what to remove
                let undone_event = sqlx::query(
                    r#"
                    SELECT aggregate_type, aggregate_id, event_type
                    FROM events
                    WHERE event_id = $1
                    "#
                )
                .bind(undone_event_id)
                .fetch_optional(&*state.db_pool)
                .await?;

                if let Some(undone_row) = undone_event {
                    let undone_aggregate_type: String = undone_row.get("aggregate_type");
                    let undone_aggregate_id: uuid::Uuid = undone_row.get("aggregate_id");
                    let undone_event_type: String = undone_row.get("event_type");

                    tracing::info!("Processing UNDO: removing {} {} event for aggregate {}", 
                        undone_event_type, undone_aggregate_type, undone_aggregate_id);

                    // Remove the undone event's effects from projections
                    match undone_aggregate_type.as_str() {
                        "transaction" => {
                            // If the undone event was a transaction CREATED, remove the transaction
                            if undone_event_type == "CREATED" || undone_event_type == "TRANSACTION_CREATED" {
                                let deleted = sqlx::query(
                                    "DELETE FROM transactions_projection WHERE id = $1 AND wallet_id = $2"
                                )
                                .bind(undone_aggregate_id)
                                .bind(wallet_id)
                                .execute(&*state.db_pool)
                                .await?;
                                
                                tracing::info!("Deleted {} transaction(s) from projection", deleted.rows_affected());
                            } else if undone_event_type == "UPDATED" {
                                // For UPDATED events, we need to restore the previous state
                                // This is complex - for now, trigger a full rebuild
                                tracing::warn!("UNDO of transaction UPDATED event - triggering rebuild");
                                // Note: Full rebuild will handle this correctly
                            }
                        }
                        "contact" => {
                            // If the undone event was a contact CREATED, remove the contact
                            if undone_event_type == "CREATED" {
                                let deleted = sqlx::query(
                                    "DELETE FROM contacts_projection WHERE id = $1 AND wallet_id = $2"
                                )
                                .bind(undone_aggregate_id)
                                .bind(wallet_id)
                                .execute(&*state.db_pool)
                                .await?;
                                
                                tracing::info!("Deleted {} contact(s) from projection", deleted.rows_affected());
                            } else if undone_event_type == "UPDATED" {
                                // For UPDATED events, we need to restore the previous state
                                // This is complex - for now, trigger a full rebuild
                                tracing::warn!("UNDO of contact UPDATED event - triggering rebuild");
                                // Note: Full rebuild will handle this correctly
                            }
                        }
                        _ => {
                            tracing::warn!("UNDO event for unknown aggregate type: {}", undone_aggregate_type);
                        }
                    }
                } else {
                    tracing::warn!("UNDO event references non-existent event: {}", undone_id_str);
                }
            } else {
                tracing::warn!("UNDO event has invalid undone_event_id UUID: {}", undone_id_str);
            }
        } else {
            tracing::warn!("UNDO event missing undone_event_id in event_data");
        }
        return Ok(());
    }

    // Check if this event has been undone by checking for UNDO events
    let event_id = uuid::Uuid::parse_str(&event.id).map_err(|_| sqlx::Error::RowNotFound)?;
    let undone_check = sqlx::query_scalar::<_, bool>(
        r#"
        SELECT EXISTS(
            SELECT 1 FROM events 
            WHERE event_type = 'UNDO' 
            AND event_data->>'undone_event_id' = $1
        )
        "#
    )
    .bind(event_id.to_string())
    .fetch_one(&*state.db_pool)
    .await?;

    if undone_check {
        // This event has been undone, skip it
        return Ok(());
    }

    let event_data = &event.event_data;
    
    match event.aggregate_type.as_str() {
        "contact" => {
            match event.event_type.as_str() {
                "CREATED" => {
                    let name = event_data.get("name")
                        .and_then(|v| v.as_str())
                        .ok_or_else(|| sqlx::Error::RowNotFound)?;
                    
                    sqlx::query(
                        r#"
                        INSERT INTO contacts_projection 
                        (id, user_id, wallet_id, name, username, phone, email, notes, is_deleted, created_at, updated_at, last_event_id)
                        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, false, $9, $9, 0)
                        ON CONFLICT (id) DO UPDATE SET
                            name = EXCLUDED.name,
                            username = EXCLUDED.username,
                            phone = EXCLUDED.phone,
                            email = EXCLUDED.email,
                            notes = EXCLUDED.notes,
                            updated_at = EXCLUDED.updated_at
                        "#
                    )
                    .bind(aggregate_id)
                    .bind(user_id)
                    .bind(wallet_id)
                    .bind(name)
                    .bind(event_data.get("username").and_then(|v| v.as_str()))
                    .bind(event_data.get("phone").and_then(|v| v.as_str()))
                    .bind(event_data.get("email").and_then(|v| v.as_str()))
                    .bind(event_data.get("notes").and_then(|v| v.as_str()))
                    .bind(created_at)
                    .execute(&*state.db_pool)
                    .await?;
                }
                "UPDATED" => {
                    sqlx::query(
                        r#"
                        UPDATE contacts_projection 
                        SET name = COALESCE($1, name),
                            username = COALESCE($2, username),
                            phone = COALESCE($3, phone),
                            email = COALESCE($4, email),
                            notes = COALESCE($5, notes),
                            updated_at = $6
                        WHERE id = $7 AND wallet_id = $8
                        "#
                    )
                    .bind(event_data.get("name").and_then(|v| v.as_str()))
                    .bind(event_data.get("username").and_then(|v| v.as_str()))
                    .bind(event_data.get("phone").and_then(|v| v.as_str()))
                    .bind(event_data.get("email").and_then(|v| v.as_str()))
                    .bind(event_data.get("notes").and_then(|v| v.as_str()))
                    .bind(created_at)
                    .bind(aggregate_id)
                    .bind(wallet_id)
                    .execute(&*state.db_pool)
                    .await?;
                }
                "DELETED" => {
                    // Mark contact as deleted
                    sqlx::query(
                        "UPDATE contacts_projection SET is_deleted = true, updated_at = $1 WHERE id = $2 AND wallet_id = $3"
                    )
                    .bind(created_at)
                    .bind(aggregate_id)
                    .bind(wallet_id)
                    .execute(&*state.db_pool)
                    .await?;
                    
                    // Also delete all transactions that reference this deleted contact
                    // This ensures data consistency: deleted contacts don't leave orphaned transactions
                    let deleted_transactions = sqlx::query(
                        "UPDATE transactions_projection SET is_deleted = true, updated_at = $1 WHERE contact_id = $2 AND wallet_id = $3 AND is_deleted = false"
                    )
                    .bind(created_at)
                    .bind(aggregate_id)
                    .bind(wallet_id)
                    .execute(&*state.db_pool)
                    .await?;
                    
                    if deleted_transactions.rows_affected() > 0 {
                        tracing::info!("Deleted {} transaction(s) for deleted contact {}", deleted_transactions.rows_affected(), aggregate_id);
                    }
                }
                _ => {}
            }
        }
        "transaction" => {
            match event.event_type.as_str() {
                "CREATED" => {
                    // Get contact_id first to check if contact exists
                    let contact_id = event_data.get("contact_id")
                        .and_then(|v| v.as_str())
                        .and_then(|s| uuid::Uuid::parse_str(s).ok())
                        .ok_or_else(|| sqlx::Error::RowNotFound)?;
                    
                    // Only create transaction if contact exists and is not deleted
                    // If contact was deleted, its transactions should also be ignored/deleted
                    let contact_exists = sqlx::query_scalar::<_, bool>(
                        "SELECT EXISTS(SELECT 1 FROM contacts_projection WHERE id = $1 AND wallet_id = $2 AND is_deleted = false)"
                    )
                    .bind(contact_id)
                    .bind(wallet_id)
                    .fetch_one(&*state.db_pool)
                    .await?;
                    
                    if !contact_exists {
                        tracing::warn!("Skipping transaction creation for deleted contact {}", contact_id);
                        return Ok(());
                    }
                    
                    let amount = event_data.get("amount")
                        .and_then(|v| v.as_i64())
                        .ok_or_else(|| sqlx::Error::RowNotFound)?;
                    let direction = event_data.get("direction")
                        .and_then(|v| v.as_str())
                        .ok_or_else(|| sqlx::Error::RowNotFound)?;
                    let txn_type = event_data.get("type")
                        .and_then(|v| v.as_str())
                        .unwrap_or("money");
                    
                    let transaction_date = event_data.get("transaction_date")
                        .and_then(|v| v.as_str())
                        .and_then(|s| chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d").ok())
                        .unwrap_or_else(|| created_at.date());
                    
                    let due_date = event_data.get("due_date")
                        .and_then(|v| v.as_str())
                        .and_then(|s| chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d").ok());
                    
                    sqlx::query(
                        r#"
                        INSERT INTO transactions_projection 
                        (id, user_id, wallet_id, contact_id, type, direction, amount, currency, description, transaction_date, due_date, is_deleted, created_at, updated_at, last_event_id)
                        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, false, $12, $12, 0)
                        ON CONFLICT (id) DO UPDATE SET
                            contact_id = EXCLUDED.contact_id,
                            type = EXCLUDED.type,
                            direction = EXCLUDED.direction,
                            amount = EXCLUDED.amount,
                            currency = EXCLUDED.currency,
                            description = EXCLUDED.description,
                            transaction_date = EXCLUDED.transaction_date,
                            due_date = EXCLUDED.due_date,
                            updated_at = EXCLUDED.updated_at
                        "#
                    )
                    .bind(aggregate_id)
                    .bind(user_id)
                    .bind(wallet_id)
                    .bind(contact_id)
                    .bind(txn_type)
                    .bind(direction)
                    .bind(amount)
                    .bind(event_data.get("currency").and_then(|v| v.as_str()).unwrap_or("USD"))
                    .bind(event_data.get("description").and_then(|v| v.as_str()))
                    .bind(transaction_date)
                    .bind(due_date)
                    .bind(created_at)
                    .execute(&*state.db_pool)
                    .await?;
                }
                "UPDATED" => {
                    let amount = event_data.get("amount")
                        .and_then(|v| v.as_i64())
                        .ok_or_else(|| sqlx::Error::RowNotFound)?;
                    let direction = event_data.get("direction")
                        .and_then(|v| v.as_str())
                        .ok_or_else(|| sqlx::Error::RowNotFound)?;
                    let txn_type = event_data.get("type")
                        .and_then(|v| v.as_str())
                        .unwrap_or("money");
                    
                    let contact_id = event_data.get("contact_id")
                        .and_then(|v| v.as_str())
                        .and_then(|s| uuid::Uuid::parse_str(s).ok())
                        .ok_or_else(|| sqlx::Error::RowNotFound)?;
                    
                    let transaction_date = event_data.get("transaction_date")
                        .and_then(|v| v.as_str())
                        .and_then(|s| chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d").ok())
                        .unwrap_or_else(|| created_at.date());
                    
                    let due_date = event_data.get("due_date")
                        .and_then(|v| v.as_str())
                        .and_then(|s| chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d").ok());
                    
                    sqlx::query(
                        r#"
                        UPDATE transactions_projection 
                        SET contact_id = $1, type = $2, direction = $3, amount = $4, currency = $5, 
                            description = $6, transaction_date = $7, due_date = $8, updated_at = $9
                        WHERE id = $10 AND wallet_id = $11
                        "#
                    )
                    .bind(contact_id)
                    .bind(txn_type)
                    .bind(direction)
                    .bind(amount)
                    .bind(event_data.get("currency").and_then(|v| v.as_str()).unwrap_or("USD"))
                    .bind(event_data.get("description").and_then(|v| v.as_str()))
                    .bind(transaction_date)
                    .bind(due_date)
                    .bind(created_at)
                    .bind(aggregate_id)
                    .bind(wallet_id)
                    .execute(&*state.db_pool)
                    .await?;
                }
                "DELETED" => {
                    sqlx::query(
                        "UPDATE transactions_projection SET is_deleted = true, updated_at = $1 WHERE id = $2 AND wallet_id = $3"
                    )
                    .bind(created_at)
                    .bind(aggregate_id)
                    .bind(wallet_id)
                    .execute(&*state.db_pool)
                    .await?;
                }
                _ => {}
            }
        }
        _ => {}
    }
    
    Ok(())
}
