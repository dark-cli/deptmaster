use axum::{
    extract::{Query, State, Extension},
    http::StatusCode,
    response::Json,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use chrono::{DateTime, Utc};

use crate::AppState;
use crate::websocket;
use crate::services::snapshots;
use crate::handlers::responses;
use crate::middleware::auth::AuthUser;
use crate::middleware::wallet_context::WalletContext;
use crate::permissions::{Action, PermissionContext, PermissionModel, Resource};
use crate::database::repository::Database;
use crate::database::models::EventRow;
use crate::services::projections::Projections;
use crate::domain::DomainEvent;
use sha2::{Sha256, Digest};
use std::collections::{HashMap, HashSet};

// Re-exports for backward compatibility
pub use crate::domain::SyncEventRequest;

// ============ RESPONSE TYPES ============

#[derive(Serialize)]
pub struct SyncHashResponse {
    pub hash: String,
    pub event_count: i64,
    pub last_event_timestamp: Option<chrono::NaiveDateTime>,
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

#[derive(Serialize)]
pub struct SyncEventsResponse {
    pub accepted: Vec<String>,
    pub conflicts: Vec<String>,
}

// ============ QUERY TYPES ============

#[derive(Deserialize)]
pub struct SyncEventsQuery {
    pub since: Option<String>,
}

// ============ INTERNAL HELPERS ============

/// Build transaction_id -> contact_id map for permission filtering
fn build_transaction_contact_map(
    events: &[EventRow],
    db_map: &HashMap<Uuid, Uuid>,
) -> HashMap<Uuid, Uuid> {
    let mut result = HashMap::new();
    for event in events {
        match event.aggregate_type.as_str() {
            "transaction" => {
                // Try to get contact_id from event_data first
                if let Some(contact_id_str) = event.data
                    .get("contact_id")
                    .and_then(|v| v.as_str())
                {
                    if let Ok(contact_id) = Uuid::parse_str(contact_id_str) {
                        result.insert(event.aggregate_id, contact_id);
                    }
                }
                // Fall back to database map if not in event_data
                else if let Some(&contact_id) = db_map.get(&event.aggregate_id) {
                    result.insert(event.aggregate_id, contact_id);
                }
            }
            _ => {}
        }
    }
    result
}

/// Check if user can read an event based on permission boundaries
fn can_read_event(
    event: &EventRow,
    contact_ids: &Option<HashSet<Uuid>>,
    transaction_contact_ids: &Option<HashSet<Uuid>>,
    transaction_map: &HashMap<Uuid, Uuid>,
) -> bool {
    match event.aggregate_type.as_str() {
        "permission" => true,
        "contact" => match contact_ids {
            None => true,
            Some(set) => set.contains(&event.aggregate_id),
        },
        "transaction" => {
            if let Some(&contact_id) = transaction_map.get(&event.aggregate_id) {
                match transaction_contact_ids {
                    None => true,
                    Some(set) => set.contains(&contact_id),
                }
            } else {
                false
            }
        }
        _ => false,
    }
}

// ============ PUBLIC ENDPOINTS ============

/// Get hash of all events for sync comparison (permission-filtered)
pub async fn get_sync_hash(
    State(state): State<AppState>,
    Extension(wallet_context): Extension<WalletContext>,
    Extension(auth_user): Extension<AuthUser>,
) -> Result<Json<SyncHashResponse>, (StatusCode, Json<serde_json::Value>)> {
    let wallet_id = wallet_context.wallet_id;
    let db = Database::new((*state.db_pool).clone());

    // Fetch all events
    let events = db.get_all_events_for_wallet(wallet_id)
        .await
        .map_err(|e| {
            tracing::error!("Error fetching events: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to fetch events"})),
            )
        })?;

    // Get permission boundaries once
    let perm_ctx = PermissionContext::new(wallet_id, auth_user.user_id, wallet_context.user_role);
    let perm_model = PermissionModel::new((*state.db_pool).clone());

    let readable_contacts = perm_model.get_readable_contacts(&perm_ctx).await.map_err(|_| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to check permissions"})),
        )
    })?;

    let readable_transaction_contacts = perm_model.get_readable_transaction_contacts(&perm_ctx).await.map_err(|_| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to check permissions"})),
        )
    })?;

    // Get transaction contact map for filtering
    let missing_ids: Vec<Uuid> = events
        .iter()
        .filter(|e| e.aggregate_type == "transaction" && e.data.get("contact_id").and_then(|v| v.as_str()).is_none())
        .map(|e| e.aggregate_id)
        .collect();

    let db_map = if missing_ids.is_empty() {
        HashMap::new()
    } else {
        db.get_transaction_contact_map(wallet_id, &missing_ids)
            .await
            .unwrap_or_default()
    };

    let transaction_map = build_transaction_contact_map(&events, &db_map);

    // Filter events by permission and compute hash
    let mut hasher = Sha256::new();
    for event in &events {
        if can_read_event(event, &readable_contacts, &readable_transaction_contacts, &transaction_map) {
            hasher.update(event.event_id.to_string().as_bytes());
            hasher.update(event.created_at.to_string().as_bytes());
        }
    }

    let hash = format!("{:x}", hasher.finalize());
    let event_count = events.iter()
        .filter(|e| can_read_event(e, &readable_contacts, &readable_transaction_contacts, &transaction_map))
        .count() as i64;

    let last_timestamp = events
        .iter()
        .filter(|e| can_read_event(e, &readable_contacts, &readable_transaction_contacts, &transaction_map))
        .last()
        .map(|e| e.created_at);

    Ok(Json(SyncHashResponse {
        hash,
        event_count,
        last_event_timestamp: last_timestamp,
    }))
}

/// Get events since timestamp (permission-filtered)
pub async fn get_sync_events(
    Query(params): Query<SyncEventsQuery>,
    State(state): State<AppState>,
    Extension(wallet_context): Extension<WalletContext>,
    Extension(auth_user): Extension<AuthUser>,
) -> Result<Json<Vec<SyncEvent>>, (StatusCode, Json<serde_json::Value>)> {
    let wallet_id = wallet_context.wallet_id;
    let db = Database::new((*state.db_pool).clone());

    // Fetch events (optionally filtered by since timestamp)
    let events = if let Some(since_str) = &params.since {
        let since = DateTime::parse_from_rfc3339(since_str)
            .ok()
            .map(|dt| dt.with_timezone(&Utc))
            .ok_or_else(|| {
                (
                    StatusCode::BAD_REQUEST,
                    Json(serde_json::json!({"error": "Invalid timestamp format"})),
                )
            })?;
        db.get_events_since_impl(wallet_id, since).await
    } else {
        db.get_all_events_for_wallet(wallet_id).await
    }
    .map_err(|e| {
        tracing::error!("Error fetching events: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to fetch events"})),
        )
    })?;

    // Get permission boundaries once
    let perm_ctx = PermissionContext::new(wallet_id, auth_user.user_id, wallet_context.user_role);
    let perm_model = PermissionModel::new((*state.db_pool).clone());

    let readable_contacts = perm_model.get_readable_contacts(&perm_ctx).await.map_err(|_| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to check permissions"})),
        )
    })?;

    let readable_transaction_contacts = perm_model.get_readable_transaction_contacts(&perm_ctx).await.map_err(|_| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to check permissions"})),
        )
    })?;

    // Get transaction contact map
    let missing_ids: Vec<Uuid> = events
        .iter()
        .filter(|e| e.aggregate_type == "transaction" && e.data.get("contact_id").and_then(|v| v.as_str()).is_none())
        .map(|e| e.aggregate_id)
        .collect();

    let db_map = if missing_ids.is_empty() {
        HashMap::new()
    } else {
        db.get_transaction_contact_map(wallet_id, &missing_ids)
            .await
            .unwrap_or_default()
    };

    let transaction_map = build_transaction_contact_map(&events, &db_map);

    // Convert to response, filtering by permission
    let sync_events: Vec<SyncEvent> = events
        .into_iter()
        .filter(|e| can_read_event(e, &readable_contacts, &readable_transaction_contacts, &transaction_map))
        .map(|row| SyncEvent {
            id: row.event_id.to_string(),
            aggregate_type: row.aggregate_type,
            aggregate_id: row.aggregate_id.to_string(),
            event_type: row.event_type,
            event_data: row.data,
            timestamp: DateTime::<Utc>::from_naive_utc_and_offset(row.created_at, Utc).to_rfc3339(),
            version: row.version,
        })
        .collect();

    Ok(Json(sync_events))
}

/// Accept and process sync events from client
pub async fn post_sync_events(
    State(state): State<AppState>,
    Extension(wallet_context): Extension<WalletContext>,
    Extension(auth_user): Extension<AuthUser>,
    Json(events): Json<Vec<DomainEvent>>,
) -> Result<Json<SyncEventsResponse>, (StatusCode, Json<serde_json::Value>)> {
    let wallet_id = wallet_context.wallet_id;
    let user_id = auth_user.user_id;
    let db = Database::new((*state.db_pool).clone());

    // Get permission context once
    let perm_ctx = PermissionContext::new(wallet_id, user_id, wallet_context.user_role);
    let perm_model = PermissionModel::new((*state.db_pool).clone());

    // PERMISSION CHECK: Pattern matching on DomainEvent types (no strings)
    // All checks go through PermissionModel with WalletSuperPermission fallback
    let mut permission_checks: Vec<(Action, Resource)> = Vec::new();

    for domain_event in &events {
        match domain_event {
            // Permission events - map to their required permissions
            DomainEvent::WalletUserAdded { .. } => {
                permission_checks.push((Action::UserGroupAddMember, Resource::AllUserGroups));
            }
            DomainEvent::WalletUserRemoved { .. } => {
                permission_checks.push((Action::UserGroupRemoveMember, Resource::AllUserGroups));
            }
            DomainEvent::WalletUserRoleChanged { .. } => {
                permission_checks.push((Action::UserGroupEdit, Resource::AllUserGroups));
            }
            DomainEvent::UserGroupCreated { .. } => {
                permission_checks.push((Action::UserGroupCreate, Resource::Wallet(wallet_id)));
            }
            DomainEvent::UserGroupRenamed { .. }
            | DomainEvent::UserGroupDeleted { .. } => {
                permission_checks.push((Action::UserGroupEdit, Resource::AllUserGroups));
            }
            DomainEvent::UserGroupMemberAdded { .. } => {
                permission_checks.push((Action::UserGroupAddMember, Resource::AllUserGroups));
            }
            DomainEvent::UserGroupMemberRemoved { .. } => {
                permission_checks.push((Action::UserGroupRemoveMember, Resource::AllUserGroups));
            }
            DomainEvent::ContactGroupCreated { .. } => {
                permission_checks.push((Action::ContactGroupCreate, Resource::Wallet(wallet_id)));
            }
            DomainEvent::ContactGroupRenamed { .. }
            | DomainEvent::ContactGroupDeleted { .. } => {
                permission_checks.push((Action::ContactGroupEdit, Resource::AllUserGroups));
            }
            DomainEvent::ContactGroupMemberAdded { .. } => {
                permission_checks.push((Action::ContactGroupAddMember, Resource::AllUserGroups));
            }
            DomainEvent::ContactGroupMemberRemoved { .. } => {
                permission_checks.push((Action::ContactGroupRemoveMember, Resource::AllUserGroups));
            }
            DomainEvent::PermissionMatrixSet { .. } => {
                permission_checks.push((Action::UserGroupEdit, Resource::AllUserGroups));
            }

            // Transaction events require ContactRead permission
            DomainEvent::TransactionCreated { .. }
            | DomainEvent::TransactionUpdated { .. }
            | DomainEvent::TransactionDeleted { .. }
            | DomainEvent::TransactionUndone { .. } => {
                permission_checks.push((Action::ContactRead, Resource::AllContacts));
            }

            // Contact events use their defined permissions
            _ => {}
        }
    }

    // Verify all permissions in batch
    if !permission_checks.is_empty() {
        let results = perm_model
            .check_permissions(&perm_ctx, permission_checks)
            .await
            .map_err(|_| responses::insufficient_permission_response())?;

        if !results.iter().all(|&allowed| allowed) {
            return Err(responses::insufficient_permission_response());
        }
    }

    // Process each event
    let mut accepted = Vec::new();
    let mut conflicts = Vec::new();

    for domain_event in events {
        let event_id = domain_event.id();
        let aggregate_id = domain_event.aggregate_id();

        // Check idempotency
        let existing = db.get_event_by_id_impl(event_id)
            .await
            .map_err(|_| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(serde_json::json!({"error": "Database error"})),
                )
            })?;

        if let Some(_existing_event) = existing {
            conflicts.push(event_id.to_string());
            continue;
        }

        // Build event_data JSON from DomainEvent (serialize the data fields only)
        let event_data = match &domain_event {
            DomainEvent::ContactCreated { name, username, phone, email, notes, .. } => {
                serde_json::json!({
                    "name": name,
                    "username": username,
                    "phone": phone,
                    "email": email,
                    "notes": notes,
                })
            }
            DomainEvent::ContactUpdated { name, username, phone, email, notes, .. } => {
                serde_json::json!({
                    "name": name,
                    "username": username,
                    "phone": phone,
                    "email": email,
                    "notes": notes,
                })
            }
            DomainEvent::ContactDeleted { comment, .. } => {
                serde_json::json!({"comment": comment})
            }
            DomainEvent::ContactUndone { undone_event_id, .. } => {
                serde_json::json!({"undone_event_id": undone_event_id.to_string()})
            }
            DomainEvent::TransactionCreated { contact_id, amount, direction, transaction_type, currency, description, transaction_date, due_date, .. } => {
                serde_json::json!({
                    "contact_id": contact_id.to_string(),
                    "amount": amount,
                    "direction": direction,
                    "transaction_type": transaction_type,
                    "currency": currency,
                    "description": description,
                    "transaction_date": transaction_date,
                    "due_date": due_date,
                })
            }
            DomainEvent::TransactionUpdated { contact_id, amount, direction, transaction_type, currency, description, transaction_date, due_date, .. } => {
                serde_json::json!({
                    "contact_id": contact_id,
                    "amount": amount,
                    "direction": direction,
                    "transaction_type": transaction_type,
                    "currency": currency,
                    "description": description,
                    "transaction_date": transaction_date,
                    "due_date": due_date,
                })
            }
            DomainEvent::TransactionDeleted { comment, .. } => {
                serde_json::json!({"comment": comment})
            }
            DomainEvent::TransactionUndone { undone_event_id, .. } => {
                serde_json::json!({"undone_event_id": undone_event_id.to_string()})
            }
            // Permission events already have data field
            DomainEvent::WalletUserAdded { data, .. }
            | DomainEvent::WalletUserRoleChanged { data, .. }
            | DomainEvent::WalletUserRemoved { data, .. }
            | DomainEvent::UserGroupCreated { data, .. }
            | DomainEvent::UserGroupRenamed { data, .. }
            | DomainEvent::UserGroupDeleted { data, .. }
            | DomainEvent::UserGroupMemberAdded { data, .. }
            | DomainEvent::UserGroupMemberRemoved { data, .. }
            | DomainEvent::ContactGroupCreated { data, .. }
            | DomainEvent::ContactGroupRenamed { data, .. }
            | DomainEvent::ContactGroupDeleted { data, .. }
            | DomainEvent::ContactGroupMemberAdded { data, .. }
            | DomainEvent::ContactGroupMemberRemoved { data, .. }
            | DomainEvent::PermissionMatrixSet { data, .. } => data.clone(),
        };

        // Insert event
        let aggregate_type = domain_event.aggregate_type();
        let event_type = domain_event.event_type();

        if db.insert_event_impl(
            event_id,
            aggregate_id,
            aggregate_type.to_string(),
            event_type.to_string(),
            event_data,
            wallet_id,
            user_id,
            domain_event.version(),
            None,
        ).await.is_err() {
            conflicts.push(event_id.to_string());
            continue;
        }

        accepted.push(event_id.to_string());

        // Apply event using strongly-typed DomainEvent (already validated at boundary)
        if let Ok(Some(db_id)) = db.get_event_db_id_by_uuid(event_id).await {
            if let Ok(Some(event_row)) = db.get_event_by_id_impl(event_id).await {
                if let Err(e) = domain_event.apply_self(&*state.db_pool, wallet_id, user_id, db_id, event_row.created_at).await {
                    tracing::error!("Error applying event: {:?}", e);
                } else {
                    // Broadcast using pattern matching on DomainEvent
                    let broadcast_type = match domain_event {
                        DomainEvent::ContactCreated { .. }
                        | DomainEvent::ContactUpdated { .. }
                        | DomainEvent::ContactDeleted { .. }
                        | DomainEvent::ContactUndone { .. } => "contact",

                        DomainEvent::TransactionCreated { .. }
                        | DomainEvent::TransactionUpdated { .. }
                        | DomainEvent::TransactionDeleted { .. }
                        | DomainEvent::TransactionUndone { .. } => "transaction",

                        _ => "permission",
                    };
                    websocket::broadcast_events_synced(&state.broadcast_tx, wallet_id, broadcast_type);
                }

                // Handle UNDO: full wallet rebuild (using pattern matching)
                match domain_event {
                    DomainEvent::ContactUndone { .. } | DomainEvent::TransactionUndone { .. } => {
                        tracing::info!("UNDO event processed, rebuilding wallet projections");
                        if let Err(e) = Projections::rebuild_projections_from_events(&state, wallet_id).await {
                            tracing::error!("Error rebuilding projections: {:?}", e);
                        }
                    }
                    _ => {}
                }

                // Save snapshot if needed
                let event_count = db.get_event_count_for_wallet(wallet_id).await;
                let should_snapshot = snapshots::should_create_snapshot(event_count)
                    || matches!(domain_event, DomainEvent::ContactUndone { .. } | DomainEvent::TransactionUndone { .. });

                if should_snapshot {
                    if let Ok(snapshot_json) = snapshots::create_snapshot_json(&*state.db_pool, wallet_id).await {
                        let _ = snapshots::save_snapshot(
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

    Ok(Json(SyncEventsResponse { accepted, conflicts }))
}

/// Insert permission event directly (used by wallet management handlers)
pub async fn insert_permission_event_and_apply(
    state: &AppState,
    user_id: Uuid,
    wallet_id: Uuid,
    aggregate_id: Uuid,
    event_type: &str,
    event_data: serde_json::Value,
) -> Result<(), sqlx::Error> {
    let event_id = Uuid::new_v4();
    let db = Database::new((*state.db_pool).clone());

    // Insert event
    let _ = db.insert_event_impl(
        event_id,
        aggregate_id,
        "permission".to_string(),
        event_type.to_string(),
        event_data.clone(),
        wallet_id,
        user_id,
        1,
        None,
    ).await.map_err(|_| sqlx::Error::RowNotFound)?;

    // Build synthetic SyncEventRequest from inserted event and convert to DomainEvent
    let created_at = chrono::Utc::now();
    let sync_request = SyncEventRequest {
        id: event_id.to_string(),
        aggregate_type: "permission".to_string(),
        aggregate_id: aggregate_id.to_string(),
        event_type: event_type.to_string(),
        event_data: event_data.clone(),
        timestamp: created_at.to_rfc3339(),
        version: 1,
    };

    // Apply using DomainEvent (converted from SyncEventRequest)
    if let Ok(domain_event) = sync_request.to_domain_event(wallet_id, user_id, created_at) {
        if let Ok(Some(db_id)) = db.get_event_db_id_by_uuid(event_id).await {
            if let Ok(Some(event_row)) = db.get_event_by_id_impl(event_id).await {
                domain_event.apply_self(&*state.db_pool, wallet_id, user_id, db_id, event_row.created_at).await?;
                websocket::broadcast_events_synced(&state.broadcast_tx, wallet_id, "permission");
            }
        }
    }

    Ok(())
}
