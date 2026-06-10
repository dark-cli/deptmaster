//! CRUD: append events, rebuild projection, trigger sync.
//! Uses typed IDs (WalletId, ContactId, TransactionId) for validation; dates as chrono types internally.

use crate::ids::{ContactId, TransactionId, WalletId};
use crate::rust_log;
use crate::models::{Contact, Currency, Transaction};
use crate::sdk_projection::SdkProjection;
use crate::storage;
use crate::sync;
use chrono::NaiveDate;
use rusqlite::params;
use uuid::Uuid;

fn ensure_wallet() -> Result<String, String> {
    let s = storage::config_get("current_wallet_id")?
        .ok_or_else(|| "No wallet selected".to_string())?;
    WalletId::parse(&s).map(|w| w.as_str().to_string())
}

/// Reshape a locally-created [`storage::StoredEvent`] into a typed
/// [`domain::DomainEvent`] and run it through `applier::apply` so the
/// SDK's contacts / transactions / permission SQLite tables reflect
/// the new event. The `user_id` claim from the stored JWT is used as
/// the event's user; missing claims default to nil-UUID (no harm —
/// the SDK's projection methods don't consult event.user_id).
fn apply_event_locally(e: &storage::StoredEvent) -> Result<(), String> {
    let discriminator = sync::event_data_discriminator(&e.aggregate_type, &e.event_type);
    let Some(discriminator) = discriminator else {
        // Unknown shape (shouldn't happen for events we generate locally);
        // skip silently, same as parse_server_event_for_applier.
        return Ok(());
    };
    let event_data_val: serde_json::Value = serde_json::from_str(&e.event_data)
        .map_err(|err| err.to_string())?;
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
            rust_log!("[debitum_rs] apply_event_locally: deserialize failed: {}", err);
            return Ok(());
        }
    };
    let mut proj = SdkProjection::new();
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|err| err.to_string())?;
    if let Err(err) = rt.block_on(applier::apply(&mut proj, &domain_event)) {
        rust_log!("[debitum_rs] applier::apply failed for local event: {:?}", err);
    }
    Ok(())
}

/// Wipe and re-apply every event for the wallet (UNDO-aware). Needed
/// after appending an UNDO locally, since applier::apply is a no-op
/// for UNDO variants and the undone event's effect still sits in the
/// projection tables.
fn rebuild_projection_for_wallet(wallet_id: &str) -> Result<(), String> {
    let events = storage::events_get_all(wallet_id)?;
    sync::rebuild_projection_tables(wallet_id, &events)
}

/// Sum the balance column on the projection table to compute the
/// wallet's total debt (used to stamp events for the chart).
fn wallet_total_debt(wallet_id: &str) -> Result<i64, String> {
    let wid = wallet_id.to_string();
    storage::with_db(|conn| {
        let total: i64 = conn
            .query_row(
                "SELECT COALESCE(SUM(balance), 0) FROM contacts WHERE wallet_id = ?1",
                params![wid],
                |r| r.get(0),
            )
            .unwrap_or(0);
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
        wallet_id, aggregate_type, aggregate_id, event_type
    );
    // Client generates event_id locally (UUID v4). Uniqueness is enforced per-wallet
    // on the server (UNIQUE (wallet_id, event_id)); collision odds at our scale are
    // ~10^-18 — see vault/06-client/01-design-notes.md. Generating client-side lets
    // offline events reference each other (e.g. UNDO -> original) without waiting
    // for sync.
    let id = Uuid::new_v4().to_string();
    let timestamp = chrono::Utc::now().to_rfc3339();
    let event_data_str = serde_json::to_string(&event_data).map_err(|e| e.to_string())?;
    let e = storage::StoredEvent {
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
    storage::events_insert(&e)?;
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
    sync::push_unsynced()?;
    // Stamp the new event with total_debt so the chart can plot it
    // (matches the server's denormalized total_debt column).
    let total_debt = wallet_total_debt(wallet_id)?;
    let mut data = serde_json::from_str::<serde_json::Value>(&event_data_str).unwrap_or(event_data);
    data["total_debt"] = serde_json::json!(total_debt);
    let updated = serde_json::to_string(&data).map_err(|e| e.to_string())?;
    storage::events_update_event_data(&id, &updated)?;
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
    storage::load_contacts_from_tables(&wallet_id)?
        .into_iter()
        .find(|c| c.id == id)
        .ok_or_else(|| "Contact not found after create".to_string())
}

pub fn get_contacts() -> Result<String, String> {
    let wallet_id = ensure_wallet()?;
    let contacts = storage::load_contacts_from_tables(&wallet_id)?;
    Ok(serde_json::to_string(&contacts).map_err(|e| e.to_string())?)
}

pub fn get_transactions() -> Result<String, String> {
    let wallet_id = ensure_wallet()?;
    let transactions = storage::load_transactions_from_tables(&wallet_id)?;
    Ok(serde_json::to_string(&transactions).map_err(|e| e.to_string())?)
}

pub fn get_contact(id: String) -> Result<Option<String>, String> {
    let _ = ContactId::parse(&id).map_err(|e| e)?;
    let json = get_contacts()?;
    let contacts: Vec<Contact> = serde_json::from_str(&json).map_err(|e| e.to_string())?;
    let c = contacts.into_iter().find(|c| c.id == id);
    Ok(c.map(|c| serde_json::to_string(&c).unwrap()))
}

pub fn get_transaction(id: String) -> Result<Option<String>, String> {
    let _ = TransactionId::parse(&id).map_err(|e| e)?;
    let json = get_transactions()?;
    let transactions: Vec<Transaction> = serde_json::from_str(&json).map_err(|e| e.to_string())?;
    let t = transactions.into_iter().find(|t| t.id == id);
    Ok(t.map(|t| serde_json::to_string(&t).unwrap()))
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
        "type": type_,
        "direction": direction,
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
    storage::load_transactions_from_tables(&wallet_id)?
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
        "type": type_,
        "direction": direction,
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
) -> Result<Option<storage::StoredEvent>, String> {
    let events = storage::events_get_for_aggregate(wallet_id, aggregate_type, aggregate_id)?;
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
        append_event(&wallet_id, &last.aggregate_type, &last.aggregate_id, "UNDO", data)?;
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
    append_event(&wallet_id, &last.aggregate_type, &last.aggregate_id, "UNDO", data)?;
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
    append_event(&wallet_id, &last.aggregate_type, &last.aggregate_id, "UNDO", data)?;
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
    storage::clear_all()?;
    Ok(())
}
