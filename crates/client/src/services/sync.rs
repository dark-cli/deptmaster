//! Sync: push unsynced events, pull server events, merge, rebuild projection.

use crate::api;
use crate::rust_log;
use crate::database;

/// Storage key for the per-wallet last_hash from the most recent pull.
/// The name is historical; under the migration-033 protocol the value
/// is the server's `latest_hash` (the hash of the last row in
/// user_readable_events for this user at the moment of that pull),
/// which the client echoes back on the next pull so the server can
/// resolve "what came after" via a single SQL lookup.
fn server_hash_key(wallet_id: &str) -> String {
    format!("server_hash_{}", wallet_id)
}

/// Build the snake_case discriminator the server's `EventData` (serde `#[tag = "type"]`)
/// expects for a given (aggregate_type, event_type) pair. Returns `None` for unknown
/// combinations so the caller can skip the event rather than send something the server
/// will reject.
pub(crate) fn event_data_discriminator(
    aggregate_type: &str,
    event_type: &str,
) -> Option<&'static str> {
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
    e: &database::StoredEvent,
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
    let wallet_id = database::config_get("current_wallet_id")?
        .ok_or_else(|| "No wallet selected".to_string())?;
    let unsynced = database::events_get_unsynced(&wallet_id)?;
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

    let user_id = database::config_get("user_id")?
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
            rust_log!("[debitum_rs] push_unsynced accepted={}", accepted.len());
            database::events_mark_synced(&accepted)?;
            // No need to invalidate any local permission cache here: the next
            // pull's hash comparison will detect any visibility change caused
            // by this push (contact-group membership flip, etc.) and trigger
            // a wipe + full-repull as needed.
            Ok(())
        }
        Err(e) => {
            // Only drop local events when the server explicitly sent our permission-denied code (in response body).
            // Network/offline errors never contain this string, so we never drop events for connection/timeout/etc.
            if e.to_string().contains("DEBITUM_INSUFFICIENT_WALLET_PERMISSION") {
                let dropped = database::events_delete_unsynced(&wallet_id)?;
                rust_log!(
                    "[debitum_rs] push_unsynced: server returned DEBITUM_INSUFFICIENT_WALLET_PERMISSION -> dropped {} local pending events (wallet_id={})",
                    dropped,
                    wallet_id
                );
                let events = database::events_get_all(&wallet_id)?;
                // Forget the rolled-back events: rebuild from the remaining
                // synced ones. Wipes + re-applies; UNDO-aware so any
                // pending UNDO chains stay consistent.
                rebuild_projection_tables(&wallet_id, &events)?;
                return Err(format!(
                    "DEBITUM_INSUFFICIENT_WALLET_PERMISSION (dropped {} local pending events)",
                    dropped
                ));
            }
            // Network/offline or other error: do NOT fail the write. Events stay unsynced and will sync later.
            rust_log!("[debitum_rs] push_unsynced: sync failed (e.g. offline), keeping {} local events for later sync: {}", unsynced.len(), e);
            Ok(())
        }
    }
}

/// Pull server events for this wallet, merge into local.
///
/// Per-row chain-hash protocol (server migration 033):
///   - Client sends its `last_hash` (the `latest_hash` returned by the
///     previous pull). Server does `WHERE hash = ?` on
///     `user_readable_events`; found → returns events with greater id
///     (incremental). Not found / first sync → returns all events plus
///     `flush=true`.
///   - Client never validates the hash. The server is authoritative.
///   - If `flush` is set, client wipes local events for the wallet
///     before applying the returned batch.
pub fn pull_and_merge() -> Result<(), String> {
    let wallet_id = database::config_get("current_wallet_id")?
        .ok_or_else(|| "No wallet selected".to_string())?;
    let last_hash = database::config_get(&server_hash_key(&wallet_id))?.unwrap_or_default();
    let last_hash_for_log = if last_hash.is_empty() {
        "<none>".to_string()
    } else {
        last_hash.clone()
    };
    rust_log!(
        "[debitum_rs] pull_and_merge: pulling wallet={} last_hash={}",
        wallet_id,
        last_hash_for_log
    );

    let last_hash_arg = if last_hash.is_empty() {
        None
    } else {
        Some(last_hash.clone())
    };
    let (server_events, latest_hash, flush) = api::get_sync_events(last_hash_arg)?;
    rust_log!(
        "[debitum_rs] pull_and_merge: server returned {} events, latest_hash={}, flush={}",
        server_events.len(),
        latest_hash,
        flush
    );

    // If the server says "your last_hash isn't in my chain anymore",
    // wipe the wallet's local events + projection and absorb the
    // returned set from scratch. This fires on:
    //   - first sync (no last_hash sent)
    //   - permission flip removed events from view (server's chain
    //     diverged from what client has)
    //   - client storage corruption (last_hash points to nothing
    //     server knows about)
    // The decision is made by the server — client never second-guesses.
    if flush {
        rust_log!(
            "[debitum_rs] pull_and_merge: server requested flush — wiping wallet and absorbing {} events",
            server_events.len()
        );
        database::events_delete_all_for_wallet(&wallet_id)?;
    }

    for ev in &server_events {
        let id = ev.get("id").and_then(|v| v.as_str()).unwrap_or("");
        let aggregate_type = ev
            .get("aggregate_type")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        let aggregate_id = ev
            .get("aggregate_id")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        let event_type = ev.get("event_type").and_then(|v| v.as_str()).unwrap_or("");
        let event_data = ev
            .get("event_data")
            .cloned()
            .unwrap_or(serde_json::Value::Null);
        let timestamp = ev.get("timestamp").and_then(|v| v.as_str()).unwrap_or("");
        let version = ev.get("version").and_then(|v| v.as_i64()).unwrap_or(1) as i32;
        if id.is_empty() {
            continue;
        }
        let stored = database::StoredEvent {
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
        database::events_insert(&stored)?;
    }

    if !server_events.is_empty() {
        let mut proj = crate::sdk_projection::SdkProjection::new();
        let rt = tokio::runtime::Runtime::new().map_err(|e| e.to_string())?;
        for ev_json in &server_events {
            if let Some(domain_event) = parse_server_event_for_applier(ev_json, &wallet_id) {
                if let Err(e) = rt.block_on(applier::apply(&mut proj, &domain_event)) {
                    rust_log!("[debitum_rs] applier::apply failed for event: {:?}", e);
                }
            }
        }
    }

    // UNDO events make applier::apply a no-op for the undone event; rebuild
    // the projection from the full local events log so undone effects drop.
    let has_undo = snapshots::batch_has_undo(server_events.iter().filter_map(|ev| {
        ev.get("event_type")
            .and_then(|v| v.as_str())
            .and_then(domain::EventType::from_str)
    }));
    if has_undo {
        let all_events = database::events_get_all(&wallet_id)?;
        rebuild_projection_tables(&wallet_id, &all_events)?;
    }

    if !server_events.is_empty() {
        if let Err(e) = maybe_save_snapshot(&wallet_id, has_undo) {
            rust_log!("[debitum_rs] save_snapshot skipped: {}", e);
        }
    }

    // Fire one DataChangeEvent per aggregate kind touched in this batch.
    let mut kinds_touched: std::collections::HashSet<crate::DataChangeKind> =
        std::collections::HashSet::new();
    for ev in &server_events {
        if let Some(agg) = ev
            .get("aggregate_type")
            .and_then(|v| v.as_str())
            .and_then(domain::AggregateType::from_str)
        {
            kinds_touched.insert(crate::data_bus::kind_from_aggregate(agg));
        }
    }
    for k in kinds_touched {
        crate::data_bus::emit(k, Some(wallet_id.clone()));
    }

    // Store the server's latest_hash for the next pull. Server-driven; no
    // client computation needed.
    database::config_set(&server_hash_key(&wallet_id), &latest_hash)?;
    rust_log!(
        "[debitum_rs] pull_and_merge: stored last_hash={} (applied {} events, flush={})",
        latest_hash,
        server_events.len(),
        flush
    );
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
    database::clear_wallet(wallet_id)?;
    pull_and_merge()
}

/// Invalidate permission cache, clear local data, and full resync. Use after contact group
/// membership or permission matrix changes so the client sees updated data without logout/login.
/// Only has effect when wallet_id is the current wallet.
pub fn invalidate_perms_cache_and_pull(wallet_id: &str) -> Result<(), String> {
    let current = database::config_get("current_wallet_id")?.filter(|c| !c.is_empty());
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
    events: &[database::StoredEvent],
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
        parsed
            .iter()
            .filter_map(|(t, d)| domain::EventType::from_str(t).map(|et| (et, d))),
    );

    crate::database::with_db(|conn| {
        conn.execute(
            "DELETE FROM contacts WHERE wallet_id = ?1",
            params![wallet_id],
        )?;
        conn.execute(
            "DELETE FROM transactions WHERE wallet_id = ?1",
            params![wallet_id],
        )?;
        conn.execute(
            "DELETE FROM wallet_users WHERE wallet_id = ?1",
            params![wallet_id],
        )?;
        conn.execute(
            "DELETE FROM wallet_owners WHERE wallet_id = ?1",
            params![wallet_id],
        )?;
        conn.execute(
            "DELETE FROM user_groups WHERE wallet_id = ?1",
            params![wallet_id],
        )?;
        conn.execute(
            "DELETE FROM contact_groups WHERE wallet_id = ?1",
            params![wallet_id],
        )?;
        conn.execute(
            "DELETE FROM projection_snapshots WHERE wallet_id = ?1",
            params![wallet_id],
        )?;
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
                rust_log!(
                    "[debitum_rs] rebuild_projection_tables: apply failed: {:?}",
                    err
                );
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
    let event_count = database::events_count(wallet_id)?;
    if !has_undo && !snapshots::should_create_snapshot(event_count) {
        return Ok(());
    }
    let wallet_uuid = uuid::Uuid::parse_str(wallet_id).map_err(|e| e.to_string())?;
    let contacts = database::load_contacts_from_tables(wallet_id)?;
    let transactions = database::load_transactions_from_tables(wallet_id)?;
    let contacts_json = serde_json::to_value(&contacts).map_err(|e| e.to_string())?;
    let transactions_json = serde_json::to_value(&transactions).map_err(|e| e.to_string())?;
    let last_event_id = database::events_get_all(wallet_id)?
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
