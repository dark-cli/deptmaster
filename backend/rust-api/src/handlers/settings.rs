use axum::{
    extract::State,
    http::StatusCode,
    response::Json,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use crate::AppState;

#[derive(Deserialize)]
pub struct UpdateSettingRequest {
    pub value: String,
}

#[derive(Serialize)]
pub struct SettingResponse {
    pub key: String,
    pub value: String,
}

#[derive(Serialize)]
pub struct SettingsResponse {
    pub dark_mode: bool,
    pub default_direction: String,
    pub flip_colors: bool,
    pub due_date_enabled: bool,
    pub default_due_date_days: i32,
    pub default_due_date_switch: bool,
}

// Get all settings for the current user
pub async fn get_settings(
    State(state): State<AppState>,
) -> Result<Json<SettingsResponse>, (StatusCode, Json<serde_json::Value>)> {
    let user_id = sqlx::query_scalar::<_, Uuid>(
        "SELECT id FROM users_projection LIMIT 1"
    )
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching user: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    // Get all settings for this user
    let settings = sqlx::query_as::<_, (String, Option<String>)>(
        "SELECT setting_key, setting_value FROM user_settings WHERE user_id = $1"
    )
    .bind(user_id)
    .fetch_all(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching settings: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    let mut dark_mode = true; // Default
    let mut default_direction = "give".to_string();
    let mut flip_colors = false;
    let mut due_date_enabled = false;
    let mut default_due_date_days = 30;
    let mut default_due_date_switch = false;

    for (key, value) in settings {
        match key.as_str() {
            "dark_mode" => dark_mode = value.as_deref().unwrap_or("true") == "true",
            "default_direction" => default_direction = value.unwrap_or_else(|| "give".to_string()),
            "flip_colors" => flip_colors = value.as_deref().unwrap_or("false") == "true",
            "due_date_enabled" => due_date_enabled = value.as_deref().unwrap_or("false") == "true",
            "default_due_date_days" => default_due_date_days = value.and_then(|v| v.parse().ok()).unwrap_or(30),
            "default_due_date_switch" => default_due_date_switch = value.as_deref().unwrap_or("false") == "true",
            _ => {}
        }
    }

    Ok(Json(SettingsResponse {
        dark_mode,
        default_direction,
        flip_colors,
        due_date_enabled,
        default_due_date_days,
        default_due_date_switch,
    }))
}

// Update a specific setting
pub async fn update_setting(
    axum::extract::Path(setting_key): axum::extract::Path<String>,
    State(state): State<AppState>,
    Json(payload): Json<UpdateSettingRequest>,
) -> Result<Json<SettingResponse>, (StatusCode, Json<serde_json::Value>)> {
    let user_id = sqlx::query_scalar::<_, Uuid>(
        "SELECT id FROM users_projection LIMIT 1"
    )
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching user: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    // Upsert setting
    sqlx::query(
        r#"
        INSERT INTO user_settings (user_id, setting_key, setting_value, updated_at)
        VALUES ($1, $2, $3, NOW())
        ON CONFLICT (user_id, setting_key)
        DO UPDATE SET setting_value = $3, updated_at = NOW()
        "#
    )
    .bind(user_id)
    .bind(&setting_key)
    .bind(&payload.value)
    .execute(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error updating setting: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to update setting"})),
        )
    })?;

    Ok(Json(SettingResponse {
        key: setting_key,
        value: payload.value,
    }))
}
