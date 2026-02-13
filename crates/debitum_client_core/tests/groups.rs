//! User groups and contact groups: create, list, add members; permission matrix by (user_group × contact_group).
//!
//! Simple: CRUD on groups and membership. Complex: revoke default read, grant read only for specific
//! (user_group, contact_group); member syncs and sees only contacts in permitted contact groups.

use crate::common::app_instance::{create_unique_test_user_and_wallet, AppInstance};
use crate::common::test_helpers::test_server_url;
use debitum_client_core::{
    add_wallet_contact_group_member,
    add_wallet_user_group_member,
    add_user_to_wallet,
    clear_wallet_data,
    create_wallet_contact_group,
    create_wallet_invite_code,
    create_wallet_user_group,
    get_contacts,
    get_current_wallet_id,
    get_wallet_permission_matrix,
    join_wallet_by_code,
    list_wallet_contact_group_members,
    list_wallet_contact_groups,
    list_wallet_user_group_members,
    list_wallet_user_groups,
    put_wallet_permission_matrix,
    set_current_wallet_id,
};

fn contact_id_by_name(contacts_json: &str, name: &str) -> Result<String, String> {
    let arr: Vec<serde_json::Value> = serde_json::from_str(contacts_json).map_err(|e| e.to_string())?;
    for c in &arr {
        if c.get("name").and_then(|v| v.as_str()) == Some(name) {
            return c.get("id").and_then(|v| v.as_str()).map(String::from).ok_or_else(|| "no id".to_string());
        }
    }
    Err(format!("contact named '{}' not found", name))
}

fn group_id_by_name(groups_json: &str, name: &str) -> Result<String, String> {
    let arr: Vec<serde_json::Value> = serde_json::from_str(groups_json).map_err(|e| e.to_string())?;
    for g in &arr {
        if g.get("name").and_then(|v| v.as_str()) == Some(name) {
            return g.get("id").and_then(|v| v.as_str()).map(String::from).ok_or_else(|| "no id".to_string());
        }
    }
    Err(format!("group named '{}' not found", name))
}

fn get_default_matrix_ids(wallet_id: &str) -> Result<(String, String), String> {
    let json = get_wallet_permission_matrix(wallet_id.to_string())?;
    let arr: Vec<serde_json::Value> = serde_json::from_str(&json).map_err(|e| e.to_string())?;
    let row = arr.iter().find(|r| {
        r.get("user_group_id").is_some() && r.get("contact_group_id").is_some()
    }).ok_or("Permission matrix has no row")?;
    let ug = row["user_group_id"].as_str().ok_or("No user_group_id")?.to_string();
    let cg = row["contact_group_id"].as_str().ok_or("No contact_group_id")?.to_string();
    Ok((ug, cg))
}

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

// --- Simple: user groups ---

/// Create user group, list groups (contains it), add member, list members (contains member).
#[test]
#[ignore]
fn groups_user_group_create_list_add_member_list_members() {
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

    owner.activate().expect("owner");
    let create_res = create_wallet_user_group(wallet_id.clone(), "Editors".to_string()).expect("create user group");
    let created: serde_json::Value = serde_json::from_str(&create_res).map_err(|e| e.to_string()).expect("parse");
    let editors_id = created["id"].as_str().expect("id").to_string();

    let list_json = list_wallet_user_groups(wallet_id.clone()).expect("list user groups");
    let editors_found = group_id_by_name(&list_json, "Editors").expect("Editors in list");
    assert_eq!(editors_found, editors_id, "list should return created group");

    add_wallet_user_group_member(wallet_id.clone(), editors_id.clone(), member.username.clone())
        .expect("add member to Editors (by username)");

    let members_json = list_wallet_user_group_members(wallet_id.clone(), editors_id).expect("list members");
    let members: Vec<serde_json::Value> = serde_json::from_str(&members_json).map_err(|e| e.to_string()).expect("parse");
    assert!(!members.is_empty(), "Editors should have at least one member");
    let has_member = members.iter().any(|m| m.get("username").and_then(|v| v.as_str()) == Some(&member.username));
    assert!(has_member, "Editors members should include member username");
}

// --- Simple: contact groups ---

/// Create contact, create contact group, add contact to group, list groups and list members.
#[test]
#[ignore]
fn groups_contact_group_create_list_add_contact_list_members() {
    let server_url = test_server_url();
    let owner = AppInstance::new("owner", &server_url);
    owner.initialize().expect("initialize");
    owner.signup().expect("signup");
    owner.activate().expect("activate");
    let wallet_id = get_current_wallet_id().ok_or("no wallet").expect("wallet");

    owner
        .run_commands(&["contact create \"Alice\" alice", "wait 300"])
        .expect("create contact");
    owner.sync().expect("sync");
    let contacts_json = get_contacts().expect("get_contacts");
    let alice_id = contact_id_by_name(&contacts_json, "Alice").expect("Alice id");

    let create_res = create_wallet_contact_group(wallet_id.clone(), "VIP".to_string()).expect("create contact group");
    let created: serde_json::Value = serde_json::from_str(&create_res).map_err(|e| e.to_string()).expect("parse");
    let vip_id = created["id"].as_str().expect("id").to_string();

    let list_json = list_wallet_contact_groups(wallet_id.clone()).expect("list contact groups");
    let vip_found = group_id_by_name(&list_json, "VIP").expect("VIP in list");
    assert_eq!(vip_found, vip_id);

    add_wallet_contact_group_member(wallet_id.clone(), vip_id.clone(), alice_id.clone())
        .expect("add Alice to VIP");

    let members_json = list_wallet_contact_group_members(wallet_id.clone(), vip_id).expect("list VIP members");
    let members: Vec<serde_json::Value> = serde_json::from_str(&members_json).map_err(|e| e.to_string()).expect("parse");
    assert_eq!(members.len(), 1, "VIP should have one member");
    assert_eq!(members[0].get("contact_id").and_then(|v| v.as_str()), Some(alice_id.as_str()));
}

// --- Complex: member sees only contacts in the contact group they have read for ---

/// Revoke default all_users×all_contacts read. Create user group Viewers, contact group Public.
/// Add member to Viewers. Add only Alice to Public. Grant Viewers×Public read. Member syncs and sees only Alice.
#[test]
#[ignore]
fn groups_complex_member_sees_only_contacts_in_permitted_group() {
    let server_url = test_server_url();
    let owner = AppInstance::new("owner", &server_url);
    owner.initialize().expect("initialize");
    owner.signup().expect("signup");
    owner.activate().expect("activate");
    let wallet_id = get_current_wallet_id().ok_or("no wallet").expect("wallet");

    let (all_ug, all_cg) = get_default_matrix_ids(&wallet_id).expect("default matrix ids");
    set_matrix_actions(&wallet_id, &all_ug, &all_cg, &[]).expect("revoke default read");

    let member = AppInstance::new("member", &server_url);
    member.initialize().expect("initialize");
    member.signup().expect("member signup");
    owner.activate().expect("owner");
    add_user_to_wallet(wallet_id.clone(), member.username.clone()).expect("add member");

    let ug_res = create_wallet_user_group(wallet_id.clone(), "Viewers".to_string()).expect("create Viewers");
    let viewers_ug_id: String = serde_json::from_str::<serde_json::Value>(&ug_res).expect("parse")["id"].as_str().expect("id").to_string();
    add_wallet_user_group_member(wallet_id.clone(), viewers_ug_id.clone(), member.username.clone()).expect("add member to Viewers");

    let cg_res = create_wallet_contact_group(wallet_id.clone(), "Public".to_string()).expect("create Public");
    let public_cg_id: String = serde_json::from_str::<serde_json::Value>(&cg_res).expect("parse")["id"].as_str().expect("id").to_string();

    owner
        .run_commands(&[
            "contact create \"Alice\" alice",
            "contact create \"Bob\" bob",
            "wait 300",
        ])
        .expect("create contacts");
    owner.sync().expect("sync");
    let contacts_json = get_contacts().expect("get_contacts");
    let alice_id = contact_id_by_name(&contacts_json, "Alice").expect("Alice id");
    add_wallet_contact_group_member(wallet_id.clone(), public_cg_id.clone(), alice_id).expect("add Alice to Public (Bob stays only in all_contacts)");

    set_matrix_actions(
        &wallet_id,
        &viewers_ug_id,
        &public_cg_id,
        &["contact:read", "transaction:read", "events:read"],
    ).expect("Viewers x Public = read");

    let member_in_wallet = AppInstance::with_credentials(
        "member",
        &server_url,
        member.username.clone(),
        member.password.clone(),
        Some(wallet_id.clone()),
    );
    member_in_wallet.initialize().expect("initialize");
    member_in_wallet.login().expect("login");
    member_in_wallet.sync().expect("member sync");
    std::thread::sleep(std::time::Duration::from_millis(300));

    member_in_wallet.assert_commands(&[
        "contacts count 1",
        "contact name \"Alice\"",
    ]).expect("member sees only Alice (in Public); Bob not visible");
    // Viewers×Public is read-only: create must be denied.
    let create_res = member_in_wallet.run_commands(&["contact create \"Denied\" x"]);
    assert!(create_res.is_err(), "member with read-only on Public must not be allowed to create contact");
}

// --- Complex: two contact groups, two user groups; member in one user group sees only that group's contacts ---

/// Viewers×GroupA and Viewers×GroupB = read. GroupAOnly×GroupA = read. Alice in GroupA, Bob in GroupB.
/// Member1 in Viewers sees Alice and Bob. Member2 in GroupAOnly sees only Alice.
#[test]
#[ignore]
fn groups_complex_two_user_groups_two_contact_groups_scoped_visibility() {
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

    let (all_ug, all_cg) = get_default_matrix_ids(&wallet_id).expect("default matrix ids");
    set_matrix_actions(&wallet_id, &all_ug, &all_cg, &[]).expect("revoke default read");

    let member1 = AppInstance::new("member1", &server_url);
    member1.initialize().expect("initialize");
    member1.signup().expect("member1 signup");
    let member2 = AppInstance::new("member2", &server_url);
    member2.initialize().expect("initialize");
    member2.signup().expect("member2 signup");
    owner.activate().expect("owner");
    add_user_to_wallet(wallet_id.clone(), member1.username.clone()).expect("add member1");
    add_user_to_wallet(wallet_id.clone(), member2.username.clone()).expect("add member2");

    let ug_viewers_id: String = serde_json::from_str::<serde_json::Value>(&create_wallet_user_group(wallet_id.clone(), "Viewers".to_string()).expect("create")).expect("parse")["id"].as_str().expect("id").to_string();
    let ug_group_a_only_id: String = serde_json::from_str::<serde_json::Value>(&create_wallet_user_group(wallet_id.clone(), "GroupAOnly".to_string()).expect("create")).expect("parse")["id"].as_str().expect("id").to_string();
    add_wallet_user_group_member(wallet_id.clone(), ug_viewers_id.clone(), member1.username.clone()).expect("member1 -> Viewers");
    add_wallet_user_group_member(wallet_id.clone(), ug_group_a_only_id.clone(), member2.username.clone()).expect("member2 -> GroupAOnly");

    let cg_a_id: String = serde_json::from_str::<serde_json::Value>(&create_wallet_contact_group(wallet_id.clone(), "GroupA".to_string()).expect("create")).expect("parse")["id"].as_str().expect("id").to_string();
    let cg_b_id: String = serde_json::from_str::<serde_json::Value>(&create_wallet_contact_group(wallet_id.clone(), "GroupB".to_string()).expect("create")).expect("parse")["id"].as_str().expect("id").to_string();

    owner
        .run_commands(&[
            "contact create \"Alice\" alice",
            "contact create \"Bob\" bob",
            "wait 300",
        ])
        .expect("create contacts");
    owner.sync().expect("sync");
    let contacts_json = get_contacts().expect("get_contacts");
    let alice_id = contact_id_by_name(&contacts_json, "Alice").expect("Alice id");
    let bob_id = contact_id_by_name(&contacts_json, "Bob").expect("Bob id");
    add_wallet_contact_group_member(wallet_id.clone(), cg_a_id.clone(), alice_id).expect("Alice -> GroupA");
    add_wallet_contact_group_member(wallet_id.clone(), cg_b_id.clone(), bob_id).expect("Bob -> GroupB");

    set_matrix_actions(&wallet_id, &ug_viewers_id, &cg_a_id, &["contact:read", "transaction:read", "events:read"]).expect("Viewers x GroupA");
    set_matrix_actions(&wallet_id, &ug_viewers_id, &cg_b_id, &["contact:read", "transaction:read", "events:read"]).expect("Viewers x GroupB");
    set_matrix_actions(&wallet_id, &ug_group_a_only_id, &cg_a_id, &["contact:read", "transaction:read", "events:read"]).expect("GroupAOnly x GroupA");

    let m1 = AppInstance::with_credentials("m1", &server_url, member1.username.clone(), member1.password.clone(), Some(wallet_id.clone()));
    m1.initialize().expect("initialize");
    m1.login().expect("login");
    m1.sync().expect("sync");
    std::thread::sleep(std::time::Duration::from_millis(300));
    m1.assert_commands(&["contacts count 2", "contact name \"Alice\"", "contact name \"Bob\""]).expect("member1 (Viewers) sees Alice and Bob");
    let m1_create = m1.run_commands(&["contact create \"Denied\" x"]);
    assert!(m1_create.is_err(), "member1 (Viewers) has read-only; create must be denied");

    let m2 = AppInstance::with_credentials("m2", &server_url, member2.username.clone(), member2.password.clone(), Some(wallet_id.clone()));
    m2.initialize().expect("initialize");
    m2.login().expect("login");
    m2.sync().expect("sync");
    std::thread::sleep(std::time::Duration::from_millis(300));
    m2.assert_commands(&["contacts count 1", "contact name \"Alice\""]).expect("member2 (GroupAOnly) sees only Alice");
    let m2_create = m2.run_commands(&["contact create \"Denied\" y"]);
    assert!(m2_create.is_err(), "member2 (GroupAOnly) has read-only; create must be denied");
}

// --- Priority / union: all_users × all_contacts, different user groups × all_contacts, different × different ---

/// Baseline: all_users × all_contacts has read. Every member sees all contacts (no custom groups needed).
#[test]
#[ignore]
fn groups_priority_all_users_all_contacts_member_sees_all() {
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
    owner
        .run_commands(&[
            "contact create \"Alice\" alice",
            "contact create \"Bob\" bob",
            "wait 300",
        ])
        .expect("create contacts");
    owner.sync().expect("sync");

    let member = AppInstance::new("member", &server_url);
    member.initialize().expect("initialize");
    member.signup().expect("member signup");
    owner.activate().expect("owner");
    add_user_to_wallet(wallet_id.clone(), member.username.clone()).expect("add member");
    let member_app = AppInstance::with_credentials(
        "member",
        &server_url,
        member.username.clone(),
        member.password.clone(),
        Some(wallet_id.clone()),
    );
    member_app.initialize().expect("initialize");
    member_app.login().expect("login");
    member_app.sync().expect("sync");
    std::thread::sleep(std::time::Duration::from_millis(300));
    member_app
        .assert_commands(&["contacts count 2", "contact name \"Alice\"", "contact name \"Bob\""])
        .expect("member sees all contacts via all_users × all_contacts");
    // Default matrix is read-only: create must be denied.
    let create_res = member_app.run_commands(&["contact create \"Denied\" x"]);
    assert!(create_res.is_err(), "member with default read-only must not be allowed to create contact");
}

/// Different user group × all_contacts: revoke all_users×all_contacts, grant Viewers×all_contacts = read.
/// Only users in Viewers see all contacts.
#[test]
#[ignore]
fn groups_priority_custom_user_group_times_all_contacts_sees_all() {
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

    let (all_ug, all_cg) = get_default_matrix_ids(&wallet_id).expect("default matrix ids");
    set_matrix_actions(&wallet_id, &all_ug, &all_cg, &[]).expect("revoke all_users × all_contacts");

    let ug_viewers_id: String = serde_json::from_str::<serde_json::Value>(
        &create_wallet_user_group(wallet_id.clone(), "Viewers".to_string()).expect("create"),
    )
    .expect("parse")["id"]
        .as_str()
        .expect("id")
        .to_string();
    set_matrix_actions(
        &wallet_id,
        &ug_viewers_id,
        &all_cg,
        &["contact:read", "transaction:read", "events:read"],
    )
    .expect("Viewers × all_contacts = read");

    let member = AppInstance::new("member", &server_url);
    member.initialize().expect("initialize");
    member.signup().expect("member signup");
    owner.activate().expect("owner");
    add_user_to_wallet(wallet_id.clone(), member.username.clone()).expect("add member");
    add_wallet_user_group_member(wallet_id.clone(), ug_viewers_id, member.username.clone()).expect("member -> Viewers");

    owner
        .run_commands(&[
            "contact create \"Alice\" alice",
            "contact create \"Bob\" bob",
            "wait 300",
        ])
        .expect("create contacts");
    owner.sync().expect("sync");

    let member_app = AppInstance::with_credentials(
        "member",
        &server_url,
        member.username.clone(),
        member.password.clone(),
        Some(wallet_id.clone()),
    );
    member_app.initialize().expect("initialize");
    member_app.login().expect("login");
    member_app.sync().expect("sync");
    std::thread::sleep(std::time::Duration::from_millis(300));
    member_app
        .assert_commands(&["contacts count 2", "contact name \"Alice\"", "contact name \"Bob\""])
        .expect("member in Viewers sees all (Viewers × all_contacts)");
    // Viewers × all_contacts is read-only: create must be denied.
    let create_res = member_app.run_commands(&["contact create \"Denied\" x"]);
    assert!(create_res.is_err(), "member in Viewers with read-only must not be allowed to create contact");
}

/// Union of permissions: user in multiple user groups gets union of what each (ug × cg) grants.
/// Viewers×all_contacts=read, VIPOnly×VIP=read. Member in Viewers only sees all. Member in VIPOnly only sees VIP. Member in BOTH sees all (union).
#[test]
#[ignore]
fn groups_priority_union_multiple_user_groups_see_union_of_contact_groups() {
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

    let (all_ug, all_cg) = get_default_matrix_ids(&wallet_id).expect("default matrix ids");
    set_matrix_actions(&wallet_id, &all_ug, &all_cg, &[]).expect("revoke all_users × all_contacts");

    let ug_viewers_id: String = serde_json::from_str::<serde_json::Value>(
        &create_wallet_user_group(wallet_id.clone(), "Viewers".to_string()).expect("create"),
    )
    .expect("parse")["id"]
        .as_str()
        .expect("id")
        .to_string();
    let ug_vip_only_id: String = serde_json::from_str::<serde_json::Value>(
        &create_wallet_user_group(wallet_id.clone(), "VIPOnly".to_string()).expect("create"),
    )
    .expect("parse")["id"]
        .as_str()
        .expect("id")
        .to_string();

    let cg_vip_id: String = serde_json::from_str::<serde_json::Value>(
        &create_wallet_contact_group(wallet_id.clone(), "VIP".to_string()).expect("create"),
    )
    .expect("parse")["id"]
        .as_str()
        .expect("id")
        .to_string();

    set_matrix_actions(
        &wallet_id,
        &ug_viewers_id,
        &all_cg,
        &["contact:read", "transaction:read", "events:read"],
    )
    .expect("Viewers × all_contacts = read");
    set_matrix_actions(
        &wallet_id,
        &ug_vip_only_id,
        &cg_vip_id,
        &["contact:read", "transaction:read", "events:read"],
    )
    .expect("VIPOnly × VIP = read");

    owner
        .run_commands(&[
            "contact create \"Alice\" alice",
            "contact create \"Bob\" bob",
            "wait 300",
        ])
        .expect("create contacts");
    owner.sync().expect("sync");
    let contacts_json = get_contacts().expect("get_contacts");
    let alice_id = contact_id_by_name(&contacts_json, "Alice").expect("Alice id");
    add_wallet_contact_group_member(wallet_id.clone(), cg_vip_id.clone(), alice_id).expect("Alice -> VIP");

    let member_viewers = AppInstance::new("mv", &server_url);
    member_viewers.initialize().expect("initialize");
    member_viewers.signup().expect("signup");
    let member_vip = AppInstance::new("mvip", &server_url);
    member_vip.initialize().expect("initialize");
    member_vip.signup().expect("signup");
    let member_both = AppInstance::new("mboth", &server_url);
    member_both.initialize().expect("initialize");
    member_both.signup().expect("signup");
    owner.activate().expect("owner");
    add_user_to_wallet(wallet_id.clone(), member_viewers.username.clone()).expect("add");
    add_user_to_wallet(wallet_id.clone(), member_vip.username.clone()).expect("add");
    add_user_to_wallet(wallet_id.clone(), member_both.username.clone()).expect("add");
    add_wallet_user_group_member(wallet_id.clone(), ug_viewers_id.clone(), member_viewers.username.clone()).expect("Viewers only");
    add_wallet_user_group_member(wallet_id.clone(), ug_vip_only_id.clone(), member_vip.username.clone()).expect("VIPOnly only");
    add_wallet_user_group_member(wallet_id.clone(), ug_viewers_id.clone(), member_both.username.clone()).expect("both 1");
    add_wallet_user_group_member(wallet_id.clone(), ug_vip_only_id.clone(), member_both.username.clone()).expect("both 2");

    let app_viewers = AppInstance::with_credentials("mv", &server_url, member_viewers.username.clone(), member_viewers.password.clone(), Some(wallet_id.clone()));
    app_viewers.initialize().expect("initialize");
    app_viewers.login().expect("login");
    app_viewers.sync().expect("sync");
    std::thread::sleep(std::time::Duration::from_millis(300));
    app_viewers.assert_commands(&["contacts count 2", "contact name \"Alice\"", "contact name \"Bob\""]).expect("Viewers-only sees all");
    assert!(app_viewers.run_commands(&["contact create \"X\" x"]).is_err(), "Viewers-only has read-only; create denied");

    let app_vip = AppInstance::with_credentials("mvip", &server_url, member_vip.username.clone(), member_vip.password.clone(), Some(wallet_id.clone()));
    app_vip.initialize().expect("initialize");
    app_vip.login().expect("login");
    app_vip.sync().expect("sync");
    std::thread::sleep(std::time::Duration::from_millis(300));
    app_vip.assert_commands(&["contacts count 1", "contact name \"Alice\""]).expect("VIPOnly sees only Alice");
    assert!(app_vip.run_commands(&["contact create \"X\" x"]).is_err(), "VIPOnly has read-only; create denied");

    let app_both = AppInstance::with_credentials("mboth", &server_url, member_both.username.clone(), member_both.password.clone(), Some(wallet_id.clone()));
    app_both.initialize().expect("initialize");
    app_both.login().expect("login");
    app_both.sync().expect("sync");
    std::thread::sleep(std::time::Duration::from_millis(300));
    app_both.assert_commands(&["contacts count 2", "contact name \"Alice\"", "contact name \"Bob\""]).expect("Viewers+VIPOnly sees union = all");
    assert!(app_both.run_commands(&["contact create \"X\" x"]).is_err(), "Viewers+VIPOnly union is read-only; create denied");
}

/// Different user groups × different contact groups: Viewers×all_contacts, Editors×Staff, VIPOnly×VIP.
/// Member in Viewers sees all; in Editors sees only Staff; in VIPOnly sees only VIP; in Viewers+VIPOnly sees all (union).
#[test]
#[ignore]
fn groups_priority_different_ug_to_different_cg_scoped_and_union() {
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

    let (all_ug, all_cg) = get_default_matrix_ids(&wallet_id).expect("default matrix ids");
    set_matrix_actions(&wallet_id, &all_ug, &all_cg, &[]).expect("revoke all_users × all_contacts");

    let ug_viewers_id: String = serde_json::from_str::<serde_json::Value>(
        &create_wallet_user_group(wallet_id.clone(), "Viewers".to_string()).expect("create"),
    )
    .expect("parse")["id"]
        .as_str()
        .expect("id")
        .to_string();
    let ug_editors_id: String = serde_json::from_str::<serde_json::Value>(
        &create_wallet_user_group(wallet_id.clone(), "Editors".to_string()).expect("create"),
    )
    .expect("parse")["id"]
        .as_str()
        .expect("id")
        .to_string();
    let ug_vip_only_id: String = serde_json::from_str::<serde_json::Value>(
        &create_wallet_user_group(wallet_id.clone(), "VIPOnly".to_string()).expect("create"),
    )
    .expect("parse")["id"]
        .as_str()
        .expect("id")
        .to_string();

    let cg_staff_id: String = serde_json::from_str::<serde_json::Value>(
        &create_wallet_contact_group(wallet_id.clone(), "Staff".to_string()).expect("create"),
    )
    .expect("parse")["id"]
        .as_str()
        .expect("id")
        .to_string();
    let cg_vip_id: String = serde_json::from_str::<serde_json::Value>(
        &create_wallet_contact_group(wallet_id.clone(), "VIP".to_string()).expect("create"),
    )
    .expect("parse")["id"]
        .as_str()
        .expect("id")
        .to_string();

    set_matrix_actions(
        &wallet_id,
        &ug_viewers_id,
        &all_cg,
        &["contact:read", "transaction:read", "events:read"],
    )
    .expect("Viewers × all_contacts");
    set_matrix_actions(
        &wallet_id,
        &ug_editors_id,
        &cg_staff_id,
        &["contact:read", "transaction:read", "events:read"],
    )
    .expect("Editors × Staff");
    set_matrix_actions(
        &wallet_id,
        &ug_vip_only_id,
        &cg_vip_id,
        &["contact:read", "transaction:read", "events:read"],
    )
    .expect("VIPOnly × VIP");

    owner
        .run_commands(&[
            "contact create \"Alice\" alice",
            "contact create \"Bob\" bob",
            "contact create \"Carol\" carol",
            "wait 300",
        ])
        .expect("create contacts");
    owner.sync().expect("sync");
    let contacts_json = get_contacts().expect("get_contacts");
    let alice_id = contact_id_by_name(&contacts_json, "Alice").expect("Alice id");
    let carol_id = contact_id_by_name(&contacts_json, "Carol").expect("Carol id");
    add_wallet_contact_group_member(wallet_id.clone(), cg_vip_id.clone(), alice_id).expect("Alice -> VIP");
    add_wallet_contact_group_member(wallet_id.clone(), cg_staff_id.clone(), carol_id).expect("Carol -> Staff");

    let member_viewers = AppInstance::new("m1", &server_url);
    member_viewers.initialize().expect("initialize");
    member_viewers.signup().expect("signup");
    let member_editors = AppInstance::new("m2", &server_url);
    member_editors.initialize().expect("initialize");
    member_editors.signup().expect("signup");
    let member_vip = AppInstance::new("m3", &server_url);
    member_vip.initialize().expect("initialize");
    member_vip.signup().expect("signup");
    owner.activate().expect("owner");
    for (u, ug) in [
        (&member_viewers, &ug_viewers_id),
        (&member_editors, &ug_editors_id),
        (&member_vip, &ug_vip_only_id),
    ] {
        add_user_to_wallet(wallet_id.clone(), u.username.clone()).expect("add");
        add_wallet_user_group_member(wallet_id.clone(), ug.clone(), u.username.clone()).expect("ug");
    }

    let app_v = AppInstance::with_credentials("m1", &server_url, member_viewers.username.clone(), member_viewers.password.clone(), Some(wallet_id.clone()));
    app_v.initialize().expect("initialize");
    app_v.login().expect("login");
    app_v.sync().expect("sync");
    std::thread::sleep(std::time::Duration::from_millis(300));
    app_v.assert_commands(&["contacts count 3", "contact name \"Alice\"", "contact name \"Bob\"", "contact name \"Carol\""]).expect("Viewers sees all");
    assert!(app_v.run_commands(&["contact create \"X\" x"]).is_err(), "Viewers has read-only; create denied");

    let app_e = AppInstance::with_credentials("m2", &server_url, member_editors.username.clone(), member_editors.password.clone(), Some(wallet_id.clone()));
    app_e.initialize().expect("initialize");
    app_e.login().expect("login");
    app_e.sync().expect("sync");
    std::thread::sleep(std::time::Duration::from_millis(300));
    app_e.assert_commands(&["contacts count 1", "contact name \"Carol\""]).expect("Editors sees only Staff (Carol)");
    assert!(app_e.run_commands(&["contact create \"X\" x"]).is_err(), "Editors has read-only; create denied");

    let app_vip = AppInstance::with_credentials("m3", &server_url, member_vip.username.clone(), member_vip.password.clone(), Some(wallet_id.clone()));
    app_vip.initialize().expect("initialize");
    app_vip.login().expect("login");
    app_vip.sync().expect("sync");
    std::thread::sleep(std::time::Duration::from_millis(300));
    app_vip.assert_commands(&["contacts count 1", "contact name \"Alice\""]).expect("VIPOnly sees only VIP (Alice)");
    assert!(app_vip.run_commands(&["contact create \"X\" x"]).is_err(), "VIPOnly has read-only; create denied");
}

/// Two apps: app1 creates wallet, contacts, transactions; sets all_users×all_contacts = none; app2 joins via invite.
/// App2 sees nothing and cannot create. Then app1 creates a contact group, adds some (not all) contacts, grants
/// all_users full actions on that contact group; app2 syncs (after clear for full pull) and sees only those contacts.
#[test]
#[ignore]
fn groups_two_apps_join_with_no_default_then_grant_via_contact_group() {
    let server_url = test_server_url();

    let app1 = AppInstance::new("app1", &server_url);
    app1.initialize().expect("initialize");
    app1.signup().expect("signup");
    app1.activate().expect("activate");
    let wallet_id = get_current_wallet_id().ok_or("no wallet").expect("wallet");

    let app2 = AppInstance::new("app2", &server_url);
    app2.initialize().expect("initialize");
    app2.signup().expect("signup");

    app1.activate().expect("app1");
    app1
        .run_commands(&[
            "contact create \"Alice\" alice",
            "contact create \"Bob\" bob",
            "contact create \"Carol\" carol",
            "transaction create alice owed 100 \"T1\" t1",
            "transaction create bob lent 50 \"T2\" t2",
            "wait 300",
        ])
        .expect("app1 create contacts and transactions");
    app1.sync().expect("app1 sync");

    let (all_ug, all_cg) = get_default_matrix_ids(&wallet_id).expect("matrix ids");
    set_matrix_actions(&wallet_id, &all_ug, &all_cg, &[]).expect("all_users × all_contacts = none");

    let code = create_wallet_invite_code(wallet_id.clone()).expect("create invite code");
    app2.activate().expect("app2");
    app2.login().expect("app2 login");
    let joined_wallet_id = join_wallet_by_code(code).expect("app2 join wallet");
    set_current_wallet_id(joined_wallet_id.clone()).expect("app2 switch to joined wallet");
    assert_eq!(joined_wallet_id, wallet_id, "joined wallet is app1's wallet");

    let app2_in_wallet = AppInstance::with_credentials(
        "app2",
        &server_url,
        app2.username.clone(),
        app2.password.clone(),
        Some(wallet_id.clone()),
    );
    app2_in_wallet.initialize().expect("initialize");
    app2_in_wallet.login().expect("login");
    app2_in_wallet.sync().expect("app2 sync");
    std::thread::sleep(std::time::Duration::from_millis(300));

    app2_in_wallet
        .assert_commands(&["contacts count 0"])
        .expect("app2 sees no contacts (all_users × all_contacts = none)");
    let create_res = app2_in_wallet.run_commands(&["contact create \"Forbidden\" x"]);
    assert!(create_res.is_err(), "app2 cannot create contact when no permissions");

    app1.activate().expect("app1");
    let cg_shared_id: String = serde_json::from_str::<serde_json::Value>(
        &create_wallet_contact_group(wallet_id.clone(), "Shared".to_string()).expect("create contact group"),
    )
    .expect("parse")["id"]
        .as_str()
        .expect("id")
        .to_string();
    let contacts_json = get_contacts().expect("get_contacts");
    let alice_id = contact_id_by_name(&contacts_json, "Alice").expect("Alice id");
    let bob_id = contact_id_by_name(&contacts_json, "Bob").expect("Bob id");
    add_wallet_contact_group_member(wallet_id.clone(), cg_shared_id.clone(), alice_id).expect("Alice -> Shared");
    add_wallet_contact_group_member(wallet_id.clone(), cg_shared_id.clone(), bob_id).expect("Bob -> Shared");
    set_matrix_actions(
        &wallet_id,
        &all_ug,
        &cg_shared_id,
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
    .expect("all_users × Shared = full actions");

    std::thread::sleep(std::time::Duration::from_millis(500));
    app2_in_wallet.activate().expect("app2");
    clear_wallet_data(wallet_id.clone()).expect("clear app2 local data so full pull fetches Shared contacts");
    app2_in_wallet.sync().expect("app2 sync after grant (full pull)");
    std::thread::sleep(std::time::Duration::from_millis(300));
    app2_in_wallet
        .assert_commands(&[
            "contacts count 2",
            "contact name \"Alice\"",
            "contact name \"Bob\"",
        ])
        .expect("app2 sees only contacts in Shared and can read them (permission granted)");
    // all_users × Shared has full actions (including contact:create): app2 must be allowed to create contact.
    app2_in_wallet
        .run_commands(&["contact create \"ByApp2\" app2c", "wait 300"])
        .expect("app2 with full on Shared can create contact");
    app2_in_wallet.sync().expect("app2 sync after create");
    std::thread::sleep(std::time::Duration::from_millis(300));
    app2_in_wallet
        .assert_commands(&["contacts count 3", "contact name \"ByApp2\""])
        .expect("app2 sees own created contact");
}
