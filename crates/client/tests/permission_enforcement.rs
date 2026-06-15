//! Permission enforcement tests written against the user's reported bug:
//! "members can do everything regardless of the permission matrix."
//!
//! The existing permissions.rs tests verify the POSITIVE direction
//! (member CAN do X after grant) but rarely the NEGATIVE direction
//! (member CANNOT do X without grant). This file fills that gap.
//!
//! Every test is a controlled scenario:
//!   - Create owner + member.
//!   - Member is in the default `all_users` group only (read perms only).
//!   - Member attempts an unauthorized action.
//!   - Assert the action is REJECTED at the server boundary
//!     (push returns DEBITUM_INSUFFICIENT_WALLET_PERMISSION; client
//!     drops the unsynced event).
//!
//! If any of these tests pass on a server with broken enforcement,
//! they will fail loudly. If they fail on a working server, we've
//! found the actual gap.

use client::{
    add_user_to_wallet, create_contact, create_transaction, delete_contact,
    delete_transaction, manual_sync, set_current_wallet_id, update_contact,
    update_transaction,
};

use crate::common::app_instance::{create_unique_test_user_and_wallet, AppInstance};
use crate::common::test_helpers::test_server_url;

const PERM_ERR: &str = "DEBITUM_INSUFFICIENT_WALLET_PERMISSION";

/// Builds an owner + a member who is in the wallet's default
/// `all_users` group with the default `contact:read` + `transaction:read`
/// permissions only. No extra grants. Returns (owner, member, wallet_id,
/// contact_id_owned_by_owner) where the contact is one the owner created
/// for the member to try to mutate.
fn setup_owner_and_member_with_one_contact() -> (AppInstance, AppInstance, String, String) {
    let server_url = test_server_url();
    let (owner_user, owner_pass, wallet_id) =
        create_unique_test_user_and_wallet(&server_url).expect("create owner");
    let owner =
        AppInstance::with_credentials("owner", &server_url, owner_user, owner_pass);
    owner.initialize().expect("init owner");
    owner.login().expect("login owner");
    owner.select_wallet(&wallet_id).expect("select wallet");

    // Owner creates one contact and syncs so it lands in the server's
    // user_readable_events for the about-to-be-added member.
    owner.activate().expect("activate owner");
    set_current_wallet_id(wallet_id.clone()).expect("owner current wallet");
    let contact_json =
        create_contact("Target".to_string(), None, None, None, None, None)
            .expect("owner create contact");
    let contact: serde_json::Value =
        serde_json::from_str(&contact_json).expect("parse contact");
    let contact_id = contact["id"].as_str().expect("contact id").to_string();
    manual_sync().expect("owner sync");

    // Member signup + join wallet.
    let member = AppInstance::new("member", &server_url);
    member.initialize().expect("init member");
    member.signup().expect("signup member");

    owner.activate().expect("activate owner for add_user_to_wallet");
    add_user_to_wallet(wallet_id.clone(), member.username.clone())
        .expect("add member to wallet");

    let member_in_wallet = AppInstance::with_credentials(
        "member",
        &server_url,
        member.username.clone(),
        member.password.clone(),
    );
    member_in_wallet.initialize().expect("init member-in-wallet");
    member_in_wallet.login().expect("login member-in-wallet");
    member_in_wallet
        .select_wallet(&wallet_id)
        .expect("member select wallet");

    // Member syncs so they can see the contact.
    member_in_wallet.activate().expect("activate member");
    set_current_wallet_id(wallet_id.clone()).expect("member current wallet");
    manual_sync().expect("member initial sync");

    (owner, member_in_wallet, wallet_id, contact_id)
}

fn assert_perm_denied(result: Result<impl std::fmt::Debug, String>, what: &str) {
    match result {
        Ok(ok) => panic!(
            "{}: expected DEBITUM_INSUFFICIENT_WALLET_PERMISSION, got Ok({:?}). \
             Permission enforcement is broken — the server accepted an action the \
             member's matrix doesn't grant.",
            what, ok
        ),
        Err(e) => {
            assert!(
                e.contains(PERM_ERR),
                "{}: expected error containing {}, got: {}",
                what,
                PERM_ERR,
                e
            );
        }
    }
}

/// A pure member (only in `all_users`, only contact:read + transaction:read
/// granted by default) attempts to CREATE a contact. Server must reject
/// with DEBITUM_INSUFFICIENT_WALLET_PERMISSION.
#[test]
#[ignore]
fn member_default_cannot_create_contact() {
    let (_owner, member, _wallet_id, _contact_id) =
        setup_owner_and_member_with_one_contact();

    member.activate().expect("activate member");
    let res = create_contact("Member's Try".to_string(), None, None, None, None, None);
    assert_perm_denied(res, "member default cannot create contact");
}

/// Member attempts to UPDATE the owner's contact. Default member perms
/// don't include contact:update; server must reject.
#[test]
#[ignore]
fn member_default_cannot_update_contact() {
    let (_owner, member, _wallet_id, contact_id) =
        setup_owner_and_member_with_one_contact();

    member.activate().expect("activate member");
    let res = update_contact(
        contact_id,
        "Hijacked Name".to_string(),
        None,
        None,
        None,
        None,
        None,
    );
    assert_perm_denied(res, "member default cannot update contact");
}

/// Member attempts to DELETE the owner's contact. Default member perms
/// don't include contact:delete; server must reject.
#[test]
#[ignore]
fn member_default_cannot_delete_contact() {
    let (_owner, member, _wallet_id, contact_id) =
        setup_owner_and_member_with_one_contact();

    member.activate().expect("activate member");
    let res = delete_contact(contact_id);
    assert_perm_denied(res, "member default cannot delete contact");
}

/// Member attempts to CREATE a transaction against the owner's contact.
/// Default member perms don't include transaction:create.
#[test]
#[ignore]
fn member_default_cannot_create_transaction() {
    let (_owner, member, _wallet_id, contact_id) =
        setup_owner_and_member_with_one_contact();

    member.activate().expect("activate member");
    let res = create_transaction(
        contact_id,
        "expense".to_string(),
        "owed".to_string(),
        100,
        "IQD".to_string(),
        Some("Member's tx".to_string()),
        "2026-01-01".to_string(),
        None,
    );
    assert_perm_denied(res, "member default cannot create transaction");
}

/// Owner creates a transaction. Member attempts to UPDATE it. Default
/// member perms don't include transaction:update.
#[test]
#[ignore]
fn member_default_cannot_update_transaction() {
    let (owner, member, wallet_id, contact_id) =
        setup_owner_and_member_with_one_contact();

    // Owner creates a transaction the member can read but shouldn't update.
    owner.activate().expect("activate owner");
    set_current_wallet_id(wallet_id.clone()).expect("owner wallet");
    let tx_json = create_transaction(
        contact_id.clone(),
        "expense".to_string(),
        "owed".to_string(),
        500,
        "IQD".to_string(),
        Some("owner's tx".to_string()),
        "2026-01-01".to_string(),
        None,
    )
    .expect("owner create transaction");
    let tx: serde_json::Value = serde_json::from_str(&tx_json).expect("parse tx");
    let tx_id = tx["id"].as_str().expect("tx id").to_string();
    manual_sync().expect("owner sync after tx");

    member.activate().expect("activate member");
    set_current_wallet_id(wallet_id).expect("member wallet");
    manual_sync().expect("member sync to see the tx");

    let res = update_transaction(
        tx_id,
        contact_id,
        "expense".to_string(),
        "lent".to_string(),
        999,
        "IQD".to_string(),
        Some("hijacked".to_string()),
        "2026-01-01".to_string(),
        None,
    );
    assert_perm_denied(res, "member default cannot update transaction");
}

/// Owner creates a transaction. Member attempts to DELETE it. Default
/// member perms don't include transaction:delete.
#[test]
#[ignore]
fn member_default_cannot_delete_transaction() {
    let (owner, member, wallet_id, contact_id) =
        setup_owner_and_member_with_one_contact();

    owner.activate().expect("activate owner");
    set_current_wallet_id(wallet_id.clone()).expect("owner wallet");
    let tx_json = create_transaction(
        contact_id,
        "expense".to_string(),
        "owed".to_string(),
        500,
        "IQD".to_string(),
        Some("to-delete".to_string()),
        "2026-01-01".to_string(),
        None,
    )
    .expect("owner create transaction");
    let tx: serde_json::Value = serde_json::from_str(&tx_json).expect("parse tx");
    let tx_id = tx["id"].as_str().expect("tx id").to_string();
    manual_sync().expect("owner sync after tx");

    member.activate().expect("activate member");
    set_current_wallet_id(wallet_id).expect("member wallet");
    manual_sync().expect("member sync");

    let res = delete_transaction(tx_id);
    assert_perm_denied(res, "member default cannot delete transaction");
}

/// Combined check: a brand-new member with no extra grants must fail
/// every write action. If a single one of these slips through, the
/// enforcement is broken regardless of which one.
#[test]
#[ignore]
fn member_default_blocked_on_every_write_action() {
    let (owner, member, wallet_id, contact_id) =
        setup_owner_and_member_with_one_contact();

    // Owner pre-creates a transaction we can try to mutate.
    owner.activate().expect("activate owner");
    set_current_wallet_id(wallet_id.clone()).expect("owner wallet");
    let tx_json = create_transaction(
        contact_id.clone(),
        "expense".to_string(),
        "owed".to_string(),
        500,
        "IQD".to_string(),
        Some("pre-existing".to_string()),
        "2026-01-01".to_string(),
        None,
    )
    .expect("owner create tx");
    let tx: serde_json::Value = serde_json::from_str(&tx_json).expect("parse tx");
    let tx_id = tx["id"].as_str().expect("tx id").to_string();
    manual_sync().expect("owner sync");

    member.activate().expect("activate member");
    set_current_wallet_id(wallet_id).expect("member wallet");
    manual_sync().expect("member sync");

    assert_perm_denied(
        create_contact("X".to_string(), None, None, None, None, None),
        "create_contact",
    );
    assert_perm_denied(
        update_contact(
            contact_id.clone(),
            "Y".to_string(),
            None,
            None,
            None,
            None,
            None,
        ),
        "update_contact",
    );
    assert_perm_denied(delete_contact(contact_id.clone()), "delete_contact");
    assert_perm_denied(
        create_transaction(
            contact_id.clone(),
            "expense".to_string(),
            "owed".to_string(),
            1,
            "IQD".to_string(),
            None,
            "2026-01-01".to_string(),
            None,
        ),
        "create_transaction",
    );
    assert_perm_denied(
        update_transaction(
            tx_id.clone(),
            contact_id,
            "expense".to_string(),
            "owed".to_string(),
            2,
            "IQD".to_string(),
            None,
            "2026-01-01".to_string(),
            None,
        ),
        "update_transaction",
    );
    assert_perm_denied(delete_transaction(tx_id), "delete_transaction");
}
