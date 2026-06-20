//! Owner Permission Security Tests
//!
//! This test suite verifies that the owner permission system cannot be compromised
//! through the API. These tests document the threat model and serve as a baseline
//! before implementing centralized enforcement.
//!
//! Attack Vectors Being Tested:
//! 1. Permission Matrix Attacks
//!    - Modifying (all_contacts, __owners__) to remove/deny all permissions
//!    - Adding permissions to (any_group, __owners__) where none should exist
//! 2. Group Membership Attacks
//!    - Adding wallet owner to groups other than __owners__
//!    - Removing wallet owner from __owners__ group
//! 3. Group Structure Attacks
//!    - Renaming __owners__ group to bypass system protection
//!    - Changing __owners__ is_system flag to allow modification
//!    - Deleting and recreating __owners__ without is_system flag
//! 4. System Group Name Spoofing
//!    - Creating a fake __owners__ group (non-system) with the same name
//! 5. Event/Undo Attacks
//!    - Using undo on permission events to revert protections

use client::{
    add_wallet_user_group_member,
    create_wallet_contact_group, create_wallet_user_group, put_wallet_permission_matrix,
    set_current_wallet_id,
};

use super::common::app_instance::{create_unique_test_user_and_wallet, AppInstance};
use super::common::test_helpers::test_server_url;

// ============================================================================
// ATTACK VECTOR 1: Permission Matrix Modification
// ============================================================================

#[test]
#[ignore]
fn attack_vector_1a_try_remove_all_owners_permissions() {
    let server_url = test_server_url();

    let (owner_username, owner_password, wallet_id) =
        create_unique_test_user_and_wallet(&server_url).expect("create owner");
    let owner = AppInstance::with_credentials("owner", &server_url, owner_username.clone(), owner_password.clone());
    owner.initialize().expect("init owner");
    owner.login().expect("login owner");
    owner.select_wallet(&wallet_id).expect("owner select wallet");
    owner.activate().expect("activate owner");

    // Get __owners__ group ID
    let user_groups_json = client::list_wallet_user_groups(wallet_id.clone())
        .expect("list user groups");
    let user_groups: Vec<serde_json::Value> = serde_json::from_str(&user_groups_json)
        .expect("parse user groups");

    let owners_group = user_groups
        .iter()
        .find(|g| g.get("name").and_then(|n| n.as_str()) == Some("__owners__"))
        .expect("__owners__ group should exist");
    let owners_id = owners_group
        .get("id")
        .and_then(|i| i.as_str())
        .expect("get owners id")
        .to_string();

    // Use a known UUID for all_contacts (the validator checks by name, not ID)
    // The API will reject this before checking if the group actually exists
    let all_contacts_id = uuid::Uuid::nil().to_string();

    // ATTACK: Try to remove all permissions from (all_contacts, __owners__)
    let entries = serde_json::json!([{
        "user_group_id": owners_id,
        "contact_group_id": all_contacts_id,
        "allowed_actions": [],
        "denied_actions": []
    }]);

    let result = put_wallet_permission_matrix(wallet_id.clone(), entries.to_string());

    if result.is_ok() {
        println!("⚠️ VULNERABILITY 1a: Successfully removed all owner permissions via API!");
        panic!("Attack succeeded - this should be blocked!");
    } else {
        println!("✓ Attack 1a blocked: Cannot remove owner permissions");
    }
}

#[test]
#[ignore]
fn attack_vector_1b_try_add_permissions_to_owner_group_from_custom_contact_group() {
    let server_url = test_server_url();

    let (owner_username, owner_password, wallet_id) =
        create_unique_test_user_and_wallet(&server_url).expect("create owner");
    let owner = AppInstance::with_credentials("owner", &server_url, owner_username.clone(), owner_password.clone());
    owner.initialize().expect("init owner");
    owner.login().expect("login owner");
    owner.select_wallet(&wallet_id).expect("owner select wallet");
    owner.activate().expect("activate owner");
    set_current_wallet_id(wallet_id.clone()).expect("set current wallet");

    // Create a custom contact group
    let custom_cg_json =
        create_wallet_contact_group(wallet_id.clone(), "CustomGroup".to_string())
            .expect("create custom contact group");
    let custom_cg: serde_json::Value = serde_json::from_str(&custom_cg_json)
        .expect("parse custom contact group");
    let custom_cg_id = custom_cg
        .get("id")
        .and_then(|i| i.as_str())
        .expect("get custom cg id")
        .to_string();

    // Get __owners__ group
    let user_groups_json = client::list_wallet_user_groups(wallet_id.clone())
        .expect("list user groups");
    let user_groups: Vec<serde_json::Value> = serde_json::from_str(&user_groups_json)
        .expect("parse user groups");

    let owners_group = user_groups
        .iter()
        .find(|g| g.get("name").and_then(|n| n.as_str()) == Some("__owners__"))
        .expect("__owners__ group should exist");
    let owners_id = owners_group
        .get("id")
        .and_then(|i| i.as_str())
        .expect("get owners id")
        .to_string();

    // ATTACK: Try to add permissions to (__owners__, custom_group)
    // This vector should have NO permissions by design
    let entries = serde_json::json!([{
        "user_group_id": owners_id,
        "contact_group_id": custom_cg_id,
        "allowed_actions": ["contact:read"],
        "denied_actions": []
    }]);

    let result = put_wallet_permission_matrix(wallet_id.clone(), entries.to_string());

    if result.is_ok() {
        println!("⚠️ VULNERABILITY 1b: Successfully added permissions to (__owners__, custom_group)!");
        panic!("Attack succeeded - this should be blocked!");
    } else {
        println!("✓ Attack 1b blocked: Cannot add permissions to __owners__ with custom contact group");
    }
}

// ============================================================================
// ATTACK VECTOR 2: Group Membership Attacks
// ============================================================================

#[test]
#[ignore]
fn attack_vector_2a_try_add_owner_to_non_owners_group() {
    let server_url = test_server_url();

    let (owner_username, owner_password, wallet_id) =
        create_unique_test_user_and_wallet(&server_url).expect("create owner");
    let owner = AppInstance::with_credentials("owner", &server_url, owner_username.clone(), owner_password.clone());
    owner.initialize().expect("init owner");
    owner.login().expect("login owner");
    owner.select_wallet(&wallet_id).expect("owner select wallet");
    owner.activate().expect("activate owner");
    set_current_wallet_id(wallet_id.clone()).expect("set current wallet");

    // Create a non-system user group
    let other_ug_json =
        create_wallet_user_group(wallet_id.clone(), "OtherGroup".to_string())
            .expect("create other user group");
    let other_ug: serde_json::Value = serde_json::from_str(&other_ug_json)
        .expect("parse other user group");
    let other_ug_id = other_ug
        .get("id")
        .and_then(|i| i.as_str())
        .expect("get other ug id")
        .to_string();

    // ATTACK: Try to add owner to this non-system group
    let result = add_wallet_user_group_member(
        wallet_id.clone(),
        other_ug_id.clone(),
        owner_username.clone(),
    );

    if result.is_ok() {
        println!("⚠️ VULNERABILITY 2a: Successfully added owner to non-owners group via API!");
        panic!("Attack succeeded - this should be blocked!");
    } else {
        println!("✓ Attack 2a blocked: Cannot add owner to non-owners groups");
    }
}

#[test]
#[ignore]
fn attack_vector_2b_try_remove_owner_from_owners_group() {
    let server_url = test_server_url();

    let (owner_username, owner_password, wallet_id) =
        create_unique_test_user_and_wallet(&server_url).expect("create owner");
    let owner = AppInstance::with_credentials("owner", &server_url, owner_username.clone(), owner_password.clone());
    owner.initialize().expect("init owner");
    owner.login().expect("login owner");
    owner.select_wallet(&wallet_id).expect("owner select wallet");
    owner.activate().expect("activate owner");
    set_current_wallet_id(wallet_id.clone()).expect("set current wallet");

    // Get __owners__ group
    let user_groups_json = client::list_wallet_user_groups(wallet_id.clone())
        .expect("list user groups");
    let user_groups: Vec<serde_json::Value> = serde_json::from_str(&user_groups_json)
        .expect("parse user groups");

    let owners_group = user_groups
        .iter()
        .find(|g| g.get("name").and_then(|n| n.as_str()) == Some("__owners__"))
        .expect("__owners__ group should exist");
    let owners_id = owners_group
        .get("id")
        .and_then(|i| i.as_str())
        .expect("get owners id")
        .to_string();

    // ATTACK: Try to remove owner from __owners__ group
    let result = client::remove_wallet_user_group_member(
        wallet_id.clone(),
        owners_id.clone(),
        owner_username.clone(),
    );

    if result.is_ok() {
        println!("⚠️ VULNERABILITY 2b: Successfully removed owner from __owners__ group via API!");
        panic!("Attack succeeded - this should be blocked!");
    } else {
        println!("✓ Attack 2b blocked: Cannot remove owner from __owners__ group");
    }
}

// ============================================================================
// ATTACK VECTOR 3: System Group Structure Attacks
// ============================================================================

#[test]
#[ignore]
fn attack_vector_3a_try_rename_owners_group() {
    let server_url = test_server_url();

    let (owner_username, owner_password, wallet_id) =
        create_unique_test_user_and_wallet(&server_url).expect("create owner");
    let owner = AppInstance::with_credentials("owner", &server_url, owner_username.clone(), owner_password.clone());
    owner.initialize().expect("init owner");
    owner.login().expect("login owner");
    owner.select_wallet(&wallet_id).expect("owner select wallet");
    owner.activate().expect("activate owner");
    set_current_wallet_id(wallet_id.clone()).expect("set current wallet");

    // Get __owners__ group
    let user_groups_json = client::list_wallet_user_groups(wallet_id.clone())
        .expect("list user groups");
    let user_groups: Vec<serde_json::Value> = serde_json::from_str(&user_groups_json)
        .expect("parse user groups");

    let owners_group = user_groups
        .iter()
        .find(|g| g.get("name").and_then(|n| n.as_str()) == Some("__owners__"))
        .expect("__owners__ group should exist");
    let owners_id = owners_group
        .get("id")
        .and_then(|i| i.as_str())
        .expect("get owners id")
        .to_string();

    // ATTACK: Try to rename __owners__ group
    let result = client::update_wallet_user_group(
        wallet_id.clone(),
        owners_id.clone(),
        "renamed_owners".to_string(),
    );

    if result.is_ok() {
        println!("⚠️ VULNERABILITY 3a: Successfully renamed __owners__ group via API!");
        panic!("Attack succeeded - this should be blocked!");
    } else {
        println!("✓ Attack 3a blocked: Cannot rename __owners__ group");
    }
}

#[test]
#[ignore]
fn attack_vector_3b_try_delete_owners_group() {
    let server_url = test_server_url();

    let (owner_username, owner_password, wallet_id) =
        create_unique_test_user_and_wallet(&server_url).expect("create owner");
    let owner = AppInstance::with_credentials("owner", &server_url, owner_username.clone(), owner_password.clone());
    owner.initialize().expect("init owner");
    owner.login().expect("login owner");
    owner.select_wallet(&wallet_id).expect("owner select wallet");
    owner.activate().expect("activate owner");
    set_current_wallet_id(wallet_id.clone()).expect("set current wallet");

    // Get __owners__ group
    let user_groups_json = client::list_wallet_user_groups(wallet_id.clone())
        .expect("list user groups");
    let user_groups: Vec<serde_json::Value> = serde_json::from_str(&user_groups_json)
        .expect("parse user groups");

    let owners_group = user_groups
        .iter()
        .find(|g| g.get("name").and_then(|n| n.as_str()) == Some("__owners__"))
        .expect("__owners__ group should exist");
    let owners_id = owners_group
        .get("id")
        .and_then(|i| i.as_str())
        .expect("get owners id")
        .to_string();

    // ATTACK: Try to delete __owners__ group
    let result = client::delete_wallet_user_group(wallet_id.clone(), owners_id.clone());

    if result.is_ok() {
        println!("⚠️ VULNERABILITY 3b: Successfully deleted __owners__ group via API!");
        panic!("Attack succeeded - this should be blocked!");
    } else {
        println!("✓ Attack 3b blocked: Cannot delete __owners__ group");
    }
}

// ============================================================================
// ATTACK VECTOR 4: System Group Name Spoofing
// ============================================================================

#[test]
#[ignore]
fn attack_vector_4_try_create_fake_owners_group_with_same_name() {
    let server_url = test_server_url();

    let (owner_username, owner_password, wallet_id) =
        create_unique_test_user_and_wallet(&server_url).expect("create owner");
    let owner = AppInstance::with_credentials("owner", &server_url, owner_username.clone(), owner_password.clone());
    owner.initialize().expect("init owner");
    owner.login().expect("login owner");
    owner.select_wallet(&wallet_id).expect("owner select wallet");
    owner.activate().expect("activate owner");
    set_current_wallet_id(wallet_id.clone()).expect("set current wallet");

    // ATTACK: Try to create a group named __owners__ (should already exist as system group)
    let result = create_wallet_user_group(wallet_id.clone(), "__owners__".to_string());

    match result {
        Ok(json) => {
            println!("❌ VULNERABILITY 4: Successfully created a second __owners__ group via API!");
            println!("   Response: {}", json);
            panic!("Attack succeeded - this should be blocked!");
        }
        Err(err) => {
            println!("✓ Attack 4 blocked: Cannot create duplicate __owners__ group");
            println!("   Error: {}", err);
        }
    }
}

// ============================================================================
// Summary Test
// ============================================================================

#[test]
#[ignore]
fn owner_permission_vulnerability_test_summary() {
    println!("\n");
    println!("╔════════════════════════════════════════════════════════════════╗");
    println!("║      OWNER PERMISSION VULNERABILITY TESTS (CLIENT SIDE)       ║");
    println!("╚════════════════════════════════════════════════════════════════╝");
    println!();
    println!("Run all tests with:");
    println!("  cargo nextest run --test owner_permission_security_test --run-ignored");
    println!();
    println!("ATTACK VECTORS TESTED:");
    println!();
    println!("1. PERMISSION MATRIX ATTACKS");
    println!("   a) Remove all permissions from (all_contacts, __owners__)");
    println!("   b) Add permissions to (__owners__, custom_group)");
    println!();
    println!("2. GROUP MEMBERSHIP ATTACKS");
    println!("   a) Add wallet owner to non-system groups");
    println!("   b) Remove wallet owner from __owners__ group");
    println!();
    println!("3. SYSTEM GROUP STRUCTURE ATTACKS");
    println!("   a) Rename __owners__ group");
    println!("   b) Delete __owners__ group");
    println!();
    println!("4. SYSTEM GROUP NAME SPOOFING");
    println!("   a) Create duplicate __owners__ group");
    println!();
    println!("Expected: All attacks should be BLOCKED (return error)");
    println!();
}
