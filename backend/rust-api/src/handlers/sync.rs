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
use crate::permissions::{PermissionContext, PermissionModel};
use crate::database::repository::Database;
use crate::database::models::EventRow;
use crate::services::projections::Projections;
use crate::domain::{DomainEvent, EventData};
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

    // Check all event permissions at once (batched by PermissionModel)
    let denied_event_ids = perm_model
        .get_denied_event_ids(&perm_ctx, &events)
        .await
        .map_err(|_| responses::insufficient_permission_response())?;

    // All-or-nothing: if ANY event is denied, reject the entire batch
    if !denied_event_ids.is_empty() {
        return Err(responses::insufficient_permission_response());
    }

    // Deduplicate within the batch (check for duplicate event_ids in the incoming request)
    let mut seen_ids = std::collections::HashSet::new();
    let mut unique_events = Vec::new();
    let mut duplicate_event_ids = Vec::new();

    for event in events {
        let event_id = event.id;
        if !seen_ids.insert(event_id) {
            // Duplicate within batch - skip processing
            duplicate_event_ids.push(event_id.to_string());
        } else {
            unique_events.push(event);
        }
    }

    // Process unique events only
    let mut accepted = Vec::new();
    let mut skipped = duplicate_event_ids; // Duplicates found in batch

    for domain_event in unique_events {
        let event_id = domain_event.id;
        let aggregate_id = domain_event.aggregate_id;

        // Check idempotency: if event already exists, skip silently (idempotent operation)
        let existing = db.get_event_by_id_impl(event_id)
            .await
            .map_err(|_| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(serde_json::json!({"error": "Database error"})),
                )
            })?;

        if existing.is_some() {
            // Already synced before - idempotent, skip without error
            skipped.push(event_id.to_string());
            continue;
        }

        // Serialize event_data: remove the serde(tag) "type" field since event_type is stored separately
        let mut event_data = serde_json::to_value(&domain_event.event_data)
            .unwrap_or_else(|_| serde_json::json!({}));

        // Remove the serde tag discriminator field (not needed since event_type is stored separately)
        if let Some(obj) = event_data.as_object_mut() {
            obj.remove("type");
        }

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
            domain_event.version,
            None,
        ).await.is_err() {
            skipped.push(event_id.to_string());
            continue;
        }

        accepted.push(event_id.to_string());

        // Apply event to projections via database layer
        let rows: Vec<_> = sqlx::query(
            "SELECT id, event_id, aggregate_id, aggregate_type, event_type, event_data, wallet_id, user_id, created_at, event_version FROM events WHERE event_id = $1 AND wallet_id = $2"
        )
        .bind(event_id)
        .bind(wallet_id)
        .fetch_all(&*state.db_pool)
        .await
        .unwrap_or_default();

        if !rows.is_empty() {
            let row_refs: Vec<_> = rows.iter().collect();
            let mut undone_set = std::collections::HashSet::new();
            if let Err(e) = db.apply_event_batch(&row_refs, user_id, wallet_id, &mut undone_set).await {
                tracing::error!("Error applying event: {:?}", e);
            }
        }

        // Broadcast using event_data discriminant
        let broadcast_type = match &domain_event.event_data {
            EventData::ContactCreated { .. }
            | EventData::ContactUpdated { .. }
            | EventData::ContactDeleted { .. }
            | EventData::ContactUndone { .. } => "contact",

            EventData::TransactionCreated { .. }
            | EventData::TransactionUpdated { .. }
            | EventData::TransactionDeleted { .. }
            | EventData::TransactionUndone { .. } => "transaction",

            _ => "permission",
        };
        websocket::broadcast_events_synced(&state.broadcast_tx, wallet_id, broadcast_type);

        // Handle UNDO: full wallet rebuild
        match &domain_event.event_data {
            EventData::ContactUndone { .. } | EventData::TransactionUndone { .. } => {
                tracing::info!("UNDO event processed, rebuilding wallet projections");
                if let Err(e) = Projections::rebuild_projections_from_events(&state, wallet_id).await {
                    tracing::error!("Error rebuilding projections: {:?}", e);
                }
            }
            _ => {}
        }

        // Save snapshot if needed
        let event_count = db.get_event_count_for_wallet(wallet_id).await;
        let should_snapshot = snapshots::should_create_snapshot_with_interval(event_count, state.config.snapshot_interval)
            || matches!(&domain_event.event_data, EventData::ContactUndone { .. } | EventData::TransactionUndone { .. });

        if should_snapshot {
            if let Ok(snapshot_json) = snapshots::create_snapshot_json(&*state.db_pool, wallet_id).await {
                let _ = snapshots::save_snapshot_with_limit(
                    &*state.db_pool,
                    1,
                    event_count,
                    snapshot_json.0,
                    snapshot_json.1,
                    wallet_id,
                    state.config.max_snapshots_per_wallet,
                ).await;
            }
        }
    }

    Ok(Json(SyncEventsResponse { accepted, conflicts: skipped }))
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
    let _sync_request = SyncEventRequest {
        id: event_id.to_string(),
        aggregate_type: "permission".to_string(),
        aggregate_id: aggregate_id.to_string(),
        event_type: event_type.to_string(),
        event_data: event_data.clone(),
        timestamp: created_at.to_rfc3339(),
        version: 1,
    };

    // Event stored, broadcast permission change
    websocket::broadcast_events_synced(&state.broadcast_tx, wallet_id, "permission");

    Ok(())
}