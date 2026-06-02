use axum::{
    extract::{Extension, Query, State},
    http::StatusCode,
    response::Json,
};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use uuid::Uuid;

use crate::database::repository::Database;
use crate::domain::events::{DomainEvent, EventData};
use crate::handlers::responses;
use crate::middleware::auth::AuthUser;
use crate::middleware::wallet_context::WalletContext;
use crate::permissions::{PermissionContext, PermissionModel};
use crate::services::projections::Projections;
use crate::services::snapshots;
use crate::websocket;
use crate::AppState;

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


// ============ PUBLIC ENDPOINTS ============

/// Get hash of all events for sync comparison (permission-filtered)
/// Returns pre-calculated incremental hash stored in user_event_hashes table (O(1))
pub async fn get_sync_hash(
    State(state): State<AppState>,
    Extension(wallet_context): Extension<WalletContext>,
    Extension(auth_user): Extension<AuthUser>,
) -> Result<Json<SyncHashResponse>, (StatusCode, Json<serde_json::Value>)> {
    let wallet_id = wallet_context.wallet_id;
    let user_id = auth_user.user_id;
    let db = Database::new((*state.db_pool).clone());

    let (hash, event_count, last_event_timestamp) = db
        .get_sync_hash_data_impl(wallet_id, user_id)
        .await
        .map_err(|e| {
            tracing::error!("Error fetching sync hash data: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to fetch sync hash"})),
            )
        })?;

    Ok(Json(SyncHashResponse {
        hash,
        event_count,
        last_event_timestamp,
    }))
}

/// Get events since timestamp (permission-filtered)
/// Tries cache first for O(1) lookup, falls back to permission model if cache is empty
pub async fn get_sync_events(
    Query(params): Query<SyncEventsQuery>,
    State(state): State<AppState>,
    Extension(wallet_context): Extension<WalletContext>,
    Extension(auth_user): Extension<AuthUser>,
) -> Result<Json<Vec<SyncEvent>>, (StatusCode, Json<serde_json::Value>)> {
    let wallet_id = wallet_context.wallet_id;
    let user_id = auth_user.user_id;
    let db = Database::new((*state.db_pool).clone());

    // Parse timestamp if provided
    let since = match &params.since {
        Some(since_str) => Some(parse_timestamp(since_str)?),
        None => None,
    };

    // Get readable events from denormalized table
    let events = db
        .get_readable_events_impl(wallet_id, user_id, since)
        .await
        .map_err(|e| {
            tracing::error!("Error fetching readable events: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to fetch events"})),
            )
        })?;

    // Convert to response
    let sync_events: Vec<SyncEvent> = events
        .into_iter()
        .map(|event| SyncEvent {
            id: event.id.to_string(),
            aggregate_type: event.aggregate_type_enum().as_str().to_string(),
            aggregate_id: event.aggregate_id.to_string(),
            event_type: event.event_type().to_string(),
            event_data: serde_json::to_value(&event.event_data).unwrap_or_default(),
            timestamp: event.created_at.to_rfc3339(),
            version: event.version,
        })
        .collect();

    Ok(Json(sync_events))
}

fn get_broadcast_type(event_data: &EventData) -> &'static str {
    match event_data {
        EventData::ContactCreated { .. }
        | EventData::ContactUpdated { .. }
        | EventData::ContactDeleted { .. }
        | EventData::ContactUndone { .. } => "contact",
        EventData::TransactionCreated { .. }
        | EventData::TransactionUpdated { .. }
        | EventData::TransactionDeleted { .. }
        | EventData::TransactionUndone { .. } => "transaction",
        _ => "permission",
    }
}

fn is_undo_event(event_data: &EventData) -> bool {
    matches!(
        event_data,
        EventData::ContactUndone { .. } | EventData::TransactionUndone { .. }
    )
}

fn parse_timestamp(
    since_str: &str,
) -> Result<DateTime<Utc>, (StatusCode, Json<serde_json::Value>)> {
    DateTime::parse_from_rfc3339(since_str)
        .ok()
        .map(|dt| dt.with_timezone(&Utc))
        .ok_or_else(|| {
            (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({"error": "Invalid timestamp format"})),
            )
        })
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

    // Check permissions
    let perm_ctx = PermissionContext::new(wallet_id, user_id, wallet_context.user_role);
    let perm_model = PermissionModel::new((*state.db_pool).clone());
    let denied_event_ids = perm_model
        .get_denied_event_ids(&perm_ctx, &events)
        .await
        .map_err(|_| responses::insufficient_permission_response())?;

    if !denied_event_ids.is_empty() {
        return Err(responses::insufficient_permission_response());
    }

    // Deduplicate within batch
    let (unique_events, duplicate_ids) = deduplicate_events(events);

    // Try to insert all unique events, let database handle conflicts
    let mut accepted = Vec::new();
    let mut skipped = duplicate_ids;
    let mut accepted_events = Vec::new();

    for domain_event in unique_events {
        match insert_event(&db, wallet_id, user_id, &domain_event).await {
            Ok(inserted) => {
                if inserted {
                    // Event was actually inserted (new to database)
                    accepted.push(domain_event.id.to_string());
                    accepted_events.push(domain_event);
                } else {
                    // Event already existed in database (ON CONFLICT skipped it)
                    skipped.push(domain_event.id.to_string());
                }
            }
            Err(e) => {
                // Insert failed for other reasons
                tracing::error!("Failed to insert event {}: {:?}", domain_event.id, e);
                skipped.push(domain_event.id.to_string());
            }
        }
    }

    // Batch populate cache for all accepted events (automatically done by database)
    if !accepted_events.is_empty() {
        if let Err(e) = db.populate_event_cache(wallet_id, &accepted_events).await {
            tracing::error!("Error populating event cache: {:?}", e);
        }

        // Batch apply all events to projections
        let event_ids: Vec<Uuid> = accepted_events.iter().map(|e| e.id).collect();
        apply_events_batch(&db, wallet_id, user_id, &event_ids).await;

        // Track undo events for rebuild
        let has_undo = accepted_events.iter().any(|e| is_undo_event(&e.event_data));
        if has_undo {
            tracing::info!("UNDO event processed, rebuilding wallet projections");
            if let Err(e) = Projections::rebuild_projections_from_events(&state, wallet_id).await {
                tracing::error!("Error rebuilding projections: {:?}", e);
            }
        }

        // Batch broadcast: group by type and notify once per type
        let mut broadcast_types = HashSet::new();
        for event in &accepted_events {
            broadcast_types.insert(get_broadcast_type(&event.event_data));
        }
        for broadcast_type in broadcast_types {
            websocket::broadcast_events_synced(&state.broadcast_tx, wallet_id, broadcast_type);
        }

        // Handle snapshots for each event that triggers one
        for domain_event in accepted_events {
            create_snapshot_if_needed(&db, &state, wallet_id, &domain_event).await;
        }
    }

    Ok(Json(SyncEventsResponse {
        accepted,
        conflicts: skipped,
    }))
}

fn deduplicate_events(events: Vec<DomainEvent>) -> (Vec<DomainEvent>, Vec<String>) {
    let mut seen_ids = HashSet::new();
    let mut unique = Vec::new();
    let mut duplicates = Vec::new();

    for event in events {
        if !seen_ids.insert(event.id) {
            duplicates.push(event.id.to_string());
        } else {
            unique.push(event);
        }
    }

    (unique, duplicates)
}

async fn insert_event(
    db: &Database,
    wallet_id: Uuid,
    user_id: Uuid,
    domain_event: &DomainEvent,
) -> Result<bool, Box<dyn std::error::Error>> {
    let mut event_data = serde_json::to_value(&domain_event.event_data)
        .unwrap_or_else(|_| serde_json::json!({}));

    if let Some(obj) = event_data.as_object_mut() {
        obj.remove("type");
    }

    let inserted_id = db.insert_event_impl(
        domain_event.id,
        domain_event.aggregate_id,
        domain_event.aggregate_type_enum().as_str().to_string(),
        domain_event.event_type().to_string(),
        event_data,
        wallet_id,
        user_id,
        domain_event.version,
        None,
    )
    .await?;

    // If id is 0, event already existed (ON CONFLICT DO NOTHING returned nothing)
    Ok(inserted_id > 0)
}

async fn apply_events_batch(
    db: &Database,
    wallet_id: Uuid,
    user_id: Uuid,
    event_ids: &[Uuid],
) {
    if event_ids.is_empty() {
        return;
    }

    let rows: Vec<_> = sqlx::query(
        "SELECT id, event_id, aggregate_id, aggregate_type, event_type, event_data, wallet_id, user_id, created_at, event_version FROM events WHERE event_id = ANY($1) AND wallet_id = $2"
    )
    .bind(event_ids)
    .bind(wallet_id)
    .fetch_all(db.pool())
    .await
    .unwrap_or_default();

    if !rows.is_empty() {
        let row_refs: Vec<_> = rows.iter().collect();
        let mut undone_set = HashSet::new();
        if let Err(e) = db.apply_event_batch(&row_refs, user_id, wallet_id, &mut undone_set).await {
            tracing::error!("Error applying event batch: {:?}", e);
        }
    }
}

async fn create_snapshot_if_needed(
    db: &Database,
    state: &AppState,
    wallet_id: Uuid,
    domain_event: &DomainEvent,
) {
    let event_count = db.get_event_count_for_wallet(wallet_id).await;
    let should_snapshot = snapshots::should_create_snapshot_with_interval(
        event_count,
        state.config.snapshot_interval,
    ) || is_undo_event(&domain_event.event_data);

    if should_snapshot {
        if let Ok(snapshot_json) = snapshots::create_snapshot_json(db.pool(), wallet_id).await {
            let _ = snapshots::save_snapshot_with_limit(
                db.pool(),
                1,
                event_count,
                snapshot_json.0,
                snapshot_json.1,
                wallet_id,
                state.config.max_snapshots_per_wallet,
            )
            .await;
        }
    }
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
    let _ = db
        .insert_event_impl(
            event_id,
            aggregate_id,
            "permission".to_string(),
            event_type.to_string(),
            event_data.clone(),
            wallet_id,
            user_id,
            1,
            Some(Uuid::new_v4().to_string()),
        )
        .await
        .map_err(|_| sqlx::Error::RowNotFound)?;

    // Apply event to projections
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
        if let Err(e) = db
            .apply_event_batch(&row_refs, user_id, wallet_id, &mut undone_set)
            .await
        {
            tracing::error!("Error applying event: {:?}", e);
        }
    }

    // Permission events are readable by all wallet users - add to their readable events cache
    let wallet_users = match db.get_wallet_users_impl(wallet_id).await {
        Ok(users) => users,
        Err(e) => {
            tracing::error!("Error fetching wallet users for permission event cache: {:?}", e);
            Vec::new()
        }
    };

    for (wallet_user_id, _role) in wallet_users {
        if let Err(e) = db
            .add_readable_event_impl(wallet_id, wallet_user_id, event_id)
            .await
        {
            tracing::error!(
                "Error adding readable permission event for user: {:?}",
                e
            );
        }
    }

    // Broadcast permission change
    websocket::broadcast_events_synced(&state.broadcast_tx, wallet_id, "permission");

    Ok(())
}