//! Sync endpoints: pull and push events.

use crate::database;
use crate::error::ClientError;
use super::{base_url, CLIENT, RUNTIME};
use super::auth::auth_headers;

pub fn get_sync_events(
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

pub fn post_sync_events(events_json: Vec<String>) -> Result<Vec<String>, ClientError> {
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
        if status.as_u16() == 403 && text.contains("DEBITUM_INSUFFICIENT_WALLET_PERMISSION") {
            return Err(ClientError::InvalidInput(format!("Insufficient permissions to push events: {}", text)));
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
