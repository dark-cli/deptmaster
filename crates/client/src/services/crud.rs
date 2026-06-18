//! CRUD: append events, rebuild projection, trigger sync.
//! Uses typed IDs (WalletId, ContactId, TransactionId) for validation; dates as chrono types internally.

use crate::util::ids::{ContactId, TransactionId, WalletId};
use crate::types::models::{Contact, Currency, Transaction};
use crate::rust_log;
use crate::sdk::projection::SdkProjection;
use crate::database;
use crate::services::sync;
use chrono::NaiveDate;
use rusqlite::params;
use uuid::Uuid;

fn ensure_wallet() -> Result<String, String> {
    let s = database::storage::config_get("current_wallet_id")?
        .ok_or_else(|| "No wallet selected".to_string())?;
    WalletId::parse(&s).map(|w| w.as_str().to_string())
}

/// Reshape a locally-created [`database::storage::StoredEvent`] into a typed
/// [`domain::DomainEvent`] and run it through `applier::apply` so the
/// SDK's contacts / transactions / permission SQLite tables reflect
/// the new event. The `user_id` claim from the stored JWT is used as
/// the event's user; missing claims default to nil-UUID (no harm —
/// the SDK's projection methods don't consult event.user_id).
fn apply_event_locally(e: &database::storage::StoredEvent) -> Result<(), String> {
    let discriminator = sync::event_data_discriminator(&e.aggregate_type, &e.event_type);
    let Some(discriminator) = discriminator else {
        // Unknown shape (shouldn't happen for events we generate locally);
        // skip silently, same as parse_server_event_for_applier.
        return Ok(());
    };
    let event_data_val: serde_json::Value =
        serde_json::from_str(&e.event_data).map_err(|err| err.to_string())?;
    let mut payload = event_data_val;
    if let Some(obj) = payload.as_object_mut() {
        if e.aggregate_type == "permission" && !obj.contains_key("data") {
            let inner = serde_json::Value::Object(obj.clone());
            obj.clear();
            obj.insert("data".to_string(), inner);
        }
        obj.insert(
            "type".to_string(),
            serde_json::Value::String(discriminator.to_string()),
        );
    }
    let dto = serde_json::json!({
        "id": e.id,
        "aggregate_id": e.aggregate_id,
        "wallet_id": e.wallet_id,
        "user_id": crate::current_user_id_or_nil(),
        "created_at": e.timestamp,
        "version": e.version,
        "event_data": payload,
    });
    let domain_event = match serde_json::from_value::<domain::DomainEvent>(dto) {
        Ok(de) => de,
        Err(err) => {
            rust_log!(
                "[debitum_rs] apply_event_locally: deserialize failed: {}",
                err
            );
            return Ok(());
        }
    };
    let mut proj = SdkProjection::new();
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|err| err.to_string())?;
    if let Err(err) = rt.block_on(applier::apply(&mut proj, &domain_event)) {
        rust_log!(
            "[debitum_rs] applier::apply failed for local event: {:?}",
            err
        );
    }
    Ok(())
}

/// Wipe and re-apply every event for the wallet (UNDO-aware). Needed
/// after appending an UNDO locally, since applier::apply is a no-op
/// for UNDO variants and the undone event's effect still sits in the
/// projection tables.
fn rebuild_projection_for_wallet(wallet_id: &str) -> Result<(), String> {
    let events = database::storage::events_get_all(wallet_id)?;
    sync::rebuild_projection_tables(wallet_id, &events)
}

/// Sum transaction amounts (filtered to live rows) to compute the
/// wallet's total debt. Used to stamp events for the chart so the
/// client value matches what the server records.
pub fn wallet_total_debt(wallet_id: &str) -> Result<i64, String> {

    let wid = wallet_id.to_string();
    database::storage::with_db(|conn| {
        let total: i64 = conn.query_row(
            "SELECT COALESCE(SUM(
                CASE direction
                    WHEN 'owed' THEN  amount
                    WHEN 'lent' THEN -amount
                    ELSE              amount
                END
             ), 0)
             FROM transactions
             WHERE wallet_id = ?1 AND is_deleted = 0",
            params![wid],
            |r| r.get(0),
        )?;
        Ok(total)
    })
}

fn append_event(
    wallet_id: &str,
    aggregate_type: &str,
    aggregate_id: &str,
    event_type: &str,
    event_data: serde_json::Value,
) -> Result<(), String> {
    rust_log!(
        "[debitum_rs] crud::append_event wallet_id={} aggregate={}/{} event_type={}",
        wallet_id,
        aggregate_type,
        aggregate_id,
        event_type
    );
    // Client generates event_id locally (UUID v4). Uniqueness is enforced per-wallet
    // on the server (UNIQUE (wallet_id, event_id)); collision odds at our scale are
    // ~10^-18 — see vault/06-client/01-design-notes.md. Generating client-side lets
    // offline events reference each other (e.g. UNDO -> original) without waiting
    // for sync.
    let id = Uuid::new_v4().to_string();
    let timestamp = chrono::Utc::now().to_rfc3339();
    let event_data_str = serde_json::to_string(&event_data).map_err(|e| e.to_string())?;
    let e = database::storage::StoredEvent {
        id: id.clone(),
        wallet_id: wallet_id.to_string(),
        aggregate_type: aggregate_type.to_string(),
        aggregate_id: aggregate_id.to_string(),
        event_type: event_type.to_string(),
        event_data: event_data_str.clone(),
        timestamp: timestamp.clone(),
        version: 1,
        synced: false,
    };
    database::storage::events_insert(&e)?;
    // Feed the new event through applier so the contacts / transactions
    // SQLite tables reflect this event. Errors are logged but not
    // propagated — same defensive posture as `sync::pull_and_merge`.
    apply_event_locally(&e)?;
    // applier::apply is a no-op for UNDO; the undone event's effect is
    // still in the tables. A full rebuild is the simplest way to
    // remove it — UNDOs are rare, so the cost is acceptable.
    if event_type == "UNDO" {
        rebuild_projection_for_wallet(wallet_id)?;
    }
    // Notify Dart-side providers that the relevant projection changed.
    // Emit before push so the UI updates instantly; the push happens
    // in the background and any server rejection produces its own
    // emission via the resync path.
    if let Some(agg) = domain::AggregateType::from_str(aggregate_type) {
        crate::integration::data_bus::emit(
            crate::integration::data_bus::kind_from_aggregate(agg),
            Some(wallet_id.to_string()),
        );
    }
    sync::push_unsynced()?;
    // Stamp the new event with total_debt so the chart can plot it
    // (matches the server's denormalized total_debt column).
    let total_debt = wallet_total_debt(wallet_id)?;
    let mut data = serde_json::from_str::<serde_json::Value>(&event_data_str).unwrap_or(event_data);
    data["total_debt"] = serde_json::json!(total_debt);
    let updated = serde_json::to_string(&data).map_err(|e| e.to_string())?;
    database::storage::events_update_event_data(&id, &updated)?;
    Ok(())
}

pub fn create_contact(
    name: String,
    username: Option<String>,
    phone: Option<String>,
    email: Option<String>,
    notes: Option<String>,
    group_ids: Option<Vec<String>>,
) -> Result<Contact, String> {
    let wallet_id = ensure_wallet()?;
    let id = Uuid::new_v4().to_string();
    let ts = chrono::Utc::now().to_rfc3339();
    let mut data = serde_json::json!({
        "name": name,
        "timestamp": ts,
        "wallet_id": wallet_id
    });
    if let Some(u) = username {
        data["username"] = serde_json::json!(u);
    }
    if let Some(p) = phone {
        data["phone"] = serde_json::json!(p);
    }
    if let Some(e) = email {
        data["email"] = serde_json::json!(e);
    }
    if let Some(n) = notes {
        data["notes"] = serde_json::json!(n);
    }
    if let Some(ids) = &group_ids {
        if !ids.is_empty() {
            data["group_ids"] = serde_json::json!(ids);
        }
    }
    append_event(&wallet_id, "contact", &id, "CREATED", data)?;
    database::storage::load_contacts_from_tables(&wallet_id)?
        .into_iter()
        .find(|c| c.id == id)
        .ok_or_else(|| "Contact not found after create".to_string())
}

pub fn get_contacts() -> Result<String, String> {
    let wallet_id = ensure_wallet()?;
    let contacts = database::storage::load_contacts_from_tables(&wallet_id)?;
    Ok(serde_json::to_string(&contacts).map_err(|e| e.to_string())?)
}

pub fn get_transactions() -> Result<String, String> {
    let wallet_id = ensure_wallet()?;
    let transactions = database::storage::load_transactions_from_tables(&wallet_id)?;
    Ok(serde_json::to_string(&transactions).map_err(|e| e.to_string())?)
}

pub fn get_contact(id: String) -> Result<String, String> {
    let _ = ContactId::parse(&id).map_err(|e| e)?;
    let json = get_contacts()?;
    let contacts: Vec<Contact> = serde_json::from_str(&json).map_err(|e| e.to_string())?;
    let c = contacts
        .into_iter()
        .find(|c| c.id == id)
        .ok_or_else(|| format!("Contact {} not found", id))?;
    serde_json::to_string(&c).map_err(|e| e.to_string())
}

pub fn get_transaction(id: String) -> Result<String, String> {
    let _ = TransactionId::parse(&id).map_err(|e| e)?;
    let json = get_transactions()?;
    let transactions: Vec<Transaction> = serde_json::from_str(&json).map_err(|e| e.to_string())?;
    let t = transactions
        .into_iter()
        .find(|t| t.id == id)
        .ok_or_else(|| format!("Transaction {} not found", id))?;
    serde_json::to_string(&t).map_err(|e| e.to_string())
}

pub fn create_transaction(
    contact_id: String,
    type_: String,
    direction: String,
    amount: i64,
    currency: String,
    description: Option<String>,
    transaction_date: String,
    due_date: Option<String>,
) -> Result<Transaction, String> {
    let _contact_id = ContactId::parse(&contact_id).map_err(|e| e)?;
    // FFI entry: convert wire strings to typed domain values immediately
    // and reject unknown ones. Past behavior silently tolerated unknown
    // type/direction (e.g. "expense") with whatever fallback the applier
    // happened to pick — that's the kind of string drift the no-strings
    // rule exists to prevent. Now: invalid → clear error.
    let type_typed = domain::TransactionType::from_str(&type_)
        .ok_or_else(|| format!("Invalid transaction type: {}", type_))?;
    let direction_typed = domain::TransactionDirection::from_str(&direction)
        .ok_or_else(|| format!("Invalid transaction direction: {}", direction))?;
    let currency_typed = Currency::from_str(currency.as_str()).unwrap_or(Currency::IQD);
    let tx_date = NaiveDate::parse_from_str(transaction_date.trim(), "%Y-%m-%d")
        .map_err(|e| format!("Invalid transaction_date: {}", e))?;
    let due_date_typed = due_date
        .as_ref()
        .map(|d| NaiveDate::parse_from_str(d.trim(), "%Y-%m-%d"))
        .transpose()
        .map_err(|e| format!("Invalid due_date: {}", e))?;
    let wallet_id = ensure_wallet()?;
    let id = Uuid::new_v4().to_string();
    let ts = chrono::Utc::now().to_rfc3339();
    let mut data = serde_json::json!({
        "contact_id": contact_id,
        "type": type_typed.as_str(),
        "direction": direction_typed.as_str(),
        "amount": amount,
        "currency": currency_typed.as_str(),
        "transaction_date": tx_date.format("%Y-%m-%d").to_string(),
        "timestamp": ts,
        "wallet_id": wallet_id
    });
    if let Some(d) = description {
        data["description"] = serde_json::json!(d);
    }
    if let Some(d) = &due_date_typed {
        data["due_date"] = serde_json::json!(d.format("%Y-%m-%d").to_string());
    }
    append_event(&wallet_id, "transaction", &id, "CREATED", data)?;
    database::storage::load_transactions_from_tables(&wallet_id)?
        .into_iter()
        .find(|t| t.id == id)
        .ok_or_else(|| "Transaction not found after create".to_string())
}

pub fn update_contact(
    id: String,
    name: String,
    username: Option<String>,
    phone: Option<String>,
    email: Option<String>,
    notes: Option<String>,
    group_ids: Option<Vec<String>>,
) -> Result<(), String> {
    let _ = ContactId::parse(&id).map_err(|e| e)?;
    let wallet_id = ensure_wallet()?;
    let ts = chrono::Utc::now().to_rfc3339();
    let mut data = serde_json::json!({
        "name": name,
        "timestamp": ts,
        "wallet_id": wallet_id
    });
    if let Some(u) = username {
        data["username"] = serde_json::json!(u);
    }
    if let Some(p) = phone {
        data["phone"] = serde_json::json!(p);
    }
    if let Some(e) = email {
        data["email"] = serde_json::json!(e);
    }
    if let Some(n) = notes {
        data["notes"] = serde_json::json!(n);
    }
    if let Some(ids) = &group_ids {
        if !ids.is_empty() {
            data["group_ids"] = serde_json::json!(ids);
        }
    }
    append_event(&wallet_id, "contact", &id, "UPDATED", data)?;
    Ok(())
}

pub fn delete_contact(contact_id: String) -> Result<(), String> {
    let _ = ContactId::parse(&contact_id).map_err(|e| e)?;
    let wallet_id = ensure_wallet()?;
    let ts = chrono::Utc::now().to_rfc3339();
    let data = serde_json::json!({
        "comment": "Contact deleted",
        "timestamp": ts,
        "wallet_id": wallet_id
    });
    append_event(&wallet_id, "contact", &contact_id, "DELETED", data)?;
    Ok(())
}

pub fn update_transaction(
    id: String,
    contact_id: String,
    type_: String,
    direction: String,
    amount: i64,
    currency: String,
    description: Option<String>,
    transaction_date: String,
    due_date: Option<String>,
) -> Result<(), String> {
    let _ = TransactionId::parse(&id).map_err(|e| e)?;
    let _ = ContactId::parse(&contact_id).map_err(|e| e)?;
    let wallet_id = ensure_wallet()?;
    let ts = chrono::Utc::now().to_rfc3339();
    // FFI entry typing (see create_transaction for the rationale).
    let type_typed = domain::TransactionType::from_str(&type_)
        .ok_or_else(|| format!("Invalid transaction type: {}", type_))?;
    let direction_typed = domain::TransactionDirection::from_str(&direction)
        .ok_or_else(|| format!("Invalid transaction direction: {}", direction))?;
    let currency_typed = Currency::from_str(currency.as_str()).unwrap_or(Currency::IQD);
    let tx_date = NaiveDate::parse_from_str(transaction_date.trim(), "%Y-%m-%d")
        .map_err(|e| format!("Invalid transaction_date: {}", e))?;
    let due_date_typed = due_date
        .as_ref()
        .map(|d| NaiveDate::parse_from_str(d.trim(), "%Y-%m-%d"))
        .transpose()
        .map_err(|e| format!("Invalid due_date: {}", e))?;
    let mut data = serde_json::json!({
        "contact_id": contact_id,
        "type": type_typed.as_str(),
        "direction": direction_typed.as_str(),
        "amount": amount,
        "currency": currency_typed.as_str(),
        "transaction_date": tx_date.format("%Y-%m-%d").to_string(),
        "timestamp": ts,
        "wallet_id": wallet_id
    });
    if let Some(d) = description {
        data["description"] = serde_json::json!(d);
    }
    if let Some(d) = &due_date_typed {
        data["due_date"] = serde_json::json!(d.format("%Y-%m-%d").to_string());
    }
    append_event(&wallet_id, "transaction", &id, "UPDATED", data)?;
    Ok(())
}

const UNDO_WINDOW_SECS: i64 = 5;

fn last_event_for_aggregate(
    wallet_id: &str,
    aggregate_type: &str,
    aggregate_id: &str,
) -> Result<Option<database::storage::StoredEvent>, String> {
    let events = database::storage::events_get_for_aggregate(wallet_id, aggregate_type, aggregate_id)?;
    Ok(events.into_iter().last())
}

fn is_within_undo_window(timestamp_rfc3339: &str) -> bool {
    let t = match chrono::DateTime::parse_from_rfc3339(timestamp_rfc3339) {
        Ok(dt) => dt.with_timezone(&chrono::Utc),
        Err(_) => return false,
    };
    let now = chrono::Utc::now();
    (now - t).num_seconds() < UNDO_WINDOW_SECS
}

/// Delete transaction: if last event is within 5s, append UNDO; otherwise append DELETED.
pub fn delete_transaction(transaction_id: String) -> Result<(), String> {
    let _ = TransactionId::parse(&transaction_id).map_err(|e| e)?;
    let wallet_id = ensure_wallet()?;
    let last = last_event_for_aggregate(&wallet_id, "transaction", &transaction_id)?
        .ok_or_else(|| "No events found for transaction".to_string())?;
    let ts = chrono::Utc::now().to_rfc3339();
    if is_within_undo_window(&last.timestamp) {
        let data = serde_json::json!({
            "undone_event_id": last.id,
            "comment": "Transaction deleted (undo)",
            "timestamp": ts,
            "wallet_id": wallet_id
        });
        append_event(
            &wallet_id,
            &last.aggregate_type,
            &last.aggregate_id,
            "UNDO",
            data,
        )?;
    } else {
        let data = serde_json::json!({
            "comment": "Transaction deleted",
            "timestamp": ts,
            "wallet_id": wallet_id
        });
        append_event(&wallet_id, "transaction", &transaction_id, "DELETED", data)?;
    }
    Ok(())
}

/// Undo last action for a contact (append UNDO event). Fails if last event is older than 5s.
pub fn undo_contact_action(contact_id: String) -> Result<(), String> {
    let wallet_id = ensure_wallet()?;
    let last = last_event_for_aggregate(&wallet_id, "contact", &contact_id)?
        .ok_or_else(|| "No events found for contact".to_string())?;
    if !is_within_undo_window(&last.timestamp) {
        return Err("Cannot undo: Action is too old (must be within 5 seconds)".to_string());
    }
    let ts = chrono::Utc::now().to_rfc3339();
    let data = serde_json::json!({
        "undone_event_id": last.id,
        "comment": "Action undone",
        "timestamp": ts,
        "wallet_id": wallet_id
    });
    append_event(
        &wallet_id,
        &last.aggregate_type,
        &last.aggregate_id,
        "UNDO",
        data,
    )?;
    Ok(())
}

/// Undo last action for a transaction (append UNDO event). Fails if last event is older than 5s.
pub fn undo_transaction_action(transaction_id: String) -> Result<(), String> {
    let _ = TransactionId::parse(&transaction_id).map_err(|e| e)?;
    let wallet_id = ensure_wallet()?;
    let last = last_event_for_aggregate(&wallet_id, "transaction", &transaction_id)?
        .ok_or_else(|| "No events found for transaction".to_string())?;
    if !is_within_undo_window(&last.timestamp) {
        return Err("Cannot undo: Action is too old (must be within 5 seconds)".to_string());
    }
    let ts = chrono::Utc::now().to_rfc3339();
    let data = serde_json::json!({
        "undone_event_id": last.id,
        "comment": "Action undone",
        "timestamp": ts,
        "wallet_id": wallet_id
    });
    append_event(
        &wallet_id,
        &last.aggregate_type,
        &last.aggregate_id,
        "UNDO",
        data,
    )?;
    Ok(())
}

pub fn bulk_delete_contacts(contact_ids: Vec<String>) -> Result<(), String> {
    for id in contact_ids {
        delete_contact(id)?;
    }
    Ok(())
}

pub fn bulk_delete_transactions(transaction_ids: Vec<String>) -> Result<(), String> {
    for id in transaction_ids {
        delete_transaction(id)?;
    }
    Ok(())
}

pub fn logout() -> Result<(), String> {
    // Best-effort: ask the server to revoke this device's refresh
    // token first, so a leaked copy stops working the moment the user
    // taps logout instead of living until its 30-day expiry. If the
    // request fails (offline, dead access token, server down) we
    // still wipe local — the user's intent is to log out and a stuck
    // logout button is worse than a refresh row that auto-expires.
    let _ = crate::api::server_logout();
    database::storage::clear_all()?;
    // Tell Dart that the session changed so every cached provider
    // invalidates. Without this, Riverpod hands the next user (or the
    // pre-login screens) lists computed from the previous user's data.
    crate::integration::data_bus::emit(crate::integration::data_bus::DataChangeKind::Session, None);
    Ok(())
}