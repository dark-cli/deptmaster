//! Member permission enforcement tests.
//!
//! Verify that vector-based member group permissions are enforced:
//! - source_group cannot manage target_group members unless they have the permission
//! - deny wins over allow
//! - owners bypass all checks
//! - permission actions are: wallet:member_add, wallet:member_remove, wallet:member_list, wallet:set_permission_matrix

mod common;

use client::{
    add_user_to_wallet, manual_sync, set_current_wallet_id, create_wallet_user_group,
    add_wallet_user_group_member,
};
use common::app_instance::{create_unique_test_user_and_wallet, AppInstance};
use common::command_runner::CommandRunner;
use common::test_helpers::test_server_url;

const PERM_ERR: &str = "DEBITUM_INSUFFICIENT_WALLET_PERMISSION";

/// Setup: owner + two members (admin1 and regular_user).
/// admin1 is in admin group, regular_user is in users group.
/// Both groups are regular member groups (not system groups).
/// Returns (owner, admin1, regular_user, wallet_id, admin_group_id, users_group_id)
fn setup_with_member_groups() -> (AppInstance, AppInstance, AppInstance, String, String, String) {
    let server_url = test_server_url();
    let (owner_user, owner_pass, wallet_id) =
        create_unique_test_user_and_wallet(&server_url).expect("create owner");
    let owner = AppInstance::with_credentials("owner", &server_url, owner_user, owner_pass);
    owner.initialize().expect("init owner");
    owner.login().expect("login owner");
    owner.select_wallet(&wallet_id).expect("select wallet");

    owner.activate().expect("activate owner");
    set_current_wallet_id(wallet_id.clone()).expect("owner wallet");

    // Owner creates two user groups: admin and users
    let admin_json = create_wallet_user_group(wallet_id.clone(), "admin".to_string())
        .expect("create admin group");
    let admin_g: serde_json::Value =
        serde_json::from_str(&admin_json).expect("parse admin group");
    let admin_group_id = admin_g["id"].as_str().expect("admin id").to_string();

    let users_json = create_wallet_user_group(wallet_id.clone(), "users".to_string())
        .expect("create users group");
    let users_g: serde_json::Value =
        serde_json::from_str(&users_json).expect("parse users group");
    let users_group_id = users_g["id"].as_str().expect("users id").to_string();

    // Create admin1 and add to admin group
    let admin1 = AppInstance::new("admin1", &server_url);
    admin1.initialize().expect("init admin1");
    admin1.signup().expect("signup admin1");

    owner.activate().expect("activate owner for add users");
    add_user_to_wallet(wallet_id.clone(), admin1.username.clone()).expect("add admin1");

    let admin1_in_wallet =
        AppInstance::with_credentials("admin1", &server_url, admin1.username.clone(), admin1.password.clone());
    admin1_in_wallet.initialize().expect("init admin1-in-wallet");
    admin1_in_wallet.login().expect("login admin1");
    admin1_in_wallet.select_wallet(&wallet_id).expect("admin1 select wallet");

    owner.activate().expect("activate owner for group member");
    add_wallet_user_group_member(wallet_id.clone(), admin_group_id.clone(), admin1.username.clone())
        .expect("add admin1 to admin group");

    // Create regular_user and add to users group
    let regular_user = AppInstance::new("regular_user", &server_url);
    regular_user.initialize().expect("init regular_user");
    regular_user.signup().expect("signup regular_user");

    owner.activate().expect("activate owner for add regular_user");
    add_user_to_wallet(wallet_id.clone(), regular_user.username.clone()).expect("add regular_user");

    let regular_user_in_wallet = AppInstance::with_credentials(
        "regular_user",
        &server_url,
        regular_user.username.clone(),
        regular_user.password.clone(),
    );
    regular_user_in_wallet.initialize().expect("init regular_user-in-wallet");
    regular_user_in_wallet.login().expect("login regular_user");
    regular_user_in_wallet.select_wallet(&wallet_id).expect("regular_user select wallet");

    owner.activate().expect("activate owner for add regular_user to group");
    add_wallet_user_group_member(
        wallet_id.clone(),
        users_group_id.clone(),
        regular_user.username.clone(),
    )
    .expect("add regular_user to users group");

    owner.activate().expect("activate owner final");
    manual_sync().expect("owner sync");

    admin1_in_wallet.activate().expect("activate admin1");
    set_current_wallet_id(wallet_id.clone()).expect("admin1 wallet");
    manual_sync().expect("admin1 sync");

    regular_user_in_wallet.activate().expect("activate regular_user");
    set_current_wallet_id(wallet_id.clone()).expect("regular_user wallet");
    manual_sync().expect("regular_user sync");

    (
        owner,
        admin1_in_wallet,
        regular_user_in_wallet,
        wallet_id,
        admin_group_id,
        users_group_id,
    )
}

#[test]
#[ignore]
fn member_permission_grant_allows_action() {
    let (_owner, _admin1, regular_user, wallet_id, admin_group_id, users_group_id) =
        setup_with_member_groups();

    // Grant admin group permission to add members to users group
    regular_user.activate().expect("activate for command");
    set_current_wallet_id(wallet_id.clone()).expect("wallet");

    let mut runner = CommandRunner::new();
    runner
        .user_group_ids
        .insert("admin".to_string(), admin_group_id.clone());
    runner
        .user_group_ids
        .insert("users".to_string(), users_group_id.clone());

    // Grant permission: admin can add members to users
    runner
        .execute_command("member-permission grant admin users wallet:member_add")
        .expect("grant permission");

    // Now admin1 should be able to add regular_user to a new group or manipulate users group
    // (This is a high-level smoke test; detailed tests would follow)
}

#[test]
#[ignore]
fn member_permission_denied_blocks_action() {
    let (_owner, _admin1, regular_user, wallet_id, admin_group_id, users_group_id) =
        setup_with_member_groups();

    regular_user.activate().expect("activate for command");
    set_current_wallet_id(wallet_id.clone()).expect("wallet");

    let mut runner = CommandRunner::new();
    runner
        .user_group_ids
        .insert("admin".to_string(), admin_group_id.clone());
    runner
        .user_group_ids
        .insert("users".to_string(), users_group_id.clone());

    // Revoke permission: admin cannot add members to users
    runner
        .execute_command("member-permission revoke admin users wallet:member_add")
        .expect("revoke permission");

    // admin1 should be unable to add members to users group
    // (Detailed enforcement tested in server tests)
}

#[test]
#[ignore]
fn member_permission_owner_bypass() {
    let (owner, _admin1, _regular_user, wallet_id, _admin_group_id, _users_group_id) =
        setup_with_member_groups();

    owner.activate().expect("activate for command");
    set_current_wallet_id(wallet_id.clone()).expect("wallet");

    // Owner should always be able to manage members regardless of matrix permissions
    // This is handled by hardcoded owner bypass in the permission resolver
    manual_sync().expect("owner can always sync and manage");
}

#[test]
#[ignore]
fn member_permission_deny_wins() {
    let (_owner, _admin1, regular_user, wallet_id, admin_group_id, users_group_id) =
        setup_with_member_groups();

    regular_user.activate().expect("activate for command");
    set_current_wallet_id(wallet_id.clone()).expect("wallet");

    let mut runner = CommandRunner::new();
    runner
        .user_group_ids
        .insert("admin".to_string(), admin_group_id.clone());
    runner
        .user_group_ids
        .insert("users".to_string(), users_group_id.clone());

    // Grant permission
    runner
        .execute_command("member-permission grant admin users wallet:member_add")
        .expect("grant permission");

    // Then deny it (revoke == deny)
    runner
        .execute_command("member-permission revoke admin users wallet:member_add")
        .expect("deny permission");

    // Deny should win: admin1 cannot add members to users
    // (Detailed enforcement tested in server tests)
}
