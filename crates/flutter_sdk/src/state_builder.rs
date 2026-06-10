//! Build contacts and transactions from events (ported from frontend state_builder).

use crate::models::{Contact, Currency, Transaction, TransactionDirection, TransactionType};
use chrono::{DateTime, NaiveDate, Utc};
use std::collections::HashMap;

/// Internal event for building state (chrono timestamp).
struct BuildEvent {
    id: String,
    aggregate_type: String,
    aggregate_id: String,
    event_type: String,
    event_data: serde_json::Value,
    timestamp: DateTime<Utc>,
    synced: bool,
}

/// Internal contact/transaction with chrono for calculation; we convert to model with string dates at the end.
#[derive(Clone)]
struct BuildContact {
    id: String,
    name: String,
    username: Option<String>,
    phone: Option<String>,
    email: Option<String>,
    notes: Option<String>,
    created_at: DateTime<Utc>,
    updated_at: DateTime<Utc>,
    is_synced: bool,
    balance: i64,
    wallet_id: Option<String>,
}

#[derive(Clone)]
struct BuildTransaction {
    id: String,
    contact_id: String,
    type_: TransactionType,
    direction: TransactionDirection,
    amount: i64,
    currency: Currency,
    description: Option<String>,
    transaction_date: NaiveDate,
    due_date: Option<NaiveDate>,
    image_paths: Vec<String>,
    created_at: DateTime<Utc>,
    updated_at: DateTime<Utc>,
    is_synced: bool,
    wallet_id: Option<String>,
}

pub fn build_state_from_stored(
    events: &[crate::storage::StoredEvent],
) -> Result<(Vec<Contact>, Vec<Transaction>), String> {
    let build_events: Vec<BuildEvent> = events
        .iter()
        .map(|e| {
            let event_data: serde_json::Value =
                serde_json::from_str(&e.event_data).unwrap_or(serde_json::Value::Null);
            let timestamp = chrono::DateTime::parse_from_rfc3339(&e.timestamp)
                .map(|dt| dt.with_timezone(&Utc))
                .unwrap_or_else(|_| Utc::now());
            BuildEvent {
                id: e.id.clone(),
                aggregate_type: e.aggregate_type.clone(),
                aggregate_id: e.aggregate_id.clone(),
                event_type: e.event_type.clone(),
                event_data,
                timestamp,
                synced: e.synced,
            }
        })
        .collect();

    let mut sorted: Vec<&BuildEvent> = build_events.iter().collect();
    sorted.sort_by(|a, b| a.timestamp.cmp(&b.timestamp));

    let undone_event_ids: std::collections::HashSet<&str> = sorted
        .iter()
        .filter(|e| e.event_type == "UNDO")
        .filter_map(|e| e.event_data.get("undone_event_id").and_then(|v| v.as_str()))
        .collect();

    let mut contacts: HashMap<String, BuildContact> = HashMap::new();
    let mut transactions: HashMap<String, BuildTransaction> = HashMap::new();

    for event in &sorted {
        if event.event_type == "UNDO" {
            continue;
        }
        if undone_event_ids.contains(event.id.as_str()) {
            continue;
        }
        if event.aggregate_type == "contact" {
            apply_contact_event(&mut contacts, event, &mut transactions);
        } else if event.aggregate_type == "transaction" {
            apply_transaction_event(&mut transactions, event, &contacts);
        }
    }

    calculate_balances(&mut contacts, transactions.values().cloned().collect());

    let contacts_out: Vec<Contact> = contacts
        .into_values()
        .map(|c| Contact {
            id: c.id,
            name: c.name,
            username: c.username,
            phone: c.phone,
            email: c.email,
            notes: c.notes,
            created_at: c.created_at.to_rfc3339(),
            updated_at: c.updated_at.to_rfc3339(),
            is_synced: c.is_synced,
            balance: c.balance,
            wallet_id: c.wallet_id,
        })
        .collect();
    let transactions_out: Vec<Transaction> = transactions
        .into_values()
        .map(|t| Transaction {
            id: t.id,
            contact_id: t.contact_id,
            type_: t.type_,
            direction: t.direction,
            amount: t.amount,
            currency: t.currency,
            description: t.description,
            transaction_date: t.transaction_date.format("%Y-%m-%d").to_string(),
            due_date: t.due_date.map(|d| d.format("%Y-%m-%d").to_string()),
            image_paths: t.image_paths,
            created_at: t.created_at.to_rfc3339(),
            updated_at: t.updated_at.to_rfc3339(),
            is_synced: t.is_synced,
            wallet_id: t.wallet_id,
        })
        .collect();
    Ok((contacts_out, transactions_out))
}

fn apply_contact_event(
    contacts: &mut HashMap<String, BuildContact>,
    event: &BuildEvent,
    transactions: &mut HashMap<String, BuildTransaction>,
) {
    let contact_id = event.aggregate_id.clone();
    let data = &event.event_data;

    match event.event_type.as_str() {
        "CREATED" => {
            let ts = parse_ts(data.get("timestamp"));
            contacts.insert(
                contact_id.clone(),
                BuildContact {
                    id: contact_id,
                    name: data.get("name").and_then(|v| v.as_str()).unwrap_or("").to_string(),
                    username: data.get("username").and_then(|v| v.as_str()).map(String::from),
                    phone: data.get("phone").and_then(|v| v.as_str()).map(String::from),
                    email: data.get("email").and_then(|v| v.as_str()).map(String::from),
                    notes: data.get("notes").and_then(|v| v.as_str()).map(String::from),
                    created_at: ts,
                    updated_at: ts,
                    is_synced: event.synced,
                    balance: 0,
                    wallet_id: data.get("wallet_id").and_then(|v| v.as_str()).map(String::from),
                },
            );
        }
        "UPDATED" => {
            if let Some(existing) = contacts.get(&contact_id) {
                let ts = parse_ts(data.get("timestamp"));
                contacts.insert(
                    contact_id.clone(),
                    BuildContact {
                        name: data.get("name").and_then(|v| v.as_str()).unwrap_or(&existing.name).to_string(),
                        username: data.get("username").and_then(|v| v.as_str()).map(String::from).or(existing.username.clone()),
                        phone: data.get("phone").and_then(|v| v.as_str()).map(String::from).or(existing.phone.clone()),
                        email: data.get("email").and_then(|v| v.as_str()).map(String::from).or(existing.email.clone()),
                        notes: data.get("notes").and_then(|v| v.as_str()).map(String::from).or(existing.notes.clone()),
                        updated_at: ts,
                        wallet_id: data.get("wallet_id").and_then(|v| v.as_str()).map(String::from).or(existing.wallet_id.clone()),
                        ..existing.clone()
                    },
                );
            }
        }
        "DELETED" => {
            contacts.remove(&contact_id);
            let to_remove: Vec<String> = transactions
                .values()
                .filter(|t| t.contact_id == contact_id)
                .map(|t| t.id.clone())
                .collect();
            for id in to_remove {
                transactions.remove(&id);
            }
        }
        _ => {}
    }
}

fn apply_transaction_event(
    transactions: &mut HashMap<String, BuildTransaction>,
    event: &BuildEvent,
    contacts: &HashMap<String, BuildContact>,
) {
    let txn_id = event.aggregate_id.clone();
    let data = &event.event_data;

    match event.event_type.as_str() {
        "CREATED" => {
            let contact_id = data.get("contact_id").and_then(|v| v.as_str()).unwrap_or("").to_string();
            if contact_id.is_empty() || !contacts.contains_key(&contact_id) {
                return;
            }
            let type_ = match data.get("type").and_then(|v| v.as_str()).unwrap_or("money") {
                "item" => TransactionType::Item,
                _ => TransactionType::Money,
            };
            let direction = match data.get("direction").and_then(|v| v.as_str()).unwrap_or("owed") {
                "lent" => TransactionDirection::Lent,
                _ => TransactionDirection::Owed,
            };
            let amount = data.get("amount").and_then(|v| v.as_i64()).unwrap_or(0);
            let currency = data
                .get("currency")
                .and_then(|v| v.as_str())
                .and_then(Currency::from_str)
                .unwrap_or(Currency::IQD);
            let transaction_date = parse_date(data.get("transaction_date"))
                .unwrap_or_else(|| Utc::now().date_naive());
            let created_ts = parse_ts(data.get("timestamp"));
            transactions.insert(
                txn_id.clone(),
                BuildTransaction {
                    id: txn_id,
                    contact_id,
                    type_,
                    direction,
                    amount,
                    currency,
                    description: data.get("description").and_then(|v| v.as_str()).map(String::from),
                    transaction_date,
                    due_date: parse_date(data.get("due_date")),
                    image_paths: vec![],
                    created_at: created_ts,
                    updated_at: created_ts,
                    is_synced: event.synced,
                    wallet_id: data.get("wallet_id").and_then(|v| v.as_str()).map(String::from),
                },
            );
        }
        "UPDATED" => {
            if let Some(existing) = transactions.get(&txn_id) {
                let type_ = match data.get("type").and_then(|v| v.as_str()) {
                    Some("item") => TransactionType::Item,
                    Some("money") => TransactionType::Money,
                    _ => existing.type_,
                };
                let direction = match data.get("direction").and_then(|v| v.as_str()) {
                    Some("lent") => TransactionDirection::Lent,
                    Some("owed") => TransactionDirection::Owed,
                    _ => existing.direction,
                };
                let updated_ts = parse_ts(data.get("timestamp"));
                transactions.insert(
                    txn_id.clone(),
                    BuildTransaction {
                        contact_id: data.get("contact_id").and_then(|v| v.as_str()).map(String::from).unwrap_or_else(|| existing.contact_id.clone()),
                        type_,
                        direction,
                        amount: data.get("amount").and_then(|v| v.as_i64()).unwrap_or(existing.amount),
                        currency: data.get("currency").and_then(|v| v.as_str()).and_then(Currency::from_str).unwrap_or(existing.currency),
                        description: data.get("description").and_then(|v| v.as_str()).map(String::from).or(existing.description.clone()),
                        transaction_date: parse_date(data.get("transaction_date")).unwrap_or(existing.transaction_date),
                        due_date: parse_date(data.get("due_date")).or(existing.due_date),
                        updated_at: updated_ts,
                        is_synced: event.synced,
                        wallet_id: data.get("wallet_id").and_then(|v| v.as_str()).map(String::from).or(existing.wallet_id.clone()),
                        id: existing.id.clone(),
                        created_at: existing.created_at,
                        image_paths: existing.image_paths.clone(),
                    },
                );
            }
        }
        "DELETED" => {
            transactions.remove(&txn_id);
        }
        _ => {}
    }
}

fn calculate_balances(contacts: &mut HashMap<String, BuildContact>, transactions: Vec<BuildTransaction>) {
    for c in contacts.values_mut() {
        c.balance = 0;
    }
    for t in transactions {
        if let Some(c) = contacts.get_mut(&t.contact_id) {
            let amount = match t.direction {
                TransactionDirection::Lent => t.amount,
                TransactionDirection::Owed => -t.amount,
            };
            c.balance += amount;
        }
    }
}

fn parse_ts(v: Option<&serde_json::Value>) -> DateTime<Utc> {
    let s = match v {
        Some(serde_json::Value::String(s)) => s.as_str(),
        _ => return Utc::now(),
    };
    chrono::DateTime::parse_from_rfc3339(s)
        .map(|dt| dt.with_timezone(&Utc))
        .unwrap_or_else(|_| Utc::now())
}

fn parse_date(v: Option<&serde_json::Value>) -> Option<chrono::NaiveDate> {
    let s = match v {
        Some(serde_json::Value::String(s)) => s.as_str(),
        _ => return None,
    };
    let s = if s.contains('T') || s.contains(' ') {
        s.to_string()
    } else {
        format!("{}T00:00:00", s)
    };
    chrono::NaiveDateTime::parse_from_str(&s, "%Y-%m-%dT%H:%M:%S")
        .ok()
        .map(|dt| dt.date())
        .or_else(|| chrono::NaiveDate::parse_from_str(s.trim_matches(|c| c == 'T' || c == ' '), "%Y-%m-%d").ok())
}
