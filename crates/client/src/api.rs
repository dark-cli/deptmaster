//! HTTP client for backend API (auth, sync, wallets).
use crate::error::ClientError;
use crate::models::Wallet;
use crate::database;
use once_cell::sync::Lazy;
use std::future::Future;

static CLIENT: Lazy<reqwest::Client> = Lazy::new(|| {
    reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(30))
        .build()
        .expect("reqwest client")
});

static RUNTIME: Lazy<tokio::runtime::Runtime> =
    Lazy::new(|| tokio::runtime::Runtime::new().expect("tokio runtime"));

#[allow(dead_code)]
pub(crate) fn spawn_background<F>(fut: F)
where
    F: Future<Output = ()> + Send + 'static,
{
    RUNTIME.spawn(fut);
}

fn base_url() -> Result<String, ClientError> {
    if crate::is_network_offline() {
        return Err(ClientError::Network("Network offline".to_string()));
    }
    crate::get_base_url().map_err(ClientError::Network)
}

/// Persist the response from any auth-issuing endpoint
/// (login, register, refresh). Keeps the three storage keys in lockstep
/// so a half-written rotation can't leave us with mismatched tokens.
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

/// Trade the stored refresh token for a new access+refresh pair.
/// On failure (refresh expired/revoked/unknown) clears local auth and
/// emits a `Session` event so Dart providers bounce the user to the
/// login screen rather than spinning on permanent 401s.
///
/// Caller must be running outside the tokio runtime context — this is
/// safe from `auth_headers` (called before `RUNTIME.block_on`) but not
/// from inside another `RUNTIME.block_on` async block.
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
            // Refresh-token chain is dead. Wipe everything and signal
            // the UI; otherwise every future request 401s in a loop
            // and Dart keeps showing stale data with a "syncing"
            // spinner that never resolves.
            let _ = database::clear_all();
            crate::data_bus::emit(crate::data_bus::DataChangeKind::Session, None);
            Err(e)
        }
    }
}

/// Inspect the JWT's `exp` claim and decide whether we should refresh
/// before sending. Refresh window is generous (60s) so a request that
/// flies as the access token is about to expire doesn't race the
/// server clock and 401.
///
/// Returns `true` for any token we cannot parse — better to attempt
/// a refresh and fail back to the old token than to ship a malformed
/// or unparseable Bearer header.
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

fn auth_headers() -> Result<reqwest::header::HeaderMap, ClientError> {
    let mut token = database::config_get("token")
        ?
        .ok_or(ClientError::AuthExpired)?;
    if jwt_needs_refresh(&token) {
        // Refresh proactively. If it succeeds, pick up the fresh token;
        // if it fails (e.g. refresh chain dead) `try_refresh_blocking`
        // has already wiped storage and emitted Session — bubble the
        // error so the caller stops instead of sending a stale Bearer.
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

/// POST /api/auth/logout — best-effort server-side revoke of this
/// device's refresh token. Caller must still wipe local storage; we
/// only handle the "tell the server about it" half. Returns Err
/// (logged but ignored upstream) when offline, when there's no token
/// to send, or when the server rejects — none of those should block
/// the user from logging out locally.
pub(crate) fn server_logout() -> Result<(), ClientError> {
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
    // Build headers directly instead of calling `auth_headers()` —
    // that helper would trigger a refresh-token round-trip if the JWT
    // is near expiry, which is pointless when we're about to revoke
    // the refresh token anyway.
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

/// POST /api/auth/login -> { token, user_id, username }
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
        // Signal session change: Dart providers were populated from
        // whatever the (logged-out / previous-user) state was; force
        // them to refetch against the just-authenticated user.
        crate::data_bus::emit(crate::data_bus::DataChangeKind::Session, None);
        Ok(())
    })
}

/// POST /api/auth/register -> { token, user_id, username }; stores token and user_id like login.
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
        // Same rationale as `login`: a new session is now active,
        // every cached provider must refetch.
        crate::data_bus::emit(crate::data_bus::DataChangeKind::Session, None);
        Ok(())
    })
}

/// GET /api/wallets/<wallet_id>/sync/events?since=... (internal; not exposed to FFI).
/// wallet_id is path-only — backend's wallet_context middleware doesn't read header/query.
/// GET `/api/wallets/<wallet_id>/sync/events`.
///
/// GET /api/wallets/<wallet_id>/sync/events under the per-row chain-hash
/// protocol (server migration 033).
///
/// Sends the client's last_hash from the previous successful pull. Server
/// looks it up in user_readable_events; found → returns events with greater
/// id (incremental). Not found / empty / first sync → returns all events
/// plus `flush=true` so the client wipes local before applying.
///
/// Returns `(events, latest_hash, flush)`. `latest_hash` is what the client
/// must store for the next pull. `flush` tells the client to wipe local
/// state before applying the returned events. The client never validates
/// the hash itself — the server is authoritative.
pub(crate) fn get_sync_events(
    last_hash: Option<String>,
) -> Result<(Vec<serde_json::Value>, String, bool), ClientError> {
    let base = base_url()?;
    let wallet_id = database::config_get("current_wallet_id")
        ?
        .ok_or(ClientError::InvalidInput("No wallet selected".to_string()))?;
    let headers = auth_headers()?;
    let url = format!(
        "{}/api/wallets/{}/sync/events",
        base.trim_end_matches('/'),
        wallet_id
    );
    let last_hash_ref = last_hash.as_deref();
    RUNTIME.block_on(async {
        let mut req = CLIENT.get(&url).headers(headers);
        if let Some(h) = last_hash_ref {
            if !h.is_empty() {
                req = req.query(&[("last_hash", h)]);
            }
        }
        let resp = req.send().await?;
        let status = resp.status();
        let text = resp.text().await.map_err(|e| ClientError::Network(e.to_string()))?;
        if status.as_u16() == 401 && text.contains("DEBITUM_AUTH_DECLINED") {
            return Err(ClientError::AuthDeclined);
        }
        if !status.is_success() {
            return Err(ClientError::Sync(format!("{} {}", status, text)));
        }
        let body: serde_json::Value = serde_json::from_str(&text).map_err(ClientError::from)?;
        let events = body
            .get("events")
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default();
        let latest_hash = body
            .get("latest_hash")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        let flush = body.get("flush").and_then(|v| v.as_bool()).unwrap_or(false);
        Ok((events, latest_hash, flush))
    })
}

/// POST /api/wallets/<wallet_id>/sync/events (internal; not exposed to FFI).
/// wallet_id is path-only — backend's wallet_context middleware doesn't read header/query.
pub(crate) fn post_sync_events(events_json: Vec<String>) -> Result<Vec<String>, ClientError> {
    let events: Vec<serde_json::Value> = events_json
        .iter()
        .filter_map(|s| serde_json::from_str(s).ok())
        .collect();
    let base = base_url()?;
    let wallet_id = database::config_get("current_wallet_id")
        ?
        .ok_or(ClientError::InvalidInput("No wallet selected".to_string()))?;
    let headers = auth_headers()?;
    let url = format!(
        "{}/api/wallets/{}/sync/events",
        base.trim_end_matches('/'),
        wallet_id
    );
    let accepted: Vec<String> = RUNTIME.block_on(async {
        let resp = CLIENT
            .post(&url)
            .headers(headers)
            .json(&events)
            .send()
            .await?;
        let status = resp.status();
        let text = resp.text().await.map_err(|e| ClientError::Network(e.to_string()))?;
        // Only treat as "permission denied" when the server body contains our unique code (never in network errors).
        if status.as_u16() == 403 && text.contains("DEBITUM_INSUFFICIENT_WALLET_PERMISSION") {
            return Err(ClientError::InvalidInput("Insufficient permissions to push events".to_string()));
        }
        if status.as_u16() == 401 && text.contains("DEBITUM_AUTH_DECLINED") {
            return Err(ClientError::AuthDeclined);
        }
        if status.as_u16() == 401 {
            return Err(ClientError::AuthExpired);
        }
        if status.as_u16() == 403 || !status.is_success() {
            return Err(ClientError::Sync(format!("{} {}", status, text)));
        }
        let json: serde_json::Value = serde_json::from_str(&text).map_err(ClientError::from)?;
        let acc = json
            .get("accepted")
            .and_then(|v| v.as_array())
            .map(|a| {
                a.iter()
                    .filter_map(|v| v.as_str().map(String::from))
                    .collect()
            })
            .unwrap_or_default();
        Ok::<_, ClientError>(acc)
    })?;
    Ok(accepted)
}

/// GET /api/wallets
pub fn get_wallets_api() -> Result<Vec<crate::models::Wallet>, ClientError> {
    let base = base_url()?;
    let url = base
        .strip_suffix("/api/admin")
        .unwrap_or(base.as_str())
        .to_string()
        + "/api/wallets";
    let headers = auth_headers()?;
    let list = RUNTIME.block_on(async {
        let resp = CLIENT
            .get(&url)
            .headers(headers)
            .send()
            .await?;
        let text = resp.text().await.map_err(|e| ClientError::Network(e.to_string()))?;
        let json: serde_json::Value = serde_json::from_str(&text).map_err(ClientError::from)?;
        let arr = json
            .get("wallets")
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_else(|| json.as_array().cloned().unwrap_or_default());
        let wallets: Vec<Wallet> = arr
            .iter()
            .filter_map(|v| serde_json::from_value(v.clone()).ok())
            .collect();
        Ok::<_, ClientError>(wallets)
    })?;
    Ok(list)
}

/// POST /api/wallets - create wallet (server returns { id, name, message })
pub fn create_wallet_api(name: String, description: String) -> Result<Wallet, ClientError> {
    let base = base_url()?;
    let url = base
        .strip_suffix("/api/admin")
        .unwrap_or(base.as_str())
        .to_string()
        + "/api/wallets";
    let headers = auth_headers()?;
    let body = serde_json::json!({ "name": name, "description": description });
    let name_clone = name.clone();
    RUNTIME.block_on(async {
        let resp = CLIENT
            .post(&url)
            .headers(headers)
            .json(&body)
            .send()
            .await
            ?;
        let text = resp.text().await.map_err(|e| ClientError::Network(e.to_string()))?;
        let json: serde_json::Value = serde_json::from_str(&text).map_err(ClientError::from)?;
        let id_str = json
            .get("id")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        let name_str = json
            .get("name")
            .and_then(|v| v.as_str())
            .unwrap_or(&name_clone)
            .to_string();
        let now = chrono::Utc::now().to_rfc3339();
        Ok(Wallet {
            id: id_str,
            name: name_str,
            description: if description.is_empty() {
                None
            } else {
                Some(description)
            },
            created_at: now.clone(),
            updated_at: now,
            is_active: true,
            created_by: None,
        })
    })
}

// --- Wallet management (user-facing: list/add/update/remove users, groups, matrix) ---

fn wallet_management_url(wallet_id: &str, path: &str) -> Result<String, ClientError> {
    let base = base_url()?;
    let base = base
        .strip_suffix("/api/admin")
        .unwrap_or(base.as_str())
        .trim_end_matches('/');
    // Path and query so middleware can read wallet_id from query (path is also set)
    Ok(format!(
        "{}/api/wallets/{}{}?wallet_id={}",
        base, wallet_id, path, wallet_id
    ))
}

fn wallet_management_headers(wallet_id: &str) -> Result<reqwest::header::HeaderMap, String> {
    let mut headers = auth_headers()?;
    headers.insert(
        reqwest::header::HeaderName::from_static("x-wallet-id"),
        wallet_id
            .parse()
            .map_err(|e: reqwest::header::InvalidHeaderValue| e.to_string())?,
    );
    Ok(headers)
}

/// GET /api/wallets/:wallet_id/users
pub fn list_wallet_users_api(wallet_id: &str) -> Result<String, ClientError> {
    let url = wallet_management_url(wallet_id, "/users")?;
    let headers = wallet_management_headers(wallet_id)?;
    let text = RUNTIME.block_on(async {
        let resp = CLIENT
            .get(&url)
            .headers(headers)
            .send()
            .await?;
        let status = resp.status();
        let text = resp.text().await.map_err(|e| ClientError::Network(e.to_string()))?;
        if !status.is_success() {
            return Err(ClientError::Sync(format!("{} {}", status, text)));
        }
        Ok::<_, ClientError>(text)
    })?;
    Ok(text)
}

/// GET /api/wallets/:wallet_id/users/search?q=...
/// Returns JSON array of { id, email } for typeahead when adding a member.
pub fn search_wallet_users_api(wallet_id: &str, query: &str) -> Result<String, ClientError> {
    let mut url = wallet_management_url(wallet_id, "/users/search")?;
    if !query.is_empty() {
        url.push_str("&q=");
        url.push_str(&urlencoding::encode(query).to_string());
    }
    let headers = wallet_management_headers(wallet_id)?;
    RUNTIME.block_on(async {
        let resp = CLIENT
            .get(&url)
            .headers(headers)
            .send()
            .await?;
        let status = resp.status();
        let text = resp.text().await.map_err(|e| ClientError::Network(e.to_string()))?;
        if !status.is_success() {
            return Err(ClientError::Sync(format!("{} {}", status, text)));
        }
        Ok(text)
    })
}

/// POST /api/wallets/:wallet_id/users
/// Adds a member by username (lookup by email). New members get role 'member'; change role later.
pub fn add_user_to_wallet_api(wallet_id: &str, username: &str) -> Result<(), ClientError> {
    let url = wallet_management_url(wallet_id, "/users")?;
    let headers = wallet_management_headers(wallet_id)?;
    let body = serde_json::json!({ "username": username });
    RUNTIME.block_on(async {
        let resp = CLIENT
            .post(&url)
            .headers(headers.clone())
            .json(&body)
            .send()
            .await?;
        let status = resp.status();
        let text = resp.text().await.map_err(|e| ClientError::Network(e.to_string()))?;
        if !status.is_success() {
            return Err(ClientError::Sync(format!("{} {}", status, text)));
        }
        let _: serde_json::Value = serde_json::from_str(&text).map_err(ClientError::from)?;
        Ok::<_, ClientError>(())
    })
}

/// PUT /api/wallets/:wallet_id/users/:user_id
pub fn update_wallet_user_api(wallet_id: &str, user_id: &str, role: &str) -> Result<(), ClientError> {
    let url = wallet_management_url(wallet_id, &format!("/users/{}", user_id))?;
    let headers = wallet_management_headers(wallet_id)?;
    let body = serde_json::json!({ "role": role });
    RUNTIME.block_on(async {
        let resp = CLIENT
            .put(&url)
            .headers(headers.clone())
            .json(&body)
            .send()
            .await?;
        let status = resp.status();
        let text = resp.text().await.map_err(|e| ClientError::Network(e.to_string()))?;
        if !status.is_success() {
            return Err(ClientError::Sync(format!("{} {}", status, text)));
        }
        let _: serde_json::Value = serde_json::from_str(&text).map_err(ClientError::from)?;
        Ok::<_, ClientError>(())
    })
}

/// POST /api/wallets/:wallet_id/invite — create or replace 4-digit invite code. Returns the code.
pub fn create_wallet_invite_api(wallet_id: &str) -> Result<String, ClientError> {
    let url = wallet_management_url(wallet_id, "/invite")?;
    let headers = wallet_management_headers(wallet_id)?;
    let text = RUNTIME.block_on(async {
        let resp = CLIENT
            .post(&url)
            .headers(headers)
            .send()
            .await?;
        let status = resp.status();
        let resp_text = resp.text().await.map_err(|e| ClientError::Network(e.to_string()))?;
        if !status.is_success() {
            return Err(ClientError::Sync(format!("{} {}", status, resp_text)));
        }
        Ok::<_, ClientError>(resp_text)
    })?;
    let json: serde_json::Value = serde_json::from_str(&text).map_err(ClientError::from)?;
    let code = json
        .get("code")
        .and_then(|v| v.as_str())
        .ok_or(ClientError::InvalidResponse("No code in response".to_string()))?;
    Ok(code.to_string())
}

/// POST /api/wallets/join — join a wallet by invite code (no wallet context; auth only).
pub fn join_wallet_by_code_api(code: &str) -> Result<String, ClientError> {
    let base = base_url()?;
    let url = format!("{}/api/wallets/join", base.trim_end_matches('/'));
    let headers = auth_headers()?;
    let body = serde_json::json!({ "code": code.trim() });
    let text = RUNTIME.block_on(async {
        let resp = CLIENT
            .post(&url)
            .headers(headers)
            .json(&body)
            .send()
            .await
            .map_err(|e| ClientError::Network(e.to_string()))?;
        let status = resp.status();
        let resp_text = resp.text().await.map_err(|e| ClientError::Network(e.to_string()))?;
        if !status.is_success() {
            // Try to extract clean error message from JSON response
            if let Ok(json) = serde_json::from_str::<serde_json::Value>(&resp_text) {
                if let Some(msg) = json.get("error").and_then(|v| v.as_str()) {
                    return Err(ClientError::Sync(msg.to_string()));
                }
            }
            return Err(ClientError::Sync(format!("{} {}", status, resp_text)));
        }
        Ok::<_, ClientError>(resp_text)
    })?;
    let json: serde_json::Value = serde_json::from_str(&text).map_err(ClientError::from)?;
    let wallet_id = json
        .get("wallet_id")
        .and_then(|v| v.as_str())
        .ok_or(ClientError::InvalidResponse("No wallet_id in response".to_string()))?;
    Ok(wallet_id.to_string())
}

/// DELETE /api/wallets/:wallet_id/users/:user_id
pub fn remove_wallet_user_api(wallet_id: &str, user_id: &str) -> Result<(), ClientError> {
    let url = wallet_management_url(wallet_id, &format!("/users/{}", user_id))?;
    let headers = wallet_management_headers(wallet_id)?;
    let text = RUNTIME.block_on(async {
        let resp = CLIENT
            .delete(&url)
            .headers(headers)
            .send()
            .await
            .map_err(|e| ClientError::Network(e.to_string()))?;
        let status = resp.status();
        let resp_text = resp.text().await.map_err(|e| ClientError::Network(e.to_string()))?;
        if !status.is_success() {
            return Err(ClientError::Sync(format!("{} {}", status, resp_text)));
        }
        Ok::<_, ClientError>(resp_text)
    })?;
    let _: serde_json::Value = serde_json::from_str(&text).map_err(ClientError::from)?;
    Ok(())
}

fn wallet_management_get(wallet_id: &str, path: &str) -> Result<String, ClientError> {
    let url = wallet_management_url(wallet_id, path)?;
    let headers = wallet_management_headers(wallet_id)?;
    RUNTIME.block_on(async {
        let resp = CLIENT
            .get(&url)
            .headers(headers)
            .send()
            .await
            .map_err(|e| ClientError::Network(e.to_string()))?;
        let status = resp.status();
        let text = resp.text().await.map_err(|e| ClientError::Network(e.to_string()))?;
        if !status.is_success() {
            return Err(ClientError::Sync(format!("{} {}", status, text)));
        }
        Ok::<_, ClientError>(text)
    })
}

fn wallet_management_post_json(
    wallet_id: &str,
    path: &str,
    body: &serde_json::Value,
) -> Result<String, ClientError> {
    let url = wallet_management_url(wallet_id, path)?;
    let headers = wallet_management_headers(wallet_id)?;
    RUNTIME.block_on(async {
        let resp = CLIENT
            .post(&url)
            .headers(headers)
            .json(body)
            .send()
            .await
            .map_err(|e| ClientError::Network(e.to_string()))?;
        let status = resp.status();
        let text = resp.text().await.map_err(|e| ClientError::Network(e.to_string()))?;
        if !status.is_success() {
            return Err(ClientError::Sync(format!("{} {}", status, text)));
        }
        Ok::<_, ClientError>(text)
    })
}

fn wallet_management_put_json(
    wallet_id: &str,
    path: &str,
    body: &serde_json::Value,
) -> Result<String, ClientError> {
    let url = wallet_management_url(wallet_id, path)?;
    let headers = wallet_management_headers(wallet_id)?;
    RUNTIME.block_on(async {
        let resp = CLIENT
            .put(&url)
            .headers(headers)
            .json(body)
            .send()
            .await
            .map_err(|e| ClientError::Network(e.to_string()))?;
        let status = resp.status();
        let text = resp.text().await.map_err(|e| ClientError::Network(e.to_string()))?;
        if !status.is_success() {
            return Err(ClientError::Sync(format!("{} {}", status, text)));
        }
        Ok::<_, ClientError>(text)
    })
}

fn wallet_management_delete(wallet_id: &str, path: &str) -> Result<String, ClientError> {
    let url = wallet_management_url(wallet_id, path)?;
    let headers = wallet_management_headers(wallet_id)?;
    RUNTIME.block_on(async {
        let resp = CLIENT
            .delete(&url)
            .headers(headers)
            .send()
            .await
            .map_err(|e| ClientError::Network(e.to_string()))?;
        let status = resp.status();
        let text = resp.text().await.map_err(|e| ClientError::Network(e.to_string()))?;
        if !status.is_success() {
            return Err(ClientError::Sync(format!("{} {}", status, text)));
        }
        Ok::<_, ClientError>(text)
    })
}

pub fn list_user_groups_api(wallet_id: &str) -> Result<String, ClientError> {
    wallet_management_get(wallet_id, "/user-groups")
}

pub fn create_user_group_api(wallet_id: &str, name: &str) -> Result<String, ClientError> {
    let body = serde_json::json!({ "name": name });
    wallet_management_post_json(wallet_id, "/user-groups", &body)
}

pub fn update_user_group_api(wallet_id: &str, group_id: &str, name: &str) -> Result<(), ClientError> {
    let body = serde_json::json!({ "name": name });
    wallet_management_put_json(wallet_id, &format!("/user-groups/{}", group_id), &body).map(|_| ())
}

pub fn delete_user_group_api(wallet_id: &str, group_id: &str) -> Result<(), ClientError> {
    wallet_management_delete(wallet_id, &format!("/user-groups/{}", group_id)).map(|_| ())
}

pub fn list_user_group_members_api(wallet_id: &str, group_id: &str) -> Result<String, ClientError> {
    wallet_management_get(wallet_id, &format!("/user-groups/{}/members", group_id))
}

pub fn add_user_group_member_api(
    wallet_id: &str,
    group_id: &str,
    username: &str,
) -> Result<(), ClientError> {
    let body = serde_json::json!({ "username": username });
    wallet_management_post_json(
        wallet_id,
        &format!("/user-groups/{}/members", group_id),
        &body,
    )
    .map(|_| ())
}

pub fn remove_user_group_member_api(
    wallet_id: &str,
    group_id: &str,
    user_id: &str,
) -> Result<(), ClientError> {
    wallet_management_delete(
        wallet_id,
        &format!("/user-groups/{}/members/{}", group_id, user_id),
    )
    .map(|_| ())
}

pub fn list_contact_groups_api(wallet_id: &str) -> Result<String, ClientError> {
    wallet_management_get(wallet_id, "/contact-groups")
}

pub fn create_contact_group_api(wallet_id: &str, name: &str) -> Result<String, ClientError> {
    let body = serde_json::json!({ "name": name });
    wallet_management_post_json(wallet_id, "/contact-groups", &body)
}

pub fn update_contact_group_api(wallet_id: &str, group_id: &str, name: &str) -> Result<(), ClientError> {
    let body = serde_json::json!({ "name": name });
    wallet_management_put_json(wallet_id, &format!("/contact-groups/{}", group_id), &body)
        .map(|_| ())
}

pub fn delete_contact_group_api(wallet_id: &str, group_id: &str) -> Result<(), ClientError> {
    wallet_management_delete(wallet_id, &format!("/contact-groups/{}", group_id)).map(|_| ())
}

pub fn list_contact_group_members_api(wallet_id: &str, group_id: &str) -> Result<String, ClientError> {
    wallet_management_get(wallet_id, &format!("/contact-groups/{}/members", group_id))
}

pub fn add_contact_group_member_api(
    wallet_id: &str,
    group_id: &str,
    contact_id: &str,
) -> Result<(), ClientError> {
    let body = serde_json::json!({ "contact_id": contact_id });
    wallet_management_post_json(
        wallet_id,
        &format!("/contact-groups/{}/members", group_id),
        &body,
    )
    .map(|_| ())
}

pub fn remove_contact_group_member_api(
    wallet_id: &str,
    group_id: &str,
    contact_id: &str,
) -> Result<(), ClientError> {
    wallet_management_delete(
        wallet_id,
        &format!("/contact-groups/{}/members/{}", group_id, contact_id),
    )
    .map(|_| ())
}

pub fn list_permission_actions_api(wallet_id: &str) -> Result<String, ClientError> {
    wallet_management_get(wallet_id, "/permission-actions")
}

/// GET /api/wallets/:wallet_id/me/permissions - Returns {"actions": ["contact:read", ...]}
pub fn get_my_permissions_api(wallet_id: &str) -> Result<String, ClientError> {
    wallet_management_get(wallet_id, "/me/permissions")
}

pub fn get_permission_matrix_api(wallet_id: &str) -> Result<String, ClientError> {
    wallet_management_get(wallet_id, "/permission-matrix")
}

/// entries_json: JSON array of { user_group_id, contact_group_id, action_names }
pub fn put_permission_matrix_api(wallet_id: &str, entries_json: &str) -> Result<(), ClientError> {
    let entries: Vec<serde_json::Value> =
        serde_json::from_str(entries_json)?;
    let body = serde_json::json!({ "entries": entries });
    wallet_management_put_json(wallet_id, "/permission-matrix", &body).map(|_| ())
}
