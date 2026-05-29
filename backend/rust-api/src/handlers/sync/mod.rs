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
use crate::handlers::responses;
use crate::middleware::auth::AuthUser;
use crate::middleware::wallet_context::WalletContext;
use crate::{permissions::{Action, PermissionContext, PermissionModel, Resource, WalletRole}};
use crate::database::repository::Database;
use sha2::{Sha256, Digest};

pub mod request;
pub use request::SyncEventRequest;

/// Sync contact_group_members for a contact from event_data.group_ids (contact UPDATED).
/// Desired set is all_contacts + group_ids from event. Clears wallet's group memberships for this contact then inserts desired.
/// Returns true if the user is allowed to read this event using precomputed ReadContext (no DB).
fn event_read_allowed(
    ctx: &ReadContext,
    aggregate_type: &str,
    aggregate_id: uuid::Uuid,
    event_data: &serde_json::Value,
    transaction_contact_map: &std::collections::HashMap<uuid::Uuid, uuid::Uuid>,
) -> bool {
    if aggregate_type == "permission" {
        return true;
    }
    if aggregate_type == "contact" {
        return match &ctx.contact_ids_allowed {
            None => true,
            Some(set) => set.contains(&aggregate_id),
        };
    }
    if aggregate_type == "transaction" {
        let contact_id = event_data
            .get("contact_id")
            .and_then(|v| v.as_str())
            .and_then(|s| uuid::Uuid::parse_str(s).ok())
            .or_else(|| transaction_contact_map.get(&aggregate_id).copied());
        let Some(contact_id) = contact_id else {
            return false;
        };
        // Transactions don't have their own groups; visibility is by contact's contact groups (transaction:read).
        return match &ctx.transaction_contact_ids_allowed {
            None => true,
            Some(set) => set.contains(&contact_id),
        };
    }
    false
}

/// Build map transaction_id -> contact_id for transaction events that don't have contact_id in event_data.
async fn transaction_contact_ids_for_events(
    state: &AppState,
    wallet_id: uuid::Uuid,
    transaction_ids: &[uuid::Uuid],
) -> Result<std::collections::HashMap<uuid::Uuid, uuid::Uuid>, sqlx::Error> {
    if transaction_ids.is_empty() {
        return Ok(std::collections::HashMap::new());
    }
    let rows = sqlx::query(
        "SELECT id, contact_id FROM transactions_projection WHERE wallet_id = $1 AND id = ANY($2)",
    )
    .bind(wallet_id)
    .bind(transaction_ids)
    .fetch_all(&*state.db_pool)
    .await?;
    Ok(rows
        .iter()
        .map(|r| {
            (
                r.get::<uuid::Uuid, _>("id"),
                r.get::<uuid::Uuid, _>("contact_id"),
            )
        })
        .collect())
}

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
    .unwrap_or_else(|e| {
        tracing::error!("calculate_total_debt failed for wallet {}: {:?}", wallet_id, e);
        0
    })
}

#[derive(Serialize)]
pub struct SyncHashResponse {
    pub hash: String,
    pub event_count: i64,
    pub last_event_timestamp: Option<chrono::NaiveDateTime>,
}

/// Get hash of all events for sync comparison. Hash is computed only over events the user is allowed to read (same filter as get_sync_events).
pub async fn get_sync_hash(
    State(state): State<AppState>,
    Extension(wallet_context): Extension<WalletContext>,
    Extension(auth_user): Extension<AuthUser>,
) -> Result<Json<SyncHashResponse>, (StatusCode, Json<serde_json::Value>)> {
    let wallet_id = wallet_context.wallet_id;
    let events = sqlx::query(
        r#"
        SELECT event_id, aggregate_type, aggregate_id, event_type, event_data, created_at
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

    let transaction_ids_missing_contact: Vec<uuid::Uuid> = events
        .iter()
        .filter(|row| row.get::<String, _>("aggregate_type") == "transaction")
        .filter(|row| {
            let event_data: serde_json::Value = row.get("event_data");
            !event_data.get("contact_id").and_then(|v| v.as_str()).is_some()
        })
        .map(|row| row.get::<uuid::Uuid, _>("aggregate_id"))
        .collect();
    let transaction_contact_map = transaction_contact_ids_for_events(
        &state,
        wallet_id,
        &transaction_ids_missing_contact,
    )
    .await
    .map_err(|e| {
        tracing::error!("transaction_contact_ids_for_events: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to fetch events"})),
        )
    })?;

    let read_ctx = ReadContext::new(
        &*state.db_pool,
        wallet_id,
        auth_user.user_id,
        &wallet_context.user_role,
    )
    .await
    .map_err(|e| {
        tracing::error!("ReadContext: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to check permissions"})),
        )
    })?;

    let mut filtered_event_ids_with_timestamps: Vec<(uuid::Uuid, chrono::NaiveDateTime)> = Vec::new();
    for row in &events {
        let aggregate_type: String = row.get("aggregate_type");
        let aggregate_id: uuid::Uuid = row.get("aggregate_id");
        let event_data: serde_json::Value = row.get("event_data");
        if event_read_allowed(
            &read_ctx,
            &aggregate_type,
            aggregate_id,
            &event_data,
            &transaction_contact_map,
        ) {
            let event_id: uuid::Uuid = row.get("event_id");
            let created_at: chrono::NaiveDateTime = row.get("created_at");
            filtered_event_ids_with_timestamps.push((event_id, created_at));
        }
    }

    let mut hasher = Sha256::new();
    for (event_id, created_at) in &filtered_event_ids_with_timestamps {
        hasher.update(event_id.to_string().as_bytes());
        hasher.update(created_at.to_string().as_bytes());
    }
    let hash = format!("{:x}", hasher.finalize());

    let last_event_timestamp = filtered_event_ids_with_timestamps
        .last()
        .map(|(_, created_at)| *created_at);

    Ok(Json(SyncHashResponse {
        hash,
        event_count: filtered_event_ids_with_timestamps.len() as i64,
        last_event_timestamp,
    }))
}

#[derive(Deserialize)]
pub struct SyncEventsQuery {
    pub since: Option<String>, // ISO timestamp
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

/// Get events since a timestamp. Only returns events the user is allowed to read (contact:read / transaction:read).
pub async fn get_sync_events(
    Query(params): Query<SyncEventsQuery>,
    State(state): State<AppState>,
    Extension(wallet_context): Extension<WalletContext>,
    Extension(auth_user): Extension<AuthUser>,
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

    let transaction_ids_missing_contact: Vec<uuid::Uuid> = events
        .iter()
        .filter(|row| row.get::<String, _>("aggregate_type") == "transaction")
        .filter(|row| {
            let event_data: serde_json::Value = row.get("event_data");
            !event_data.get("contact_id").and_then(|v| v.as_str()).is_some()
        })
        .map(|row| row.get::<uuid::Uuid, _>("aggregate_id"))
        .collect();
    let transaction_contact_map = transaction_contact_ids_for_events(
        &state,
        wallet_id,
        &transaction_ids_missing_contact,
    )
    .await
    .map_err(|e| {
        tracing::error!("transaction_contact_ids_for_events: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to fetch events"})),
        )
    })?;

    let read_ctx = ReadContext::new(
        &*state.db_pool,
        wallet_id,
        auth_user.user_id,
        &wallet_context.user_role,
    )
    .await
    .map_err(|e| {
        tracing::error!("ReadContext: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to check permissions"})),
        )
    })?;

    let mut sync_events = Vec::with_capacity(events.len());
    for row in &events {
        let aggregate_type: String = row.get("aggregate_type");
        let aggregate_id: uuid::Uuid = row.get("aggregate_id");
        let event_data: serde_json::Value = row.get("event_data");
        if !event_read_allowed(
            &read_ctx,
            &aggregate_type,
            aggregate_id,
            &event_data,
            &transaction_contact_map,
        ) {
            continue;
        }
        sync_events.push(SyncEvent {
            id: row.get::<uuid::Uuid, _>("event_id").to_string(),
            aggregate_type,
            aggregate_id: aggregate_id.to_string(),
            event_type: row.get("event_type"),
            event_data,
            timestamp: {
                let naive_dt: chrono::NaiveDateTime = row.get("created_at");
                chrono::DateTime::<chrono::Utc>::from_naive_utc_and_offset(naive_dt, chrono::Utc).to_rfc3339()
            },
            version: row.get("event_version"),
        });
    }

    Ok(Json(sync_events))
}

/// Insert a permission event and apply it to projections. Used by wallet management handlers.
pub(crate) async fn insert_permission_event_and_apply(
    state: &AppState,
    user_id: uuid::Uuid,
    wallet_id: uuid::Uuid,
    aggregate_id: uuid::Uuid,
    event_type: &str,
    event_data: serde_json::Value,
) -> Result<(), sqlx::Error> {
    let event_id = uuid::Uuid::new_v4();
    let created_at = chrono::Utc::now().naive_utc();
    sqlx::query(
        r#"
        INSERT INTO events (event_id, user_id, wallet_id, aggregate_type, aggregate_id, event_type, event_version, event_data, created_at)
        VALUES ($1, $2, $3, 'permission', $4, $5, 1, $6, $7)
        "#
    )
    .bind(event_id)
    .bind(user_id)
    .bind(wallet_id)
    .bind(aggregate_id)
    .bind(event_type)
    .bind(&event_data)
    .bind(created_at)
    .execute(&*state.db_pool)
    .await?;

    let event_req = SyncEventRequest {
        id: event_id.to_string(),
        aggregate_type: "permission".to_string(),
        aggregate_id: aggregate_id.to_string(),
        event_type: event_type.to_string(),
        event_data,
        timestamp: chrono::DateTime::<chrono::Utc>::from_naive_utc_and_offset(created_at, chrono::Utc).to_rfc3339(),
        version: 1,
    };
    let db = Database::new((*state.db_pool).clone());
    db.apply_single_event_to_projections_impl(&event_req, aggregate_id, user_id, wallet_id, created_at).await?;
    websocket::broadcast_events_synced(&state.broadcast_tx, wallet_id, &event_req.aggregate_type);

    Ok(())
}

#[derive(Serialize)]
pub struct SyncEventsResponse {
    pub accepted: Vec<String>,
    pub conflicts: Vec<String>,
}

/// Read context for filtering sync events based on user permissions
/// Replaces permission_service::SyncReadContext - uses PermissionModel for all queries
pub struct ReadContext {
    /// None = can read all contacts; Some(set) = can only read these contact ids
    pub contact_ids_allowed: Option<std::collections::HashSet<uuid::Uuid>>,
    /// None = can read all transactions; Some(set) = can only read transactions for these contact ids
    pub transaction_contact_ids_allowed: Option<std::collections::HashSet<uuid::Uuid>>,
}

impl ReadContext {
    /// Create ReadContext from PermissionModel
    pub async fn new(
        pool: &sqlx::PgPool,
        wallet_id: uuid::Uuid,
        user_id: uuid::Uuid,
        user_role: &str,
    ) -> Result<Self, crate::database::error::DbError> {
        let perm_model = PermissionModel::new(pool.clone());
        let perm_ctx = PermissionContext::new(
            wallet_id,
            user_id,
            match user_role {
                "owner" => WalletRole::Owner,
                "admin" => WalletRole::Admin,
                _ => WalletRole::Member,
            },
        );

        // Get contacts user can read (contact:read permission)
        let contact_ids_allowed = perm_model.get_readable_contacts(&perm_ctx).await?;

        // Get contacts whose transactions user can read (transaction:read permission)
        let transaction_contact_ids_allowed = perm_model.get_readable_transaction_contacts(&perm_ctx).await?;

        Ok(ReadContext {
            contact_ids_allowed,
            transaction_contact_ids_allowed,
        })
    }
}

/// Permission event types (write-only; projection builds wallet_users, user_groups, etc.)
// Validation is now handled at deserialization time via custom serde deserializers
// in request.rs. Invalid JSON is rejected before reaching handler logic.

/// Accept events from client and insert them
pub async fn post_sync_events(
    State(state): State<AppState>,
    axum::extract::Extension(wallet_context): axum::extract::Extension<WalletContext>,
    axum::extract::Extension(auth_user): axum::extract::Extension<AuthUser>,
    Json(events): Json<Vec<SyncEventRequest>>,
) -> Result<Json<SyncEventsResponse>, (StatusCode, Json<serde_json::Value>)> {
    let wallet_id = wallet_context.wallet_id;
    let user_id = auth_user.user_id;
    let mut accepted = Vec::new();
    let mut conflicts = Vec::new();

    // Preflight permission checks using batched API to avoid partial writes in a batch.
    // Convert wallet role string to enum for PermissionContext
    let user_role = match wallet_context.user_role.as_str() {
        "owner" => WalletRole::Owner,
        "admin" => WalletRole::Admin,
        _ => WalletRole::Member,
    };
    let perm_ctx = PermissionContext::new(wallet_id, user_id, user_role);

    // Collect all permission checks for batch verification
    let mut permission_checks: Vec<(Action, Resource)> = Vec::new();
    for event in &events {
        // Permission events are admin/owner only.
        if event.aggregate_type == "permission" {
            if wallet_context.user_role != "owner" && wallet_context.user_role != "admin" {
                return Err(responses::insufficient_permission_response());
            }
            continue;
        }

        // Get required permissions from event trait
        permission_checks.extend(event.required_permissions());

        // Transactions require contact read (dependency safety).
        if event.aggregate_type == "transaction" {
            permission_checks.push((Action::ContactRead, Resource::AllContacts));
        }
    }

    // Verify all permissions in batch using optimized single query
    if !permission_checks.is_empty() {
        let db_pool = (*state.db_pool).clone();
        let perm_model = PermissionModel::new(db_pool);
        let results: Vec<bool> = perm_model
            .check_permissions(&perm_ctx, permission_checks)
            .await
            .map_err(|_| responses::insufficient_permission_response())?;

        // Check that all permission checks passed
        if !results.iter().all(|&allowed| allowed) {
            return Err(responses::insufficient_permission_response());
        }
    }

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

        // Validation at deserialization (custom serde deserializers) + data validation for programmatic creation
        if let Some(validation_error) = event.validate_data() {
            conflicts.push(event.id.clone());
            tracing::warn!("Event validation failed for {}: {}", event.id, validation_error);
            continue;
        }

        // Special validation for UNDO events: check 5-second window from server sync time
        // The 5 seconds is measured between when the undone event was synced to the server
        // and when the UNDO event is being synced. This supports offline-first:
        // - User creates event and UNDO offline (within 5 seconds of each other)
        // - Both are synced to server shortly after when user comes online
        // - Validation passes because synced times are within 5 seconds
        if event.event_type == "UNDO" {
            if let Some(undone_event_id_str) = event.event_data.get("undone_event_id").and_then(|v| v.as_str()) {
                if let Ok(undone_event_uuid) = uuid::Uuid::parse_str(undone_event_id_str) {
                    // Query the undone event to get its synced_at timestamp (must be in same wallet)
                    let undone_event = sqlx::query(
                        "SELECT synced_at FROM events WHERE event_id = $1 AND wallet_id = $2"
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
                        let undone_synced_at: chrono::NaiveDateTime = undone_row.get("synced_at");
                        let undo_synced_at = chrono::Utc::now().naive_utc();

                        // Calculate time difference between when undone event was synced and when UNDO is being synced
                        let time_diff = undo_synced_at.signed_duration_since(undone_synced_at);

                        // Check if more than 5 seconds have passed since undone event was synced
                        if time_diff.num_seconds() > 5 {
                            conflicts.push(event.id);
                            tracing::warn!(
                                "UNDO event rejected: undone event was synced {} seconds ago (max 5 seconds allowed)",
                                time_diff.num_seconds()
                            );
                            continue;
                        }
                    }
                    // If undone event doesn't exist, we still accept the UNDO event (structural validation passed)
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
                let db = Database::new((*state.db_pool).clone());
                if let Err(e) = db.apply_single_event_to_projections_impl(&event, aggregate_id, user_id, wallet_id, timestamp).await {
                    tracing::error!("Error applying event to projections: {:?}", e);
                    // Continue anyway - event is inserted
                } else {
                    websocket::broadcast_events_synced(&state.broadcast_tx, wallet_id, &event.aggregate_type);
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

    // Each accepted event already triggered broadcast_events_synced in apply_single_event_to_projections.

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
                    let db = Database::new((*state.db_pool).clone());
                    if db.apply_events_to_projections_impl(&events_after_snapshot, user_id, wallet_id, &mut empty_undone_set).await.is_ok() {
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
                        let db = Database::new((*state.db_pool).clone());
                        if db.apply_events_to_projections_impl(&events_after_snapshot, user_id, wallet_id, &mut empty_undone_set).await.is_ok() {
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
        let db = Database::new((*state.db_pool).clone());
        db.apply_events_to_projections_impl(&events_to_process, user_id, wallet_id, &mut undone_event_ids).await?;
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
