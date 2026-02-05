//! CRUD: append events, rebuild projection, trigger sync.
//! Uses typed IDs (WalletId, ContactId, TransactionId) for validation; dates as chrono types internally.

use crate::ids::{ContactId, TransactionId, WalletId};
use crate::rust_log;
use crate::models::{Contact, Currency, Transaction};
use crate::state_builder;
use crate::storage;
use crate::sync;
use chrono::NaiveDate;
use uuid::Uuid;

fn ensure_wallet() -> Result<String, String> {
    let s = storage::config_get("current_wallet_id")?
        .ok_or_else(|| "No wallet selected".to_string())?;
    WalletId::parse(&s).map(|w| w.as_str().to_string())
}

fn rebuild_and_save(wallet_id: &str) -> Result<(), String> {
    let events = storage::events_get_all(wallet_id)?;
    let (contacts, transactions) = state_builder::build_state_from_stored(&events)?;
    storage::state_save(wallet_id, &contacts, &transactions)?;
    sync::push_unsynced()?;
    Ok(())
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
    rebuild_and_save(wallet_id)?;
    // Add total_debt to event_data so the chart can display this event (matches server behavior)
    if let Some((contacts, _)) = storage::state_load(wallet_id)? {
        let total_debt: i64 = contacts.iter().map(|c| c.balance).sum();
        let mut data = serde_json::from_str::<serde_json::Value>(&event_data_str).unwrap_or(event_data);
        data["total_debt"] = serde_json::json!(total_debt);
        let updated = serde_json::to_string(&data).map_err(|e| e.to_string())?;
        storage::events_update_event_data(&id, &updated)?;
    }
    Ok(())
}

pub fn create_contact(
    name: String,
    username: Option<String>,
    phone: Option<String>,
    email: Option<String>,
    notes: Option<String>,
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
    append_event(&wallet_id, "contact", &id, "CREATED", data)?;
    let events = storage::events_get_all(&wallet_id)?;
    let (contacts, _) = state_builder::build_state_from_stored(&events)?;
    contacts
        .into_iter()
        .find(|c| c.id == id)
        .ok_or_else(|| "Contact not found after create".to_string())
}

pub fn get_contacts() -> Result<String, String> {
    let wallet_id = ensure_wallet()?;
    if let Some((contacts, _)) = storage::state_load(&wallet_id)? {
        return Ok(serde_json::to_string(&contacts).map_err(|e| e.to_string())?);
    }
    let events = storage::events_get_all(&wallet_id)?;
    let (contacts, _) = state_builder::build_state_from_stored(&events)?;
    storage::state_save(&wallet_id, &contacts, &[])?;
    Ok(serde_json::to_string(&contacts).map_err(|e| e.to_string())?)
}

pub fn get_transactions() -> Result<String, String> {
    let wallet_id = ensure_wallet()?;
    if let Some((_, transactions)) = storage::state_load(&wallet_id)? {
        return Ok(serde_json::to_string(&transactions).map_err(|e| e.to_string())?);
    }
    let events = storage::events_get_all(&wallet_id)?;
    let (_, transactions) = state_builder::build_state_from_stored(&events)?;
    storage::state_save(&wallet_id, &[], &transactions)?;
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
    let events = storage::events_get_all(&wallet_id)?;
    let (_, transactions) = state_builder::build_state_from_stored(&events)?;
    transactions
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
    storage::config_remove("token")?;
    storage::config_remove("user_id")?;
    storage::config_remove("current_wallet_id")?;
    storage::config_remove("last_sync_timestamp")?;
    Ok(())
}
