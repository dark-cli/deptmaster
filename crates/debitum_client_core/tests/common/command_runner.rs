//! Run text commands against the client API (same style as server event_generator).
//! Commands: contact create "Name" [label], contact update label field "value", contact delete label,
//!   transaction create contactLabel direction amount ["description"] [label],
//!   transaction update transLabel field value, transaction delete transLabel, sync, wait [ms]
//! Empty lines and # comments are skipped.
//!
//! Full vocabulary: see project docs at `docs/INTEGRATION_TEST_COMMANDS.md`.

use debitum_client_core::{
    create_contact, create_transaction, delete_contact, delete_transaction,
    get_transaction, manual_sync, update_contact, update_transaction,
};
use std::collections::HashMap;

fn parse_args(input: &str) -> Vec<String> {
    let mut args = Vec::new();
    let mut buf = String::new();
    let mut in_quotes = false;
    for c in input.chars() {
        if c == '"' {
            in_quotes = !in_quotes;
        } else if c == ' ' && !in_quotes {
            if !buf.is_empty() {
                args.push(std::mem::take(&mut buf));
            }
        } else {
            buf.push(c);
        }
    }
    if !buf.is_empty() {
        args.push(buf);
    }
    args
}

fn unquote(s: &str) -> &str {
    let s = s.trim();
    if s.len() >= 2 && s.starts_with('"') && s.ends_with('"') {
        &s[1..s.len() - 1]
    } else {
        s
    }
}

/// Tracks label -> id for contacts and transactions; runs commands via client API.
pub struct CommandRunner {
    pub contact_ids: HashMap<String, String>,
    pub transaction_ids: HashMap<String, String>,
}

impl CommandRunner {
    pub fn new() -> Self {
        Self {
            contact_ids: HashMap::new(),
            transaction_ids: HashMap::new(),
        }
    }

    pub fn execute_command(&mut self, command: &str) -> Result<(), String> {
        let parts: Vec<&str> = command.splitn(2, ':').collect();
        let action_part = if parts.len() == 2 {
            parts[1].trim()
        } else {
            command.trim()
        };
        let args = parse_args(action_part);
        if args.is_empty() {
            return Err("Empty command".to_string());
        }
        let action = args[0].to_lowercase();
        let args: Vec<&str> = args.iter().map(String::as_str).collect();

        if action == "sync" {
            manual_sync()?;
            return Ok(());
        }
        if action == "wait" {
            let ms = args.get(1).and_then(|s| s.parse::<u64>().ok()).unwrap_or(100);
            std::thread::sleep(std::time::Duration::from_millis(ms));
            return Ok(());
        }
        if action == "contact" {
            self.do_contact(&args[1..], command)?;
            return Ok(());
        }
        if action == "transaction" {
            self.do_transaction(&args[1..], command)?;
            return Ok(());
        }
        Err(format!("Unknown action: {}", action))
    }

    fn do_contact(&mut self, args: &[&str], original: &str) -> Result<(), String> {
        if args.is_empty() {
            return Err(format!("Contact command requires action: {}", original));
        }
        let sub = args[0].to_lowercase();
        match sub.as_str() {
            "create" => {
                if args.len() < 2 {
                    return Err(format!("Contact create requires name: {}", original));
                }
                let name = unquote(args[1]).to_string();
                let label = args
                    .get(2)
                    .map(|s| unquote(s).to_lowercase().replace(' ', "_"))
                    .filter(|s| !s.is_empty())
                    .unwrap_or_else(|| name.to_lowercase().replace(' ', "_"));
                let json = create_contact(name, None, None, None, None, None)?;
                let c: serde_json::Value = serde_json::from_str(&json).map_err(|e| e.to_string())?;
                let id = c["id"].as_str().ok_or("No id in contact response")?.to_string();
                self.contact_ids.insert(label, id);
            }
            "update" => {
                if args.len() < 4 {
                    return Err(format!("Contact update requires label field value: {}", original));
                }
                let contact_id = self
                    .contact_ids
                    .get(args[1])
                    .cloned()
                    .ok_or_else(|| format!("Contact label not found: {}", args[1]))?;
                let field = args[2].to_lowercase();
                let value = unquote(args[3]).to_string();
                let (name, username, phone, email, notes) = match field.as_str() {
                    "name" => (Some(value), None, None, None, None),
                    "phone" => (None, None, Some(value), None, None),
                    "email" => (None, None, None, Some(value), None),
                    "notes" => (None, None, None, None, Some(value)),
                    _ => return Err(format!("Unknown contact field: {}", field)),
                };
                update_contact(
                    contact_id,
                    name.unwrap_or_default(),
                    username,
                    phone,
                    email,
                    notes,
                )?;
            }
            "delete" => {
                if args.len() < 2 {
                    return Err(format!("Contact delete requires label: {}", original));
                }
                let contact_id = self
                    .contact_ids
                    .get(args[1])
                    .cloned()
                    .ok_or_else(|| format!("Contact label not found: {}", args[1]))?;
                delete_contact(contact_id)?;
            }
            _ => return Err(format!("Unknown contact action: {}", sub)),
        }
        Ok(())
    }

    fn do_transaction(&mut self, args: &[&str], original: &str) -> Result<(), String> {
        if args.is_empty() {
            return Err(format!("Transaction command requires action: {}", original));
        }
        let sub = args[0].to_lowercase();
        let today = chrono::Utc::now().format("%Y-%m-%d").to_string();
        let currency = "IQD".to_string();
        let type_ = "money".to_string();

        match sub.as_str() {
            "create" => {
                if args.len() < 4 {
                    return Err(format!(
                        "Transaction create requires contactLabel direction amount: {}",
                        original
                    ));
                }
                let contact_id = self
                    .contact_ids
                    .get(args[1])
                    .cloned()
                    .ok_or_else(|| format!("Contact label not found: {}", args[1]))?;
                let direction = args[2].to_lowercase();
                let amount: i64 = args[3].parse().map_err(|_| "Invalid amount")?;
                let description = args.get(4).map(|s| unquote(s).to_string());
                let label = args
                    .get(5)
                    .map(|s| unquote(s).to_lowercase().replace(' ', "_"))
                    .filter(|s| !s.is_empty())
                    .unwrap_or_else(|| format!("t{}", self.transaction_ids.len()));
                let json = create_transaction(
                    contact_id,
                    type_,
                    direction,
                    amount,
                    currency.clone(),
                    description,
                    today,
                    None,
                )?;
                let t: serde_json::Value = serde_json::from_str(&json).map_err(|e| e.to_string())?;
                let id = t["id"].as_str().ok_or("No id in transaction response")?.to_string();
                self.transaction_ids.insert(label, id);
            }
            "update" => {
                if args.len() < 4 {
                    return Err(format!(
                        "Transaction update requires transLabel field value: {}",
                        original
                    ));
                }
                let trans_id = self
                    .transaction_ids
                    .get(args[1])
                    .cloned()
                    .ok_or_else(|| format!("Transaction label not found: {}", args[1]))?;
                let field = args[2].to_lowercase();
                let value = args[3];
                let tx_json = get_transaction(trans_id.clone())?
                    .ok_or_else(|| "Transaction not found".to_string())?;
                let tx: serde_json::Value = serde_json::from_str(&tx_json).map_err(|e| e.to_string())?;
                let contact_id = tx["contact_id"].as_str().ok_or("No contact_id")?.to_string();
                let type_s = tx["type"].as_str().unwrap_or("money").to_string();
                let direction = tx["direction"].as_str().unwrap_or("owed").to_string();
                let mut amount = tx["amount"].as_i64().unwrap_or(0);
                let mut description = tx["description"].as_str().map(String::from);
                let transaction_date = tx["transaction_date"]
                    .as_str()
                    .unwrap_or(&today)
                    .to_string();
                let due_date = tx["due_date"].as_str().map(String::from);
                match field.as_str() {
                    "amount" => amount = value.parse().map_err(|_| "Invalid amount")?,
                    "description" => description = Some(unquote(value).to_string()),
                    _ => return Err(format!("Unknown transaction field: {}", field)),
                }
                update_transaction(
                    trans_id,
                    contact_id,
                    type_s,
                    direction,
                    amount,
                    currency.clone(),
                    description,
                    transaction_date,
                    due_date,
                )?;
            }
            "delete" => {
                if args.len() < 2 {
                    return Err(format!("Transaction delete requires label: {}", original));
                }
                let trans_id = self
                    .transaction_ids
                    .get(args[1])
                    .cloned()
                    .ok_or_else(|| format!("Transaction label not found: {}", args[1]))?;
                delete_transaction(trans_id)?;
            }
            _ => return Err(format!("Unknown transaction action: {}", sub)),
        }
        Ok(())
    }
}

impl Default for CommandRunner {
    fn default() -> Self {
        Self::new()
    }
}
