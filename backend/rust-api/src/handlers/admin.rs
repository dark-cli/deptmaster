use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::{Json, Html},
};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, Row, postgres::PgRow, QueryBuilder};
use bcrypt::{hash, DEFAULT_COST};
use uuid::Uuid;
use chrono::Utc;
use crate::AppState;

#[derive(Deserialize)]
pub struct EventQuery {
    limit: Option<i64>,
    offset: Option<i64>,
    event_type: Option<String>,
    aggregate_type: Option<String>,
    user_id: Option<String>,
    wallet_id: Option<String>, // Filter by wallet (admin)
    search: Option<String>, // Search in event_data (comment, name, etc.)
    date_from: Option<String>, // ISO date string
    date_to: Option<String>, // ISO date string
}

#[derive(Deserialize)]
pub struct AdminListQuery {
    pub wallet_id: Option<String>,
}

#[derive(Serialize)]
pub struct EventResponse {
    pub event_id: String,
    pub aggregate_id: String, // Added aggregate_id to response
    pub aggregate_type: String,
    pub event_type: String,
    pub user_id: String,
    pub username: Option<String>,
    pub created_at: chrono::NaiveDateTime,
    pub event_data: serde_json::Value,
}

impl<'r> FromRow<'r, PgRow> for EventResponse {
    fn from_row(row: &'r PgRow) -> Result<Self, sqlx::Error> {
        Ok(Self {
            event_id: row.try_get::<uuid::Uuid, _>("event_id")?.to_string(),
            aggregate_id: row.try_get::<uuid::Uuid, _>("aggregate_id")?.to_string(),
            aggregate_type: row.try_get("aggregate_type")?,
            event_type: row.try_get("event_type")?,
            user_id: row.try_get::<uuid::Uuid, _>("user_id")?.to_string(),
            username: row.try_get("username").ok(),
            created_at: row.try_get("created_at")?,
            event_data: row.try_get("event_data")?,
        })
    }
}

#[derive(Serialize)]
pub struct ProjectionStatus {
    pub last_event_id: Option<i64>,
    pub projections_updated: Option<bool>,
    pub last_update: Option<chrono::DateTime<chrono::Utc>>,
}

pub async fn admin_panel() -> Html<&'static str> {
    Html(include_str!("../../static/admin/index.html"))
}

/// Serve favicon.ico
pub async fn favicon() -> axum::response::Response {
    use axum::response::{Response, IntoResponse};
    use axum::http::{header, StatusCode};
    use axum::body::Body;
    
    // Try to read favicon from multiple possible locations (relative to where server runs)
    // Server typically runs from rust-api directory, so paths are relative to that
    let favicon_paths = [
        "../mobile/web/favicon.png",  // From rust-api directory
        "mobile/web/favicon.png",     // From project root
        "static/admin/favicon.ico",
        "backend/rust-api/static/admin/favicon.ico",
        "../static/admin/favicon.ico",
    ];
    
    for path in &favicon_paths {
        if let Ok(content) = std::fs::read(path) {
            // Determine content type based on file extension
            let content_type = if path.ends_with(".png") {
                "image/png"
            } else {
                "image/x-icon"
            };
            
            return Response::builder()
                .status(StatusCode::OK)
                .header(header::CONTENT_TYPE, content_type)
                .body(Body::from(content))
                .unwrap()
                .into_response();
        }
    }
    
    // Return 404 if favicon not found
    Response::builder()
        .status(StatusCode::NOT_FOUND)
        .body(Body::from(""))
        .unwrap()
        .into_response()
}

/// Serve config.js with correct MIME type (optional config file)
/// Returns empty JavaScript if file doesn't exist (to avoid MIME type errors)
pub async fn config_js() -> axum::response::Response {
    use axum::response::{Response, IntoResponse};
    use axum::http::{header, StatusCode};
    use axum::body::Body;
    
    // Try to read config.js if it exists, otherwise return empty JS
    // Path is relative to where the server runs (usually rust-api directory)
    let config_paths = [
        "../static/admin/config.js",  // From rust-api directory
        "static/admin/config.js",     // From project root
        "backend/rust-api/static/admin/config.js",
    ];
    
    let mut found_content: Option<String> = None;
    for path in &config_paths {
        if let Ok(content) = std::fs::read_to_string(path) {
            found_content = Some(content);
            break;
        }
    }
    
    let content = found_content.unwrap_or_else(|| {
        "// Config file not found, using defaults\nwindow.ADMIN_CONFIG = {};".to_string()
    });
    
    Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, "application/javascript; charset=utf-8")
        .body(Body::from(content))
        .unwrap()
        .into_response()
}

pub async fn get_events(
    Query(params): Query<EventQuery>,
    State(state): State<AppState>,
) -> Result<Json<Vec<EventResponse>>, (StatusCode, Json<serde_json::Value>)> {
    let limit = params.limit.unwrap_or(100);
    let offset = params.offset.unwrap_or(0);

    // Build dynamic query with filters. Resolve actor username from users_projection (app users) or admin_users (admins).
    let mut query_builder: QueryBuilder<'_, sqlx::Postgres> = QueryBuilder::new(
        "SELECT e.event_id, e.aggregate_id, e.aggregate_type, e.event_type, e.user_id, COALESCE(u.username, a.username) AS username, e.created_at, e.event_data FROM events e LEFT JOIN users_projection u ON e.user_id = u.id LEFT JOIN admin_users a ON e.user_id = a.id AND a.is_active = true WHERE 1=1"
    );
    
    // Filter by event_type (case-insensitive, supports multiple formats)
    if let Some(event_type) = &params.event_type {
        if !event_type.is_empty() {
            // Handle specific formats:
            // - CREATED_TRANSACTION, UPDATE_TRANSACTION, DELETE_TRANSACTION
            // - CREATED_CONTACT, UPDATE_CONTACT, DELETE_CONTACT
            // - TRANSACTION_CREATED, TRANSACTION_UPDATED, TRANSACTION_DELETED
            // - CONTACT_CREATED, CONTACT_UPDATED, CONTACT_DELETED
            // - CREATED, UPDATED, DELETED (generic)
            
            // Parse user-friendly format (CREATED_TRANSACTION) to extract action and aggregate
            let (action, aggregate_opt) = if event_type.contains("_") {
                let parts: Vec<&str> = event_type.split("_").collect();
                if parts.len() >= 2 {
                    let action_part = parts[0].to_uppercase();
                    let aggregate_part = parts[1..].join("_").to_uppercase();
                    (action_part, Some(aggregate_part))
                } else {
                    (event_type.to_uppercase(), None)
                }
            } else {
                (event_type.to_uppercase(), None)
            };
            
            // Convert action to database format
            let db_action = if action == "CREATED" || action == "CREATE" {
                "CREATED".to_string()
            } else if action == "UPDATE" || action == "UPDATED" {
                "UPDATED".to_string()
            } else if action == "DELETE" || action == "DELETED" {
                "DELETED".to_string()
            } else {
                action
            };
            
            // Build query to match both specific and generic formats
            if let Some(aggregate) = aggregate_opt {
                // User selected CREATED_TRANSACTION - match:
                // 1. TRANSACTION_CREATED (server format)
                // 2. CREATED with aggregate_type = transaction (mobile app format)
                let db_action_clone = db_action.clone();
                query_builder.push(" AND (");
                query_builder.push("(UPPER(e.event_type) = UPPER(");
                query_builder.push_bind(format!("{}_{}", aggregate, db_action_clone.clone()));
                query_builder.push(") OR UPPER(e.event_type) LIKE UPPER(");
                query_builder.push_bind(format!("%{}_{}%", aggregate, db_action_clone.clone()));
                query_builder.push(")) OR (UPPER(e.event_type) = UPPER(");
                query_builder.push_bind(db_action_clone.clone());
                query_builder.push(") AND e.aggregate_type = ");
                query_builder.push_bind(aggregate.to_lowercase());
                query_builder.push("))");
            } else {
                // Generic filter (CREATED, UPDATED, DELETED) - match any format
                let db_action_clone = db_action.clone();
                query_builder.push(" AND (UPPER(e.event_type) = UPPER(");
                query_builder.push_bind(db_action_clone.clone());
                query_builder.push(") OR UPPER(e.event_type) LIKE UPPER(");
                query_builder.push_bind(format!("%{}%", db_action_clone));
                query_builder.push("))");
            }
        }
    }
    
    // Filter by aggregate_type
    if let Some(aggregate_type) = &params.aggregate_type {
        if !aggregate_type.is_empty() {
            query_builder.push(" AND e.aggregate_type = ");
            query_builder.push_bind(aggregate_type);
        }
    }
    
    // Filter by user_id
    if let Some(user_id) = &params.user_id {
        if !user_id.is_empty() {
            query_builder.push(" AND e.user_id::text = ");
            query_builder.push_bind(user_id);
        }
    }

    // Filter by wallet_id (admin view)
    if let Some(wallet_id) = &params.wallet_id {
        if !wallet_id.is_empty() {
            query_builder.push(" AND e.wallet_id::text = ");
            query_builder.push_bind(wallet_id);
        }
    }
    
    // Filter by date range
    if let Some(date_from) = &params.date_from {
        if !date_from.is_empty() {
            query_builder.push(" AND e.created_at >= ");
            query_builder.push_bind(date_from);
            query_builder.push("::timestamp");
        }
    }
    
    if let Some(date_to) = &params.date_to {
        if !date_to.is_empty() {
            query_builder.push(" AND e.created_at <= ");
            query_builder.push_bind(date_to);
            query_builder.push("::timestamp");
        }
    }
    
    // Search in event_data (comment, name, etc.)
    if let Some(search) = &params.search {
        if !search.is_empty() {
            let search_pattern = format!("%{}%", search);
            query_builder.push(" AND (e.event_data::text ILIKE ");
            query_builder.push_bind(search_pattern.clone());
            query_builder.push(" OR e.event_type ILIKE ");
            query_builder.push_bind(search_pattern.clone());
            query_builder.push(" OR e.aggregate_type ILIKE ");
            query_builder.push_bind(search_pattern);
            query_builder.push(")");
        }
    }
    
    query_builder.push(" ORDER BY e.created_at DESC LIMIT ");
    query_builder.push_bind(limit);
    query_builder.push(" OFFSET ");
    query_builder.push_bind(offset);
    
    let query = query_builder.build_query_as::<EventResponse>();
    let events = query.fetch_all(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching events: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": format!("Database error: {}", e)})),
        )
    })?;

    Ok(Json(events))
}

// Get the latest event ID for change detection
pub async fn get_latest_event_id(
    State(state): State<AppState>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<serde_json::Value>)> {
    use crate::database::repository::{Database, DatabaseRepository};

    let db = Database::new((*state.db_pool).clone());
    let latest_id = db.get_latest_event_id()
        .await
        .map_err(|e| {
            tracing::error!("Error fetching latest event ID: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": format!("Database error: {}", e)})),
            )
        })?;

    Ok(Json(serde_json::json!({
        "latest_event_id": latest_id,
        "timestamp": chrono::Utc::now().to_rfc3339()
    })))
}

// Delete an event if it's less than 5 seconds old (for undo functionality)
// delete_event endpoint removed - UNDO events are now used instead of event deletion

// Backfill events for transactions that don't have events
pub async fn backfill_transaction_events(
    State(state): State<AppState>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<serde_json::Value>)> {
    use crate::database::repository::{Database, DatabaseRepository};

    let db = Database::new((*state.db_pool).clone());

    // Get user ID
    let user_id = db.get_first_user_id()
        .await
        .map_err(|e| {
            tracing::error!("Error fetching user: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Database error"})),
            )
        })?
        .ok_or_else(|| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "No users found"})),
            )
        })?;

    // Get all transactions that don't have events
    let transactions = db.get_transactions_without_events()
        .await
        .map_err(|e| {
            tracing::error!("Error fetching transactions: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Database error"})),
            )
        })?;

    if transactions.is_empty() {
        return Ok(Json(serde_json::json!({
            "message": "All transactions already have events",
            "created": 0
        })));
    }

    let total_count = transactions.len();
    tracing::info!("Backfilling {} transaction events", total_count);

    let mut created_count = 0;
    let mut error_count = 0;

    for txn in transactions {
        // Create event data
        let event_data = serde_json::json!({
            "contact_id": txn.contact_id.to_string(),
            "type": txn.txn_type,
            "direction": txn.direction,
            "amount": txn.amount,
            "currency": txn.currency.unwrap_or_else(|| "USD".to_string()),
            "description": txn.description,
            "transaction_date": txn.transaction_date.format("%Y-%m-%d").to_string(),
            "due_date": txn.due_date.map(|d| d.format("%Y-%m-%d").to_string()),
            "comment": format!("Backfilled event for existing transaction - Created: {}", txn.created_at.format("%Y-%m-%d %H:%M:%S")),
            "timestamp": txn.created_at.format("%Y-%m-%dT%H:%M:%S%.fZ").to_string()
        });

        // Insert event
        match db.insert_backfill_event(user_id, txn.id, event_data, txn.created_at).await {
            Ok(eid) => {
                // Update transaction's last_event_id
                if let Err(e) = db.update_transaction_last_event_id(txn.id, eid).await {
                    tracing::error!("Error updating transaction last_event_id: {:?}", e);
                }
                created_count += 1;
            }
            Err(e) => {
                tracing::error!("Error creating event for transaction {}: {:?}", txn.id, e);
                error_count += 1;
            }
        }
    }

    Ok(Json(serde_json::json!({
        "message": "Backfill complete",
        "created": created_count,
        "errors": error_count,
        "total_processed": total_count
    })))
}

pub async fn get_projection_status(
    State(state): State<AppState>,
) -> Result<Json<ProjectionStatus>, (StatusCode, Json<serde_json::Value>)> {
    use crate::database::repository::{Database, DatabaseRepository};

    let db = Database::new((*state.db_pool).clone());
    let last_event = db.get_latest_event_id()
        .await
        .map_err(|e| {
            tracing::error!("Error fetching projection status: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": format!("Database error: {}", e)})),
            )
        })?;

    Ok(Json(ProjectionStatus {
        last_event_id: last_event,
        projections_updated: Some(true),
        last_update: Some(chrono::Utc::now()),
    }))
}

/// Get total debt.
/// - Optional query param wallet_id: when set, returns total debt for that wallet (from latest event or projection).
/// - When not set ("All wallets"), returns the sum of total debt across all wallets (from projections).
pub async fn get_total_debt(
    Query(params): Query<std::collections::HashMap<String, String>>,
    State(state): State<AppState>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<serde_json::Value>)> {
    use crate::database::repository::{Database, DatabaseRepository};
    use uuid::Uuid;

    let db = Database::new((*state.db_pool).clone());
    let wallet_id_param = params.get("wallet_id").and_then(|s| {
        let s = s.trim();
        if s.is_empty() { None } else { Some(s) }
    });

    let total_debt = if let Some(wid) = wallet_id_param {
        // Single wallet: use latest event total_debt when available, else projection
        match Uuid::parse_str(wid) {
            Ok(wallet_id) => {
                db.get_total_debt_for_wallet(wallet_id)
                    .await
                    .unwrap_or(0)
            }
            Err(_) => {
                return Err((
                    StatusCode::BAD_REQUEST,
                    Json(serde_json::json!({"error": "Invalid wallet_id format"})),
                ));
            }
        }
    } else {
        // All wallets: always use projection sum so we get the sum of every wallet's total
        db.get_total_debt_all_wallets()
            .await
            .unwrap_or(0)
    };

    Ok(Json(serde_json::json!({
        "total_debt": total_debt
    })))
}

/// Rebuild projections from all events for a specific wallet
/// Requires wallet_id query parameter: ?wallet_id=...
pub async fn rebuild_projections(
    Query(params): Query<std::collections::HashMap<String, String>>,
    State(state): State<AppState>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<serde_json::Value>)> {
    use crate::services::projections::Projections;

    // Get wallet_id from query parameters
    let wallet_id_str = params.get("wallet_id")
        .ok_or_else(|| {
            (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({"error": "wallet_id query parameter is required"})),
            )
        })?;

    let wallet_id = uuid::Uuid::parse_str(wallet_id_str)
        .map_err(|e| {
            (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({"error": format!("Invalid wallet_id: {}", e)})),
            )
        })?;

    match Projections::rebuild_projections_from_events(&state, wallet_id).await {
        Ok(_) => Ok(Json(serde_json::json!({
            "message": "Projections rebuilt successfully"
        }))),
        Err(e) => {
            tracing::error!("Error rebuilding projections: {:?}", e);
            Err((
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": format!("Failed to rebuild projections: {}", e)})),
            ))
        }
    }
}

/// Dev-only endpoint: Clear all database data (only available in development mode)
/// This endpoint is used by integration tests to reset the database state
pub async fn dev_clear_database(
    State(state): State<AppState>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<serde_json::Value>)> {
    use std::env;
    
    // Only allow in development mode
    let environment = env::var("ENVIRONMENT")
        .unwrap_or_else(|_| "development".to_string())
        .to_lowercase();
    
    if environment == "production" {
        return Err((
            StatusCode::FORBIDDEN,
            Json(serde_json::json!({
                "error": "This endpoint is only available in development mode"
            })),
        ));
    }
    
    tracing::info!("🧹 Dev clear database endpoint called - clearing all data...");
    
    // Start a transaction to ensure atomicity
    let mut tx = state.db_pool.begin().await.map_err(|e| {
        tracing::error!("Error starting transaction: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": format!("Database error: {}", e)})),
        )
    })?;
    
    // Truncate all tables in correct order (respecting foreign key constraints)
    // Delete in reverse dependency order
    sqlx::query("TRUNCATE TABLE login_logs CASCADE")
        .execute(&mut *tx)
        .await
        .map_err(|e| {
            tracing::error!("Error truncating login_logs: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": format!("Database error: {}", e)})),
            )
        })?;
    
    sqlx::query("TRUNCATE TABLE projection_snapshots CASCADE")
        .execute(&mut *tx)
        .await
        .map_err(|e| {
            tracing::error!("Error truncating projection_snapshots: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": format!("Database error: {}", e)})),
            )
        })?;
    
    sqlx::query("TRUNCATE TABLE transactions_projection CASCADE")
        .execute(&mut *tx)
        .await
        .map_err(|e| {
            tracing::error!("Error truncating transactions_projection: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": format!("Database error: {}", e)})),
            )
        })?;
    
    sqlx::query("TRUNCATE TABLE contacts_projection CASCADE")
        .execute(&mut *tx)
        .await
        .map_err(|e| {
            tracing::error!("Error truncating contacts_projection: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": format!("Database error: {}", e)})),
            )
        })?;
    
    sqlx::query("TRUNCATE TABLE events CASCADE")
        .execute(&mut *tx)
        .await
        .map_err(|e| {
            tracing::error!("Error truncating events: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": format!("Database error: {}", e)})),
            )
        })?;
    
    // Keep admin_users and users_projection, but clear all users except test user
    sqlx::query("DELETE FROM users_projection WHERE username != 'max'")
        .execute(&mut *tx)
        .await
        .map_err(|e| {
            tracing::error!("Error cleaning users_projection: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": format!("Database error: {}", e)})),
            )
        })?;
    
    // Hash passwords using bcrypt
    // Hash password for regular user "max" with password "12345678"
    let max_password_hash = hash("12345678", DEFAULT_COST).map_err(|e| {
        tracing::error!("Error hashing password for max: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": format!("Database error: {}", e)})),
        )
    })?;
    
    // Ensure test user "max" exists with password "12345678"
    sqlx::query(
        r#"
        INSERT INTO users_projection (id, username, password_hash, created_at, last_event_id)
        VALUES (gen_random_uuid(), 'max', $1, NOW(), 0)
        ON CONFLICT (username) DO UPDATE SET password_hash = $1, last_event_id = 0
        "#,
    )
    .bind(&max_password_hash)
    .execute(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!("Error ensuring test user exists: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": format!("Database error: {}", e)})),
        )
    })?;
    
    // Hash password for admin user "admin" with password "admin"
    let admin_password_hash = hash("admin", DEFAULT_COST).map_err(|e| {
        tracing::error!("Error hashing password for admin: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": format!("Database error: {}", e)})),
        )
    })?;
    
    // Ensure admin user "admin" exists with password "admin"
    let admin_id = Uuid::new_v4();
    sqlx::query(
        r#"
        INSERT INTO admin_users (id, username, password_hash, email, is_active, created_at)
        VALUES ($1, 'admin', $2, 'admin@debitum.local', true, $3)
        ON CONFLICT (username) DO UPDATE SET password_hash = $2, is_active = true
        "#,
    )
    .bind(&admin_id)
    .bind(&admin_password_hash)
    .bind(Utc::now())
    .execute(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!("Error ensuring admin user exists: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": format!("Database error: {}", e)})),
        )
    })?;
    
    // Commit transaction
    tx.commit().await.map_err(|e| {
        tracing::error!("Error committing transaction: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": format!("Database error: {}", e)})),
        )
    })?;
    
    tracing::info!("✅ Database cleared successfully");
    
    Ok(Json(serde_json::json!({
        "message": "Database cleared successfully",
        "test_user": "max"
    })))
}
