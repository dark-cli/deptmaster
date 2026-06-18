//! FFI handlers for wallet management.

use crate::api;
use crate::types::models::Wallet;

pub fn get_wallets_api() -> Result<Vec<Wallet>, String> {
    api::get_wallets_api().map_err(|e| e.to_string())
}

pub fn create_wallet_api(name: String, description: String) -> Result<Wallet, String> {
    api::create_wallet_api(name, description).map_err(|e| e.to_string())
}

pub fn list_wallet_users_api(wallet_id: &str) -> Result<String, String> {
    api::list_wallet_users_api(wallet_id).map_err(|e| e.to_string())
}

pub fn search_wallet_users_api(wallet_id: &str, query: &str) -> Result<String, String> {
    api::search_wallet_users_api(wallet_id, query).map_err(|e| e.to_string())
}

pub fn add_user_to_wallet_api(wallet_id: &str, username: &str) -> Result<(), String> {
    api::add_user_to_wallet_api(wallet_id, username).map_err(|e| e.to_string())
}

pub fn update_wallet_user_api(wallet_id: &str, user_id: &str, role: &str) -> Result<(), String> {
    api::update_wallet_user_api(wallet_id, user_id, role).map_err(|e| e.to_string())
}

pub fn remove_wallet_user_api(wallet_id: &str, user_id: &str) -> Result<(), String> {
    api::remove_wallet_user_api(wallet_id, user_id).map_err(|e| e.to_string())
}

pub fn create_wallet_invite_api(wallet_id: &str) -> Result<String, String> {
    api::create_wallet_invite_api(wallet_id).map_err(|e| e.to_string())
}

pub fn join_wallet_by_code_api(code: &str) -> Result<String, String> {
    api::join_wallet_by_code_api(code).map_err(|e| e.to_string())
}

pub fn list_user_groups_api(wallet_id: &str) -> Result<String, String> {
    api::list_user_groups_api(wallet_id).map_err(|e| e.to_string())
}

pub fn create_user_group_api(wallet_id: &str, name: &str) -> Result<String, String> {
    api::create_user_group_api(wallet_id, name).map_err(|e| e.to_string())
}

pub fn update_user_group_api(wallet_id: &str, group_id: &str, name: &str) -> Result<(), String> {
    api::update_user_group_api(wallet_id, group_id, name).map_err(|e| e.to_string())
}

pub fn delete_user_group_api(wallet_id: &str, group_id: &str) -> Result<(), String> {
    api::delete_user_group_api(wallet_id, group_id).map_err(|e| e.to_string())
}

pub fn list_user_group_members_api(wallet_id: &str, group_id: &str) -> Result<String, String> {
    api::list_user_group_members_api(wallet_id, group_id).map_err(|e| e.to_string())
}

pub fn add_user_group_member_api(
    wallet_id: &str,
    group_id: &str,
    username: &str,
) -> Result<(), String> {
    api::add_user_group_member_api(wallet_id, group_id, username).map_err(|e| e.to_string())
}

pub fn remove_user_group_member_api(
    wallet_id: &str,
    group_id: &str,
    user_id: &str,
) -> Result<(), String> {
    api::remove_user_group_member_api(wallet_id, group_id, user_id).map_err(|e| e.to_string())
}

pub fn list_contact_groups_api(wallet_id: &str) -> Result<String, String> {
    api::list_contact_groups_api(wallet_id).map_err(|e| e.to_string())
}

pub fn create_contact_group_api(wallet_id: &str, name: &str) -> Result<String, String> {
    api::create_contact_group_api(wallet_id, name).map_err(|e| e.to_string())
}

pub fn update_contact_group_api(wallet_id: &str, group_id: &str, name: &str) -> Result<(), String> {
    api::update_contact_group_api(wallet_id, group_id, name).map_err(|e| e.to_string())
}

pub fn delete_contact_group_api(wallet_id: &str, group_id: &str) -> Result<(), String> {
    api::delete_contact_group_api(wallet_id, group_id).map_err(|e| e.to_string())
}

pub fn list_contact_group_members_api(wallet_id: &str, group_id: &str) -> Result<String, String> {
    api::list_contact_group_members_api(wallet_id, group_id).map_err(|e| e.to_string())
}

pub fn add_contact_group_member_api(
    wallet_id: &str,
    group_id: &str,
    contact_id: &str,
) -> Result<(), String> {
    api::add_contact_group_member_api(wallet_id, group_id, contact_id).map_err(|e| e.to_string())
}

pub fn remove_contact_group_member_api(
    wallet_id: &str,
    group_id: &str,
    contact_id: &str,
) -> Result<(), String> {
    api::remove_contact_group_member_api(wallet_id, group_id, contact_id).map_err(|e| e.to_string())
}

pub fn list_permission_actions_api(wallet_id: &str) -> Result<String, String> {
    api::list_permission_actions_api(wallet_id).map_err(|e| e.to_string())
}

pub fn get_my_permissions_api(wallet_id: &str) -> Result<String, String> {
    api::get_my_permissions_api(wallet_id).map_err(|e| e.to_string())
}

pub fn get_permission_matrix_api(wallet_id: &str) -> Result<String, String> {
    api::get_permission_matrix_api(wallet_id).map_err(|e| e.to_string())
}

pub fn put_permission_matrix_api(wallet_id: &str, entries_json: &str) -> Result<(), String> {
    api::put_permission_matrix_api(wallet_id, entries_json).map_err(|e| e.to_string())
}
