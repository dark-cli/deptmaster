//! Pure state rebuild from events - ported from Flutter StateBuilder.
//! No side effects, easy to test.

use crate::models::{Contact, Event, Transaction, TransactionDirection, TransactionType};
use chrono::{DateTime, Utc};
use std::collections::HashMap;

/// Application state: contacts and transactions built from events.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct AppState {
    pub contacts: Vec<Contact>,
    pub transactions: Vec<Transaction>,
    pub last_built_at: DateTime<Utc>,
}

/// Build full state from all events (sorted by timestamp).
pub fn build_state(events: &[Event]) -> AppState {
    let mut sorted: Vec<&Event> = events.iter().collect();
    sorted.sort_by(|a, b| a.timestamp.cmp(&b.timestamp));

    let undone_event_ids: std::collections::HashSet<_> = sorted
        .iter()
        .filter(|e| e.event_type == "UNDO")
        .filter_map(|e| e.event_data.get("undone_event_id").and_then(|v| v.as_str()))
        .collect();

    let mut contacts: HashMap<String, Contact> = HashMap::new();
    let mut transactions: HashMap<String, Transaction> = HashMap::new();

    for event in sorted {
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

    AppState {
        contacts: contacts.into_values().collect(),
        transactions: transactions.into_values().collect(),
        last_built_at: Utc::now(),
    }
}

/// Apply new events to existing state (incremental update).
pub fn apply_events(current: &AppState, new_events: &[Event]) -> AppState {
    if new_events.is_empty() {
        return current.clone();
    }

    let mut sorted: Vec<&Event> = new_events.iter().collect();
    sorted.sort_by(|a, b| a.timestamp.cmp(&b.timestamp));

    let undone_event_ids: std::collections::HashSet<_> = sorted
        .iter()
        .filter(|e| e.event_type == "UNDO")
        .filter_map(|e| e.event_data.get("undone_event_id").and_then(|v| v.as_str()))
        .collect();

    let mut contacts: HashMap<String, Contact> = current
        .contacts
        .iter()
        .map(|c| (c.id.clone(), c.clone()))
        .collect();
    let mut transactions: HashMap<String, Transaction> = current
        .transactions
        .iter()
        .map(|t| (t.id.clone(), t.clone()))
        .collect();

    for event in sorted {
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

    AppState {
        contacts: contacts.into_values().collect(),
        transactions: transactions.into_values().collect(),
        last_built_at: Utc::now(),
    }
}

fn apply_contact_event(
    contacts: &mut HashMap<String, Contact>,
    event: &Event,
    transactions: &mut HashMap<String, Transaction>,
) {
    let contact_id = event.aggregate_id.clone();
    let data = &event.event_data;

    if event.event_type == "CREATED" {
        let ts = parse_timestamp(data.get("timestamp"));
        contacts.insert(
            contact_id.clone(),
            Contact {
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
    } else if event.event_type == "UPDATED" {
        if let Some(existing) = contacts.get(&contact_id) {
            let ts = parse_timestamp(data.get("timestamp"));
            contacts.insert(
                contact_id.clone(),
                Contact {
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
    } else if event.event_type == "DELETED" {
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
}

fn apply_transaction_event(
    transactions: &mut HashMap<String, Transaction>,
    event: &Event,
    contacts: &HashMap<String, Contact>,
) {
    let txn_id = event.aggregate_id.clone();
    let data = &event.event_data;

    if event.event_type == "CREATED" {
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
        let currency = data.get("currency").and_then(|v| v.as_str()).unwrap_or("IQD").to_string();
        let transaction_date = parse_date(data.get("transaction_date")).unwrap_or_else(|| chrono::Utc::now().date_naive());
        let created_ts = parse_timestamp(data.get("timestamp"));

        transactions.insert(
            txn_id.clone(),
            Transaction {
                id: txn_id,
                contact_id: contact_id.clone(),
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
    } else if event.event_type == "UPDATED" {
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
            let updated_ts = parse_timestamp(data.get("timestamp"));

            transactions.insert(
                txn_id.clone(),
                Transaction {
                    contact_id: data.get("contact_id").and_then(|v| v.as_str()).map(String::from).unwrap_or_else(|| existing.contact_id.clone()),
                    type_,
                    direction,
                    amount: data.get("amount").and_then(|v| v.as_i64()).unwrap_or(existing.amount),
                    currency: data.get("currency").and_then(|v| v.as_str()).map(String::from).unwrap_or_else(|| existing.currency.clone()),
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
    } else if event.event_type == "DELETED" {
        transactions.remove(&txn_id);
    }
}

fn calculate_balances(contacts: &mut HashMap<String, Contact>, transactions: Vec<Transaction>) {
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

fn parse_timestamp(v: Option<&serde_json::Value>) -> DateTime<Utc> {
    let s = match v {
        Some(serde_json::Value::String(s)) => s,
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
