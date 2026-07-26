//! Run text commands against the client API (same style as server event_generator).
//! Commands: contact create "Name" [label], contact update label field "value", contact delete label,
//!   transaction create contactLabel direction amount ["description"] [label],
//!   transaction update transLabel field value, transaction delete transLabel, sync, wait [ms]
//! Permission format (compact & readable):
//!   user-group create "Name" label
//!   contact-group create "Name" label
//!   group-member add user_group_var user_id
//!   group-member add contact_group_var contact_id
//!   permission set user_group contact_group "C: a a a -, T: a a - - -"
//!     where: C/T = Contact/Transaction, a = allow, d = deny, - = unset
//! Empty lines and # comments are skipped.
//!
//! Full vocabulary: see project docs at `docs/INTEGRATION_TEST_COMMANDS.md`.

use client::{
    create_contact, create_transaction, delete_contact, delete_transaction, get_transaction,
    get_contacts, get_transactions,
    list_wallet_contact_groups, list_wallet_user_groups, manual_sync, put_wallet_permission_matrix,
    update_contact, update_transaction, create_wallet_user_group, create_wallet_contact_group,
    add_wallet_user_group_member, add_wallet_contact_group_member, set_wallet_permissions,
    set_member_permissions,
};
use std::collections::HashMap;

fn parse_args(input: &str) -> Vec<String> {
    let mut args = Vec::new();
    let mut buf = String::new();
    // Tracks the active opening quote char, if any. Tests mix `"..."` and `'...'`
    // so we support both — but only honour the matching closer (e.g. a `'` inside
    // `"..."` is a literal apostrophe, not a closer).
    let mut quote: Option<char> = None;
    for c in input.chars() {
        match (quote, c) {
            (Some(opener), ch) if ch == opener => quote = None,
            (None, '"') | (None, '\'') => quote = Some(c),
            (None, ' ') => {
                if !buf.is_empty() {
                    args.push(std::mem::take(&mut buf));
                }
            }
            _ => buf.push(c),
        }
    }
    if !buf.is_empty() {
        args.push(buf);
    }
    args
}

/// Locate a group id by its `name` field inside a JSON list returned from
/// list_wallet_user_groups / list_wallet_contact_groups (either a bare array
/// or `{groups: [...]}`).
fn find_group_id(json: &str, name: &str) -> Result<String, String> {
    let v: serde_json::Value = serde_json::from_str(json).map_err(|e| e.to_string())?;
    let arr = v
        .get("groups")
        .and_then(|g| g.as_array())
        .cloned()
        .or_else(|| v.as_array().cloned())
        .ok_or_else(|| "Response is neither {groups:[...]} nor an array".to_string())?;
    arr.iter()
        .find(|g| g.get("name").and_then(|n| n.as_str()) == Some(name))
        .and_then(|g| g.get("id").and_then(|i| i.as_str()).map(String::from))
        .ok_or_else(|| format!("Group '{}' not found in response", name))
}

fn unquote(s: &str) -> &str {
    let s = s.trim();
    if s.len() >= 2
        && ((s.starts_with('"') && s.ends_with('"')) || (s.starts_with('\'') && s.ends_with('\'')))
    {
        &s[1..s.len() - 1]
    } else {
        s
    }
}

/// Tracks label -> id for contacts, transactions, user groups, and contact groups; runs commands via client API.
pub struct CommandRunner {
    pub contact_ids: HashMap<String, String>,
    pub transaction_ids: HashMap<String, String>,
    pub user_group_ids: HashMap<String, String>,
    pub contact_group_ids: HashMap<String, String>,
    pub user_ids: HashMap<String, String>,  // app_name -> user_id for resolving user labels
    pub usernames: HashMap<String, String>,  // app_name -> username for API calls
}

impl CommandRunner {
    pub fn new() -> Self {
        Self {
            contact_ids: HashMap::new(),
            transaction_ids: HashMap::new(),
            user_group_ids: HashMap::new(),
            contact_group_ids: HashMap::new(),
            user_ids: HashMap::new(),
            usernames: HashMap::new(),
        }
    }

    /// Set user IDs mapping (called by EventGenerator with app_name -> user_id)
    pub fn set_user_ids(&mut self, user_ids: HashMap<String, String>) {
        self.user_ids = user_ids;
    }

    /// Set usernames mapping (called by EventGenerator with app_name -> username for API calls)
    pub fn set_usernames(&mut self, usernames: HashMap<String, String>) {
        self.usernames = usernames;
    }

    pub fn execute_command(&mut self, command: &str) -> Result<(), String> {
        // Note: EventGenerator has already extracted the action part (removed "app:" prefix),
        // so we should NOT try to split on colons again. The command is already cleaned.
        let action_part = command.trim();
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
            let ms = args
                .get(1)
                .and_then(|s| s.parse::<u64>().ok())
                .unwrap_or(100);
            std::thread::sleep(std::time::Duration::from_millis(ms));
            return Ok(());
        }
        if action == "assert" {
            self.do_assert(&args[1..], command)?;
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
        if action == "permission" {
            self.do_permission(&args[1..], command)?;
            return Ok(());
        }
        if action == "user-group" {
            self.do_user_group(&args[1..], command)?;
            return Ok(());
        }
        if action == "contact-group" {
            self.do_contact_group(&args[1..], command)?;
            return Ok(());
        }
        if action == "group-member" {
            self.do_group_member(&args[1..], command)?;
            return Ok(());
        }
        if action == "wallet-permission" {
            self.do_wallet_permission(&args[1..], command)?;
            return Ok(());
        }
        if action == "member-permission" {
            self.do_member_permission(&args[1..], command)?;
            return Ok(());
        }
        Err(format!("Unknown action: {}", action))
    }

    /// `permission grant-full` / `permission grant-read` / `permission revoke-all` / `permission set user_group contact_group "C: a a a -, T: a a - - -"`
    ///
    /// First three operate on the all_users user group × all_contacts contact group pair
    /// (the wallet's default "everyone gets these permissions on every contact" axis).
    /// The "set" command uses readable format for custom groups.
    fn do_permission(&mut self, args: &[&str], original: &str) -> Result<(), String> {
        if args.is_empty() {
            return Err(format!("Permission command requires action: {}", original));
        }

        let action = args[0].to_lowercase();
        match action.as_str() {
            "set" => {
                if args.len() < 4 {
                    return Err(format!("Permission set requires user_group contact_group format: {}", original));
                }
                let user_group_label = args[1];
                let contact_group_label = args[2];
                let format_str = unquote(args[3]);
                self.set_permissions_format(user_group_label, contact_group_label, format_str)?;
            }
            "grant-full" | "grant-read" | "revoke-all" => {
                let wallet_id = client::get_current_wallet_id()?;
                let ug_all_users =
                    find_group_id(&list_wallet_user_groups(wallet_id.clone())?, "all_users")?;
                let cg_all_contacts = find_group_id(
                    &list_wallet_contact_groups(wallet_id.clone())?,
                    "all_contacts",
                )?;
                let (allowed, denied): (Vec<&str>, Vec<&str>) = match action.as_str() {
                    "grant-full" => (
                        vec![
                            "contact:create",
                            "contact:read",
                            "contact:update",
                            "contact:delete",
                            "transaction:create",
                            "transaction:read",
                            "transaction:update",
                            "transaction:delete",
                        ],
                        vec![],
                    ),
                    "grant-read" => (vec!["contact:read", "transaction:read"], vec![]),
                    "revoke-all" => (vec![], vec![]),
                    _ => return Err("Unreachable".to_string()),
                };
                let entry = serde_json::json!({
                    "user_group_id": ug_all_users,
                    "contact_group_id": cg_all_contacts,
                    "allowed_actions": allowed,
                    "denied_actions": denied,
                });
                let entries = serde_json::json!([entry]);
                put_wallet_permission_matrix(wallet_id, entries.to_string())?;
            }
            other => return Err(format!("Unknown permission subcommand: {}", other)),
        }
        Ok(())
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
                let c: serde_json::Value =
                    serde_json::from_str(&json).map_err(|e| e.to_string())?;
                let id = c["id"]
                    .as_str()
                    .ok_or("No id in contact response")?
                    .to_string();
                self.contact_ids.insert(label, id);
            }
            "update" => {
                if args.len() < 4 {
                    return Err(format!(
                        "Contact update requires label field value: {}",
                        original
                    ));
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
                    None, // group_ids: command runner doesn't drive group membership
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
                let t: serde_json::Value =
                    serde_json::from_str(&json).map_err(|e| e.to_string())?;
                let id = t["id"]
                    .as_str()
                    .ok_or("No id in transaction response")?
                    .to_string();
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
                let tx_json = get_transaction(trans_id.clone())?;
                let tx: serde_json::Value =
                    serde_json::from_str(&tx_json).map_err(|e| e.to_string())?;
                let contact_id = tx["contact_id"]
                    .as_str()
                    .ok_or("No contact_id")?
                    .to_string();
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

    fn do_user_group(&mut self, args: &[&str], original: &str) -> Result<(), String> {
        if args.is_empty() {
            return Err(format!("User-group command requires action: {}", original));
        }
        let sub = args[0].to_lowercase();
        match sub.as_str() {
            "create" => {
                if args.len() < 2 {
                    return Err(format!("User-group create requires name: {}", original));
                }
                let name = unquote(args[1]).to_string();
                let label = args
                    .get(2)
                    .map(|s| unquote(s).to_lowercase().replace(' ', "_"))
                    .filter(|s| !s.is_empty())
                    .unwrap_or_else(|| name.to_lowercase().replace(' ', "_"));
                let wallet_id = client::get_current_wallet_id()?;
                let json = create_wallet_user_group(wallet_id, name)?;
                let g: serde_json::Value =
                    serde_json::from_str(&json).map_err(|e| e.to_string())?;
                let id = g["id"]
                    .as_str()
                    .ok_or("No id in user_group response")?
                    .to_string();
                self.user_group_ids.insert(label, id);
            }
            _ => return Err(format!("Unknown user-group action: {}", sub)),
        }
        Ok(())
    }

    fn do_contact_group(&mut self, args: &[&str], original: &str) -> Result<(), String> {
        if args.is_empty() {
            return Err(format!("Contact-group command requires action: {}", original));
        }
        let sub = args[0].to_lowercase();
        match sub.as_str() {
            "create" => {
                if args.len() < 2 {
                    return Err(format!("Contact-group create requires name: {}", original));
                }
                let name = unquote(args[1]).to_string();
                let label = args
                    .get(2)
                    .map(|s| unquote(s).to_lowercase().replace(' ', "_"))
                    .filter(|s| !s.is_empty())
                    .unwrap_or_else(|| name.to_lowercase().replace(' ', "_"));
                let wallet_id = client::get_current_wallet_id()?;
                let json = create_wallet_contact_group(wallet_id, name)?;
                let g: serde_json::Value =
                    serde_json::from_str(&json).map_err(|e| e.to_string())?;
                let id = g["id"]
                    .as_str()
                    .ok_or("No id in contact_group response")?
                    .to_string();
                self.contact_group_ids.insert(label, id);
            }
            _ => return Err(format!("Unknown contact-group action: {}", sub)),
        }
        Ok(())
    }

    fn do_group_member(&mut self, args: &[&str], original: &str) -> Result<(), String> {
        if args.len() < 3 {
            return Err(format!("Group-member requires: add user_group_var user_id or add contact_group_var contact_id: {}", original));
        }
        let action = args[0].to_lowercase();
        if action != "add" {
            return Err(format!("Unknown group-member action: {}", action));
        }
        let group_label = args[1];
        let id = args[2];
        let wallet_id = client::get_current_wallet_id()?;

        // Try to find in user groups first (these take usernames)
        if let Some(group_id) = self.user_group_ids.get(group_label).cloned() {
            // Resolve to username if it's a known user label
            let resolved_username = self.usernames
                .get(id)
                .cloned()
                .unwrap_or_else(|| id.to_string());
            add_wallet_user_group_member(wallet_id, group_id, resolved_username)?;
            return Ok(());
        }

        // Try contact groups (these take contact IDs)
        if let Some(group_id) = self.contact_group_ids.get(group_label).cloned() {
            // Resolve to contact ID if it's a known contact label
            let resolved_id = self.contact_ids
                .get(id)
                .cloned()
                .unwrap_or_else(|| id.to_string());
            add_wallet_contact_group_member(wallet_id, group_id, resolved_id)?;
            return Ok(());
        }

        Err(format!("Group label not found: {}", group_label))
    }

    /// Parse readable permission format with rwx-inspired naming
    /// Supports: "C: r:a c:a w:a d:-, T: r:a c:d w:a d:- x:-"
    /// Where: r=read, c=create, w=write/update, d=delete, x=close
    /// State: a=allow, d=deny, -=unset
    /// Returns tuple of (contact_allow, contact_deny, transaction_allow, transaction_deny)
    fn parse_permission_format(format_str: &str) -> Result<(Vec<String>, Vec<String>, Vec<String>, Vec<String>), String> {
        let mut contact_allow = Vec::new();
        let mut contact_deny = Vec::new();
        let mut transaction_allow = Vec::new();
        let mut transaction_deny = Vec::new();

        for part in format_str.split(',') {
            let part = part.trim();
            if part.is_empty() {
                continue;
            }

            if let Some(rest) = part.strip_prefix("C:") {
                let (allow, deny) = Self::parse_permission_part(rest, "contact")?;
                contact_allow = allow;
                contact_deny = deny;
            } else if let Some(rest) = part.strip_prefix("T:") {
                let (allow, deny) = Self::parse_permission_part(rest, "transaction")?;
                transaction_allow = allow;
                transaction_deny = deny;
            }
        }

        Ok((contact_allow, contact_deny, transaction_allow, transaction_deny))
    }

    /// Parse individual permission section like "r:a c:a w:a d:-"
    /// Maps: r=read, c=create, w=write/update, d=delete, x=close (transaction only)
    /// State: a=allow, d=deny, -=unset
    /// Returns tuple of (allow_actions, deny_actions)
    fn parse_permission_part(part: &str, resource: &str) -> Result<(Vec<String>, Vec<String>), String> {
        let mut allow_result = Vec::new();
        let mut deny_result = Vec::new();

        // Parse "r:a c:a w:a d:-" format
        for item in part.split_whitespace() {
            let item = item.trim();
            if item.is_empty() {
                continue;
            }

            let parts: Vec<&str> = item.split(':').collect();
            if parts.len() != 2 {
                continue;
            }

            let permission_letter = parts[0];
            let state = parts[1];

            if state == "-" {
                continue; // Unset, skip
            }

            let perm = match permission_letter {
                "r" => format!("{}:read", resource),
                "c" => format!("{}:create", resource),
                "w" => format!("{}:update", resource),
                "d" => format!("{}:delete", resource),
                "x" => format!("{}:close", resource),
                other => return Err(format!("Unknown permission letter: {}", other)),
            };

            match state {
                "a" => allow_result.push(perm),
                "d" => deny_result.push(perm),
                _ => return Err(format!("Unknown permission state: {}", state)),
            }
        }

        Ok((allow_result, deny_result))
    }

    /// Set permissions using readable format: "C: r:a c:a w:a d:-, T: r:a c:- w:- d:- x:-"
    fn set_permissions_format(&self, user_group_label: &str, contact_group_label: &str, format_str: &str) -> Result<(), String> {
        let user_group_id = self.user_group_ids.get(user_group_label)
            .cloned()
            .ok_or_else(|| format!("User group not found: {}", user_group_label))?;
        let contact_group_id = self.contact_group_ids.get(contact_group_label)
            .cloned()
            .ok_or_else(|| format!("Contact group not found: {}", contact_group_label))?;

        let (contact_allow, contact_deny, transaction_allow, transaction_deny)
            = Self::parse_permission_format(format_str)?;

        // Merge contact and transaction actions
        let mut all_allow_actions = contact_allow;
        all_allow_actions.extend(transaction_allow);
        let mut all_deny_actions = contact_deny;
        all_deny_actions.extend(transaction_deny);

        let entry = serde_json::json!({
            "user_group_id": user_group_id,
            "contact_group_id": contact_group_id,
            "allowed_actions": all_allow_actions,
            "denied_actions": all_deny_actions
        });
        let entries = serde_json::json!([entry]);
        let wallet_id = client::get_current_wallet_id()?;
        put_wallet_permission_matrix(wallet_id, entries.to_string())
    }

    /// `wallet-permission grant user_group action` / `wallet-permission revoke user_group action`
    /// Grant or revoke a wallet-level action for a user group
    fn do_wallet_permission(&self, args: &[&str], original: &str) -> Result<(), String> {
        if args.len() < 3 {
            return Err(format!(
                "Wallet-permission requires: grant|revoke user_group action: {}",
                original
            ));
        }

        let subcommand = args[0].to_lowercase();
        let user_group_label = args[1];
        let action = args[2];
        let wallet_id = client::get_current_wallet_id()?;

        let user_group_id = self
            .user_group_ids
            .get(user_group_label)
            .cloned()
            .ok_or_else(|| format!("User group not found: {}", user_group_label))?;

        let is_deny = match subcommand.as_str() {
            "grant" => false,
            "revoke" => true,
            other => return Err(format!("Unknown wallet-permission subcommand: {}", other)),
        };

        let entry = serde_json::json!({
            "user_group_id": user_group_id,
            "action": action,
            "is_deny": is_deny
        });
        let entries = serde_json::json!([entry]);
        set_wallet_permissions(wallet_id, entries.to_string())
    }

    fn do_member_permission(&self, args: &[&str], original: &str) -> Result<(), String> {
        if args.len() < 4 {
            return Err(format!(
                "Member-permission requires: grant|revoke source_group target_group action: {}",
                original
            ));
        }

        let subcommand = args[0].to_lowercase();
        let source_group_label = args[1];
        let target_group_label = args[2];
        let action = args[3];
        let wallet_id = client::get_current_wallet_id()?;

        let source_group_id = self
            .user_group_ids
            .get(source_group_label)
            .cloned()
            .ok_or_else(|| format!("Source user group not found: {}", source_group_label))?;

        let target_group_id = self
            .user_group_ids
            .get(target_group_label)
            .cloned()
            .ok_or_else(|| format!("Target user group not found: {}", target_group_label))?;

        let is_deny = match subcommand.as_str() {
            "grant" => false,
            "revoke" => true,
            other => return Err(format!("Unknown member-permission subcommand: {}", other)),
        };

        let entry = serde_json::json!({
            "source_group_id": source_group_id,
            "target_group_id": target_group_id,
            "action": action,
            "is_deny": is_deny
        });
        let entries = serde_json::json!([entry]);
        set_member_permissions(wallet_id, entries.to_string())
    }

    fn do_assert(&self, args: &[&str], original: &str) -> Result<(), String> {
        if args.is_empty() {
            return Err(format!("Assert requires a command: {}", original));
        }

        // Get current state
        let contacts_json = get_contacts()?;
        let events_json = client::get_events()?;
        let transactions_json = get_transactions()?;

        // Reconstruct full command string from args (assert_runner expects full strings, not split args)
        let command_str = args.join(" ");
        let commands = [command_str.as_str()];

        // Run the assertion
        super::assert_runner::assert_commands(&contacts_json, &events_json, &transactions_json, &commands)
    }
}

impl Default for CommandRunner {
    fn default() -> Self {
        Self::new()
    }
}
