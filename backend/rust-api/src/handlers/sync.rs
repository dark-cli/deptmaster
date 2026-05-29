use axum::{
    extract::{Query, State, Extension},
    http::StatusCode,
    response::Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use crate::AppState;
use crate::websocket;
use crate::services::snapshots;
use crate::handlers::responses;
use crate::middleware::auth::AuthUser;
use crate::middleware::wallet_context::WalletContext;
use crate::{permissions::{Action, PermissionContext, PermissionModel, Resource, WalletRole}};
use crate::database::repository::Database;
use crate::database::models::EventRow;
use crate::services::projections::Projections;
use sha2::{Sha256, Digest};

// Re-exports for backward compatibility with tests and other modules
pub use crate::domain::SyncEventRequest;

// Wrapper function for backward compatibility
pub async fn rebuild_projections_from_events(state: &crate::AppState, wallet_id: uuid::Uuid) -> Result<(), sqlx::Error> {
    Projections::rebuild_projections_from_events(state, wallet_id).await
}

/// Sync contact_group_members for a contact from event_data.group_ids (contact UPDATED).
/// Desired set is all_contacts + group_ids from event. Clears wallet's group memberships for this contact then inserts desired.
/// Returns true if the user is allowed to read this event based on permission filtering.
fn event_read_allowed(
    contact_ids_allowed: &Option<std::collections::HashSet<uuid::Uuid>>,
    transaction_contact_ids_allowed: &Option<std::collections::HashSet<uuid::Uuid>>,
    aggregate_type: &str,
    aggregate_id: uuid::Uuid,
    event_data: &serde_json::Value,
    transaction_contact_map: &std::collections::HashMap<uuid::Uuid, uuid::Uuid>,
) -> bool {
    if aggregate_type == "permission" {
        return true;
    }
    if aggregate_type == "contact" {
        return match contact_ids_allowed {
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
        return match transaction_contact_ids_allowed {
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
    let db = Database::new((*state.db_pool).clone());
    db.get_transaction_contact_map(wallet_id, transaction_ids).await
}

/// Calculate total debt (sum of all contact balances) at current time for a wallet
async fn calculate_total_debt(state: &AppState, wallet_id: uuid::Uuid) -> i64 {
    let db = Database::new((*state.db_pool).clone());
    db.calculate_total_debt(wallet_id).await
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
    let db = Database::new((*state.db_pool).clone());
    let events = db.get_all_events_for_wallet(wallet_id)
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
        .filter(|row| row.aggregate_type == "transaction")
        .filter(|row| {
            !row.data.get("contact_id").and_then(|v| v.as_str()).is_some()
        })
        .map(|row| row.aggregate_id)
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

    // Get readable contacts and transactions for permission filtering
    let user_role = match wallet_context.user_role.as_str() {
        "owner" => WalletRole::Owner,
        "admin" => WalletRole::Admin,
        _ => WalletRole::Member,
    };
    let perm_ctx = PermissionContext::new(wallet_id, auth_user.user_id, user_role);
    let perm_model = PermissionModel::new((*state.db_pool).clone());

    let contact_ids_allowed = perm_model.get_readable_contacts(&perm_ctx).await.map_err(|e| {
        tracing::error!("Failed to get readable contacts: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to check permissions"})),
        )
    })?;

    let transaction_contact_ids_allowed = perm_model.get_readable_transaction_contacts(&perm_ctx).await.map_err(|e| {
        tracing::error!("Failed to get readable transaction contacts: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to check permissions"})),
        )
    })?;

    let mut filtered_event_ids_with_timestamps: Vec<(uuid::Uuid, chrono::NaiveDateTime)> = Vec::new();
    for row in &events {
        if event_read_allowed(
            &contact_ids_allowed,
            &transaction_contact_ids_allowed,
            &row.aggregate_type,
            row.aggregate_id,
            &row.data,
            &transaction_contact_map,
        ) {
            filtered_event_ids_with_timestamps.push((row.event_id, row.created_at));
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
            .map(|dt| dt.with_timezone(&chrono::Utc))
    });

    let db = Database::new((*state.db_pool).clone());
    let events = if let Some(since) = since_timestamp {
        db.get_events_since_impl(wallet_id, since)
            .await
    } else {
        db.get_all_events_for_wallet(wallet_id)
            .await
    }
    .map_err(|e| {
        tracing::error!("Error fetching events: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to fetch events"})),
        )
    })?;

    let transaction_ids_missing_contact: Vec<uuid::Uuid> = events
        .iter()
        .filter(|row| row.aggregate_type == "transaction")
        .filter(|row| {
            !row.data.get("contact_id").and_then(|v| v.as_str()).is_some()
        })
        .map(|row| row.aggregate_id)
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

    // Get readable contacts and transactions for permission filtering
    let user_role = match wallet_context.user_role.as_str() {
        "owner" => WalletRole::Owner,
        "admin" => WalletRole::Admin,
        _ => WalletRole::Member,
    };
    let perm_ctx = PermissionContext::new(wallet_id, auth_user.user_id, user_role);
    let perm_model = PermissionModel::new((*state.db_pool).clone());

    let contact_ids_allowed = perm_model.get_readable_contacts(&perm_ctx).await.map_err(|e| {
        tracing::error!("Failed to get readable contacts: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to check permissions"})),
        )
    })?;

    let transaction_contact_ids_allowed = perm_model.get_readable_transaction_contacts(&perm_ctx).await.map_err(|e| {
        tracing::error!("Failed to get readable transaction contacts: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to check permissions"})),
        )
    })?;

    let mut sync_events = Vec::with_capacity(events.len());
    for row in &events {
        if !event_read_allowed(
            &contact_ids_allowed,
            &transaction_contact_ids_allowed,
            &row.aggregate_type,
            row.aggregate_id,
            &row.data,
            &transaction_contact_map,
        ) {
            continue;
        }
        sync_events.push(SyncEvent {
            id: row.event_id.to_string(),
            aggregate_type: row.aggregate_type.clone(),
            aggregate_id: row.aggregate_id.to_string(),
            event_type: row.event_type.clone(),
            event_data: row.data.clone(),
            timestamp: chrono::DateTime::<chrono::Utc>::from_naive_utc_and_offset(row.created_at, chrono::Utc).to_rfc3339(),
            version: row.version,
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

    let db = Database::new((*state.db_pool).clone());
    db.insert_event_impl(
        event_id,
        aggregate_id,
        "permission".to_string(),
        event_type.to_string(),
        event_data.clone(),
        wallet_id,
        user_id,
        1,
        None,
    )
    .await
    .map_err(|e| sqlx::Error::RowNotFound)?;

    let event_req = SyncEventRequest {
        id: event_id.to_string(),
        aggregate_type: "permission".to_string(),
        aggregate_id: aggregate_id.to_string(),
        event_type: event_type.to_string(),
        event_data,
        timestamp: chrono::DateTime::<chrono::Utc>::from_naive_utc_and_offset(created_at, chrono::Utc).to_rfc3339(),
        version: 1,
    };
    db.apply_single_event_to_projections_impl(&event_req, aggregate_id, user_id, wallet_id, created_at).await?;
    websocket::broadcast_events_synced(&state.broadcast_tx, wallet_id, &event_req.aggregate_type);

    Ok(())
}

#[derive(Serialize)]
pub struct SyncEventsResponse {
    pub accepted: Vec<String>,
    pub conflicts: Vec<String>,
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
                    // Query the undone event to get its created_at timestamp (must be in same wallet)
                    let db = Database::new((*state.db_pool).clone());
                    if let Ok(Some(undone_row)) = db.get_event_by_id_impl(undone_event_uuid).await {
                        // Check if the event belongs to this wallet
                        if undone_row.wallet_id == wallet_id {
                            let undone_created_at = undone_row.created_at;
                            let undo_synced_at = chrono::Utc::now().naive_utc();

                            // Calculate time difference between when undone event was created and when UNDO is being synced
                            let time_diff = undo_synced_at.signed_duration_since(undone_created_at);

                            // Check if more than 5 seconds have passed since undone event was created
                            if time_diff.num_seconds() > 5 {
                                conflicts.push(event.id);
                                tracing::warn!(
                                    "UNDO event rejected: undone event was created {} seconds ago (max 5 seconds allowed)",
                                    time_diff.num_seconds()
                                );
                                continue;
                            }
                        }
                    }
                    // If undone event doesn't exist, we still accept the UNDO event (structural validation passed)
                }
            }
        }

        // Check if event already exists (idempotency) - must be in same wallet
        let db = Database::new((*state.db_pool).clone());
        let existing_event = db.get_event_by_id_impl(event_id)
            .await
            .map_err(|_| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(serde_json::json!({"error": "Database error"})),
                )
            })?;

        if let Some(existing) = existing_event {
            // Event already exists - check if it belongs to this wallet and has same data
            if existing.wallet_id == wallet_id {
                if existing.data != event.event_data {
                    // Conflict: same ID but different data
                    conflicts.push(event.id);
                    continue;
                }
            } else {
                // Event exists but belongs to different wallet - conflict
                conflicts.push(event.id);
                continue;
            }
            // Same event in same wallet - accept it
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
        let insert_result = db.insert_event_impl(
            event_id,
            aggregate_id,
            event.aggregate_type.clone(),
            event.event_type.clone(),
            event.event_data.clone(),
            wallet_id,
            user_id,
            event.version,
            None,
        ).await;

        match insert_result {
            Ok(_) => {
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
                    if let Err(e) = Projections::rebuild_projections_from_events(&state, wallet_id).await {
                        tracing::error!("Error rebuilding projections after UNDO: {:?}", e);
                    }
                }
                
                // Calculate total_debt AFTER this event is applied
                let total_debt_after = calculate_total_debt(&state, wallet_id).await;
                
                // Update this event with total_debt (so event log shows correct running total)
                // For now, skip total_debt update as it requires raw SQL jsonb_set
                // TODO: Add update_event method to repository for this use case

                // Save snapshot if needed (every 10 events or after UNDO)
                if let Ok(Some(db_id)) = db.get_event_db_id_by_uuid(event_id).await {
                    let event_count = db.get_event_count().await;
                    let should_save = crate::services::snapshots::should_create_snapshot(event_count)
                        || event.event_type == "UNDO";

                    if should_save {
                        // Create snapshot JSON from current projections
                        if let Ok(snapshot_json) = snapshots::create_snapshot_json(&*state.db_pool, wallet_id).await {
                            let _ = crate::services::snapshots::save_snapshot(
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
