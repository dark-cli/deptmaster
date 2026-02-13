//! Sync: push unsynced events, pull server events, merge, rebuild projection.

use crate::api;
use crate::rust_log;
use crate::state_builder;
use crate::storage;

const READ_ACTIONS: &[&str] = &["contact:read", "transaction:read"];
fn perms_cache_key(wallet_id: &str) -> String {
    format!("perms_cache_{}", wallet_id)
}

fn last_sync_key(wallet_id: &str) -> String {
    format!("last_sync_timestamp_{}", wallet_id)
}

/// If the server has revoked or granted contact:read / transaction:read since last sync, clear
/// local wallet data and full resync so the client sees exactly what they are allowed to see
/// (revoke: less data; grant: more data without needing logout/login).
fn check_read_revoked_and_resync(wallet_id: &str) -> Result<(), String> {
    let current_json = api::get_my_permissions_api(wallet_id)?;
    let current: serde_json::Value = serde_json::from_str(&current_json).map_err(|e| e.to_string())?;
    let actions = current
        .get("actions")
        .and_then(|v| v.as_array())
        .map(|a| a.iter().filter_map(|v| v.as_str()).collect::<Vec<_>>())
        .unwrap_or_default();
    let current_set: std::collections::HashSet<&str> = actions.iter().copied().collect();

    let cached_json = storage::config_get(&perms_cache_key(wallet_id))?;
    storage::config_set(&perms_cache_key(wallet_id), &current_json)?;

    let cached = match cached_json {
        Some(s) => s,
        None => return Ok(()),
    };
    let cached_val: serde_json::Value = match serde_json::from_str(&cached) {
        Ok(v) => v,
        Err(_) => return Ok(()),
    };
    let cached_actions = cached_val
        .get("actions")
        .and_then(|v| v.as_array())
        .map(|a| a.iter().filter_map(|v| v.as_str()).collect::<Vec<_>>())
        .unwrap_or_default();
    let cached_set: std::collections::HashSet<&str> = cached_actions.iter().copied().collect();

    let read_revoked = READ_ACTIONS.iter().any(|action| {
        cached_set.contains(action) && !current_set.contains(*action)
    });
    let read_granted = READ_ACTIONS.iter().any(|action| {
        !cached_set.contains(action) && current_set.contains(*action)
    });
    if read_revoked {
        rust_log!(
            "[debitum_rs] read permission revoked for wallet {} — clearing local data and resyncing",
            wallet_id
        );
        storage::clear_wallet(wallet_id)?;
        pull_and_merge()?;
    } else if read_granted {
        rust_log!(
            "[debitum_rs] read permission granted for wallet {} — clearing local data and resyncing so new data appears",
            wallet_id
        );
        storage::clear_wallet(wallet_id)?;
        pull_and_merge()?;
    }
    Ok(())
}

/// Push unsynced events to server, mark accepted as synced.
pub fn push_unsynced() -> Result<(), String> {
    let wallet_id = storage::config_get("current_wallet_id")?
        .ok_or_else(|| "No wallet selected".to_string())?;
    let unsynced = storage::events_get_unsynced(&wallet_id)?;
    if !unsynced.is_empty() {
        rust_log!(
            "[debitum_rs] push_unsynced wallet_id={} pending={}",
            wallet_id,
            unsynced.len()
        );
    }
    if unsynced.is_empty() {
        return Ok(());
    }
    let payload: Vec<String> = unsynced
        .iter()
        .map(|e| {
            let v = serde_json::json!({
                "id": e.id,
                "aggregate_type": e.aggregate_type,
                "aggregate_id": e.aggregate_id,
                "event_type": e.event_type,
                "event_data": serde_json::from_str::<serde_json::Value>(&e.event_data).unwrap_or(serde_json::Value::Null),
                "timestamp": e.timestamp,
                "version": e.version
            });
            serde_json::to_string(&v).unwrap_or_else(|_| "{}".to_string())
        })
        .collect();
    match api::post_sync_events(payload) {
        Ok(accepted) => {
            rust_log!(
                "[debitum_rs] push_unsynced accepted={}",
                accepted.len()
            );
            storage::events_mark_synced(&accepted)?;
            Ok(())
        }
        Err(e) => {
            // Only drop local events when the server explicitly sent our permission-denied code (in response body).
            // Network/offline errors never contain this string, so we never drop events for connection/timeout/etc.
            if e.contains("DEBITUM_INSUFFICIENT_WALLET_PERMISSION") {
                let dropped = storage::events_delete_unsynced(&wallet_id)?;
                rust_log!(
                    "[debitum_rs] push_unsynced: server returned DEBITUM_INSUFFICIENT_WALLET_PERMISSION -> dropped {} local pending events (wallet_id={})",
                    dropped,
                    wallet_id
                );
                let events = storage::events_get_all(&wallet_id)?;
                let (contacts, transactions) = state_builder::build_state_from_stored(&events)?;
                storage::state_save(&wallet_id, &contacts, &transactions)?;
                return Err(format!("DEBITUM_INSUFFICIENT_WALLET_PERMISSION (dropped {} local pending events)", dropped));
            }
            // Network/offline or other error: do NOT fail the write. Events stay unsynced and will sync later.
            rust_log!("[debitum_rs] push_unsynced: sync failed (e.g. offline), keeping {} local events for later sync: {}", unsynced.len(), e);
            Ok(())
        }
    }
}

/// Pull server events (since last sync for this wallet), merge into local, rebuild state.
/// When we have zero local events for this wallet, do a full pull (no since) so server data loads.
/// On full pull (since=None), we replace local events with the server response so that permission
/// filtering takes effect: the client ends up with exactly the events the server allows.
pub fn pull_and_merge() -> Result<(), String> {
    let wallet_id = storage::config_get("current_wallet_id")?
        .ok_or_else(|| "No wallet selected".to_string())?;
    let local_count = storage::events_count(&wallet_id).unwrap_or(0);
    let since = if local_count == 0 {
        rust_log!("[debitum_rs] pull_and_merge: 0 local events for wallet {}, full pull (no since)", wallet_id);
        None
    } else {
        storage::config_get(&last_sync_key(&wallet_id))?
    };
    let is_full_pull = since.is_none();
    if since.as_ref().is_some() {
        rust_log!("[debitum_rs] pull_and_merge: incremental pull since={:?}", since);
    }
    rust_log!("[debitum_rs] pull_and_merge: requesting server events");
    let server_events = api::get_sync_events(since.clone())?;
    rust_log!("[debitum_rs] pull_and_merge: server returned {} events for wallet {}", server_events.len(), wallet_id);

    if is_full_pull {
        storage::events_delete_all_for_wallet(&wallet_id)?;
        rust_log!("[debitum_rs] pull_and_merge: full pull — cleared local events for wallet {}", wallet_id);
    }

    for ev in &server_events {
        let id = ev.get("id").and_then(|v| v.as_str()).unwrap_or("");
        let aggregate_type = ev.get("aggregate_type").and_then(|v| v.as_str()).unwrap_or("");
        let aggregate_id = ev.get("aggregate_id").and_then(|v| v.as_str()).unwrap_or("");
        let event_type = ev.get("event_type").and_then(|v| v.as_str()).unwrap_or("");
        let event_data = ev.get("event_data").cloned().unwrap_or(serde_json::Value::Null);
        let timestamp = ev.get("timestamp").and_then(|v| v.as_str()).unwrap_or("");
        let version = ev.get("version").and_then(|v| v.as_i64()).unwrap_or(1) as i32;
        if id.is_empty() {
            continue;
        }
        let stored = storage::StoredEvent {
            id: id.to_string(),
            wallet_id: wallet_id.clone(),
            aggregate_type: aggregate_type.to_string(),
            aggregate_id: aggregate_id.to_string(),
            event_type: event_type.to_string(),
            event_data: serde_json::to_string(&event_data).unwrap_or_else(|_| "{}".to_string()),
            timestamp: timestamp.to_string(),
            version,
            synced: true,
        };
        storage::events_insert(&stored)?;
    }
    let events = storage::events_get_all(&wallet_id)?;
    let (contacts, transactions) = state_builder::build_state_from_stored(&events)?;
    storage::state_save(&wallet_id, &contacts, &transactions)?;
    if let Some(ts) = server_events.last().and_then(|e| e.get("timestamp").and_then(|v| v.as_str())) {
        storage::config_set(&last_sync_key(&wallet_id), ts)?;
    }
    Ok(())
}

/// Full sync: push then pull. After pull, if read permission was revoked (contact:read or
/// transaction:read removed), clear wallet data and full resync so local state matches server.
pub fn full_sync() -> Result<(), String> {
    push_unsynced()?;
    pull_and_merge()?;
    if let Some(wallet_id) = storage::config_get("current_wallet_id")? {
        if !wallet_id.is_empty() {
            let _ = check_read_revoked_and_resync(&wallet_id);
        }
    }
    Ok(())
}
