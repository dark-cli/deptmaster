//! Authentication endpoints: login, register, refresh, logout.

use crate::database;
use crate::types::error::ClientError;
use super::{base_url, CLIENT, RUNTIME};

fn persist_auth_response(json: &serde_json::Value) -> Result<(), ClientError> {
    let token = json
        .get("token")
        .and_then(|v| v.as_str())
        .ok_or(ClientError::InvalidResponse("No token in auth response".to_string()))?;
    let refresh_token = json
        .get("refresh_token")
        .and_then(|v| v.as_str())
        .ok_or(ClientError::InvalidResponse("No refresh_token in auth response".to_string()))?;
    let user_id = json
        .get("user_id")
        .and_then(|v| v.as_str())
        .ok_or(ClientError::InvalidResponse("No user_id in auth response".to_string()))?;
    database::config_set("token", token)?;
    database::config_set("refresh_token", refresh_token)?;
    database::config_set("user_id", user_id)?;
    Ok(())
}

fn try_refresh_blocking() -> Result<(), ClientError> {
    let refresh_token = database::config_get("refresh_token")
        ?
        .ok_or(ClientError::AuthExpired)?;
    let base = base_url()?;
    let url = format!("{}/api/auth/refresh", base.trim_end_matches('/'));
    let body = serde_json::json!({ "refresh_token": refresh_token });
    let result: Result<serde_json::Value, ClientError> = RUNTIME.block_on(async {
        let resp = CLIENT
            .post(&url)
            .json(&body)
            .send()
            .await?;
        let status = resp.status();
        let text = resp.text().await.map_err(|e| ClientError::Network(e.to_string()))?;
        if !status.is_success() {
            return Err(ClientError::Sync(format!("refresh failed: {} {}", status, text)));
        }
        serde_json::from_str::<serde_json::Value>(&text).map_err(ClientError::from)
    });
    match result {
        Ok(json) => persist_auth_response(&json),
        Err(e) => {
            let _ = database::clear_all();
            crate::integration::data_bus::emit(crate::integration::data_bus::DataChangeKind::Session, None);
            Err(e)
        }
    }
}

fn jwt_needs_refresh(token: &str) -> bool {
    use base64::Engine;
    let payload = match token.split('.').nth(1) {
        Some(p) => p,
        None => return true,
    };
    let bytes = match base64::engine::general_purpose::URL_SAFE_NO_PAD.decode(payload) {
        Ok(b) => b,
        Err(_) => return true,
    };
    let json: serde_json::Value = match serde_json::from_slice(&bytes) {
        Ok(j) => j,
        Err(_) => return true,
    };
    let exp = match json.get("exp").and_then(|v| v.as_i64()) {
        Some(e) => e,
        None => return true,
    };
    let now = chrono::Utc::now().timestamp();
    exp - now < 60
}

pub(super) fn auth_headers() -> Result<reqwest::header::HeaderMap, ClientError> {
    let mut token = database::config_get("token")
        ?
        .ok_or(ClientError::AuthExpired)?;
    if jwt_needs_refresh(&token) {
        try_refresh_blocking()?;
        token = database::config_get("token")
            ?
            .ok_or(ClientError::AuthExpired)?;
    }
    let mut headers = reqwest::header::HeaderMap::new();
    headers.insert(
        reqwest::header::AUTHORIZATION,
        format!("Bearer {}", token)
            .parse()
            .map_err(|e: reqwest::header::InvalidHeaderValue| ClientError::Internal(e.to_string()))?,
    );
    headers.insert(
        reqwest::header::CONTENT_TYPE,
        "application/json".parse().unwrap(),
    );
    Ok(headers)
}

pub fn login(username: String, password: String) -> Result<(), ClientError> {
    let base = base_url()?;
    let url = format!("{}/api/auth/login", base);
    let body = serde_json::json!({ "username": username, "password": password });
    RUNTIME.block_on(async {
        let resp = CLIENT
            .post(&url)
            .json(&body)
            .send()
            .await?;
        let status = resp.status();
        let text = resp.text().await.map_err(|e| ClientError::Network(e.to_string()))?;
        if status.as_u16() == 401 && text.contains("DEBITUM_AUTH_DECLINED") {
            return Err(ClientError::AuthDeclined);
        }
        if !status.is_success() {
            return Err(ClientError::Sync(format!("Login failed: {} - {}", status, text)));
        }
        let json: serde_json::Value = serde_json::from_str(&text).map_err(ClientError::from)?;
        persist_auth_response(&json)?;
        crate::integration::data_bus::emit(crate::integration::data_bus::DataChangeKind::Session, None);
        Ok(())
    })
}

pub fn register(username: String, password: String) -> Result<(), ClientError> {
    let base = base_url()?;
    let url = format!("{}/api/auth/register", base.trim_end_matches('/'));
    let body = serde_json::json!({ "username": username.trim(), "password": password });
    RUNTIME.block_on(async {
        let resp = CLIENT
            .post(&url)
            .json(&body)
            .send()
            .await?;
        let status = resp.status();
        let text = resp.text().await.map_err(|e| ClientError::Network(e.to_string()))?;
        if status.as_u16() == 409 {
            return Err(ClientError::InvalidInput("This username is already taken".to_string()));
        }
        if !status.is_success() {
            return Err(ClientError::Sync(format!("{} - {}", status, text)));
        }
        let json: serde_json::Value = serde_json::from_str(&text).map_err(ClientError::from)?;
        persist_auth_response(&json)?;
        crate::integration::data_bus::emit(crate::integration::data_bus::DataChangeKind::Session, None);
        Ok(())
    })
}

pub fn server_logout() -> Result<(), ClientError> {
    let access = match database::config_get("token")? {
        Some(t) => t,
        None => return Ok(()),
    };
    let refresh = match database::config_get("refresh_token")? {
        Some(t) => t,
        None => return Ok(()),
    };
    let base = base_url()?;
    let url = format!("{}/api/auth/logout", base.trim_end_matches('/'));
    let mut headers = reqwest::header::HeaderMap::new();
    headers.insert(
        reqwest::header::AUTHORIZATION,
        format!("Bearer {}", access)
            .parse()
            .map_err(|e: reqwest::header::InvalidHeaderValue| ClientError::Internal(e.to_string()))?,
    );
    headers.insert(
        reqwest::header::CONTENT_TYPE,
        "application/json".parse().unwrap(),
    );
    let body = serde_json::json!({ "refresh_token": refresh });
    RUNTIME.block_on(async {
        let resp = CLIENT
            .post(&url)
            .headers(headers)
            .json(&body)
            .send()
            .await?;
        if !resp.status().is_success() {
            return Err(ClientError::Sync(format!("logout: {}", resp.status())));
        }
        Ok(())
    })
}
