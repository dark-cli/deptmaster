//! HTTP client for backend API (auth, sync, wallets).

pub(crate) mod auth;
pub(crate) mod sync;
pub(crate) mod wallets;

pub use auth::{login, register, server_logout};
pub use sync::{get_sync_events, post_sync_events};
pub use wallets::{
    add_contact_group_member_api, add_user_group_member_api, add_user_to_wallet_api,
    create_contact_group_api, create_user_group_api, create_wallet_api, create_wallet_invite_api,
    delete_contact_group_api, delete_user_group_api, get_member_permissions_api, get_my_permissions_api,
    get_permission_matrix_api, get_wallet_permissions_api, get_wallets_api, join_wallet_by_code_api,
    list_contact_group_members_api, list_contact_groups_api, list_permission_actions_api,
    list_user_group_members_api, list_user_groups_api, list_wallet_users_api,
    put_permission_matrix_api, remove_contact_group_member_api, remove_user_group_member_api,
    remove_wallet_user_api, search_wallet_users_api, set_member_permissions_api, set_wallet_permissions_api,
    update_contact_group_api, update_user_group_api, update_wallet_user_api,
};

use crate::types::error::ClientError;
use once_cell::sync::Lazy;
use std::future::Future;

pub(super) static CLIENT: Lazy<reqwest::Client> = Lazy::new(|| {
    reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(30))
        .build()
        .expect("reqwest client")
});

pub(super) static RUNTIME: Lazy<tokio::runtime::Runtime> =
    Lazy::new(|| tokio::runtime::Runtime::new().expect("tokio runtime"));

#[allow(dead_code)]
pub(crate) fn spawn_background<F>(fut: F)
where
    F: Future<Output = ()> + Send + 'static,
{
    RUNTIME.spawn(fut);
}

pub(super) fn base_url() -> Result<String, ClientError> {
    if crate::is_network_offline() {
        return Err(ClientError::Network("Network offline".to_string()));
    }
    crate::get_base_url().map_err(ClientError::Network)
}
