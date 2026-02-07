//! HTTP client for backend API (auth, sync, wallets).
use crate::models::Wallet;
use crate::storage;
use once_cell::sync::Lazy;

static CLIENT: Lazy<reqwest::Client> = Lazy::new(|| {
    reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(30))
        .build()
        .expect("reqwest client")
});

static RUNTIME: Lazy<tokio::runtime::Runtime> = Lazy::new(|| {
    tokio::runtime::Runtime::new().expect("tokio runtime")
});

fn base_url() -> Result<String, String> {
    crate::get_base_url().ok_or_else(|| "Backend not configured".to_string())
}

fn auth_headers() -> Result<reqwest::header::HeaderMap, String> {
    let token = storage::config_get("token")?
        .ok_or_else(|| "Not logged in".to_string())?;
    let mut headers = reqwest::header::HeaderMap::new();
    headers.insert(
        reqwest::header::AUTHORIZATION,
        format!("Bearer {}", token).parse().map_err(|e: reqwest::header::InvalidHeaderValue| e.to_string())?,
    );
    headers.insert(
        reqwest::header::CONTENT_TYPE,
        "application/json".parse().unwrap(),
    );
    Ok(headers)
}


/// POST /api/auth/login -> { token, user_id, username }
pub fn login(username: String, password: String) -> Result<(), String> {
    let base = base_url()?;
    let url = format!("{}/api/auth/login", base);
    let body = serde_json::json!({ "username": username, "password": password });
    RUNTIME.block_on(async {
        let resp = CLIENT.post(&url).json(&body).send().await.map_err(|e| e.to_string())?;
        let status = resp.status();
        let text = resp.text().await.map_err(|e| e.to_string())?;
        if !status.is_success() {
            return Err(format!("Login failed: {} - {}", status, text));
        }
        let json: serde_json::Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
        let token = json.get("token").and_then(|v| v.as_str()).ok_or("No token in response")?;
        let user_id = json.get("user_id").and_then(|v| v.as_str()).ok_or("No user_id in response")?;
        storage::config_set("token", token).map_err(|e| e.to_string())?;
        storage::config_set("user_id", user_id).map_err(|e| e.to_string())?;
        Ok(())
    })
}

/// GET /api/sync/events?since=... (internal; not exposed to FFI)
pub(crate) fn get_sync_events(since: Option<String>) -> Result<Vec<serde_json::Value>, String> {
    let base = base_url()?;
    let wallet_id = storage::config_get("current_wallet_id")?
        .ok_or_else(|| "No wallet selected".to_string())?;
    let mut headers = auth_headers()?;
    headers.insert(
        reqwest::header::HeaderName::from_static("x-wallet-id"),
        wallet_id.parse().map_err(|e: reqwest::header::InvalidHeaderValue| e.to_string())?,
    );
    let url = format!("{}/api/sync/events", base);
    let since_ref = since.as_deref();
    RUNTIME.block_on(async {
        let mut q = vec![("wallet_id", wallet_id.as_str())];
        if let Some(s) = since_ref {
            q.push(("since", s));
        }
        let resp = CLIENT.get(&url).query(&q).headers(headers).send().await.map_err(|e| e.to_string())?;
        let text = resp.text().await.map_err(|e| e.to_string())?;
        let arr: Vec<serde_json::Value> = serde_json::from_str(&text).map_err(|e| e.to_string())?;
        Ok(arr)
    })
}

/// POST /api/sync/events (internal; not exposed to FFI)
pub(crate) fn post_sync_events(events_json: Vec<String>) -> Result<Vec<String>, String> {
    let events: Vec<serde_json::Value> = events_json
        .iter()
        .filter_map(|s| serde_json::from_str(s).ok())
        .collect();
    let base = base_url()?;
    let wallet_id = storage::config_get("current_wallet_id")?
        .ok_or_else(|| "No wallet selected".to_string())?;
    let mut headers = auth_headers()?;
    headers.insert(
        reqwest::header::HeaderName::from_static("x-wallet-id"),
        wallet_id.parse().map_err(|e: reqwest::header::InvalidHeaderValue| e.to_string())?,
    );
    let url = format!("{}/api/sync/events", base);
    let accepted: Vec<String> = RUNTIME.block_on(async {
        let resp = CLIENT.post(&url).query(&[("wallet_id", wallet_id.as_str())]).headers(headers).json(&events).send().await.map_err(|e| e.to_string())?;
        let status = resp.status();
        let text = resp.text().await.map_err(|e| e.to_string())?;
        // Only treat as "permission denied" when the server body contains our unique code (never in network errors).
        if status.as_u16() == 403 && text.contains("DEBITUM_INSUFFICIENT_WALLET_PERMISSION") {
            return Err::<Vec<String>, String>("DEBITUM_INSUFFICIENT_WALLET_PERMISSION".to_string());
        }
        if status.as_u16() == 401 {
            return Err::<Vec<String>, String>(format!("401 Unauthorized {}", text));
        }
        if status.as_u16() == 403 || !status.is_success() {
            return Err(format!("{} {}", status, text));
        }
        let json: serde_json::Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
        let acc = json.get("accepted").and_then(|v| v.as_array()).map(|a| {
            a.iter().filter_map(|v| v.as_str().map(String::from)).collect()
        }).unwrap_or_default();
        Ok::<_, String>(acc)
    })?;
    Ok(accepted)
}

/// GET /api/wallets
pub fn get_wallets_api() -> Result<Vec<crate::models::Wallet>, String> {
    let base = base_url()?;
    let url = base.strip_suffix("/api/admin").unwrap_or(base.as_str()).to_string() + "/api/wallets";
    let headers = auth_headers()?;
    let list = RUNTIME.block_on(async {
        let resp = CLIENT.get(&url).headers(headers).send().await.map_err(|e| e.to_string())?;
        let text = resp.text().await.map_err(|e| e.to_string())?;
        let json: serde_json::Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
        let arr = json.get("wallets").and_then(|v| v.as_array()).cloned().unwrap_or_else(|| json.as_array().cloned().unwrap_or_default());
        let wallets: Vec<Wallet> = arr.iter().filter_map(|v| serde_json::from_value(v.clone()).ok()).collect();
        Ok::<_, String>(wallets)
    })?;
    Ok(list)
}

/// POST /api/wallets - create wallet (server returns { id, name, message })
pub fn create_wallet_api(name: String, description: String) -> Result<Wallet, String> {
    let base = base_url()?;
    let url = base.strip_suffix("/api/admin").unwrap_or(base.as_str()).to_string() + "/api/wallets";
    let headers = auth_headers()?;
    let body = serde_json::json!({ "name": name, "description": description });
    let name_clone = name.clone();
    RUNTIME.block_on(async {
        let resp = CLIENT.post(&url).headers(headers).json(&body).send().await.map_err(|e| e.to_string())?;
        let text = resp.text().await.map_err(|e| e.to_string())?;
        let json: serde_json::Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
        let id_str = json.get("id").and_then(|v| v.as_str()).unwrap_or("").to_string();
        let name_str = json.get("name").and_then(|v| v.as_str()).unwrap_or(&name_clone).to_string();
        let now = chrono::Utc::now().to_rfc3339();
        Ok(Wallet {
            id: id_str,
            name: name_str,
            description: if description.is_empty() { None } else { Some(description) },
            created_at: now.clone(),
            updated_at: now,
            is_active: true,
            created_by: None,
        })
    })
}
