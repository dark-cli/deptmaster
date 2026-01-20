use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use crate::AppState;
use sha2::{Sha256, Digest};

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
                timestamp: row.get::<chrono::NaiveDateTime, _>("created_at").to_rfc3339(),
                version: row.get("event_version"),
            }
        })
        .collect();

    Ok(Json(sync_events))
}

#[derive(Deserialize)]
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

        // Insert new event
        let result = sqlx::query(
            r#"
            INSERT INTO events (event_id, user_id, aggregate_type, aggregate_id, event_type, event_version, event_data, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            ON CONFLICT (event_id) DO NOTHING
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
        .execute(&*state.db_pool)
        .await;

        match result {
            Ok(result) => {
                if result.rows_affected() > 0 {
                    accepted.push(event.id);
                } else {
                    // Conflict (duplicate)
                    conflicts.push(event.id);
                }
            }
            Err(e) => {
                tracing::error!("Error inserting event: {:?}", e);
                conflicts.push(event.id);
            }
        }
    }

    Ok(Json(SyncEventsResponse {
        accepted,
        conflicts,
    }))
}
