//! Regression test: a permission matrix grant must survive an UNDO.
//!
//! Bug shape (see memory `permission-matrix-undo-corruption-bug`):
//!
//!   * `put_permission_matrix` (HTTP handler) writes
//!     `group_permission_matrix` directly via
//!     `set_permission_matrix_entries_impl`, then emits a
//!     `PERMISSION_MATRIX_SET` event for sync / cache invalidation.
//!   * The applier branch for that event is a NO-OP
//!     (`crates/core/applier/src/lib.rs:631`).
//!   * Any UNDO event in the wallet triggers
//!     `Projections::rebuild_projections_from_events`, whose UNDO branch
//!     does `DELETE FROM user_groups WHERE wallet_id = $1 AND
//!     is_system = false` (and the same for contact_groups). Both FKs
//!     on `group_permission_matrix` are ON DELETE CASCADE, so every
//!     matrix row for non-system groups is wiped.
//!   * The rebuild then replays events. `USER_GROUP_CREATED` /
//!     `CONTACT_GROUP_CREATED` re-create the groups with their original
//!     UUIDs (so the UI still sees them), but `PermissionMatrixSet`
//!     replays as a no-op — the matrix rows are gone forever.
//!
//! Observable effect: a member who used to be able to act on a contact
//! via a custom (user_group × contact_group) grant suddenly gets
//! `DEBITUM_INSUFFICIENT_WALLET_PERMISSION` after any UNDO anywhere
//! in the wallet.
//!
//! This test wires up that exact scenario end-to-end and asserts the
//! grant still works after the UNDO. It MUST fail on current code and
//! pass once the applier event-sources `PermissionMatrixSet`.

use client::{
    add_user_to_wallet, add_wallet_contact_group_member, add_wallet_user_group_member,
    create_contact, create_wallet_contact_group, create_wallet_user_group, manual_sync,
    put_wallet_permission_matrix, set_current_wallet_id, undo_contact_action, update_contact,
};

use crate::common::app_instance::{create_unique_test_user_and_wallet, AppInstance};
use crate::common::test_helpers::test_server_url;

#[test]
#[ignore]
fn permission_matrix_grant_survives_wallet_undo() {
    let server_url = test_server_url();

    // ---------- owner: wallet + contact + groups + grant ----------
    let (owner_username, owner_password, wallet_id) =
        create_unique_test_user_and_wallet(&server_url).expect("create owner");
    let owner = AppInstance::with_credentials("owner", &server_url, owner_username, owner_password);
    owner.initialize().expect("init owner");
    owner.login().expect("login owner");
    owner
        .select_wallet(&wallet_id)
        .expect("owner select wallet");
    owner.activate().expect("activate owner");
    set_current_wallet_id(wallet_id.clone()).expect("owner current wallet");

    // The contact whose permission we will guard with the custom matrix.
    let contact_json = create_contact("Target".to_string(), None, None, None, None, None)
        .expect("owner create Target");
    let target: serde_json::Value = serde_json::from_str(&contact_json).expect("parse target");
    let target_id = target["id"].as_str().expect("target id").to_string();

    let team_json =
        create_wallet_user_group(wallet_id.clone(), "Team".to_string()).expect("create Team");
    let team: serde_json::Value = serde_json::from_str(&team_json).expect("parse Team");
    let team_id = team["id"].as_str().expect("team id").to_string();

    let sensitive_json = create_wallet_contact_group(wallet_id.clone(), "Sensitive".to_string())
        .expect("create Sensitive");
    let sensitive: serde_json::Value =
        serde_json::from_str(&sensitive_json).expect("parse Sensitive");
    let sensitive_id = sensitive["id"].as_str().expect("sensitive id").to_string();

    add_wallet_contact_group_member(wallet_id.clone(), sensitive_id.clone(), target_id.clone())
        .expect("add Target to Sensitive");

    // Sign up a fresh member, join them to the wallet, put them in Team.
    let member = AppInstance::new("member", &server_url);
    member.initialize().expect("init member");
    member.signup().expect("signup member");

    owner.activate().expect("re-activate owner");
    set_current_wallet_id(wallet_id.clone()).expect("owner current wallet");
    add_user_to_wallet(wallet_id.clone(), member.username.clone()).expect("add member to wallet");
    add_wallet_user_group_member(wallet_id.clone(), team_id.clone(), member.username.clone())
        .expect("add member to Team");

    // The grant under test: Team × Sensitive allowed to read + update contacts.
    let entries = serde_json::json!([{
        "user_group_id": team_id,
        "contact_group_id": sensitive_id,
        "allowed_actions": ["contact:read", "contact:update"],
        "denied_actions": []
    }]);
    put_wallet_permission_matrix(wallet_id.clone(), entries.to_string())
        .expect("put Team × Sensitive grant");

    // ---------- member: sanity check the grant works pre-UNDO ----------
    let member_in_wallet = AppInstance::with_credentials(
        "member",
        &server_url,
        member.username.clone(),
        member.password.clone(),
    );
    member_in_wallet
        .initialize()
        .expect("init member-in-wallet");
    member_in_wallet.login().expect("login member-in-wallet");
    member_in_wallet
        .select_wallet(&wallet_id)
        .expect("member select wallet");
    member_in_wallet.activate().expect("activate member");
    set_current_wallet_id(wallet_id.clone()).expect("member current wallet");
    manual_sync().expect("member initial sync");

    update_contact(
        target_id.clone(),
        "Target v2".to_string(),
        None,
        None,
        None,
        None,
        None,
    )
    .expect(
        "pre-UNDO sanity: member must be able to update Target via the \
         Team × Sensitive grant. If this fails the test setup is wrong, \
         not the bug under test.",
    );

    // ---------- owner: introduce an UNDO event ----------
    //
    // Any UNDO in the wallet is enough to fire
    // `rebuild_projections_from_events` on the server, which is what
    // wipes the matrix today. The throwaway contact exists only to
    // give us something to undo within the 5s window.
    owner.activate().expect("activate owner for UNDO");
    set_current_wallet_id(wallet_id.clone()).expect("owner current wallet");
    let throwaway_json = create_contact("Throwaway".to_string(), None, None, None, None, None)
        .expect("owner create throwaway");
    let throwaway: serde_json::Value =
        serde_json::from_str(&throwaway_json).expect("parse throwaway");
    let throwaway_id = throwaway["id"].as_str().expect("throwaway id").to_string();
    undo_contact_action(throwaway_id).expect("owner undo throwaway");
    manual_sync().expect("owner sync — pushes UNDO and triggers server rebuild");

    // ---------- member: the grant must still be in effect ----------
    //
    // Post-rebuild today, `group_permission_matrix` has zero rows for
    // Team × Sensitive because PermissionMatrixSet replayed as a no-op.
    // The server enforces permissions live, so this update is rejected
    // with DEBITUM_INSUFFICIENT_WALLET_PERMISSION. After the fix the
    // applier writes matrix rows on replay and this passes.
    member_in_wallet
        .activate()
        .expect("activate member post-UNDO");
    set_current_wallet_id(wallet_id).expect("member current wallet post-UNDO");
    manual_sync().expect("member post-UNDO sync");

    let result = update_contact(
        target_id,
        "Target v3".to_string(),
        None,
        None,
        None,
        None,
        None,
    );

    assert!(
        result.is_ok(),
        "post-UNDO: Team × Sensitive grant was lost during the server's \
         UNDO rebuild. PermissionMatrixSet must be applied to \
         group_permission_matrix on replay — see \
         crates/core/applier/src/lib.rs:631. Got: {:?}",
        result
    );
}
