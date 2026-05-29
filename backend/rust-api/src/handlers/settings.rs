use axum::{
    extract::State,
    http::StatusCode,
    response::Json,
    extract::Extension,
};
use serde::{Deserialize, Serialize};
use crate::AppState;
use crate::database::repository::{DatabaseRepository, Database};
use crate::middleware::auth::AuthUser;

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
    Extension(auth_user): Extension<AuthUser>,
    State(state): State<AppState>,
) -> Result<Json<SettingsResponse>, (StatusCode, Json<serde_json::Value>)> {
    let db = Database::new((*state.db_pool).clone());

    // Get all settings for this user
    let settings = db.get_user_settings_all(auth_user.user_id)
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
    Extension(auth_user): Extension<AuthUser>,
    axum::extract::Path(setting_key): axum::extract::Path<String>,
    State(state): State<AppState>,
    Json(payload): Json<UpdateSettingRequest>,
) -> Result<Json<SettingResponse>, (StatusCode, Json<serde_json::Value>)> {
    let db = Database::new((*state.db_pool).clone());

    // Upsert setting
    db.upsert_user_setting(auth_user.user_id, &setting_key, &payload.value)
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
