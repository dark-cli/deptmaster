use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use crate::AppState;
use crate::websocket;
use crate::services::projection_snapshot_service;
use sha2::{Sha256, Digest};

/// Calculate total debt (sum of all contact balances) at current time
async fn calculate_total_debt(state: &AppState) -> i64 {
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
        LEFT JOIN transactions_projection t ON t.contact_id = c.id AND t.is_deleted = false
        WHERE c.is_deleted = false
        "#
    )
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
) -> Result<Json<SyncHashResponse>, (StatusCode, Json<serde_json::Value>)> {
    // Get all events ordered by timestamp
    let events = sqlx::query(
        r#"
        SELECT event_id, aggregate_type, aggregate_id, event_type, created_at
        FROM events
        ORDER BY created_at ASC
        "#
    )
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
) -> Result<Json<Vec<SyncEvent>>, (StatusCode, Json<serde_json::Value>)> {
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
            WHERE created_at > $1
            ORDER BY created_at ASC
            "#
        )
        .bind(since)
    } else {
        sqlx::query(
            r#"
            SELECT event_id, aggregate_type, aggregate_id, event_type, event_data, created_at, event_version
            FROM events
            ORDER BY created_at ASC
            "#
        )
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
    Json(events): Json<Vec<SyncEventRequest>>,
) -> Result<Json<SyncEventsResponse>, (StatusCode, Json<serde_json::Value>)> {
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
                    // Query the undone event to get its creation timestamp
                    let undone_event = sqlx::query(
                        "SELECT created_at FROM events WHERE event_id = $1"
                    )
                    .bind(undone_event_uuid)
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

        // Check if event already exists (idempotency)
        let exists = sqlx::query_scalar::<_, bool>(
            "SELECT EXISTS(SELECT 1 FROM events WHERE event_id = $1)"
        )
        .bind(event_id)
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
                "SELECT event_data, created_at FROM events WHERE event_id = $1"
            )
            .bind(event_id)
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

        // Insert event first (without total_debt - we'll add it after execution)
        let insert_result = sqlx::query(
            r#"
            INSERT INTO events (event_id, user_id, aggregate_type, aggregate_id, event_type, event_version, event_data, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            ON CONFLICT (event_id) DO NOTHING
            RETURNING event_id
            "#
        )
        .bind(event_id)
        .bind(user_id)
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
                if let Err(e) = apply_single_event_to_projections(&state, &event, aggregate_id, user_id, timestamp).await {
                    tracing::error!("Error applying event to projections: {:?}", e);
                    // Continue anyway - event is inserted
                }
                
                // Calculate total_debt AFTER this event is applied
                let total_debt_after = calculate_total_debt(&state).await;
                
                // Update this event with total_debt
                sqlx::query(
                    r#"
                    UPDATE events
                    SET event_data = jsonb_set(event_data, '{total_debt}', $1::jsonb)
                    WHERE event_id = $2
                    "#
                )
                .bind(serde_json::json!(total_debt_after))
                .bind(event_id)
                .execute(&*state.db_pool)
                .await
                .ok(); // Don't fail if update fails
                
                // Save snapshot if needed (every 10 events or after UNDO)
                if let Ok(Some(event_db_id)) = sqlx::query_scalar::<_, Option<i64>>(
                    "SELECT id FROM events WHERE event_id = $1"
                )
                .bind(event_id)
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
                            if let Ok(snapshot_json) = create_snapshot_json(&state).await {
                                let _ = crate::services::projection_snapshot_service::save_snapshot(
                                    &*state.db_pool,
                                    db_id,
                                    event_count,
                                    snapshot_json.0,
                                    snapshot_json.1,
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

/// Rebuild projections from all events in the database
pub async fn rebuild_projections_from_events(state: &AppState) -> Result<(), sqlx::Error> {
    tracing::info!("Rebuilding projections from events...");
    
    // Get user ID
    let user_id = sqlx::query_scalar::<_, uuid::Uuid>(
        "SELECT id FROM users_projection LIMIT 1"
    )
    .fetch_one(&*state.db_pool)
    .await?;

    // Get all events ordered by timestamp
    let events = sqlx::query(
        r#"
        SELECT event_id, aggregate_type, aggregate_id, event_type, event_data, created_at
        FROM events
        ORDER BY created_at ASC
        "#
    )
    .fetch_all(&*state.db_pool)
    .await?;

    // Get event count and last event info before processing (events will be moved in loop)
    let event_count = events.len() as i64;
    let last_event_uuid = events.last().map(|row| row.get::<uuid::Uuid, _>("event_id"));

    // Clear existing projections (delete transactions first due to foreign key constraints)
    sqlx::query("DELETE FROM transactions_projection WHERE true")
        .execute(&*state.db_pool)
        .await?;
    
    sqlx::query("DELETE FROM contacts_projection WHERE true")
        .execute(&*state.db_pool)
        .await?;

    // First pass: collect UNDO events to know which events to skip
    let mut undone_event_ids: std::collections::HashSet<uuid::Uuid> = std::collections::HashSet::new();
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

    // Process events to rebuild projections (skipping undone events)
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

        if aggregate_type == "contact" {
            match event_type.as_str() {
                "CREATED" => {
                    // Extract contact data from event
                    let name = event_data.get("name").and_then(|v| v.as_str()).unwrap_or("");
                    let username = event_data.get("username").and_then(|v| v.as_str());
                    let phone = event_data.get("phone").and_then(|v| v.as_str());
                    let email = event_data.get("email").and_then(|v| v.as_str());
                    let notes = event_data.get("notes").and_then(|v| v.as_str());

                    // Insert into contacts_projection
                    sqlx::query(
                        r#"
                        INSERT INTO contacts_projection 
                        (id, user_id, name, username, phone, email, notes, is_deleted, created_at, updated_at, last_event_id)
                        VALUES ($1, $2, $3, $4, $5, $6, $7, false, $8, $8, 0)
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
                    // Update existing contact - get current values first
                    let current = sqlx::query(
                        "SELECT name, username, phone, email, notes FROM contacts_projection WHERE id = $1"
                    )
                    .bind(aggregate_id)
                    .fetch_optional(&*state.db_pool)
                    .await?;

                    if let Some(row) = current {
                        let current_name: String = row.get("name");
                        let current_username: Option<String> = row.get("username");
                        let current_phone: Option<String> = row.get("phone");
                        let current_email: Option<String> = row.get("email");
                        let current_notes: Option<String> = row.get("notes");

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
                            WHERE id = $1
                            "#
                        )
                        .bind(aggregate_id)
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
                    // Soft delete contact
                    sqlx::query(
                        "UPDATE contacts_projection SET is_deleted = true, updated_at = $2 WHERE id = $1"
                    )
                    .bind(aggregate_id)
                    .bind(created_at)
                    .execute(&*state.db_pool)
                    .await?;
                }
                _ => {}
            }
        } else if aggregate_type == "transaction" {
            match event_type.as_str() {
                "CREATED" | "TRANSACTION_CREATED" => {
                    // Extract transaction data from event
                    let contact_id_str = event_data.get("contact_id").and_then(|v| v.as_str()).unwrap_or("");
                    let contact_id = uuid::Uuid::parse_str(contact_id_str).ok();
                    
                    if let Some(cid) = contact_id {
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
                                (id, user_id, contact_id, type, direction, amount, currency, description, transaction_date, due_date, is_deleted, created_at, updated_at, last_event_id)
                                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, false, $11, $11, 0)
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
                    // Update existing transaction - get current values first
                    let current = sqlx::query(
                        "SELECT contact_id, type, direction, amount, currency, description, transaction_date, due_date FROM transactions_projection WHERE id = $1"
                    )
                    .bind(aggregate_id)
                    .fetch_optional(&*state.db_pool)
                    .await?;

                    if let Some(row) = current {
                        let current_contact_id: uuid::Uuid = row.get("contact_id");
                        let current_type: String = row.get("type");
                        let current_direction: String = row.get("direction");
                        let current_amount: i64 = row.get("amount");
                        let current_currency: String = row.get("currency");
                        let current_description: Option<String> = row.get("description");
                        let current_transaction_date: chrono::NaiveDate = row.get("transaction_date");
                        let current_due_date: Option<chrono::NaiveDate> = row.get("due_date");

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
                            WHERE id = $1
                            "#
                        )
                        .bind(aggregate_id)
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
                    // Soft delete transaction
                    sqlx::query(
                        "UPDATE transactions_projection SET is_deleted = true, updated_at = $2 WHERE id = $1"
                    )
                    .bind(aggregate_id)
                    .bind(created_at)
                    .execute(&*state.db_pool)
                    .await?;
                }
                _ => {}
            }
        }
    }

    // Note: Balance is calculated on-the-fly from transactions, not stored in contacts_projection
    // So we don't need to update it here

    // Save snapshot after rebuild if needed
    if let Some(last_uuid) = last_event_uuid {
        if let Ok(Some(last_event_db_id)) = sqlx::query_scalar::<_, Option<i64>>(
            "SELECT id FROM events WHERE event_id = $1"
        )
        .bind(last_uuid)
        .fetch_optional(&*state.db_pool)
        .await {
            if let Some(db_id) = last_event_db_id {
                if crate::services::projection_snapshot_service::should_create_snapshot(event_count) {
                    if let Ok(snapshot_json) = create_snapshot_json(state).await {
                        let _ = crate::services::projection_snapshot_service::save_snapshot(
                            &*state.db_pool,
                            db_id,
                            event_count,
                            snapshot_json.0,
                            snapshot_json.1,
                        ).await;
                    }
                }
            }
        }
    }

    tracing::info!("Projections rebuilt successfully");
    Ok(())
}

/// Create snapshot JSON from current projections
/// Returns (contacts_json, transactions_json)
async fn create_snapshot_json(state: &AppState) -> Result<(serde_json::Value, serde_json::Value), sqlx::Error> {
    // Get all contacts
    let contacts = sqlx::query(
        r#"
        SELECT id, user_id, name, username, phone, email, notes, is_deleted, created_at, updated_at
        FROM contacts_projection
        WHERE is_deleted = false
        ORDER BY created_at
        "#
    )
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

    // Get all transactions
    let transactions = sqlx::query(
        r#"
        SELECT id, user_id, contact_id, type, direction, amount, currency, description, 
               transaction_date, due_date, is_deleted, created_at, updated_at
        FROM transactions_projection
        WHERE is_deleted = false
        ORDER BY created_at
        "#
    )
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

/// Apply a single event to projections (for incremental updates during sync)
async fn apply_single_event_to_projections(
    state: &AppState,
    event: &SyncEventRequest,
    aggregate_id: uuid::Uuid,
    user_id: uuid::Uuid,
    created_at: chrono::NaiveDateTime,
) -> Result<(), sqlx::Error> {
    // UNDO events don't modify projections directly - they mark other events as undone
    // The undone event's effects are skipped during rebuild
    if event.event_type == "UNDO" {
        // When UNDO event is processed, we need to rebuild projections to skip the undone event
        // For now, we'll handle this in the full rebuild - UNDO events trigger a rebuild
        // This is a simplification - in production you might want incremental UNDO handling
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
                        (id, user_id, name, username, phone, email, notes, is_deleted, created_at, updated_at, last_event_id)
                        VALUES ($1, $2, $3, $4, $5, $6, $7, false, $8, $8, 0)
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
                        WHERE id = $7
                        "#
                    )
                    .bind(event_data.get("name").and_then(|v| v.as_str()))
                    .bind(event_data.get("username").and_then(|v| v.as_str()))
                    .bind(event_data.get("phone").and_then(|v| v.as_str()))
                    .bind(event_data.get("email").and_then(|v| v.as_str()))
                    .bind(event_data.get("notes").and_then(|v| v.as_str()))
                    .bind(created_at)
                    .bind(aggregate_id)
                    .execute(&*state.db_pool)
                    .await?;
                }
                "DELETED" => {
                    sqlx::query(
                        "UPDATE contacts_projection SET is_deleted = true, updated_at = $1 WHERE id = $2"
                    )
                    .bind(created_at)
                    .bind(aggregate_id)
                    .execute(&*state.db_pool)
                    .await?;
                }
                _ => {}
            }
        }
        "transaction" => {
            match event.event_type.as_str() {
                "CREATED" => {
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
                        INSERT INTO transactions_projection 
                        (id, user_id, contact_id, type, direction, amount, currency, description, transaction_date, due_date, is_deleted, created_at, updated_at, last_event_id)
                        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, false, $11, $11, 0)
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
                        WHERE id = $10
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
                    .execute(&*state.db_pool)
                    .await?;
                }
                "DELETED" => {
                    sqlx::query(
                        "UPDATE transactions_projection SET is_deleted = true, updated_at = $1 WHERE id = $2"
                    )
                    .bind(created_at)
                    .bind(aggregate_id)
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
