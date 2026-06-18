#![allow(unexpected_cfgs)] // flutter_rust_bridge macro emits frb_expand cfg
use flutter_rust_bridge::frb;

pub use serde_json::Value;

mod api;
mod config;
mod database;
mod frb_generated;
mod handlers;
mod integration;
mod sdk;
mod services;
mod types;
mod util;

pub use config::{
    get_base_url, get_ws_url, init_storage, is_network_offline, log_context, set_backend_config,
    set_log_context, set_network_offline,
};
pub use integration::data_bus::{data_change_stream, DataChangeEvent, DataChangeKind};
pub use types::ClientError;
pub use integration::sync_control::manual_sync;
pub use integration::ws::{connect_realtime, disconnect_realtime};

#[frb(init)]
pub fn init_app() {
    // Storage is initialized via init_storage(path) from Dart.
}

// --- Auth ---
pub fn login(username: String, password: String) -> Result<(), String> {
    api::login(username, password).map_err(|e| e.to_string())
}

pub fn register(username: String, password: String) -> Result<(), String> {
    api::register(username, password).map_err(|e| e.to_string())
}

pub fn logout() -> Result<(), String> {
    services::crud::logout().map_err(|e| e.to_string())
}

pub fn is_logged_in() -> bool {
    database::storage::config_get("token").ok().and_then(|o| o).is_some()
}

pub fn get_user_id() -> Result<String, String> {
    database::storage::config_get("user_id")?.ok_or_else(|| "Not logged in".to_string())
}

pub fn get_token() -> Result<String, String> {
    database::storage::config_get("token")?.ok_or_else(|| "Not logged in".to_string())
}

// --- Wallet ---
pub fn set_current_wallet_id(wallet_id: String) -> Result<(), String> {
    rust_log!("[debitum_rs] set_current_wallet_id wallet_id={}", wallet_id);
    let _ = util::ids::WalletId::parse(&wallet_id).map_err(|e| e)?;
    database::storage::config_set("current_wallet_id", &wallet_id)?;
    // Tell Dart-side providers the active wallet changed so anything
    // scoped to currentWalletIdProvider re-fetches. Without this the
    // home screen stays stuck on its first read (often "no wallet
    // selected") even after we wrote the new value to config.
    integration::data_bus::emit(integration::data_bus::DataChangeKind::Wallets, Some(wallet_id));
    Ok(())
}

pub fn get_current_wallet_id() -> Result<String, String> {
    database::storage::config_get("current_wallet_id")?.ok_or_else(|| "No wallet selected".to_string())
}

pub fn get_wallets() -> Result<String, String> {
    let list = api::get_wallets_api()?;
    serde_json::to_string(&list).map_err(|e| e.to_string())
}

pub fn create_wallet(name: String, description: String) -> Result<String, String> {
    let w = api::create_wallet_api(name, description)?;
    // New wallet exists on the server — tell Dart-side providers so the
    // wallet list refreshes (no DataChangeKind.Wallets event would
    // otherwise reach the client until the next push/pull cycle).
    integration::data_bus::emit(integration::data_bus::DataChangeKind::Wallets, None);
    serde_json::to_string(&w).map_err(|e| e.to_string())
}

pub fn ensure_current_wallet() -> Result<(), String> {
    if get_current_wallet_id().is_ok() {
        return Ok(());
    }
    let list = api::get_wallets_api()?;
    let first = list.into_iter().next().ok_or("No wallets")?;
    let _ = util::ids::WalletId::parse(&first.id).map_err(|e| e)?;
    set_current_wallet_id(first.id)
}

// --- Data (JSON strings for Dart) ---
pub fn get_contacts() -> Result<String, String> {
    services::crud::get_contacts()
}

pub fn get_transactions() -> Result<String, String> {
    services::crud::get_transactions()
}

pub fn get_contact(id: String) -> Result<String, String> {
    services::crud::get_contact(id)
}

pub fn create_contact(
    name: String,
    username: Option<String>,
    phone: Option<String>,
    email: Option<String>,
    notes: Option<String>,
    group_ids: Option<Vec<String>>,
) -> Result<String, String> {
    let c = services::crud::create_contact(name, username, phone, email, notes, group_ids)?;
    serde_json::to_string(&c).map_err(|e| e.to_string())
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
) -> Result<String, String> {
    let t = services::crud::create_transaction(
        contact_id,
        type_,
        direction,
        amount,
        currency,
        description,
        transaction_date,
        due_date,
    )?;
    serde_json::to_string(&t).map_err(|e| e.to_string())
}

pub fn get_transaction(id: String) -> Result<String, String> {
    services::crud::get_transaction(id)
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
    services::crud::update_contact(id, name, username, phone, email, notes, group_ids)
}

pub fn delete_contact(contact_id: String) -> Result<(), String> {
    services::crud::delete_contact(contact_id)
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
    services::crud::update_transaction(
        id,
        contact_id,
        type_,
        direction,
        amount,
        currency,
        description,
        transaction_date,
        due_date,
    )
}

pub fn delete_transaction(transaction_id: String) -> Result<(), String> {
    services::crud::delete_transaction(transaction_id)
}

pub fn undo_contact_action(contact_id: String) -> Result<(), String> {
    services::crud::undo_contact_action(contact_id)
}

pub fn undo_transaction_action(transaction_id: String) -> Result<(), String> {
    services::crud::undo_transaction_action(transaction_id)
}

pub fn bulk_delete_contacts(contact_ids: Vec<String>) -> Result<(), String> {
    services::crud::bulk_delete_contacts(contact_ids)
}

pub fn bulk_delete_transactions(transaction_ids: Vec<String>) -> Result<(), String> {
    services::crud::bulk_delete_transactions(transaction_ids)
}

// --- Wallet management (manage wallet screen: users, groups, matrix) ---
pub fn list_wallet_users(wallet_id: String) -> Result<String, String> {
    api::list_wallet_users_api(&wallet_id).map_err(|e| e.to_string())
}

pub fn search_wallet_users(wallet_id: String, query: String) -> Result<String, String> {
    api::search_wallet_users_api(&wallet_id, &query).map_err(|e| e.to_string())
}

pub fn add_user_to_wallet(wallet_id: String, username: String) -> Result<(), String> {
    api::add_user_to_wallet_api(&wallet_id, &username).map_err(|e| e.to_string())
}

/// Create or replace 4-digit invite code for the wallet. Returns the code string.
pub fn create_wallet_invite_code(wallet_id: String) -> Result<String, String> {
    api::create_wallet_invite_api(&wallet_id).map_err(|e| e.to_string())
}

/// Join a wallet by invite code. Returns the wallet_id of the joined wallet.
pub fn join_wallet_by_code(code: String) -> Result<String, String> {
    let id = api::join_wallet_by_code_api(&code).map_err(|e| e.to_string())?;
    // New wallet membership — refresh wallet list + membership views.
    integration::data_bus::emit(integration::data_bus::DataChangeKind::Wallets, None);
    integration::data_bus::emit(integration::data_bus::DataChangeKind::WalletMembership, Some(id.clone()));
    Ok(id)
}

pub fn update_wallet_user_role(
    wallet_id: String,
    user_id: String,
    role: String,
) -> Result<(), String> {
    api::update_wallet_user_api(&wallet_id, &user_id, &role).map_err(|e| e.to_string())
}

pub fn remove_wallet_user(wallet_id: String, user_id: String) -> Result<(), String> {
    api::remove_wallet_user_api(&wallet_id, &user_id).map_err(|e| e.to_string())
}

pub fn list_wallet_user_groups(wallet_id: String) -> Result<String, String> {
    api::list_user_groups_api(&wallet_id).map_err(|e| e.to_string())
}

pub fn create_wallet_user_group(wallet_id: String, name: String) -> Result<String, String> {
    api::create_user_group_api(&wallet_id, &name).map_err(|e| e.to_string())
}

pub fn update_wallet_user_group(
    wallet_id: String,
    group_id: String,
    name: String,
) -> Result<(), String> {
    api::update_user_group_api(&wallet_id, &group_id, &name).map_err(|e| e.to_string())
}

pub fn delete_wallet_user_group(wallet_id: String, group_id: String) -> Result<(), String> {
    api::delete_user_group_api(&wallet_id, &group_id).map_err(|e| e.to_string())
}

pub fn list_wallet_user_group_members(
    wallet_id: String,
    group_id: String,
) -> Result<String, String> {
    api::list_user_group_members_api(&wallet_id, &group_id).map_err(|e| e.to_string())
}

pub fn add_wallet_user_group_member(
    wallet_id: String,
    group_id: String,
    user_id: String,
) -> Result<(), String> {
    api::add_user_group_member_api(&wallet_id, &group_id, &user_id).map_err(|e| e.to_string())
}

pub fn remove_wallet_user_group_member(
    wallet_id: String,
    group_id: String,
    user_id: String,
) -> Result<(), String> {
    api::remove_user_group_member_api(&wallet_id, &group_id, &user_id).map_err(|e| e.to_string())
}

pub fn list_wallet_contact_groups(wallet_id: String) -> Result<String, String> {
    api::list_contact_groups_api(&wallet_id).map_err(|e| e.to_string())
}

pub fn create_wallet_contact_group(wallet_id: String, name: String) -> Result<String, String> {
    api::create_contact_group_api(&wallet_id, &name).map_err(|e| e.to_string())
}

pub fn update_wallet_contact_group(
    wallet_id: String,
    group_id: String,
    name: String,
) -> Result<(), String> {
    api::update_contact_group_api(&wallet_id, &group_id, &name).map_err(|e| e.to_string())
}

pub fn delete_wallet_contact_group(wallet_id: String, group_id: String) -> Result<(), String> {
    api::delete_contact_group_api(&wallet_id, &group_id).map_err(|e| e.to_string())
}

pub fn list_wallet_contact_group_members(
    wallet_id: String,
    group_id: String,
) -> Result<String, String> {
    api::list_contact_group_members_api(&wallet_id, &group_id).map_err(|e| e.to_string())
}

/// Returns JSON array of contact group ids that contain this contact. Used by edit-contact UI.
pub fn get_contact_group_ids_for_contact(
    wallet_id: String,
    contact_id: String,
) -> Result<String, String> {
    let groups_json = api::list_contact_groups_api(&wallet_id)?;
    let groups: Vec<serde_json::Value> =
        serde_json::from_str(&groups_json).map_err(|e| e.to_string())?;
    let mut result = Vec::new();
    for g in groups {
        let group_id = match g.get("id").and_then(|v| v.as_str()) {
            Some(id) => id.to_string(),
            None => continue,
        };
        let members_json = api::list_contact_group_members_api(&wallet_id, &group_id)?;
        let members: Vec<serde_json::Value> =
            serde_json::from_str(&members_json).unwrap_or_default();
        for m in members {
            if m.get("contact_id").and_then(|v| v.as_str()) == Some(contact_id.as_str()) {
                result.push(group_id);
                break;
            }
        }
    }
    serde_json::to_string(&result).map_err(|e| e.to_string())
}

pub fn add_wallet_contact_group_member(
    wallet_id: String,
    group_id: String,
    contact_id: String,
) -> Result<(), String> {
    api::add_contact_group_member_api(&wallet_id, &group_id, &contact_id)?;
    if let Ok(Some(current)) = database::storage::config_get("current_wallet_id") {
        if current == wallet_id {
            let _ = services::sync::invalidate_perms_cache_and_pull(&wallet_id);
        }
    }
    Ok(())
}

pub fn remove_wallet_contact_group_member(
    wallet_id: String,
    group_id: String,
    contact_id: String,
) -> Result<(), String> {
    api::remove_contact_group_member_api(&wallet_id, &group_id, &contact_id)?;
    if let Ok(Some(current)) = database::storage::config_get("current_wallet_id") {
        if current == wallet_id {
            let _ = services::sync::invalidate_perms_cache_and_pull(&wallet_id);
        }
    }
    Ok(())
}

pub fn list_wallet_permission_actions(wallet_id: String) -> Result<String, String> {
    api::list_permission_actions_api(&wallet_id).map_err(|e| e.to_string())
}

pub fn get_my_permissions(wallet_id: String) -> Result<String, String> {
    api::get_my_permissions_api(&wallet_id).map_err(|e| e.to_string())
}

pub fn clear_wallet_data(wallet_id: String) -> Result<(), String> {
    database::storage::clear_wallet(&wallet_id)
}

pub fn get_wallet_permission_matrix(wallet_id: String) -> Result<String, String> {
    api::get_permission_matrix_api(&wallet_id).map_err(|e| e.to_string())
}

pub fn put_wallet_permission_matrix(wallet_id: String, entries_json: String) -> Result<(), String> {
    api::put_permission_matrix_api(&wallet_id, &entries_json)?;
    if let Ok(Some(current)) = database::storage::config_get("current_wallet_id") {
        if current == wallet_id {
            let _ = services::sync::clear_wallet_and_resync(&wallet_id);
        }
    }
    Ok(())
}

// --- Events (for events log / EventStoreService) ---
pub fn get_events() -> Result<String, String> {
    let wallet_id = match database::storage::config_get("current_wallet_id")? {
        Some(id) => id,
        None => {
            rust_log!("[debitum_rs] get_events: no current_wallet_id in config -> []");
            return Ok("[]".to_string());
        }
    };
    rust_log!(
        "[debitum_rs] get_events wallet_id={} querying storage...",
        wallet_id
    );
    let events = database::storage::events_get_all(&wallet_id)?;
    rust_log!("[debitum_rs] get_events returning {} events", events.len());
    let list: Vec<serde_json::Value> = events
        .into_iter()
        .map(|e| {
            let event_data: serde_json::Value =
                serde_json::from_str(&e.event_data).unwrap_or(serde_json::Value::Null);
            serde_json::json!({
                "id": e.id,
                "aggregate_type": e.aggregate_type,
                "aggregate_id": e.aggregate_id,
                "event_type": e.event_type,
                "event_data": event_data,
                "timestamp": e.timestamp,
                "version": e.version,
                "synced": e.synced,
            })
        })
        .collect();
    serde_json::to_string(&list).map_err(|e| e.to_string())
}


/// Drain buffered Rust log lines so Dart can show them (e.g. via debugPrint).
pub fn drain_rust_logs() -> Vec<String> {
    util::logging::drain_rust_logs()
}

// --- UI preferences (stored in Rust config; Dart only reads/writes via these) ---
const PREF_PREFIX: &str = "pref_";

pub fn get_preference(key: String) -> Result<String, String> {
    let storage_key = format!("{}{}", PREF_PREFIX, key);
    database::storage::config_get(&storage_key)?.ok_or_else(|| format!("Preference '{}' not set", key))
}

pub fn set_preference(key: String, value: String) -> Result<(), String> {
    let storage_key = format!("{}{}", PREF_PREFIX, key);
    database::storage::config_set(&storage_key, &value)
}

// --- JWT (single place for token parsing; Dart no longer decodes) ---
pub fn get_username() -> Result<String, String> {
    let token = database::storage::config_get("token")?.ok_or_else(|| "Not logged in".to_string())?;
    if token.is_empty() {
        return Err("Not logged in".to_string());
    }
    jwt_payload(&token)
        .and_then(|p| p.username)
        .ok_or_else(|| "No username in token".to_string())
}

/// True if JWT is expired or invalid. Used to avoid WebSocket 401 spam.
pub fn is_token_expired() -> bool {
    let token = match database::storage::config_get("token").ok().and_then(|o| o) {
        Some(t) if !t.is_empty() => t,
        _ => return true,
    };
    match jwt_payload(&token) {
        Some(p) => p.expired,
        None => true,
    }
}

#[derive(Default)]
struct JwtPayload {
    username: Option<String>,
    expired: bool,
}

fn jwt_payload(token: &str) -> Option<JwtPayload> {
    use base64::Engine;
    let parts: Vec<&str> = token.splitn(3, '.').collect();
    if parts.len() != 3 {
        return None;
    }
    let payload_b64 = parts[1];
    let decoded = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(payload_b64.as_bytes())
        .ok()?;
    let payload_str = String::from_utf8(decoded).ok()?;
    let json: serde_json::Value = serde_json::from_str(&payload_str).ok()?;
    let obj = json.as_object()?;
    let username = obj
        .get("username")
        .and_then(|v| v.as_str())
        .map(String::from);
    let expired = obj
        .get("exp")
        .and_then(|v| v.as_i64())
        .map_or(true, |exp_sec| chrono::Utc::now().timestamp() >= exp_sec);
    Some(JwtPayload { username, expired })
}

/// Extract `user_id` claim from the stored JWT, returning the nil UUID
/// if no token / no claim. Used when constructing local DomainEvents
/// to feed through applier::apply — projection methods on the SDK
/// don't consult event.user_id so the fallback is harmless.
pub(crate) fn current_user_id_or_nil() -> String {
    current_user_id().unwrap_or_else(|| uuid::Uuid::nil().to_string())
}

/// Extract `user_id` claim from the stored JWT. Returns `None` if no
/// token, the token is malformed, or the claim is missing.
fn current_user_id() -> Option<String> {
    let token = database::storage::config_get("token").ok().and_then(|o| o)?;
    if token.is_empty() {
        return None;
    }
    use base64::Engine;
    let parts: Vec<&str> = token.splitn(3, '.').collect();
    if parts.len() != 3 {
        return None;
    }
    let decoded = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(parts[1].as_bytes())
        .ok()?;
    let payload_str = String::from_utf8(decoded).ok()?;
    let json: serde_json::Value = serde_json::from_str(&payload_str).ok()?;
    json.as_object()?
        .get("user_id")
        .and_then(|v| v.as_str())
        .map(String::from)
}

/// Can the current user (taken from the stored JWT) perform `action_name`
/// (e.g. `"contact:create"`, `"transaction:read"`) on the resource named
/// by `(resource_type, resource_id)`?
///
/// `resource_type` is one of:
///   - `"contact"`, `"transaction"`, `"wallet"`,
///     `"contact_group"`, `"user_group"` — `resource_id` is the entity UUID.
///   - `"all_contacts"`, `"all_transactions"`, `"all_user_groups"` —
///     wildcard; `resource_id` is ignored.
///
/// Resolves entirely from the SDK's local SQLite permission tables —
/// no network call. The same rules the server enforces (3-state matrix,
/// deny wins, all_contacts wildcard) via the shared `resolver` crate.
/// Returns `Ok(false)` if no JWT / no current wallet (rather than an
/// error) so UI callers can use this from anywhere.
pub fn can_perform(
    action_name: String,
    resource_type: String,
    resource_id: Option<String>,
) -> Result<bool, String> {
    use domain::{Action, PermissionContext, WalletRole};

    let token = match database::storage::config_get("token").ok().and_then(|o| o) {
        Some(t) if !t.is_empty() => t,
        _ => return Ok(false),
    };
    // Token validity check first (cheap), then extract user_id.
    if jwt_payload(&token).map(|p| p.expired).unwrap_or(true) {
        return Ok(false);
    }
    let user_id_str = match current_user_id() {
        Some(s) => s,
        None => return Ok(false),
    };
    let wallet_id_str = match database::storage::config_get("current_wallet_id")
        .ok()
        .and_then(|o| o)
    {
        Some(w) if !w.is_empty() => w,
        _ => return Ok(false),
    };

    let user_id = uuid::Uuid::parse_str(&user_id_str).map_err(|e| e.to_string())?;
    let wallet_id = uuid::Uuid::parse_str(&wallet_id_str).map_err(|e| e.to_string())?;

    let resource = parse_resource(&resource_type, resource_id.as_deref())?;
    let action = match Action::from_str(&action_name) {
        Some(a) => a,
        None => return Ok(false),
    };

    // Role doesn't affect resolver output (the store does its own owner check)
    // but PermissionContext needs one. Member is the conservative default.
    let ctx = PermissionContext::new(wallet_id, user_id, WalletRole::Member);
    let store = sdk::store::SdkPermissionStore::new();
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|e| e.to_string())?;
    let allowed = rt
        .block_on(resolver::resolve_actions(&store, &ctx, &resource))
        .map_err(|e| format!("{:?}", e))?;
    // `implies()` so e.g. ContactUpdate also satisfies a ContactRead check
    // (the model's dependency rules — see Action::implies).
    Ok(allowed.iter().any(|a| a.implies(action)))
}

fn parse_resource(kind: &str, id: Option<&str>) -> Result<domain::Resource, String> {
    use domain::Resource;
    let parse_id = |label: &str| -> Result<uuid::Uuid, String> {
        let s = id.ok_or_else(|| format!("{} needs a resource_id", label))?;
        uuid::Uuid::parse_str(s).map_err(|e| format!("invalid uuid for {}: {}", label, e))
    };
    match kind {
        "contact" => Ok(Resource::Contact(parse_id("contact")?)),
        "transaction" => Ok(Resource::Transaction(parse_id("transaction")?)),
        "wallet" => Ok(Resource::Wallet(parse_id("wallet")?)),
        "contact_group" => Ok(Resource::ContactGroup(parse_id("contact_group")?)),
        "user_group" => Ok(Resource::UserGroup(parse_id("user_group")?)),
        "all_contacts" => Ok(Resource::AllContacts),
        "all_transactions" => Ok(Resource::AllTransactions),
        "all_user_groups" => Ok(Resource::AllUserGroups),
        other => Err(format!("unknown resource_type: {}", other)),
    }
}

// Kept for compatibility
pub fn greet(name: String) -> String {
    format!("Hello, {} from Rust!", name)
}

#[cfg(test)]
mod tests {
    // Storage is process-wide; run with: cargo test --lib -- --test-threads=1
    use super::*;
    use crate::database::StoredEvent;
    use std::path::PathBuf;

    fn temp_storage_path() -> PathBuf {
        let dir = tempfile::tempdir().expect("tempdir");
        dir.path().to_path_buf()
    }

    #[test]
    fn get_events_returns_empty_json_array_when_no_current_wallet() {
        let path = temp_storage_path();
        database::storage::init(path.to_str().unwrap()).expect("init");
        // Do not set current_wallet_id
        let json = get_events().expect("get_events");
        assert_eq!(json, "[]", "expected [] when no wallet set");
    }

    #[test]
    fn get_events_returns_empty_json_array_when_wallet_has_no_events() {
        let path = temp_storage_path();
        database::storage::init(path.to_str().unwrap()).expect("init");
        let wallet_id = "f27978af-e56a-4b45-aede-fb450557699a";
        database::storage::config_set("current_wallet_id", wallet_id).expect("config_set");
        let json = get_events().expect("get_events");
        let parsed: Vec<serde_json::Value> = serde_json::from_str(&json).expect("parse json");
        assert!(parsed.is_empty(), "expected no events for fresh wallet");
    }

    #[test]
    fn get_events_returns_events_after_insert() {
        let path = temp_storage_path();
        database::storage::init(path.to_str().unwrap()).expect("init");
        let wallet_id = "f27978af-e56a-4b45-aede-fb450557699a";
        database::storage::config_set("current_wallet_id", wallet_id).expect("config_set");

        let event = StoredEvent {
            id: "event-1".to_string(),
            wallet_id: wallet_id.to_string(),
            aggregate_type: "contact".to_string(),
            aggregate_id: "contact-1".to_string(),
            event_type: "CREATED".to_string(),
            event_data: r#"{"name":"Test","total_debt":0}"#.to_string(),
            timestamp: "2026-02-04T12:00:00Z".to_string(),
            version: 1,
            synced: false,
        };
        database::storage::events_insert(&event).expect("events_insert");

        let json = get_events().expect("get_events");
        let parsed: Vec<serde_json::Value> = serde_json::from_str(&json).expect("parse json");
        assert_eq!(parsed.len(), 1, "expected one event");
        assert_eq!(parsed[0]["id"], "event-1");
        assert_eq!(parsed[0]["event_type"], "CREATED");
    }

    #[test]
    fn events_count_zero_for_new_wallet() {
        let path = temp_storage_path();
        database::storage::init(path.to_str().unwrap()).expect("init");
        let wallet_id = "cb203efe-c27c-470e-bbc6-588172c3b1ae";
        let count = database::storage::events_count(wallet_id).expect("events_count");
        assert_eq!(count, 0);
    }

    #[test]
    fn set_and_get_current_wallet_id() {
        let path = temp_storage_path();
        database::storage::init(path.to_str().unwrap()).expect("init");
        let wallet_id = "f27978af-e56a-4b45-aede-fb450557699a";
        set_current_wallet_id(wallet_id.to_string()).expect("set_current_wallet_id");
        let got = get_current_wallet_id();
        assert_eq!(got.as_deref(), Ok(wallet_id));
    }

    #[test]
    fn init_storage_creates_db_file() {
        let path = temp_storage_path();
        let db_path = path.join("debitum.db");
        assert!(!db_path.exists());
        init_storage(path.to_str().unwrap().to_string()).expect("init_storage");
        assert!(db_path.exists(), "debitum.db should exist after init");
    }

    /// Sync does a full pull (no since) when local event count is 0. This test verifies
    /// that after init + set wallet, events_count is 0 so the next pull would be full.
    #[test]
    fn full_pull_condition_when_no_local_events() {
        let path = temp_storage_path();
        database::storage::init(path.to_str().unwrap()).expect("init");
        let wallet_id = "f27978af-e56a-4b45-aede-fb450557699a";
        database::storage::config_set("current_wallet_id", wallet_id).expect("config_set");
        let count = database::storage::events_count(wallet_id).expect("events_count");
        assert_eq!(
            count, 0,
            "new wallet should have 0 events so sync will do full pull"
        );
    }
}