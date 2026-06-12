//! Sync: push unsynced events, pull server events, merge, rebuild projection.

use crate::api;
use crate::rust_log;
use crate::storage;
use md5::{Digest, Md5};

fn last_sync_key(wallet_id: &str) -> String {
    format!("last_sync_timestamp_{}", wallet_id)
}

fn server_hash_key(wallet_id: &str) -> String {
    format!("server_hash_{}", wallet_id)
}

/// Mirror of the server's incremental hash (see migration 027 +
/// `crates/server/src/database/repository/hash.rs::UserEventHash::calculate_and_store`).
///
/// The server folds each new event into the user's running hash via
/// `MD5(prev_hash + event_id)` where `event_id` is the canonical UUID
/// string. We compute the same chain locally so a post-pull comparison can
/// detect when the server's readable set diverges from "previous state +
/// the events you just gave me" — i.e., when events were REMOVED from our
/// view (a permission revoke or group-membership change), which the
/// `since`-based incremental pull would otherwise miss silently.
fn fold_event_id(prev_hash: &str, event_id: &str) -> String {
    let mut hasher = Md5::new();
    hasher.update(prev_hash.as_bytes());
    hasher.update(event_id.as_bytes());
    format!("{:x}", hasher.finalize())
}

/// Apply `fold_event_id` over each event in order, starting from `starting_hash`.
fn chain_hash<'a, I: IntoIterator<Item = &'a str>>(starting_hash: &str, event_ids: I) -> String {
    let mut acc = starting_hash.to_string();
    for id in event_ids {
        acc = fold_event_id(&acc, id);
    }
    acc
}

/// Build the snake_case discriminator the server's `EventData` (serde `#[tag = "type"]`)
/// expects for a given (aggregate_type, event_type) pair. Returns `None` for unknown
/// combinations so the caller can skip the event rather than send something the server
/// will reject.
pub(crate) fn event_data_discriminator(aggregate_type: &str, event_type: &str) -> Option<&'static str> {
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
        "id":           e.id,
        "aggregate_id": e.aggregate_id,
        "wallet_id":    e.wallet_id,
        "user_id":      user_id,
        "created_at":   e.timestamp,
        "version":      e.version,
        "event_data":   event_data,
    }))
}

/// Push unsynced events to server, mark accepted as synced.
///
/// Wire contract (matches backend `DomainEvent` deserializer in
/// `backend/rust-api/src/domain/events.rs`):
/// - Client owns `id` (event_id, a UUID v4). Uniqueness is scoped per-wallet on the
///   server, so collisions are essentially impossible.
/// - Server echoes back `accepted: [<event_id>]` so we can mark local rows synced
///   (the client's local event id == the wire id == the server's event_id).
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
            // No need to invalidate any local permission cache here: the next
            // pull's hash comparison will detect any visibility change caused
            // by this push (contact-group membership flip, etc.) and trigger
            // a wipe + full-repull as needed.
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
                // Forget the rolled-back events: rebuild from the remaining
                // synced ones. Wipes + re-applies; UNDO-aware so any
                // pending UNDO chains stay consistent.
                rebuild_projection_tables(&wallet_id, &events)?;
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
    let (mut server_events, mut server_hash) = api::get_sync_events(since.clone())?;
    rust_log!("[debitum_rs] pull_and_merge: server returned {} events for wallet {}", server_events.len(), wallet_id);

    // Hash-based divergence check: did the user's readable set change in a way
    // that an incremental pull would miss? Fold the returned events onto our
    // last-known server hash and compare to the server's current hash.
    //
    //   - For an incremental pull, the starting point is the hash we stashed
    //     last time. If the server only APPENDED events since then, our
    //     fold reproduces the server's current hash exactly. If events were
    //     REMOVED from our view (permission revoke, group membership flip),
    //     the fold diverges → we wipe and full-pull to converge.
    //
    //   - For a full pull (first sync OR a prior wipe), the starting point is
    //     empty; the server returns the complete readable set and our fold
    //     should equal the server hash. If it doesn't, something is off
    //     (clock skew, hash impl drift) — we log but don't loop.
    let previous_hash = storage::config_get(&server_hash_key(&wallet_id))?.unwrap_or_default();
    let starting_hash = if is_full_pull { String::new() } else { previous_hash };
    let event_ids_iter = server_events
        .iter()
        .filter_map(|ev| ev.get("id").and_then(|v| v.as_str()));
    let computed_hash = chain_hash(&starting_hash, event_ids_iter);
    let hash_diverged = !is_full_pull && computed_hash != server_hash;
    if hash_diverged {
        rust_log!(
            "[debitum_rs] pull_and_merge: hash diverged (server={}, computed={}) — events removed from view; clearing and full pull",
            server_hash, computed_hash
        );
        storage::events_delete_all_for_wallet(&wallet_id)?;
        let refetched = api::get_sync_events(None)?;
        server_events = refetched.0;
        server_hash = refetched.1;
        // Don't re-verify after the full pull: trust the server's hash blob and
        // store it as-is. A second mismatch would mean our local md5 chain is
        // diverging from the server's, which is a bug to fix, not a state to
        // recover from.
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
    // Feed each newly-stored event through applier::apply so the
    // contacts / transactions / permission tables in SQLite stay in
    // sync with the events log. Failures are logged and swallowed so a
    // single bad event doesn't abort the whole sync — same defensive
    // posture as the existing event-store code paths.
    if !server_events.is_empty() {
        let mut proj = crate::sdk_projection::SdkProjection::new();
        let rt = tokio::runtime::Runtime::new().map_err(|e| e.to_string())?;
        for ev_json in &server_events {
            match parse_server_event_for_applier(ev_json, &wallet_id) {
                Some(domain_event) => {
                    if let Err(e) = rt.block_on(applier::apply(&mut proj, &domain_event)) {
                        rust_log!("[debitum_rs] applier::apply failed for event: {:?}", e);
                    }
                }
                None => {
                    // Skip events whose shape we can't reconstruct as a
                    // DomainEvent; they still landed in the events table
                    // above and will be processed on next rebuild.
                }
            }
        }
    }

    // If this batch contained any UNDO events, rebuild the projection tables
    // from scratch (UNDO-aware). The per-event applier::apply pass above is a
    // no-op for UNDO variants, so the projection would otherwise still
    // contain the undone event's effects. Rebuilds are rare (UNDOs are rare),
    // so the cost is acceptable.
    let has_undo = snapshots::batch_has_undo(server_events.iter().filter_map(|ev| {
        ev.get("event_type").and_then(|v| v.as_str())
    }));
    if has_undo {
        let all_events = storage::events_get_all(&wallet_id)?;
        rebuild_projection_tables(&wallet_id, &all_events)?;
    }

    // Snapshot the current projection if we crossed an interval boundary
    // or just processed an UNDO. The shared `snapshots` crate owns the
    // when-to-snapshot rule and rotation; this side just supplies the
    // data + the SQLite-backed `SdkSnapshotStore`. Failures are logged
    // and swallowed — a missing snapshot only costs replay time, never
    // correctness.
    if !server_events.is_empty() {
        if let Err(e) = maybe_save_snapshot(&wallet_id, has_undo) {
            rust_log!("[debitum_rs] save_snapshot skipped: {}", e);
        }
    }

    // Notify Dart-side providers about the projection kinds touched in
    // this batch. We collect the unique aggregate_types from the
    // server's events and emit one DataChangeEvent per kind, so a
    // batch with 100 contact UPDATED events fires Contacts once, not
    // 100 times.
    let mut kinds_touched: std::collections::HashSet<crate::DataChangeKind> =
        std::collections::HashSet::new();
    for ev in &server_events {
        if let Some(agg) = ev.get("aggregate_type").and_then(|v| v.as_str()) {
            if let Some(k) = crate::data_bus::kind_from_aggregate_type(agg) {
                kinds_touched.insert(k);
            }
        }
    }
    for k in kinds_touched {
        crate::data_bus::emit(k, Some(wallet_id.clone()));
    }

    // Always advance last_sync_timestamp — using the newest server event's timestamp if any,
    // else "now". Without the fallback, repeated empty-response syncs would all re-trigger the
    // full-pull path, which is destructive when local has data.
    let ts_to_save = server_events
        .last()
        .and_then(|e| e.get("timestamp").and_then(|v| v.as_str()))
        .map(String::from)
        .unwrap_or_else(|| chrono::Utc::now().to_rfc3339());
    storage::config_set(&last_sync_key(&wallet_id), &ts_to_save)?;
    // Stash the server's hash for the NEXT pull's divergence check (above).
    storage::config_set(&server_hash_key(&wallet_id), &server_hash)?;
    Ok(())
}

/// Full sync: push, then pull. The pull handles visibility-change detection
/// itself via the hash comparison — no separate "check permissions" pass.
pub fn full_sync() -> Result<(), String> {
    push_unsynced()?;
    pull_and_merge()
}

/// Clear local wallet data and full pull so the client sees the server's permission-filtered view.
/// Use after permission matrix or group membership changes (hot update without logout).
pub fn clear_wallet_and_resync(wallet_id: &str) -> Result<(), String> {
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

/// Reshape a server `SyncEvent` JSON value into a typed `domain::DomainEvent`.
/// The wire format the server returns matches `DomainEvent`'s serde shape
/// closely; we wrap the inner `event_data` with its `type` discriminator
/// (server strips it from storage but our typed enum needs it) and let
/// `DomainEvent`'s custom deserializer do the rest.
///
/// Returns `None` for events whose shape can't be reconstructed — they're
/// still in the events table; they just don't get applied to the
/// permission projection. The "untyped passthrough" matches the rest of
/// the SDK's defensive event handling.
fn parse_server_event_for_applier(
    ev: &serde_json::Value,
    fallback_wallet_id: &str,
) -> Option<domain::DomainEvent> {
    let aggregate_type = ev.get("aggregate_type").and_then(|v| v.as_str())?;
    let event_type = ev.get("event_type").and_then(|v| v.as_str())?;
    let discriminator = event_data_discriminator(aggregate_type, event_type)?;
    let mut event_data = ev.get("event_data").cloned()?;
    if let Some(obj) = event_data.as_object_mut() {
        // Permission events on the server wire have data wrapped one level
        // deeper. Mirror the server-side normalization (events.rs::parse_event_data_typed).
        if aggregate_type == "permission" && !obj.contains_key("data") {
            // Move existing fields under `data`.
            let payload = serde_json::Value::Object(obj.clone());
            obj.clear();
            obj.insert("data".to_string(), payload);
        }
        obj.insert(
            "type".to_string(),
            serde_json::Value::String(discriminator.to_string()),
        );
    }

    let user_id = ev
        .get("user_id")
        .and_then(|v| v.as_str())
        .unwrap_or("00000000-0000-0000-0000-000000000000");
    let wallet_id = ev
        .get("wallet_id")
        .and_then(|v| v.as_str())
        .unwrap_or(fallback_wallet_id);

    let dto = serde_json::json!({
        "id": ev.get("id"),
        "aggregate_id": ev.get("aggregate_id"),
        "wallet_id": wallet_id,
        "user_id": user_id,
        "created_at": ev.get("timestamp"),
        "version": ev.get("version").and_then(|v| v.as_i64()).unwrap_or(1),
        "event_data": event_data,
    });
    serde_json::from_value::<domain::DomainEvent>(dto).ok()
}

/// Wipe contacts / transactions / permission tables for a wallet and
/// re-apply the given events in order. Used by code paths that mutate
/// the events log out-of-band — push rollback after the server rejects
/// pending events, UNDO event arrival — to keep the projection tables
/// consistent with the events log.
///
/// UNDO handling: events whose id is named in some later event's
/// `undone_event_id` are SKIPPED. applier::apply treats UNDO itself
/// as a no-op, so a vanilla re-apply would leave the undone event's
/// effects in the tables. The filter pass below is the minimum
/// needed to keep parity.
pub(crate) fn rebuild_projection_tables(
    wallet_id: &str,
    events: &[storage::StoredEvent],
) -> Result<(), String> {
    use crate::sdk_projection::SdkProjection;
    use rusqlite::params;

    // Collect ids referenced by UNDO events — these events are filtered
    // out of the apply pass below. (UNDO events themselves are also
    // skipped because applier::apply is a no-op for them.) The
    // shared helper takes (event_type, parsed_event_data) pairs;
    // pre-parse the JSON once here.
    let parsed: Vec<(String, serde_json::Value)> = events
        .iter()
        .map(|e| {
            let data = serde_json::from_str::<serde_json::Value>(&e.event_data)
                .unwrap_or(serde_json::Value::Null);
            (e.event_type.clone(), data)
        })
        .collect();
    let undone_ids = snapshots::collect_undone_event_ids(
        parsed.iter().map(|(t, d)| (t.as_str(), d)),
    );

    crate::storage::with_db(|conn| {
        conn.execute("DELETE FROM contacts WHERE wallet_id = ?1", params![wallet_id])?;
        conn.execute("DELETE FROM transactions WHERE wallet_id = ?1", params![wallet_id])?;
        conn.execute("DELETE FROM wallet_users WHERE wallet_id = ?1", params![wallet_id])?;
        conn.execute("DELETE FROM wallet_owners WHERE wallet_id = ?1", params![wallet_id])?;
        conn.execute("DELETE FROM user_groups WHERE wallet_id = ?1", params![wallet_id])?;
        conn.execute("DELETE FROM contact_groups WHERE wallet_id = ?1", params![wallet_id])?;
        conn.execute("DELETE FROM projection_snapshots WHERE wallet_id = ?1", params![wallet_id])?;
        Ok(())
    })?;
    let mut proj = SdkProjection::new();
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|e| e.to_string())?;
    for e in events {
        if e.event_type == "UNDO" {
            continue;
        }
        if undone_ids.contains(&e.id) {
            continue;
        }
        let ev_json = serde_json::json!({
            "id": e.id,
            "aggregate_type": e.aggregate_type,
            "aggregate_id": e.aggregate_id,
            "event_type": e.event_type,
            "event_data": serde_json::from_str::<serde_json::Value>(&e.event_data)
                .unwrap_or(serde_json::Value::Null),
            "timestamp": e.timestamp,
            "version": e.version,
            "wallet_id": e.wallet_id,
        });
        if let Some(de) = parse_server_event_for_applier(&ev_json, wallet_id) {
            if let Err(err) = rt.block_on(applier::apply(&mut proj, &de)) {
                rust_log!("[debitum_rs] rebuild_projection_tables: apply failed: {:?}", err);
            }
        }
    }
    Ok(())
}

/// Save a projection snapshot iff the event count crossed
/// [`snapshots::DEFAULT_SNAPSHOT_INTERVAL`] OR an UNDO landed in
/// this batch. Snapshots speed up the next UNDO rollback and are
/// dropped to [`snapshots::DEFAULT_MAX_SNAPSHOTS`] per wallet.
fn maybe_save_snapshot(wallet_id: &str, has_undo: bool) -> Result<(), String> {
    let event_count = storage::events_count(wallet_id)?;
    if !has_undo && !snapshots::should_create_snapshot(event_count) {
        return Ok(());
    }
    let wallet_uuid = uuid::Uuid::parse_str(wallet_id).map_err(|e| e.to_string())?;
    let contacts = storage::load_contacts_from_tables(wallet_id)?;
    let transactions = storage::load_transactions_from_tables(wallet_id)?;
    let contacts_json = serde_json::to_value(&contacts).map_err(|e| e.to_string())?;
    let transactions_json = serde_json::to_value(&transactions).map_err(|e| e.to_string())?;
    let last_event_id = storage::events_get_all(wallet_id)?
        .last()
        .map(|e| e.id.clone())
        .unwrap_or_default();
    let store = crate::sdk_snapshot_store::SdkSnapshotStore::new();
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|e| e.to_string())?;
    rt.block_on(snapshots::save_snapshot(
        &store,
        wallet_uuid,
        last_event_id,
        event_count,
        contacts_json,
        transactions_json,
    ))
}
