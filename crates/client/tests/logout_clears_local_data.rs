//! Regression test: logout must wipe every trace of the previous user so
//! that a *different* user logging in on the same device sees a clean
//! slate — not the previous user's contacts, transactions, wallets, or
//! groups.
//!
//! Failing on the FFI/Rust path means `storage::clear_all()` has a hole
//! or `logout()` doesn't actually run it. Passing here means the
//! storage layer is sound and any "previous user still visible" bug
//! lives in the Flutter Riverpod provider cache (UI fix territory).

use client::{
    create_contact, get_contacts, init_storage, logout, manual_sync, register,
    set_backend_config, set_current_wallet_id,
};
use std::path::PathBuf;

use crate::common::test_helpers::test_server_url;

fn ws_url_from_base(base: &str) -> String {
    let base = base.trim_end_matches('/');
    if base.starts_with("https://") {
        base.replacen("https://", "wss://", 1) + "/ws"
    } else {
        base.replacen("http://", "ws://", 1) + "/ws"
    }
}

fn fresh_username(tag: &str) -> String {
    format!("itest-{}-{}", tag, uuid::Uuid::new_v4())
}

/// Drive the scenario directly at the client lib level: one storage
/// path, two users in sequence with logout in between. Bypasses
/// `AppInstance` because that helper gives each instance its own
/// tempdir — exactly the thing this test must NOT do.
#[test]
#[ignore]
fn logout_clears_data_so_next_user_starts_empty() {
    let server_url = test_server_url();
    let ws_url = ws_url_from_base(&server_url);

    // One device, one DB path, used for both users.
    let dir = tempfile::tempdir().expect("tempdir");
    let storage_path: PathBuf = dir.path().to_path_buf();
    init_storage(storage_path.to_string_lossy().to_string()).expect("init storage");
    set_backend_config(server_url.clone(), ws_url);

    // ---------- user A: sign up, make a wallet + contact ----------
    let user_a = fresh_username("a");
    let pass = "test-pass-1234".to_string();
    register(user_a.clone(), pass.clone()).expect("register A");

    let wallet_json =
        client::create_wallet("Wallet A".to_string(), String::new()).expect("create wallet A");
    let wallet: serde_json::Value =
        serde_json::from_str(&wallet_json).expect("parse wallet A");
    let wallet_id = wallet["id"].as_str().expect("wallet id").to_string();
    set_current_wallet_id(wallet_id.clone()).expect("select wallet A");

    create_contact(
        "Alice (A only)".to_string(),
        None,
        None,
        None,
        None,
        None,
    )
    .expect("create contact for A");
    manual_sync().expect("user A initial sync");

    let contacts_a = get_contacts().expect("contacts after A creates");
    let parsed_a: Vec<serde_json::Value> =
        serde_json::from_str(&contacts_a).expect("parse contacts A");
    assert_eq!(
        parsed_a.len(),
        1,
        "pre-logout sanity: user A must see their one contact, got {:?}",
        parsed_a
    );

    // ---------- logout ----------
    logout().expect("logout A");

    // After logout, the lib has no current_wallet_id and no user_id —
    // get_contacts should not be able to even resolve a wallet. We
    // either get Err or an empty list; the invariant is "no Alice".
    let post_logout = get_contacts().unwrap_or_else(|_| "[]".to_string());
    let parsed_post_logout: Vec<serde_json::Value> =
        serde_json::from_str(&post_logout).expect("parse post-logout contacts");
    assert!(
        parsed_post_logout.is_empty(),
        "post-logout: contacts must be empty, got {:?}",
        parsed_post_logout
    );

    // ---------- user B: sign up + new wallet, must NOT see A's data ----------
    let user_b = fresh_username("b");
    register(user_b.clone(), pass.clone()).expect("register B");

    let wallet_b_json =
        client::create_wallet("Wallet B".to_string(), String::new()).expect("create wallet B");
    let wallet_b: serde_json::Value =
        serde_json::from_str(&wallet_b_json).expect("parse wallet B");
    let wallet_b_id = wallet_b["id"].as_str().expect("wallet B id").to_string();
    set_current_wallet_id(wallet_b_id.clone()).expect("select wallet B");

    manual_sync().expect("user B initial sync");

    let contacts_b = get_contacts().expect("contacts after B logs in");
    let parsed_b: Vec<serde_json::Value> =
        serde_json::from_str(&contacts_b).expect("parse contacts B");

    assert!(
        parsed_b.is_empty(),
        "user B (fresh account) must see ZERO contacts on the same device, \
         but found {} — leftover from user A. \
         Either storage::clear_all is missing a table, or logout() didn't \
         actually run clear_all. Got: {:?}",
        parsed_b.len(),
        parsed_b
    );
}
