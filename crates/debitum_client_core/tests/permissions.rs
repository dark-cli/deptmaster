//! Permissions and groups: give/take permissions, permission limits (deny/union/scoped), user/contact groups.
//!
//! Use permission commands (grant-read, revoke-all, grant-full) for default matrix; set_matrix_actions for custom (ug × cg).
//! Single quotes, member.sync() after permission/group changes. See docs/INTEGRATION_TEST_COMMANDS.md.

use crate::common::app_instance::{create_unique_test_user_and_wallet, AppInstance};
use crate::common::test_helpers::test_server_url;
use debitum_client_core::{
    add_user_to_wallet,
    add_wallet_contact_group_member,
    add_wallet_user_group_member,
    clear_wallet_data,
    create_contact,
    create_wallet_contact_group,
    create_wallet_invite_code,
    create_wallet_user_group,
    delete_contact,
    get_contacts,
    get_contacts_from_server,
    get_wallet_permission_matrix,
    join_wallet_by_code,
    list_wallet_contact_group_members,
    list_wallet_contact_groups,
    list_wallet_user_group_members,
    list_wallet_user_groups,
    put_wallet_permission_matrix,
    set_current_wallet_id,
    update_contact,
};

// --- Shared helpers ---

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
    let row = arr
        .iter()
        .find(|r| r.get("user_group_id").is_some() && r.get("contact_group_id").is_some())
        .ok_or("Permission matrix has no row")?;
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

fn get_user_group_id(wallet_id: &str, name: &str) -> Result<String, String> {
    let json = list_wallet_user_groups(wallet_id.to_string())?;
    group_id_by_name(&json, name)
}

fn get_contact_group_id(wallet_id: &str, name: &str) -> Result<String, String> {
    let json = list_wallet_contact_groups(wallet_id.to_string())?;
    group_id_by_name(&json, name)
}

fn set_permission_matrix_allowed_denied(
    wallet_id: &str,
    user_group_id: &str,
    contact_group_id: &str,
    allowed: Vec<String>,
    denied: Vec<String>,
) -> Result<(), String> {
    let entry = serde_json::json!({
        "user_group_id": user_group_id,
        "contact_group_id": contact_group_id,
        "allowed_actions": allowed,
        "denied_actions": denied
    });
    let entries = serde_json::json!([entry]);
    put_wallet_permission_matrix(wallet_id.to_string(), entries.to_string())
}

// --- Permission: give/take and grant full ---

/// Owner creates contact; member has default read → sees contact. Owner revokes read → member syncs, sees none. Owner grants read again → member sees contact.
#[test]
#[ignore]
fn permission_give_take_read_member_sees_then_loses_then_sees() {
    let server_url = test_server_url();
    let owner = AppInstance::new("owner", &server_url);
    owner.initialize().expect("initialize");
    owner.signup().expect("signup");
    owner.login().expect("login");
    let wallet_id = owner.create_wallet("Test Wallet".to_string(), "".to_string()).expect("create_wallet");

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
    );
    member_in_wallet.initialize().expect("initialize");
    member_in_wallet.login().expect("login");
    member_in_wallet.select_wallet(&wallet_id).expect("select_wallet");

    owner.activate().expect("owner");
    owner
        .run_commands(&["contact create 'Shared Contact' shared", "wait 300"])
        .expect("owner create contact");
    std::thread::sleep(std::time::Duration::from_millis(300));
    member_in_wallet.sync().expect("member sync to pull contact");
    member_in_wallet
        .assert_commands(&["contacts count 1", "contact name 'Shared Contact'"])
        .expect("member sees contact after grant");
    let create_res = member_in_wallet.run_commands(&["contact create 'ByMember' m2"]);
    assert!(create_res.is_err(), "member with read-only must not be allowed to create contact");
    let create_err = create_res.unwrap_err();
    assert!(create_err.contains("403") || create_err.to_lowercase().contains("permission"), "expected 403 or permission error");

    owner.activate().expect("owner");
    owner.run_commands(&["permission revoke-all"]).expect("revoke all");
    member_in_wallet.sync().expect("member sync after revoke");
    std::thread::sleep(std::time::Duration::from_millis(200));
    member_in_wallet
        .assert_commands(&["contacts count 0"])
        .expect("member sees no contacts after take");
    let create_after_revoke = member_in_wallet.run_commands(&["contact create 'Denied' m3"]);
    assert!(create_after_revoke.is_err(), "member with no permissions must not be allowed to create contact");

    owner.activate().expect("owner");
    owner.run_commands(&["permission grant-read"]).expect("grant read again");
    member_in_wallet.sync().expect("member sync after re-grant");
    std::thread::sleep(std::time::Duration::from_millis(200));
    member_in_wallet
        .assert_commands(&["contacts count 1", "contact name 'Shared Contact'"])
        .expect("member sees contact again");
    let create_after_regrant = member_in_wallet.run_commands(&["contact create 'Denied2' m4"]);
    assert!(create_after_regrant.is_err(), "member with read-only re-grant must not be allowed to create contact");
}

/// Owner creates contacts/transactions. Member syncs and sees data. Owner revokes read → member sync, local cleared. Owner grants read again → member sees data again.
#[test]
#[ignore]
fn permission_read_revoke_clears_local_then_grant_restores_via_sync() {
    let server_url = test_server_url();
    let owner = AppInstance::new("owner", &server_url);
    owner.initialize().expect("initialize");
    owner.signup().expect("signup");
    owner.login().expect("login");
    let wallet_id = owner.create_wallet("Test Wallet".to_string(), "".to_string()).expect("create_wallet");

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
    );
    member_in_wallet.initialize().expect("initialize");
    member_in_wallet.login().expect("login");
    member_in_wallet.select_wallet(&wallet_id).expect("select_wallet");

    owner.activate().expect("owner");
    owner
        .run_commands(&[
            "contact create 'Alice' alice",
            "contact create 'Bob' bob",
            "contact create 'Carol' carol",
            "transaction create alice owed 1000 'T1' t1",
            "transaction create alice lent 500 'T2' t2",
            "transaction create bob lent 800 'T3' t3",
            "transaction create bob owed 1200 'T4' t4",
            "transaction create carol owed 2000 'T5' t5",
            "wait 300",
        ])
        .expect("owner create contacts and transactions");
    std::thread::sleep(std::time::Duration::from_millis(300));
    member_in_wallet.sync().expect("member sync to pull data");
    member_in_wallet
        .assert_commands(&[
            "contacts count 3",
            "contact name 'Alice'",
            "contact name 'Bob'",
            "contact name 'Carol'",
            "transactions count 5",
            "transaction description 'T1'",
            "transaction description 'T2'",
            "transaction description 'T3'",
            "transaction description 'T4'",
            "transaction description 'T5'",
            "events count 9",
        ])
        .expect("member sees all data after initial sync");
    let create_initial = member_in_wallet.run_commands(&["contact create 'No' nope"]);
    assert!(create_initial.is_err(), "member with read-only must not be allowed to create contact");

    owner.activate().expect("owner");
    owner.run_commands(&["permission revoke-all"]).expect("revoke all (read removed)");
    member_in_wallet.sync().expect("member sync after revoke");
    std::thread::sleep(std::time::Duration::from_millis(200));
    member_in_wallet
        .assert_commands(&["contacts count 0", "transactions count 0"])
        .expect("member local state cleared");
    let create_after_revoke = member_in_wallet.run_commands(&["contact create 'Denied' d"]);
    assert!(create_after_revoke.is_err(), "member with no permissions must not be allowed to create contact");

    owner.activate().expect("owner");
    owner.run_commands(&["permission grant-read"]).expect("grant read again");
    member_in_wallet.sync().expect("member sync after re-grant");
    std::thread::sleep(std::time::Duration::from_millis(200));
    member_in_wallet
        .assert_commands(&[
            "contacts count 3",
            "contact name 'Alice'",
            "contact name 'Bob'",
            "contact name 'Carol'",
            "transactions count 5",
            "transaction description 'T1'",
            "transaction description 'T2'",
            "transaction description 'T3'",
            "transaction description 'T4'",
            "transaction description 'T5'",
            "events count 11",
        ])
        .expect("member sees all data again");
    let create_after_regrant = member_in_wallet.run_commands(&["contact create 'Denied2' d2"]);
    assert!(create_after_regrant.is_err(), "member with read-only re-grant must not be allowed to create contact");
}

/// Owner grants full to default matrix. Member creates contact and transaction.
#[test]
#[ignore]
fn permission_grant_create_then_member_can_create() {
    let server_url = test_server_url();
    let (owner_user, owner_pass, wallet_id) =
        create_unique_test_user_and_wallet(&server_url).expect("create owner");
    let owner = AppInstance::with_credentials("owner", &server_url, owner_user, owner_pass);
    owner.initialize().expect("initialize");
    owner.login().expect("login");
    owner.select_wallet(&wallet_id).expect("select_wallet");

    owner.activate().expect("owner");
    owner.run_commands(&["permission grant-full"]).expect("grant full to members");

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
    );
    member_in_wallet.initialize().expect("initialize");
    member_in_wallet.login().expect("login");
    member_in_wallet.select_wallet(&wallet_id).expect("select_wallet");

    member_in_wallet
        .run_commands(&["contact create 'Member Created' m1", "wait 300"])
        .expect("member create contact");
    std::thread::sleep(std::time::Duration::from_millis(300));
    member_in_wallet
        .assert_commands(&["contacts count 1", "contact name 'Member Created'"])
        .expect("member sees own contact");
    member_in_wallet
        .run_commands(&["transaction create m1 owed 100 'Member Tx' mt1", "wait 300"])
        .expect("member with full permissions can create transaction");
    std::thread::sleep(std::time::Duration::from_millis(300));
    member_in_wallet
        .assert_commands(&["transactions count 1", "transaction description 'Member Tx'"])
        .expect("member sees own transaction");
}

// --- Permission limits: deny wins, union, scoped denial ---

fn setup_owner_and_member() -> (AppInstance, AppInstance, String) {
    let server_url = test_server_url();
    let (owner_user, owner_pass, wallet_id) = create_unique_test_user_and_wallet(&server_url).expect("create owner");
    let owner = AppInstance::with_credentials("owner", &server_url, owner_user, owner_pass);
    owner.initialize().expect("init owner");
    owner.login().expect("login owner");
    owner.select_wallet(&wallet_id).expect("select_wallet");

    let member = AppInstance::new("member", &server_url);
    member.initialize().expect("init member");
    member.signup().expect("signup member");

    owner.activate().expect("activate owner");
    add_user_to_wallet(wallet_id.clone(), member.username.clone()).expect("add member to wallet");

    member.login().expect("login member so API calls as member are authenticated");

    (owner, member, wallet_id)
}

/// Deny wins: user in Editors (Allow Create) and BadActors (Deny Create). User cannot create.
#[test]
#[ignore]
fn permission_limits_deny_overrides_allow() {
    let (owner, member, wallet_id) = setup_owner_and_member();

    owner.activate().expect("activate");
    create_wallet_user_group(wallet_id.clone(), "Editors".to_string()).expect("create Editors");
    create_wallet_user_group(wallet_id.clone(), "BadActors".to_string()).expect("create BadActors");
    std::thread::sleep(std::time::Duration::from_millis(300));

    owner.activate().expect("activate");
    let ug_editors = get_user_group_id(&wallet_id, "Editors").expect("Editors");
    let ug_bad = get_user_group_id(&wallet_id, "BadActors").expect("BadActors");
    add_wallet_user_group_member(wallet_id.clone(), ug_editors.clone(), member.username.clone()).expect("add to Editors");
    add_wallet_user_group_member(wallet_id.clone(), ug_bad.clone(), member.username.clone()).expect("add to BadActors");
    std::thread::sleep(std::time::Duration::from_millis(300));

    let cg_all = get_contact_group_id(&wallet_id, "all_contacts").expect("all_contacts");
    set_permission_matrix_allowed_denied(&wallet_id, &ug_editors, &cg_all, vec!["contact:create".to_string(), "contact:read".to_string()], vec![]).expect("set");

    std::thread::sleep(std::time::Duration::from_millis(300));
    member.activate().expect("activate");
    set_current_wallet_id(wallet_id.clone()).expect("member must use shared wallet");
    let res = create_contact("Allowed Contact".to_string(), None, None, None, None);
    assert!(res.is_ok(), "User should be able to create contact with Allow permission");

    owner.activate().expect("activate owner to set matrix");
    set_permission_matrix_allowed_denied(&wallet_id, &ug_bad, &cg_all, vec![], vec!["contact:create".to_string()]).expect("set deny");

    std::thread::sleep(std::time::Duration::from_millis(300));
    member.activate().expect("activate");
    let _ = create_contact("Denied Contact".to_string(), None, None, None, None);
    std::thread::sleep(std::time::Duration::from_millis(300));

    member.activate().expect("activate");
    set_current_wallet_id(wallet_id.clone()).expect("member use shared wallet");
    let contacts_json = get_contacts().expect("get contacts");
    let contacts: Vec<serde_json::Value> = serde_json::from_str(&contacts_json).expect("parse");
    assert!(contacts.iter().any(|c| c["name"] == "Allowed Contact"), "Allowed Contact should be present");
    assert!(!contacts.iter().any(|c| c["name"] == "Denied Contact"), "Denied Contact must not be present (server rejected push)");
}

/// Union: user in Readers (Read) and Updaters (Update). User can read and update but not delete.
#[test]
#[ignore]
fn permission_limits_union_of_groups() {
    let (owner, member, wallet_id) = setup_owner_and_member();

    owner.activate().expect("activate");
    create_wallet_user_group(wallet_id.clone(), "Readers".to_string()).expect("create Readers");
    create_wallet_user_group(wallet_id.clone(), "Updaters".to_string()).expect("create Updaters");
    std::thread::sleep(std::time::Duration::from_millis(300));

    let ug_readers = get_user_group_id(&wallet_id, "Readers").expect("Readers");
    let ug_updaters = get_user_group_id(&wallet_id, "Updaters").expect("Updaters");
    owner.activate().expect("activate");
    add_wallet_user_group_member(wallet_id.clone(), ug_readers.clone(), member.username.clone()).expect("add Readers");
    add_wallet_user_group_member(wallet_id.clone(), ug_updaters.clone(), member.username.clone()).expect("add Updaters");

    owner.activate().expect("activate");
    set_current_wallet_id(wallet_id.clone()).expect("owner");
    create_contact("Test Contact".to_string(), None, None, None, None).expect("create contact");
    std::thread::sleep(std::time::Duration::from_millis(300));

    let cg_all = get_contact_group_id(&wallet_id, "all_contacts").expect("all_contacts");
    set_permission_matrix_allowed_denied(&wallet_id, &ug_readers, &cg_all, vec!["contact:read".to_string()], vec![]).expect("set");
    set_permission_matrix_allowed_denied(&wallet_id, &ug_updaters, &cg_all, vec!["contact:update".to_string(), "contact:read".to_string()], vec![]).expect("set");

    std::thread::sleep(std::time::Duration::from_millis(300));
    member.activate().expect("activate");
    set_current_wallet_id(wallet_id.clone()).expect("member must use shared wallet");

    let contacts_json = get_contacts_from_server().expect("get contacts from server");
    let contacts: Vec<serde_json::Value> = serde_json::from_str(&contacts_json).expect("parse");
    let contact = contacts.iter().find(|c| c["name"] == "Test Contact").expect("should see contact");
    let contact_id = contact["id"].as_str().unwrap().to_string();

    let res = update_contact(contact_id.clone(), "Updated Name".to_string(), None, None, None, None);
    assert!(res.is_ok(), "Should be able to update due to Updaters group");

    let res = delete_contact(contact_id.clone());
    assert!(res.is_err(), "Should NOT be able to delete");

    std::thread::sleep(std::time::Duration::from_millis(300));
    owner.activate().expect("activate");
    set_current_wallet_id(wallet_id.clone()).expect("owner use shared wallet");
    let contacts_json = get_contacts_from_server().expect("get contacts from server");
    let contacts: Vec<serde_json::Value> = serde_json::from_str(&contacts_json).expect("parse");
    let contact = contacts.iter().find(|c| c["id"] == contact_id).unwrap();
    assert_eq!(contact["name"], "Updated Name");
}

/// Scoped denial: Employees→Work Read, Friends→Personal Read, Probation→Personal Deny Read. Member sees Work, not Personal.
#[test]
#[ignore]
fn permission_limits_scoped_denial() {
    let (owner, member, wallet_id) = setup_owner_and_member();

    owner.activate().expect("activate");
    create_wallet_user_group(wallet_id.clone(), "Employees".to_string()).expect("create Employees");
    create_wallet_user_group(wallet_id.clone(), "Friends".to_string()).expect("create Friends");
    create_wallet_user_group(wallet_id.clone(), "Probation".to_string()).expect("create Probation");
    create_wallet_contact_group(wallet_id.clone(), "Work".to_string()).expect("create Work");
    create_wallet_contact_group(wallet_id.clone(), "Personal".to_string()).expect("create Personal");
    std::thread::sleep(std::time::Duration::from_millis(300));

    owner.activate().expect("activate");
    set_current_wallet_id(wallet_id.clone()).expect("owner");
    let cg_work = get_contact_group_id(&wallet_id, "Work").expect("Work");
    let cg_personal = get_contact_group_id(&wallet_id, "Personal").expect("Personal");

    let c_work_json = create_contact("Work Contact".to_string(), None, None, None, None).expect("create work c");
    let c_work: serde_json::Value = serde_json::from_str(&c_work_json).expect("parse");
    let c_work_id = c_work["id"].as_str().unwrap().to_string();
    add_wallet_contact_group_member(wallet_id.clone(), cg_work.clone(), c_work_id).expect("add to work");

    let c_personal_json = create_contact("Personal Contact".to_string(), None, None, None, None).expect("create personal c");
    let c_personal: serde_json::Value = serde_json::from_str(&c_personal_json).expect("parse");
    let c_personal_id = c_personal["id"].as_str().unwrap().to_string();
    add_wallet_contact_group_member(wallet_id.clone(), cg_personal.clone(), c_personal_id).expect("add to personal");

    let ug_employees = get_user_group_id(&wallet_id, "Employees").expect("Employees");
    let ug_friends = get_user_group_id(&wallet_id, "Friends").expect("Friends");
    let ug_probation = get_user_group_id(&wallet_id, "Probation").expect("Probation");
    add_wallet_user_group_member(wallet_id.clone(), ug_employees.clone(), member.username.clone()).expect("add Employees");
    add_wallet_user_group_member(wallet_id.clone(), ug_friends.clone(), member.username.clone()).expect("add Friends");
    add_wallet_user_group_member(wallet_id.clone(), ug_probation.clone(), member.username.clone()).expect("add Probation");
    std::thread::sleep(std::time::Duration::from_millis(300));

    let ug_all_users = get_user_group_id(&wallet_id, "all_users").expect("all_users");
    let cg_all_contacts = get_contact_group_id(&wallet_id, "all_contacts").expect("all_contacts");
    set_permission_matrix_allowed_denied(&wallet_id, &ug_all_users, &cg_all_contacts, vec![], vec![]).expect("revoke default");

    set_permission_matrix_allowed_denied(&wallet_id, &ug_employees, &cg_work, vec!["contact:read".to_string()], vec![]).expect("set");
    set_permission_matrix_allowed_denied(&wallet_id, &ug_friends, &cg_personal, vec!["contact:read".to_string()], vec![]).expect("set");
    set_permission_matrix_allowed_denied(&wallet_id, &ug_probation, &cg_personal, vec![], vec!["contact:read".to_string()]).expect("set");

    std::thread::sleep(std::time::Duration::from_millis(300));
    member.activate().expect("activate");
    set_current_wallet_id(wallet_id.clone()).expect("member must use shared wallet");

    let contacts_json = get_contacts_from_server().expect("get contacts from server");
    let contacts: Vec<serde_json::Value> = serde_json::from_str(&contacts_json).expect("parse");
    assert!(contacts.iter().any(|c| c["name"] == "Work Contact"), "Should see Work Contact");
    assert!(!contacts.iter().any(|c| c["name"] == "Personal Contact"), "Should NOT see Personal Contact (Probation deny overrides Friends allow)");
}

// --- Groups: user groups, contact groups, matrix, join ---

/// Create user group, list, add member, list members.
#[test]
#[ignore]
fn groups_user_group_create_list_add_member_list_members() {
    let server_url = test_server_url();
    let (owner_user, owner_pass, wallet_id) =
        create_unique_test_user_and_wallet(&server_url).expect("create owner");
    let owner = AppInstance::with_credentials("owner", &server_url, owner_user, owner_pass);
    owner.initialize().expect("initialize");
    owner.login().expect("login");
    owner.select_wallet(&wallet_id).expect("select_wallet");

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

    add_wallet_user_group_member(wallet_id.clone(), editors_id.clone(), member.username.clone()).expect("add member to Editors");

    let members_json = list_wallet_user_group_members(wallet_id.clone(), editors_id).expect("list members");
    let members: Vec<serde_json::Value> = serde_json::from_str(&members_json).map_err(|e| e.to_string()).expect("parse");
    assert!(!members.is_empty(), "Editors should have at least one member");
    let has_member = members.iter().any(|m| m.get("username").and_then(|v| v.as_str()) == Some(&member.username));
    assert!(has_member, "Editors members should include member username");
}

/// Create contact, contact group, add contact to group, list groups and members.
#[test]
#[ignore]
fn groups_contact_group_create_list_add_contact_list_members() {
    let server_url = test_server_url();
    let owner = AppInstance::new("owner", &server_url);
    owner.initialize().expect("initialize");
    owner.signup().expect("signup");
    owner.login().expect("login");
    let wallet_id = owner.create_wallet("Test Wallet".to_string(), "".to_string()).expect("create_wallet");

    owner
        .run_commands(&["contact create 'Alice' alice", "wait 300"])
        .expect("create contact");
    std::thread::sleep(std::time::Duration::from_millis(300));
    let contacts_json = get_contacts().expect("get_contacts");
    let alice_id = contact_id_by_name(&contacts_json, "Alice").expect("Alice id");

    let create_res = create_wallet_contact_group(wallet_id.clone(), "VIP".to_string()).expect("create contact group");
    let created: serde_json::Value = serde_json::from_str(&create_res).map_err(|e| e.to_string()).expect("parse");
    let vip_id = created["id"].as_str().expect("id").to_string();

    let list_json = list_wallet_contact_groups(wallet_id.clone()).expect("list contact groups");
    let vip_found = group_id_by_name(&list_json, "VIP").expect("VIP in list");
    assert_eq!(vip_found, vip_id);

    add_wallet_contact_group_member(wallet_id.clone(), vip_id.clone(), alice_id.clone()).expect("add Alice to VIP");

    let members_json = list_wallet_contact_group_members(wallet_id.clone(), vip_id).expect("list VIP members");
    let members: Vec<serde_json::Value> = serde_json::from_str(&members_json).map_err(|e| e.to_string()).expect("parse");
    assert_eq!(members.len(), 1, "VIP should have one member");
    assert_eq!(members[0].get("contact_id").and_then(|v| v.as_str()), Some(alice_id.as_str()));
}

/// Revoke default read. Viewers×Public = read. Add only Alice to Public. Member sees only Alice.
#[test]
#[ignore]
fn groups_complex_member_sees_only_contacts_in_permitted_group() {
    let server_url = test_server_url();
    let owner = AppInstance::new("owner", &server_url);
    owner.initialize().expect("initialize");
    owner.signup().expect("signup");
    owner.login().expect("login");
    let wallet_id = owner.create_wallet("Test Wallet".to_string(), "".to_string()).expect("create_wallet");

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
        .run_commands(&["contact create 'Alice' alice", "contact create 'Bob' bob", "wait 300"])
        .expect("create contacts");
    std::thread::sleep(std::time::Duration::from_millis(300));
    let contacts_json = get_contacts().expect("get_contacts");
    let alice_id = contact_id_by_name(&contacts_json, "Alice").expect("Alice id");
    add_wallet_contact_group_member(wallet_id.clone(), public_cg_id.clone(), alice_id).expect("add Alice to Public");

    set_matrix_actions(
        &wallet_id,
        &viewers_ug_id,
        &public_cg_id,
        &["contact:read", "transaction:read", "events:read"],
    )
    .expect("Viewers x Public = read");

    let member_in_wallet = AppInstance::with_credentials("member", &server_url, member.username.clone(), member.password.clone());
    member_in_wallet.initialize().expect("initialize");
    member_in_wallet.login().expect("login");
    member_in_wallet.select_wallet(&wallet_id).expect("select_wallet");
    member_in_wallet.sync().expect("member sync after grant");
    std::thread::sleep(std::time::Duration::from_millis(200));
    member_in_wallet
        .assert_commands(&["contacts count 1", "contact name 'Alice'"])
        .expect("member sees only Alice (in Public)");
    let create_res = member_in_wallet.run_commands(&["contact create 'Denied' x"]);
    assert!(create_res.is_err(), "member with read-only on Public must not be allowed to create contact");
}

/// Viewers×GroupA and Viewers×GroupB = read. GroupAOnly×GroupA = read. Member1 sees Alice+Bob, Member2 sees only Alice.
#[test]
#[ignore]
fn groups_complex_two_user_groups_two_contact_groups_scoped_visibility() {
    let server_url = test_server_url();
    let (owner_user, owner_pass, wallet_id) =
        create_unique_test_user_and_wallet(&server_url).expect("create owner");
    let owner = AppInstance::with_credentials("owner", &server_url, owner_user, owner_pass);
    owner.initialize().expect("initialize");
    owner.login().expect("login");
    owner.select_wallet(&wallet_id).expect("select_wallet");

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
        .run_commands(&["contact create 'Alice' alice", "contact create 'Bob' bob", "wait 300"])
        .expect("create contacts");
    std::thread::sleep(std::time::Duration::from_millis(300));
    let contacts_json = get_contacts().expect("get_contacts");
    let alice_id = contact_id_by_name(&contacts_json, "Alice").expect("Alice id");
    let bob_id = contact_id_by_name(&contacts_json, "Bob").expect("Bob id");
    add_wallet_contact_group_member(wallet_id.clone(), cg_a_id.clone(), alice_id).expect("Alice -> GroupA");
    add_wallet_contact_group_member(wallet_id.clone(), cg_b_id.clone(), bob_id).expect("Bob -> GroupB");

    set_matrix_actions(&wallet_id, &ug_viewers_id, &cg_a_id, &["contact:read", "transaction:read", "events:read"]).expect("Viewers x GroupA");
    set_matrix_actions(&wallet_id, &ug_viewers_id, &cg_b_id, &["contact:read", "transaction:read", "events:read"]).expect("Viewers x GroupB");
    set_matrix_actions(&wallet_id, &ug_group_a_only_id, &cg_a_id, &["contact:read", "transaction:read", "events:read"]).expect("GroupAOnly x GroupA");

    let m1 = AppInstance::with_credentials("m1", &server_url, member1.username.clone(), member1.password.clone());
    m1.initialize().expect("initialize");
    m1.login().expect("login");
    m1.select_wallet(&wallet_id).expect("select_wallet");
    m1.sync().expect("m1 sync after grant");
    std::thread::sleep(std::time::Duration::from_millis(200));
    m1.assert_commands(&["contacts count 2", "contact name 'Alice'", "contact name 'Bob'"]).expect("member1 sees Alice and Bob");
    assert!(m1.run_commands(&["contact create 'Denied' x"]).is_err(), "member1 read-only; create denied");

    let m2 = AppInstance::with_credentials("m2", &server_url, member2.username.clone(), member2.password.clone());
    m2.initialize().expect("initialize");
    m2.login().expect("login");
    m2.select_wallet(&wallet_id).expect("select_wallet");
    m2.sync().expect("m2 sync after grant");
    std::thread::sleep(std::time::Duration::from_millis(200));
    m2.assert_commands(&["contacts count 1", "contact name 'Alice'"]).expect("member2 sees only Alice");
    assert!(m2.run_commands(&["contact create 'Denied' y"]).is_err(), "member2 read-only; create denied");
}

/// Viewers×all_contacts = read. Member in Viewers sees all contacts.
#[test]
#[ignore]
fn groups_priority_custom_user_group_times_all_contacts_sees_all() {
    let server_url = test_server_url();
    let (owner_user, owner_pass, wallet_id) =
        create_unique_test_user_and_wallet(&server_url).expect("create owner");
    let owner = AppInstance::with_credentials("owner", &server_url, owner_user, owner_pass);
    owner.initialize().expect("initialize");
    owner.login().expect("login");
    owner.select_wallet(&wallet_id).expect("select_wallet");

    let (all_ug, all_cg) = get_default_matrix_ids(&wallet_id).expect("default matrix ids");
    set_matrix_actions(&wallet_id, &all_ug, &all_cg, &[]).expect("revoke all_users × all_contacts");

    let ug_viewers_id: String = serde_json::from_str::<serde_json::Value>(&create_wallet_user_group(wallet_id.clone(), "Viewers".to_string()).expect("create")).expect("parse")["id"].as_str().expect("id").to_string();
    set_matrix_actions(&wallet_id, &ug_viewers_id, &all_cg, &["contact:read", "transaction:read", "events:read"]).expect("Viewers × all_contacts = read");

    let member = AppInstance::new("member", &server_url);
    member.initialize().expect("initialize");
    member.signup().expect("member signup");
    owner.activate().expect("owner");
    add_user_to_wallet(wallet_id.clone(), member.username.clone()).expect("add member");
    add_wallet_user_group_member(wallet_id.clone(), ug_viewers_id.clone(), member.username.clone()).expect("member -> Viewers");

    owner
        .run_commands(&["contact create 'Alice' alice", "contact create 'Bob' bob", "wait 300"])
        .expect("create contacts");
    std::thread::sleep(std::time::Duration::from_millis(300));

    let member_app = AppInstance::with_credentials("member", &server_url, member.username.clone(), member.password.clone());
    member_app.initialize().expect("initialize");
    member_app.login().expect("login");
    member_app.select_wallet(&wallet_id).expect("select_wallet");
    member_app.sync().expect("member sync after grant");
    std::thread::sleep(std::time::Duration::from_millis(200));
    member_app
        .assert_commands(&["contacts count 2", "contact name 'Alice'", "contact name 'Bob'"])
        .expect("member in Viewers sees all (Viewers × all_contacts)");
    assert!(member_app.run_commands(&["contact create 'Denied' x"]).is_err(), "Viewers read-only; create denied");
}

/// Union: Viewers×all_contacts=read, VIPOnly×VIP=read. Alice in VIP. Member in Viewers sees all; in VIPOnly sees Alice; in both sees all.
#[test]
#[ignore]
fn groups_priority_union_multiple_user_groups_see_union_of_contact_groups() {
    let server_url = test_server_url();
    let (owner_user, owner_pass, wallet_id) =
        create_unique_test_user_and_wallet(&server_url).expect("create owner");
    let owner = AppInstance::with_credentials("owner", &server_url, owner_user, owner_pass);
    owner.initialize().expect("initialize");
    owner.login().expect("login");
    owner.select_wallet(&wallet_id).expect("select_wallet");

    let (all_ug, all_cg) = get_default_matrix_ids(&wallet_id).expect("default matrix ids");
    set_matrix_actions(&wallet_id, &all_ug, &all_cg, &[]).expect("revoke all_users × all_contacts");

    let ug_viewers_id: String = serde_json::from_str::<serde_json::Value>(&create_wallet_user_group(wallet_id.clone(), "Viewers".to_string()).expect("create")).expect("parse")["id"].as_str().expect("id").to_string();
    let ug_vip_only_id: String = serde_json::from_str::<serde_json::Value>(&create_wallet_user_group(wallet_id.clone(), "VIPOnly".to_string()).expect("create")).expect("parse")["id"].as_str().expect("id").to_string();
    let cg_vip_id: String = serde_json::from_str::<serde_json::Value>(&create_wallet_contact_group(wallet_id.clone(), "VIP".to_string()).expect("create")).expect("parse")["id"].as_str().expect("id").to_string();

    set_matrix_actions(&wallet_id, &ug_viewers_id, &all_cg, &["contact:read", "transaction:read", "events:read"]).expect("Viewers × all_contacts");
    set_matrix_actions(&wallet_id, &ug_vip_only_id, &cg_vip_id, &["contact:read", "transaction:read", "events:read"]).expect("VIPOnly × VIP");

    owner
        .run_commands(&["contact create 'Alice' alice", "contact create 'Bob' bob", "wait 300"])
        .expect("create contacts");
    std::thread::sleep(std::time::Duration::from_millis(300));
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

    let app_viewers = AppInstance::with_credentials("mv", &server_url, member_viewers.username.clone(), member_viewers.password.clone());
    app_viewers.initialize().expect("initialize");
    app_viewers.login().expect("login");
    app_viewers.select_wallet(&wallet_id).expect("select_wallet");
    app_viewers.sync().expect("sync");
    std::thread::sleep(std::time::Duration::from_millis(200));
    app_viewers.assert_commands(&["contacts count 2", "contact name 'Alice'", "contact name 'Bob'"]).expect("Viewers-only sees all");

    let app_vip = AppInstance::with_credentials("mvip", &server_url, member_vip.username.clone(), member_vip.password.clone());
    app_vip.initialize().expect("initialize");
    app_vip.login().expect("login");
    app_vip.select_wallet(&wallet_id).expect("select_wallet");
    app_vip.sync().expect("sync");
    std::thread::sleep(std::time::Duration::from_millis(200));
    app_vip.assert_commands(&["contacts count 1", "contact name 'Alice'"]).expect("VIPOnly sees only Alice");

    let app_both = AppInstance::with_credentials("mboth", &server_url, member_both.username.clone(), member_both.password.clone());
    app_both.initialize().expect("initialize");
    app_both.login().expect("login");
    app_both.select_wallet(&wallet_id).expect("select_wallet");
    app_both.sync().expect("sync");
    std::thread::sleep(std::time::Duration::from_millis(200));
    app_both.assert_commands(&["contacts count 2", "contact name 'Alice'", "contact name 'Bob'"]).expect("Viewers+VIPOnly sees union = all");
}

/// Viewers×all_contacts, Editors×Staff, VIPOnly×VIP. Viewers sees all; Editors sees only Carol (Staff); VIPOnly sees only Alice (VIP).
#[test]
#[ignore]
fn groups_priority_different_ug_to_different_cg_scoped_and_union() {
    let server_url = test_server_url();
    let (owner_user, owner_pass, wallet_id) =
        create_unique_test_user_and_wallet(&server_url).expect("create owner");
    let owner = AppInstance::with_credentials("owner", &server_url, owner_user, owner_pass);
    owner.initialize().expect("initialize");
    owner.login().expect("login");
    owner.select_wallet(&wallet_id).expect("select_wallet");

    let (all_ug, all_cg) = get_default_matrix_ids(&wallet_id).expect("default matrix ids");
    set_matrix_actions(&wallet_id, &all_ug, &all_cg, &[]).expect("revoke all_users × all_contacts");

    let ug_viewers_id: String = serde_json::from_str::<serde_json::Value>(&create_wallet_user_group(wallet_id.clone(), "Viewers".to_string()).expect("create")).expect("parse")["id"].as_str().expect("id").to_string();
    let ug_editors_id: String = serde_json::from_str::<serde_json::Value>(&create_wallet_user_group(wallet_id.clone(), "Editors".to_string()).expect("create")).expect("parse")["id"].as_str().expect("id").to_string();
    let ug_vip_only_id: String = serde_json::from_str::<serde_json::Value>(&create_wallet_user_group(wallet_id.clone(), "VIPOnly".to_string()).expect("create")).expect("parse")["id"].as_str().expect("id").to_string();

    let cg_staff_id: String = serde_json::from_str::<serde_json::Value>(&create_wallet_contact_group(wallet_id.clone(), "Staff".to_string()).expect("create")).expect("parse")["id"].as_str().expect("id").to_string();
    let cg_vip_id: String = serde_json::from_str::<serde_json::Value>(&create_wallet_contact_group(wallet_id.clone(), "VIP".to_string()).expect("create")).expect("parse")["id"].as_str().expect("id").to_string();

    set_matrix_actions(&wallet_id, &ug_viewers_id, &all_cg, &["contact:read", "transaction:read", "events:read"]).expect("Viewers × all_contacts");
    set_matrix_actions(&wallet_id, &ug_editors_id, &cg_staff_id, &["contact:read", "transaction:read", "events:read"]).expect("Editors × Staff");
    set_matrix_actions(&wallet_id, &ug_vip_only_id, &cg_vip_id, &["contact:read", "transaction:read", "events:read"]).expect("VIPOnly × VIP");

    owner
        .run_commands(&["contact create 'Alice' alice", "contact create 'Bob' bob", "contact create 'Carol' carol", "wait 300"])
        .expect("create contacts");
    std::thread::sleep(std::time::Duration::from_millis(300));
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

    let app_v = AppInstance::with_credentials("m1", &server_url, member_viewers.username.clone(), member_viewers.password.clone());
    app_v.initialize().expect("initialize");
    app_v.login().expect("login");
    app_v.select_wallet(&wallet_id).expect("select_wallet");
    app_v.sync().expect("sync");
    std::thread::sleep(std::time::Duration::from_millis(200));
    app_v.assert_commands(&["contacts count 3", "contact name 'Alice'", "contact name 'Bob'", "contact name 'Carol'"]).expect("Viewers sees all");

    let app_e = AppInstance::with_credentials("m2", &server_url, member_editors.username.clone(), member_editors.password.clone());
    app_e.initialize().expect("initialize");
    app_e.login().expect("login");
    app_e.select_wallet(&wallet_id).expect("select_wallet");
    app_e.sync().expect("sync");
    std::thread::sleep(std::time::Duration::from_millis(200));
    app_e.assert_commands(&["contacts count 1", "contact name 'Carol'"]).expect("Editors sees only Staff (Carol)");

    let app_vip = AppInstance::with_credentials("m3", &server_url, member_vip.username.clone(), member_vip.password.clone());
    app_vip.initialize().expect("initialize");
    app_vip.login().expect("login");
    app_vip.select_wallet(&wallet_id).expect("select_wallet");
    app_vip.sync().expect("sync");
    std::thread::sleep(std::time::Duration::from_millis(200));
    app_vip.assert_commands(&["contacts count 1", "contact name 'Alice'"]).expect("VIPOnly sees only VIP (Alice)");
}

/// Two apps: app1 creates wallet, revokes default; app2 joins via invite, sees nothing. App1 grants all_users×Shared full; app2 clear+sync sees Shared contacts and can create.
#[test]
#[ignore]
fn groups_two_apps_join_with_no_default_then_grant_via_contact_group() {
    let server_url = test_server_url();

    let app1 = AppInstance::new("app1", &server_url);
    app1.initialize().expect("initialize");
    app1.signup().expect("signup");
    app1.login().expect("login");
    let wallet_id = app1.create_wallet("Test Wallet".to_string(), "".to_string()).expect("create_wallet");

    let app2 = AppInstance::new("app2", &server_url);
    app2.initialize().expect("initialize");
    app2.signup().expect("signup");

    app1.activate().expect("app1");
    app1.select_wallet(&wallet_id).expect("select_wallet");
    app1
        .run_commands(&[
            "contact create 'Alice' alice",
            "contact create 'Bob' bob",
            "contact create 'Carol' carol",
            "transaction create alice owed 100 'T1' t1",
            "transaction create bob lent 50 'T2' t2",
            "wait 300",
        ])
        .expect("app1 create contacts and transactions");
    std::thread::sleep(std::time::Duration::from_millis(300));

    let (all_ug, all_cg) = get_default_matrix_ids(&wallet_id).expect("matrix ids");
    set_matrix_actions(&wallet_id, &all_ug, &all_cg, &[]).expect("all_users × all_contacts = none");

    let code = create_wallet_invite_code(wallet_id.clone()).expect("create invite code");
    app2.activate().expect("app2");
    app2.login().expect("app2 login");
    let joined_wallet_id = join_wallet_by_code(code).expect("app2 join wallet");
    set_current_wallet_id(joined_wallet_id.clone()).expect("app2 switch to joined wallet");
    assert_eq!(joined_wallet_id, wallet_id, "joined wallet is app1's wallet");

    let app2_in_wallet = AppInstance::with_credentials("app2", &server_url, app2.username.clone(), app2.password.clone());
    app2_in_wallet.initialize().expect("initialize");
    app2_in_wallet.login().expect("login");
    app2_in_wallet.select_wallet(&wallet_id).expect("select_wallet");
    std::thread::sleep(std::time::Duration::from_millis(300));
    app2_in_wallet
        .assert_commands(&["contacts count 0"])
        .expect("app2 sees no contacts (all_users × all_contacts = none)");
    assert!(app2_in_wallet.run_commands(&["contact create 'Forbidden' x"]).is_err(), "app2 cannot create when no permissions");

    app1.activate().expect("app1");
    let cg_shared_id: String = serde_json::from_str::<serde_json::Value>(&create_wallet_contact_group(wallet_id.clone(), "Shared".to_string()).expect("create contact group")).expect("parse")["id"].as_str().expect("id").to_string();
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
            "contact:read", "contact:create", "contact:update", "contact:delete",
            "transaction:read", "transaction:create", "transaction:update", "transaction:delete",
            "events:read",
        ],
    )
    .expect("all_users × Shared = full actions");

    std::thread::sleep(std::time::Duration::from_millis(500));
    app2_in_wallet.activate().expect("app2");
    clear_wallet_data(wallet_id.clone()).expect("clear app2 local data");
    app2_in_wallet.sync().expect("app2 sync to pull with new permissions");
    std::thread::sleep(std::time::Duration::from_millis(200));
    app2_in_wallet
        .assert_commands(&["contacts count 2", "contact name 'Alice'", "contact name 'Bob'"])
        .expect("app2 sees Shared contacts");
    app2_in_wallet
        .run_commands(&["contact create 'ByApp2' app2c", "wait 300"])
        .expect("app2 with full on Shared can create contact");
    std::thread::sleep(std::time::Duration::from_millis(100));
    app2_in_wallet
        .assert_commands(&["contacts count 3", "contact name 'ByApp2'"])
        .expect("app2 sees own created contact");
}
