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

/// Build the snake_case discriminator the server's `EventData` (serde `#[tag = "type"]`)
/// expects for a given (aggregate_type, event_type) pair. Returns `None` for unknown
/// combinations so the caller can skip the event rather than send something the server
/// will reject.
fn event_data_discriminator(aggregate_type: &str, event_type: &str) -> Option<&'static str> {
    match (aggregate_type, event_type) {
        ("contact", "CREATED") => Some("contact_created"),
        ("contact", "UPDATED") => Some("contact_updated"),
        ("contact", "DELETED") => Some("contact_deleted"),
        ("contact", "UNDO") => Some("contact_undone"),
        ("transaction", "CREATED") => Some("transaction_created"),
        ("transaction", "UPDATED") => Some("transaction_updated"),
        ("transaction", "DELETED") => Some("transaction_deleted"),
        ("transaction", "UNDO") => Some("transaction_undone"),
        _ => None,
    }
}

/// Reshape a stored event into the JSON the server's `DomainEvent` deserializer accepts.
///
/// Returns `None` if the event can't be reshaped (unknown discriminator, malformed
/// event_data, missing user_id). The caller skips those — better than sending a
/// payload the server will reject for the whole batch.
fn build_server_event_payload(
    e: &storage::StoredEvent,
    user_id: &str,
) -> Option<serde_json::Value> {
    let discriminator = event_data_discriminator(&e.aggregate_type, &e.event_type)?;

    let mut event_data: serde_json::Value =
        serde_json::from_str(&e.event_data).unwrap_or(serde_json::Value::Null);

    if let Some(obj) = event_data.as_object_mut() {
        // The client writes the inner-type field as "type" for transactions, but the
        // server's EventData::Transaction* variants name it `transaction_type` (the
        // outer "type" key is consumed by serde as the variant discriminator).
        if e.aggregate_type == "transaction" {
            if let Some(inner_type) = obj.remove("type") {
                obj.insert("transaction_type".to_string(), inner_type);
            }
        }
        // Insert the variant discriminator so EventData's `#[serde(tag = "type")]`
        // can pick the right variant.
        obj.insert(
            "type".to_string(),
            serde_json::Value::String(discriminator.to_string()),
        );
    } else {
        // event_data was not an object — wrap it so we at least have a discriminator.
        let mut wrapped = serde_json::Map::new();
        wrapped.insert(
            "type".to_string(),
            serde_json::Value::String(discriminator.to_string()),
        );
        event_data = serde_json::Value::Object(wrapped);
    }

    Some(serde_json::json!({
        "aggregate_id":    e.aggregate_id,
        "wallet_id":       e.wallet_id,
        "user_id":         user_id,
        "created_at":      e.timestamp,
        "version":         e.version,
        "idempotency_key": e.id,
        "event_data":      event_data,
    }))
}

/// Push unsynced events to server, mark accepted as synced.
///
/// Wire contract (matches backend `DomainEvent` deserializer in
/// `backend/rust-api/src/domain/events.rs`):
/// - Client provides `idempotency_key` (our local event id, a UUID) — server uses it for dedup.
/// - Server generates and owns `event_id`.
/// - Server returns `accepted: [<idempotency_key>]` so we can mark local rows synced.
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

    let user_id = storage::config_get("user_id")?
        .ok_or_else(|| "Not logged in (no user_id in storage)".to_string())?;

    let payload: Vec<String> = unsynced
        .iter()
        .filter_map(|e| {
            let v = build_server_event_payload(e, &user_id)?;
            serde_json::to_string(&v).ok()
        })
        .collect();

    if payload.len() != unsynced.len() {
        rust_log!(
            "[debitum_rs] push_unsynced: skipped {} unsendable event(s) of {} pending (unknown discriminator or serialization failure)",
            unsynced.len() - payload.len(),
            unsynced.len()
        );
    }
    if payload.is_empty() {
        return Ok(());
    }
    match api::post_sync_events(payload) {
        Ok(accepted) => {
            rust_log!(
                "[debitum_rs] push_unsynced accepted={}",
                accepted.len()
            );
            storage::events_mark_synced(&accepted)?;
            // Contact group membership may have changed; clear permission cache so next check refetches.
            let had_contact_group_change = unsynced.iter().any(|e| {
                e.aggregate_type == "contact"
                    && e.event_type == "UPDATED"
                    && serde_json::from_str::<serde_json::Value>(&e.event_data)
                        .ok()
                        .map(|d| d.get("group_ids").is_some())
                        .unwrap_or(false)
            });
            if had_contact_group_change {
                let _ = storage::config_remove(&perms_cache_key(&wallet_id));
            }
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

/// Pull server events for this wallet, merge into local, rebuild state.
///
/// Sync semantics:
/// - `since = last_sync_timestamp` (per-wallet) when present → incremental pull (only newer events).
/// - `since = None` → server returns the full visible-to-this-user event set.
///
/// We only DESTRUCTIVELY replace local events when one of two things is true:
///   1. Local has zero events (nothing to lose), AND it's a full pull (first sync).
///   2. An incremental pull returned permission events — the user's visible set may
///      have shrunk, so we full-reset to match the server's filter.
///
/// Otherwise we just upsert (`INSERT OR IGNORE`); the server-issued ids don't collide
/// with our client-issued ones, and dedup happens on (id) plus replay tolerates duplicates.
/// `last_sync_timestamp` is updated at the end of every successful pull (even when the
/// server returned 0 events) so the next sync is incremental — without this, every sync
/// would re-trigger the full-pull path and destroy local-only state.
pub fn pull_and_merge() -> Result<(), String> {
    let wallet_id = storage::config_get("current_wallet_id")?
        .ok_or_else(|| "No wallet selected".to_string())?;
    let local_count = storage::events_count(&wallet_id).unwrap_or(0);
    let since = storage::config_get(&last_sync_key(&wallet_id))?;
    let is_full_pull = since.is_none();
    if let Some(ref s) = since {
        rust_log!("[debitum_rs] pull_and_merge: incremental pull since={}", s);
    } else if local_count == 0 {
        rust_log!("[debitum_rs] pull_and_merge: 0 local events for wallet {}, full pull (no since)", wallet_id);
    } else {
        rust_log!(
            "[debitum_rs] pull_and_merge: no last_sync_timestamp but {} local events for wallet {} — full pull WITHOUT clearing local",
            local_count, wallet_id
        );
    }
    rust_log!("[debitum_rs] pull_and_merge: requesting server events");
    let mut server_events = api::get_sync_events(since.clone())?;
    rust_log!("[debitum_rs] pull_and_merge: server returned {} events for wallet {}", server_events.len(), wallet_id);

    // If this was incremental and the batch includes permission events, our visible set may have changed — do a full resync.
    let has_permission_event = server_events.iter().any(|ev| {
        ev.get("aggregate_type").and_then(|v| v.as_str()) == Some("permission")
    });
    if !is_full_pull && has_permission_event {
        rust_log!("[debitum_rs] pull_and_merge: permission event in batch — clearing and full pull so view is up to date");
        let _ = storage::config_remove(&perms_cache_key(&wallet_id));
        storage::events_delete_all_for_wallet(&wallet_id)?;
        server_events = api::get_sync_events(None)?;
    } else if is_full_pull && local_count == 0 {
        // First sync, nothing local to lose. (No-op — there's nothing to delete.)
        rust_log!("[debitum_rs] pull_and_merge: full pull on empty wallet — just absorbing server events");
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
    // Always advance last_sync_timestamp — using the newest server event's timestamp if any,
    // else "now". Without the fallback, repeated empty-response syncs would all re-trigger the
    // full-pull path, which is destructive when local has data.
    let ts_to_save = server_events
        .last()
        .and_then(|e| e.get("timestamp").and_then(|v| v.as_str()))
        .map(String::from)
        .unwrap_or_else(|| chrono::Utc::now().to_rfc3339());
    storage::config_set(&last_sync_key(&wallet_id), &ts_to_save)?;
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

/// Clear local wallet data and full pull so the client sees the server's permission-filtered view.
/// Use after permission matrix or group membership changes (hot update without logout).
pub fn clear_wallet_and_resync(wallet_id: &str) -> Result<(), String> {
    let _ = storage::config_remove(&perms_cache_key(wallet_id));
    rust_log!(
        "[debitum_rs] permission-related change for wallet {} — clearing local data and full resync",
        wallet_id
    );
    storage::clear_wallet(wallet_id)?;
    pull_and_merge()
}

/// Invalidate permission cache, clear local data, and full resync. Use after contact group
/// membership or permission matrix changes so the client sees updated data without logout/login.
/// Only has effect when wallet_id is the current wallet.
pub fn invalidate_perms_cache_and_pull(wallet_id: &str) -> Result<(), String> {
    let current = storage::config_get("current_wallet_id")?.filter(|c| !c.is_empty());
    if current.as_deref() != Some(wallet_id) {
        return Ok(());
    }
    clear_wallet_and_resync(wallet_id)
}
