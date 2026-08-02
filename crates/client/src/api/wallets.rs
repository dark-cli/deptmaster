//! Wallet management endpoints: CRUD, groups, permissions.

use crate::types::error::ClientError;
use crate::types::models::Wallet;
use super::{base_url, CLIENT, RUNTIME};
use super::auth::auth_headers;

pub fn get_wallets_api() -> Result<Vec<Wallet>, ClientError> {
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

fn wallet_management_url(wallet_id: &str, path: &str) -> Result<String, ClientError> {
    let base = base_url()?;
    let base = base
        .strip_suffix("/api/admin")
        .unwrap_or(base.as_str())
        .trim_end_matches('/');
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
            if status.as_u16() == 403 {
                return Err(ClientError::InsufficientPermission(text));
            }
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
            if status.as_u16() == 403 {
                return Err(ClientError::InsufficientPermission(text));
            }
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
            if status.as_u16() == 403 {
                return Err(ClientError::InsufficientPermission(text));
            }
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
            if status.as_u16() == 403 {
                return Err(ClientError::InsufficientPermission(text));
            }
            return Err(ClientError::Sync(format!("{} {}", status, text)));
        }
        Ok::<_, ClientError>(text)
    })
}

// User management
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

// Invites
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

// User groups
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

// Contact groups
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

// Permissions
pub fn list_permission_actions_api(wallet_id: &str) -> Result<String, ClientError> {
    wallet_management_get(wallet_id, "/permission-actions")
}

pub fn get_my_permissions_api(wallet_id: &str) -> Result<String, ClientError> {
    wallet_management_get(wallet_id, "/me/permissions")
}

pub fn get_permission_matrix_api(wallet_id: &str) -> Result<String, ClientError> {
    wallet_management_get(wallet_id, "/permission-matrix")
}

pub fn put_permission_matrix_api(wallet_id: &str, entries_json: &str) -> Result<(), ClientError> {
    let entries: Vec<serde_json::Value> =
        serde_json::from_str(entries_json)?;
    let body = serde_json::json!({ "entries": entries });
    wallet_management_put_json(wallet_id, "/permission-matrix", &body).map(|_| ())
}

pub fn get_wallet_permissions_api(wallet_id: &str) -> Result<String, ClientError> {
    wallet_management_get(wallet_id, "/wallet-permissions")
}

pub fn set_wallet_permissions_api(wallet_id: &str, entries_json: &str) -> Result<(), ClientError> {
    let entries: Vec<serde_json::Value> =
        serde_json::from_str(entries_json)?;
    let body = serde_json::json!({ "entries": entries });
    wallet_management_put_json(wallet_id, "/wallet-permissions", &body).map(|_| ())
}

// Member permissions (vector-based group management)
pub fn get_member_permissions_api(wallet_id: &str) -> Result<String, ClientError> {
    wallet_management_get(wallet_id, "/member-permissions")
}

pub fn set_member_permissions_api(wallet_id: &str, entries_json: &str) -> Result<(), ClientError> {
    let entries: Vec<serde_json::Value> =
        serde_json::from_str(entries_json)?;
    let body = serde_json::json!({ "entries": entries });
    wallet_management_put_json(wallet_id, "/member-permissions", &body).map(|_| ())
}

// Contact group permissions (Layer 2.5)
pub fn get_contact_group_permissions_api(wallet_id: &str, contact_group_id: &str) -> Result<String, ClientError> {
    wallet_management_get(wallet_id, &format!("/contact-group-permissions/{}", contact_group_id))
}

pub fn set_contact_group_permissions_api(wallet_id: &str, contact_group_id: &str, entries_json: &str) -> Result<(), ClientError> {
    let entries: Vec<serde_json::Value> =
        serde_json::from_str(entries_json)?;
    let body = serde_json::json!({ "contact_group_id": contact_group_id, "entries": entries });
    wallet_management_put_json(wallet_id, &format!("/contact-group-permissions/{}", contact_group_id), &body).map(|_| ())
}
