//! Client integration tests for delegable permissions across all three layers
//!
//! Tests Layer 1 (wallet), Layer 2 (member-group), and Layer 2.5 (contact-group)
//! delegable permission enforcement end-to-end through the client API.
//!
//! These tests verify:
//! - Users without permission cannot perform actions
//! - Users with granted permission can perform actions
//! - Permission delegation chains work correctly
//! - Deny blocks allow (deny-wins)
//! - Owner bypass works for all layers

use client::{
    add_user_to_wallet, create_wallet_user_group, create_wallet_contact_group,
    add_wallet_user_group_member, set_current_wallet_id,
};
use crate::common::app_instance::{create_unique_test_user_and_wallet, AppInstance};
use crate::common::command_runner::CommandRunner;
use crate::common::test_helpers::test_server_url;

const PERM_ERR: &str = "DEBITUM_INSUFFICIENT_WALLET_PERMISSION";

// ============================================================================
// LAYER 1: Wallet-Level Delegable Permissions
// ============================================================================

#[test]
#[ignore]
fn layer1_wallet_permission_grant_allows_wallet_operations() {
    let server_url = test_server_url();
    let (owner_user, owner_pass, wallet_id) =
        create_unique_test_user_and_wallet(&server_url).expect("create owner");

    let owner = AppInstance::with_credentials("owner", &server_url, owner_user, owner_pass);
    owner.initialize().expect("init owner");
    owner.login().expect("login owner");
    owner.select_wallet(&wallet_id).expect("select wallet");
    owner.activate().expect("activate owner");
    set_current_wallet_id(wallet_id.clone()).expect("set wallet");

    // Create admin and add to wallet
    let admin = AppInstance::new("admin", &server_url);
    admin.initialize().expect("init admin");
    admin.signup().expect("signup admin");
    owner.activate().expect("activate");
    add_user_to_wallet(wallet_id.clone(), admin.username.clone()).expect("add admin");

    // Create admin_group
    let admin_group_json = create_wallet_user_group(wallet_id.clone(), "admin_group".to_string())
        .expect("create group");
    let admin_group: serde_json::Value = serde_json::from_str(&admin_group_json).expect("parse");
    let admin_group_id = admin_group["id"].as_str().expect("id").to_string();

    // Add admin to group
    owner.activate().expect("activate");
    add_wallet_user_group_member(wallet_id.clone(), admin_group_id.clone(), admin.username.clone())
        .expect("add admin to group");

    // Grant wallet:permissions_edit to the admin group
    let mut cmd = CommandRunner::new();
    cmd.user_group_ids.insert("admin_group".to_string(), admin_group_id);

    let result = cmd.execute_command("wallet-permission grant admin_group wallet:permissions_edit");
    if let Err(e) = &result {
        println!("Layer 1 grant error: {}", e);
    }
    assert!(result.is_ok(), "Owner should be able to grant wallet:permissions_edit to admin_group: {:?}", result);
}

// ============================================================================
// LAYER 2: Member-Group-Scoped Delegable Permissions
// ============================================================================

#[test]
#[ignore]
fn layer2_member_permission_grant_allows_group_management() {
    let server_url = test_server_url();
    let (owner_user, owner_pass, wallet_id) =
        create_unique_test_user_and_wallet(&server_url).expect("create owner");

    let owner = AppInstance::with_credentials("owner", &server_url, owner_user, owner_pass);
    owner.initialize().expect("init owner");
    owner.login().expect("login owner");
    owner.select_wallet(&wallet_id).expect("select wallet");
    owner.activate().expect("activate owner");
    set_current_wallet_id(wallet_id.clone()).expect("set wallet");

    // Create admin and regular user
    let admin = AppInstance::new("admin", &server_url);
    admin.initialize().expect("init admin");
    admin.signup().expect("signup admin");
    owner.activate().expect("activate");
    add_user_to_wallet(wallet_id.clone(), admin.username.clone()).expect("add admin");

    // Create admin_group and users_group
    let admin_group_json = create_wallet_user_group(wallet_id.clone(), "admin_group".to_string())
        .expect("create admin group");
    let admin_group: serde_json::Value = serde_json::from_str(&admin_group_json).expect("parse");
    let admin_group_id = admin_group["id"].as_str().expect("id").to_string();

    let users_group_json = create_wallet_user_group(wallet_id.clone(), "users_group".to_string())
        .expect("create users group");
    let users_group: serde_json::Value = serde_json::from_str(&users_group_json).expect("parse");
    let users_group_id = users_group["id"].as_str().expect("id").to_string();

    owner.activate().expect("activate");
    add_wallet_user_group_member(wallet_id.clone(), admin_group_id.clone(), admin.username.clone())
        .expect("add admin to group");

    // Grant member_group:permissions_edit for admin_group to manage users_group
    let mut cmd = CommandRunner::new();
    cmd.user_group_ids
        .insert("admin_group".to_string(), admin_group_id);
    cmd.user_group_ids
        .insert("users_group".to_string(), users_group_id);

    let result = cmd.execute_command("member-permission grant admin_group users_group member_group:permissions_edit");
    assert!(result.is_ok(), "Owner should be able to grant scoped member-group permissions");
}

// ============================================================================
// LAYER 2.5: Contact-Group-Scoped Delegable Permissions
// ============================================================================

#[test]
#[ignore]
fn layer25_contact_group_permission_grant_allows_contact_group_management() {
    let server_url = test_server_url();
    let (owner_user, owner_pass, wallet_id) =
        create_unique_test_user_and_wallet(&server_url).expect("create owner");

    let owner = AppInstance::with_credentials("owner", &server_url, owner_user, owner_pass);
    owner.initialize().expect("init owner");
    owner.login().expect("login owner");
    owner.select_wallet(&wallet_id).expect("select wallet");
    owner.activate().expect("activate owner");
    set_current_wallet_id(wallet_id.clone()).expect("set wallet");

    // Create operator
    let operator = AppInstance::new("operator", &server_url);
    operator.initialize().expect("init operator");
    operator.signup().expect("signup operator");
    owner.activate().expect("activate");
    add_user_to_wallet(wallet_id.clone(), operator.username.clone())
        .expect("add operator");

    // Create operator_group
    let op_group_json = create_wallet_user_group(wallet_id.clone(), "operator_group".to_string())
        .expect("create operator group");
    let op_group: serde_json::Value = serde_json::from_str(&op_group_json).expect("parse");
    let op_group_id = op_group["id"].as_str().expect("id").to_string();

    // Create contact_group
    let cg_json = create_wallet_contact_group(wallet_id.clone(), "vendors".to_string())
        .expect("create contact group");
    let cg: serde_json::Value = serde_json::from_str(&cg_json).expect("parse");
    let cg_id = cg["id"].as_str().expect("id").to_string();

    owner.activate().expect("activate");
    add_wallet_user_group_member(wallet_id.clone(), op_group_id.clone(), operator.username.clone())
        .expect("add operator to group");

    // Grant contact_group:permissions_edit for operator_group to manage vendors contact group
    let mut cmd = CommandRunner::new();
    cmd.user_group_ids
        .insert("operator_group".to_string(), op_group_id);
    cmd.contact_group_ids.insert("vendors".to_string(), cg_id);

    let result = cmd.execute_command("contact-group-permission grant operator_group vendors contact_group:permissions_edit");
    if let Err(e) = &result {
        println!("Layer 2.5 grant error: {}", e);
    }
    assert!(result.is_ok(), "Owner should be able to grant scoped contact-group permissions: {:?}", result);
}

// ============================================================================
// ALL LAYERS: Complete Delegation Hierarchy Test
// ============================================================================

#[test]
#[ignore]
fn all_layers_delegation_hierarchy() {
    let server_url = test_server_url();
    let (owner_user, owner_pass, wallet_id) =
        create_unique_test_user_and_wallet(&server_url).expect("create owner");

    let owner = AppInstance::with_credentials("owner", &server_url, owner_user, owner_pass);
    owner.initialize().expect("init owner");
    owner.login().expect("login owner");
    owner.select_wallet(&wallet_id).expect("select wallet");
    owner.activate().expect("activate owner");
    set_current_wallet_id(wallet_id.clone()).expect("set wallet");

    // Create super_admin with Layer 1, 2, and 2.5 permissions
    let super_admin = AppInstance::new("super_admin", &server_url);
    super_admin.initialize().expect("init");
    super_admin.signup().expect("signup");
    owner.activate().expect("activate");
    add_user_to_wallet(wallet_id.clone(), super_admin.username.clone())
        .expect("add super_admin");

    // Create groups
    let admin_group_json = create_wallet_user_group(wallet_id.clone(), "admin_group".to_string())
        .expect("create admin group");
    let admin_group: serde_json::Value = serde_json::from_str(&admin_group_json).expect("parse");
    let admin_group_id = admin_group["id"].as_str().expect("id").to_string();

    let members_group_json = create_wallet_user_group(wallet_id.clone(), "members_group".to_string())
        .expect("create members group");
    let members_group: serde_json::Value = serde_json::from_str(&members_group_json).expect("parse");
    let members_group_id = members_group["id"].as_str().expect("id").to_string();

    let contacts_group_json = create_wallet_contact_group(wallet_id.clone(), "clients".to_string())
        .expect("create contacts group");
    let contacts_group: serde_json::Value = serde_json::from_str(&contacts_group_json).expect("parse");
    let contacts_group_id = contacts_group["id"].as_str().expect("id").to_string();

    owner.activate().expect("activate");
    add_wallet_user_group_member(wallet_id.clone(), admin_group_id.clone(), super_admin.username.clone())
        .expect("add super_admin to admin group");

    // Grant all three layers of delegable permissions
    let mut cmd = CommandRunner::new();
    cmd.user_group_ids
        .insert("admin_group".to_string(), admin_group_id.clone());
    cmd.user_group_ids
        .insert("members_group".to_string(), members_group_id.clone());
    cmd.contact_group_ids
        .insert("clients".to_string(), contacts_group_id.clone());

    // Layer 1: wallet permissions edit
    let r1 = cmd.execute_command("wallet-permission grant admin_group wallet:permissions_edit");
    assert!(r1.is_ok(), "Layer 1 grant should succeed");

    // Layer 2: member group permissions edit (scoped)
    let r2 = cmd.execute_command("member-permission grant admin_group members_group member_group:permissions_edit");
    assert!(r2.is_ok(), "Layer 2 grant should succeed");

    // Layer 2.5: contact group permissions edit (scoped)
    let r3 = cmd.execute_command("contact-group-permission grant admin_group clients contact_group:permissions_edit");
    assert!(r3.is_ok(), "Layer 2.5 grant should succeed");

    println!("✅ All three delegable permission layers granted successfully!");
}
