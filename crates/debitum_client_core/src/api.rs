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
        if status.as_u16() == 401 && text.contains("DEBITUM_AUTH_DECLINED") {
            return Err::<(), String>("DEBITUM_AUTH_DECLINED".to_string());
        }
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

/// POST /api/auth/register -> { token, user_id, username }; stores token and user_id like login.
pub fn register(username: String, password: String) -> Result<(), String> {
    let base = base_url()?;
    let url = format!("{}/api/auth/register", base.trim_end_matches('/'));
    let body = serde_json::json!({ "username": username.trim(), "password": password });
    RUNTIME.block_on(async {
        let resp = CLIENT.post(&url).json(&body).send().await.map_err(|e| e.to_string())?;
        let status = resp.status();
        let text = resp.text().await.map_err(|e| e.to_string())?;
        if status.as_u16() == 409 {
            return Err::<(), String>("This username is already taken".to_string());
        }
        if !status.is_success() {
            return Err(format!("{} - {}", status, text));
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
        let status = resp.status();
        let text = resp.text().await.map_err(|e| e.to_string())?;
        if status.as_u16() == 401 && text.contains("DEBITUM_AUTH_DECLINED") {
            return Err::<Vec<serde_json::Value>, String>("DEBITUM_AUTH_DECLINED".to_string());
        }
        if !status.is_success() {
            return Err(format!("{} {}", status, text));
        }
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
        if status.as_u16() == 401 && text.contains("DEBITUM_AUTH_DECLINED") {
            return Err::<Vec<String>, String>("DEBITUM_AUTH_DECLINED".to_string());
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

// --- Wallet management (user-facing: list/add/update/remove users, groups, matrix) ---

fn wallet_management_url(wallet_id: &str, path: &str) -> Result<String, String> {
    let base = base_url()?;
    let base = base.strip_suffix("/api/admin").unwrap_or(base.as_str()).trim_end_matches('/');
    // Path and query so middleware can read wallet_id from query (path is also set)
    Ok(format!("{}/api/wallets/{}{}?wallet_id={}", base, wallet_id, path, wallet_id))
}

fn wallet_management_headers(wallet_id: &str) -> Result<reqwest::header::HeaderMap, String> {
    let mut headers = auth_headers()?;
    headers.insert(
        reqwest::header::HeaderName::from_static("x-wallet-id"),
        wallet_id.parse().map_err(|e: reqwest::header::InvalidHeaderValue| e.to_string())?,
    );
    Ok(headers)
}

/// GET /api/wallets/:wallet_id/users
pub fn list_wallet_users_api(wallet_id: &str) -> Result<String, String> {
    let url = wallet_management_url(wallet_id, "/users")?;
    let headers = wallet_management_headers(wallet_id)?;
    let text = RUNTIME.block_on(async {
        let resp = CLIENT.get(&url).headers(headers).send().await.map_err(|e| e.to_string())?;
        let status = resp.status();
        let text = resp.text().await.map_err(|e| e.to_string())?;
        if !status.is_success() {
            return Err(format!("{} {}", status, text));
        }
        Ok::<_, String>(text)
    })?;
    Ok(text)
}

/// GET /api/wallets/:wallet_id/users/search?q=...
/// Returns JSON array of { id, email } for typeahead when adding a member.
pub fn search_wallet_users_api(wallet_id: &str, query: &str) -> Result<String, String> {
    let mut url = wallet_management_url(wallet_id, "/users/search")?;
    if !query.is_empty() {
        url.push_str("&q=");
        url.push_str(&urlencoding::encode(query).to_string());
    }
    let headers = wallet_management_headers(wallet_id)?;
    let text = RUNTIME.block_on(async {
        let resp = CLIENT.get(&url).headers(headers).send().await.map_err(|e| e.to_string())?;
        let status = resp.status();
        let text = resp.text().await.map_err(|e| e.to_string())?;
        if !status.is_success() {
            return Err(format!("{} {}", status, text));
        }
        Ok::<_, String>(text)
    })?;
    Ok(text)
}

/// POST /api/wallets/:wallet_id/users
/// Adds a member by username (lookup by email). New members get role 'member'; change role later.
pub fn add_user_to_wallet_api(wallet_id: &str, username: &str) -> Result<(), String> {
    let url = wallet_management_url(wallet_id, "/users")?;
    let headers = wallet_management_headers(wallet_id)?;
    let body = serde_json::json!({ "username": username });
    let text = RUNTIME.block_on(async {
        let resp = CLIENT.post(&url).headers(headers.clone()).json(&body).send().await.map_err(|e| e.to_string())?;
        let status = resp.status();
        let text = resp.text().await.map_err(|e| e.to_string())?;
        if !status.is_success() {
            return Err(format!("{} {}", status, text));
        }
        Ok::<_, String>(text)
    })?;
    let _: serde_json::Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
    Ok(())
}

/// PUT /api/wallets/:wallet_id/users/:user_id
pub fn update_wallet_user_api(wallet_id: &str, user_id: &str, role: &str) -> Result<(), String> {
    let url = wallet_management_url(wallet_id, &format!("/users/{}", user_id))?;
    let headers = wallet_management_headers(wallet_id)?;
    let body = serde_json::json!({ "role": role });
    let text = RUNTIME.block_on(async {
        let resp = CLIENT.put(&url).headers(headers.clone()).json(&body).send().await.map_err(|e| e.to_string())?;
        let status = resp.status();
        let text = resp.text().await.map_err(|e| e.to_string())?;
        if !status.is_success() {
            return Err(format!("{} {}", status, text));
        }
        Ok::<_, String>(text)
    })?;
    let _: serde_json::Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
    Ok(())
}

/// POST /api/wallets/:wallet_id/invite — create or replace 4-digit invite code. Returns the code.
pub fn create_wallet_invite_api(wallet_id: &str) -> Result<String, String> {
    let url = wallet_management_url(wallet_id, "/invite")?;
    let headers = wallet_management_headers(wallet_id)?;
    let text = RUNTIME.block_on(async {
        let resp = CLIENT.post(&url).headers(headers).send().await.map_err(|e| e.to_string())?;
        let status = resp.status();
        let text = resp.text().await.map_err(|e| e.to_string())?;
        if !status.is_success() {
            return Err(format!("{} {}", status, text));
        }
        Ok::<_, String>(text)
    })?;
    let json: serde_json::Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
    let code = json.get("code").and_then(|v| v.as_str()).ok_or("No code in response")?;
    Ok(code.to_string())
}

/// POST /api/wallets/join — join a wallet by invite code (no wallet context; auth only).
pub fn join_wallet_by_code_api(code: &str) -> Result<String, String> {
    let base = base_url()?;
    let url = format!("{}/api/wallets/join", base.trim_end_matches('/'));
    let headers = auth_headers()?;
    let body = serde_json::json!({ "code": code.trim() });
    let text = RUNTIME.block_on(async {
        let resp = CLIENT.post(&url).headers(headers).json(&body).send().await.map_err(|e| e.to_string())?;
        let status = resp.status();
        let text = resp.text().await.map_err(|e| e.to_string())?;
        if !status.is_success() {
            return Err(format!("{} {}", status, text));
        }
        Ok::<_, String>(text)
    })?;
    let json: serde_json::Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
    let wallet_id = json.get("wallet_id").and_then(|v| v.as_str()).ok_or("No wallet_id in response")?;
    Ok(wallet_id.to_string())
}

/// DELETE /api/wallets/:wallet_id/users/:user_id
pub fn remove_wallet_user_api(wallet_id: &str, user_id: &str) -> Result<(), String> {
    let url = wallet_management_url(wallet_id, &format!("/users/{}", user_id))?;
    let headers = wallet_management_headers(wallet_id)?;
    let text = RUNTIME.block_on(async {
        let resp = CLIENT.delete(&url).headers(headers).send().await.map_err(|e| e.to_string())?;
        let status = resp.status();
        let text = resp.text().await.map_err(|e| e.to_string())?;
        if !status.is_success() {
            return Err(format!("{} {}", status, text));
        }
        Ok::<_, String>(text)
    })?;
    let _: serde_json::Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
    Ok(())
}

fn wallet_management_get(wallet_id: &str, path: &str) -> Result<String, String> {
    let url = wallet_management_url(wallet_id, path)?;
    let headers = wallet_management_headers(wallet_id)?;
    RUNTIME.block_on(async {
        let resp = CLIENT.get(&url).headers(headers).send().await.map_err(|e| e.to_string())?;
        let status = resp.status();
        let text = resp.text().await.map_err(|e| e.to_string())?;
        if !status.is_success() {
            return Err(format!("{} {}", status, text));
        }
        Ok(text)
    })
}

fn wallet_management_post_json(wallet_id: &str, path: &str, body: &serde_json::Value) -> Result<String, String> {
    let url = wallet_management_url(wallet_id, path)?;
    let headers = wallet_management_headers(wallet_id)?;
    RUNTIME.block_on(async {
        let resp = CLIENT.post(&url).headers(headers).json(body).send().await.map_err(|e| e.to_string())?;
        let status = resp.status();
        let text = resp.text().await.map_err(|e| e.to_string())?;
        if !status.is_success() {
            return Err(format!("{} {}", status, text));
        }
        Ok(text)
    })
}

fn wallet_management_put_json(wallet_id: &str, path: &str, body: &serde_json::Value) -> Result<String, String> {
    let url = wallet_management_url(wallet_id, path)?;
    let headers = wallet_management_headers(wallet_id)?;
    RUNTIME.block_on(async {
        let resp = CLIENT.put(&url).headers(headers).json(body).send().await.map_err(|e| e.to_string())?;
        let status = resp.status();
        let text = resp.text().await.map_err(|e| e.to_string())?;
        if !status.is_success() {
            return Err(format!("{} {}", status, text));
        }
        Ok(text)
    })
}

fn wallet_management_delete(wallet_id: &str, path: &str) -> Result<String, String> {
    let url = wallet_management_url(wallet_id, path)?;
    let headers = wallet_management_headers(wallet_id)?;
    RUNTIME.block_on(async {
        let resp = CLIENT.delete(&url).headers(headers).send().await.map_err(|e| e.to_string())?;
        let status = resp.status();
        let text = resp.text().await.map_err(|e| e.to_string())?;
        if !status.is_success() {
            return Err(format!("{} {}", status, text));
        }
        Ok(text)
    })
}

pub fn list_user_groups_api(wallet_id: &str) -> Result<String, String> {
    wallet_management_get(wallet_id, "/user-groups")
}

pub fn create_user_group_api(wallet_id: &str, name: &str) -> Result<String, String> {
    let body = serde_json::json!({ "name": name });
    wallet_management_post_json(wallet_id, "/user-groups", &body)
}

pub fn update_user_group_api(wallet_id: &str, group_id: &str, name: &str) -> Result<(), String> {
    let body = serde_json::json!({ "name": name });
    wallet_management_put_json(wallet_id, &format!("/user-groups/{}", group_id), &body).map(|_| ())
}

pub fn delete_user_group_api(wallet_id: &str, group_id: &str) -> Result<(), String> {
    wallet_management_delete(wallet_id, &format!("/user-groups/{}", group_id)).map(|_| ())
}

pub fn list_user_group_members_api(wallet_id: &str, group_id: &str) -> Result<String, String> {
    wallet_management_get(wallet_id, &format!("/user-groups/{}/members", group_id))
}

pub fn add_user_group_member_api(wallet_id: &str, group_id: &str, username: &str) -> Result<(), String> {
    let body = serde_json::json!({ "username": username });
    wallet_management_post_json(wallet_id, &format!("/user-groups/{}/members", group_id), &body).map(|_| ())
}

pub fn remove_user_group_member_api(wallet_id: &str, group_id: &str, user_id: &str) -> Result<(), String> {
    wallet_management_delete(wallet_id, &format!("/user-groups/{}/members/{}", group_id, user_id)).map(|_| ())
}

pub fn list_contact_groups_api(wallet_id: &str) -> Result<String, String> {
    wallet_management_get(wallet_id, "/contact-groups")
}

pub fn create_contact_group_api(wallet_id: &str, name: &str) -> Result<String, String> {
    let body = serde_json::json!({ "name": name });
    wallet_management_post_json(wallet_id, "/contact-groups", &body)
}

pub fn update_contact_group_api(wallet_id: &str, group_id: &str, name: &str) -> Result<(), String> {
    let body = serde_json::json!({ "name": name });
    wallet_management_put_json(wallet_id, &format!("/contact-groups/{}", group_id), &body).map(|_| ())
}

pub fn delete_contact_group_api(wallet_id: &str, group_id: &str) -> Result<(), String> {
    wallet_management_delete(wallet_id, &format!("/contact-groups/{}", group_id)).map(|_| ())
}

pub fn list_contact_group_members_api(wallet_id: &str, group_id: &str) -> Result<String, String> {
    wallet_management_get(wallet_id, &format!("/contact-groups/{}/members", group_id))
}

pub fn add_contact_group_member_api(wallet_id: &str, group_id: &str, contact_id: &str) -> Result<(), String> {
    let body = serde_json::json!({ "contact_id": contact_id });
    wallet_management_post_json(wallet_id, &format!("/contact-groups/{}/members", group_id), &body).map(|_| ())
}

pub fn remove_contact_group_member_api(wallet_id: &str, group_id: &str, contact_id: &str) -> Result<(), String> {
    wallet_management_delete(wallet_id, &format!("/contact-groups/{}/members/{}", group_id, contact_id)).map(|_| ())
}

pub fn list_permission_actions_api(wallet_id: &str) -> Result<String, String> {
    wallet_management_get(wallet_id, "/permission-actions")
}

pub fn get_permission_matrix_api(wallet_id: &str) -> Result<String, String> {
    wallet_management_get(wallet_id, "/permission-matrix")
}

/// entries_json: JSON array of { user_group_id, contact_group_id, action_names }
pub fn put_permission_matrix_api(wallet_id: &str, entries_json: &str) -> Result<(), String> {
    let entries: Vec<serde_json::Value> = serde_json::from_str(entries_json).map_err(|e| e.to_string())?;
    let body = serde_json::json!({ "entries": entries });
    wallet_management_put_json(wallet_id, "/permission-matrix", &body).map(|_| ())
}
