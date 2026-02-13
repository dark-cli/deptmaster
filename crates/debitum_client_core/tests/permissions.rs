//! Give/take permission scenarios: owner adds member, sets matrix; member syncs and sees or loses data.
//!
//! Requires server running. Uses default all_users × all_contacts matrix (system groups).

use crate::common::app_instance::{create_unique_test_user_and_wallet, AppInstance};
use crate::common::test_helpers::test_server_url;
use debitum_client_core::{add_user_to_wallet, get_current_wallet_id, get_wallet_permission_matrix, put_wallet_permission_matrix};

/// Helper: get (user_group_id, contact_group_id) for the first matrix row (typically all_users × all_contacts).
fn get_default_matrix_ids(wallet_id: &str) -> Result<(String, String), String> {
    let json = get_wallet_permission_matrix(wallet_id.to_string())?;
    let arr: Vec<serde_json::Value> = serde_json::from_str(&json).map_err(|e| e.to_string())?;
    let row = arr.first().ok_or("Permission matrix is empty")?;
    let ug = row["user_group_id"].as_str().ok_or("No user_group_id")?.to_string();
    let cg = row["contact_group_id"].as_str().ok_or("No contact_group_id")?.to_string();
    Ok((ug, cg))
}

/// Set actions for the default (all_users × all_contacts) matrix row.
fn set_default_matrix_actions(wallet_id: &str, action_names: &[&str]) -> Result<(), String> {
    let (ug_id, cg_id) = get_default_matrix_ids(wallet_id)?;
    set_matrix_actions(wallet_id, &ug_id, &cg_id, action_names)
}

/// Set actions for a specific (user_group_id, contact_group_id) row. Use when the row may have been removed (e.g. after revoke).
fn set_matrix_actions(
    wallet_id: &str,
    user_group_id: &str,
    contact_group_id: &str,
    action_names: &[&str],
) -> Result<(), String> {
    let actions: Vec<String> = action_names.iter().map(|s| (*s).to_string()).collect();
    let entries = serde_json::json!([{
        "user_group_id": user_group_id,
        "contact_group_id": contact_group_id,
        "action_names": actions
    }]);
    put_wallet_permission_matrix(wallet_id.to_string(), entries.to_string())
}

/// Owner creates contact; member has default read → sees contact. Owner revokes read → member syncs, sees none. Owner grants read again → member sees contact.
#[test]
#[ignore]
fn permission_give_take_read_member_sees_then_loses_then_sees() {
    let server_url = test_server_url();
    let owner = AppInstance::new("owner", &server_url);
    owner.initialize().expect("initialize");
    owner.signup().expect("signup");
    owner.activate().expect("activate");
    let wallet_id = get_current_wallet_id().ok_or("no wallet").expect("wallet");

    let member = AppInstance::new("member", &server_url);
    member.initialize().expect("initialize");
    member.signup().expect("member signup");
    owner.activate().expect("activate as owner");
    add_user_to_wallet(wallet_id.clone(), member.username.clone()).expect("add member to wallet");

    let member_in_wallet = AppInstance::with_credentials(
        "member",
        &server_url,
        member.username.clone(),
        member.password.clone(),
        Some(wallet_id.clone()),
    );
    member_in_wallet.initialize().expect("initialize");
    member_in_wallet.login().expect("login");

    owner.activate().expect("owner");
    owner
        .run_commands(&["contact create \"Shared Contact\" shared", "wait 300"])
        .expect("owner create contact");
    owner.sync().expect("owner sync");

    member_in_wallet.sync().expect("member sync");
    std::thread::sleep(std::time::Duration::from_millis(300));
    member_in_wallet
        .assert_commands(&["contacts count 1", "contact name \"Shared Contact\""])
        .expect("member sees contact after grant");

    owner.activate().expect("owner");
    let (ug_id, cg_id) = get_default_matrix_ids(&wallet_id).expect("get matrix ids before revoke");
    set_matrix_actions(&wallet_id, &ug_id, &cg_id, &[]).expect("revoke all");
    member_in_wallet.sync().expect("member sync after revoke");
    std::thread::sleep(std::time::Duration::from_millis(300));
    member_in_wallet
        .assert_commands(&["contacts count 0"])
        .expect("member sees no contacts after take");

    owner.activate().expect("owner");
    set_matrix_actions(
        &wallet_id,
        &ug_id,
        &cg_id,
        &["contact:read", "transaction:read", "events:read"],
    )
    .expect("grant read again");
    member_in_wallet.sync().expect("member sync after re-grant");
    std::thread::sleep(std::time::Duration::from_millis(300));
    member_in_wallet
        .assert_commands(&["contacts count 1", "contact name \"Shared Contact\""])
        .expect("member sees contact again");
}

/// Default matrix is read-only. Member cannot create contact; run_commands returns error.
#[test]
#[ignore]
fn permission_member_read_only_cannot_create_contact() {
    let server_url = test_server_url();
    let (owner_user, owner_pass, wallet_id) =
        create_unique_test_user_and_wallet(&server_url).expect("create owner");
    let owner = AppInstance::with_credentials(
        "owner",
        &server_url,
        owner_user,
        owner_pass,
        Some(wallet_id.clone()),
    );
    owner.initialize().expect("initialize");
    owner.login().expect("login");

    let member = AppInstance::new("member", &server_url);
    member.initialize().expect("initialize");
    member.signup().expect("member signup");
    owner.activate().expect("owner");
    add_user_to_wallet(wallet_id.clone(), member.username.clone()).expect("add member");

    let member_in_wallet = AppInstance::with_credentials(
        "member",
        &server_url,
        member.username.clone(),
        member.password.clone(),
        Some(wallet_id.clone()),
    );
    member_in_wallet.initialize().expect("initialize");
    member_in_wallet.login().expect("login");

    let res = member_in_wallet.run_commands(&["contact create \"Forbidden\" forb"]);
    assert!(res.is_err(), "member without contact:create should get error");
    let err = res.unwrap_err();
    assert!(
        err.contains("403") || err.to_lowercase().contains("permission"),
        "expected 403 or permission error, got: {}",
        err
    );
}

/// Complex: owner creates contacts and transactions (many events). Member syncs and sees data.
/// Owner revokes read → member sync triggers local clear and pull → events/contacts/transactions removed.
/// Owner grants read again → member sync triggers clear+full pull → events/contacts/transactions restored.
#[test]
#[ignore]
fn permission_read_revoke_clears_local_then_grant_restores_via_sync() {
    let server_url = test_server_url();
    let owner = AppInstance::new("owner", &server_url);
    owner.initialize().expect("initialize");
    owner.signup().expect("signup");
    owner.activate().expect("activate");
    let wallet_id = get_current_wallet_id().ok_or("no wallet").expect("wallet");

    let member = AppInstance::new("member", &server_url);
    member.initialize().expect("initialize");
    member.signup().expect("member signup");
    owner.activate().expect("activate as owner");
    add_user_to_wallet(wallet_id.clone(), member.username.clone()).expect("add member to wallet");

    let member_in_wallet = AppInstance::with_credentials(
        "member",
        &server_url,
        member.username.clone(),
        member.password.clone(),
        Some(wallet_id.clone()),
    );
    member_in_wallet.initialize().expect("initialize");
    member_in_wallet.login().expect("login");

    owner.activate().expect("owner");
    owner
        .run_commands(&[
            "contact create \"Alice\" alice",
            "contact create \"Bob\" bob",
            "contact create \"Carol\" carol",
            "transaction create alice owed 1000 \"T1\" t1",
            "transaction create alice lent 500 \"T2\" t2",
            "transaction create bob lent 800 \"T3\" t3",
            "transaction create bob owed 1200 \"T4\" t4",
            "transaction create carol owed 2000 \"T5\" t5",
            "wait 300",
        ])
        .expect("owner create contacts and transactions");
    owner.sync().expect("owner sync");

    member_in_wallet.sync().expect("member sync (initial)");
    std::thread::sleep(std::time::Duration::from_millis(300));
    member_in_wallet
        .assert_commands(&[
            "contacts count 3",
            "contact name \"Alice\"",
            "contact name \"Bob\"",
            "contact name \"Carol\"",
            "transactions count >= 5",
            "events count >= 8",
        ])
        .expect("member sees all data after initial sync");

    owner.activate().expect("owner");
    let (ug_id, cg_id) = get_default_matrix_ids(&wallet_id).expect("get matrix ids before revoke");
    set_matrix_actions(&wallet_id, &ug_id, &cg_id, &[]).expect("revoke all (read removed)");

    member_in_wallet.sync().expect("member sync after revoke — should trigger clear + full pull");
    std::thread::sleep(std::time::Duration::from_millis(300));
    member_in_wallet
        .assert_commands(&[
            "contacts count 0",
            "transactions count 0",
        ])
        .expect("member local state cleared: no contacts, no transactions (syncer removed read data)");

    owner.activate().expect("owner");
    set_matrix_actions(
        &wallet_id,
        &ug_id,
        &cg_id,
        &["contact:read", "transaction:read", "events:read"],
    )
    .expect("grant read again");

    member_in_wallet.sync().expect("member sync after re-grant — should trigger clear + full pull and restore data");
    std::thread::sleep(std::time::Duration::from_millis(300));
    member_in_wallet
        .assert_commands(&[
            "contacts count 3",
            "contact name \"Alice\"",
            "contact name \"Bob\"",
            "contact name \"Carol\"",
            "transactions count >= 5",
            "events count >= 8",
        ])
        .expect("member sees all data again (syncer restored events)");
}

/// Owner grants contact:create (and read) to all_users × all_contacts. Member creates contact and syncs.
#[test]
#[ignore]
fn permission_grant_create_then_member_can_create() {
    let server_url = test_server_url();
    let (owner_user, owner_pass, wallet_id) =
        create_unique_test_user_and_wallet(&server_url).expect("create owner");
    let owner = AppInstance::with_credentials(
        "owner",
        &server_url,
        owner_user,
        owner_pass,
        Some(wallet_id.clone()),
    );
    owner.initialize().expect("initialize");
    owner.login().expect("login");

    owner.activate().expect("owner");
    set_default_matrix_actions(
        &wallet_id,
        &[
            "contact:read",
            "contact:create",
            "contact:update",
            "contact:delete",
            "transaction:read",
            "transaction:create",
            "transaction:update",
            "transaction:delete",
            "events:read",
        ],
    )
    .expect("grant full contact/transaction to members");

    let member = AppInstance::new("member", &server_url);
    member.initialize().expect("initialize");
    member.signup().expect("member signup");
    owner.activate().expect("owner");
    add_user_to_wallet(wallet_id.clone(), member.username.clone()).expect("add member");

    let member_in_wallet = AppInstance::with_credentials(
        "member",
        &server_url,
        member.username.clone(),
        member.password.clone(),
        Some(wallet_id.clone()),
    );
    member_in_wallet.initialize().expect("initialize");
    member_in_wallet.login().expect("login");

    member_in_wallet
        .run_commands(&["contact create \"Member Created\" m1", "wait 300"])
        .expect("member create contact");
    member_in_wallet.sync().expect("member sync");
    std::thread::sleep(std::time::Duration::from_millis(300));
    member_in_wallet
        .assert_commands(&["contacts count 1", "contact name \"Member Created\""])
        .expect("member sees own contact");
}
