//! Regression tests for the "clear_wallet leaves the per-wallet last_hash
//! anchor in place" class of bugs.
//!
//! Shape of the bug we fixed:
//!
//!   1. Client syncs N events → server's `latest_hash` is some H, client
//!      stores `server_hash_{wallet}` = H, projection has the N events.
//!   2. Something invokes `clear_wallet` (a permission write triggers
//!      `put_wallet_permission_matrix` → `clear_wallet_and_resync`).
//!      Pre-fix, `clear_wallet` wiped events + projection + the
//!      `last_sync_timestamp_{wallet}` key, but NOT the
//!      `server_hash_{wallet}` key.
//!   3. The follow-up `pull_and_merge` then sent H as `last_hash`. The
//!      server's chain still contained H, so the response was an
//!      *incremental* delta from that anchor (`flush=false`) instead of
//!      a full pull with `flush=true`.
//!   4. The client's local events table had just been wiped, so any
//!      event whose row_id was <= H's row_id was permanently absent
//!      from the projection — the contact CREATE event most often.
//!
//! Tests in this file lock in the invariant: after `clear_wallet` (and
//! any path that delegates to it, like `set_permission_matrix` on the
//! current wallet), the next pull must produce a `flush=true` response
//! and the local state must end up matching everything the server says
//! is readable. Counts only — no white-box dependence on which config
//! keys exist.

use crate::common::app_instance::AppInstance;
use crate::common::test_helpers::test_server_url;

fn make_app(id: &str) -> AppInstance {
    let server_url = test_server_url();
    let app = AppInstance::new(id, &server_url);
    app.initialize().expect("initialize");
    app.signup().expect("signup");
    app
}

/// Direct call to the storage::clear_wallet path. After clearing,
/// pull_and_merge must NOT do an incremental against a stale anchor —
/// the local projection has to end up matching the server's full
/// readable set, not just the tail.
#[test]
#[ignore]
fn clear_wallet_followed_by_sync_restores_full_state() {
    let app = make_app("clear-wallet-direct");

    // Build up real state: 1 contact + 3 transactions.
    app.run_commands(&[
        "contact create \"Alice\" alice",
        "transaction create alice owed 1000 \"t1\" t1",
        "transaction create alice lent  300 \"t2\" t2",
        "transaction create alice owed  500 \"t3\" t3",
    ])
    .expect("setup");
    app.sync().expect("sync 1");

    app.assert_commands(&["contacts count 1", "transactions count 3"])
        .expect("pre-clear state");

    // The bug-shape operation: clear_wallet wipes local events +
    // projection. Pre-fix this left server_hash behind; the next pull
    // would then return only events strictly after that stale anchor.
    let wallet_id = client::get_current_wallet_id()
        .expect("current_wallet_id present");
    client::clear_wallet_data(wallet_id).expect("clear_wallet_data");

    // Local should be wiped right after clear.
    app.assert_commands(&["contacts count 0", "transactions count 0"])
        .expect("post-clear state must be empty");

    // The recovery sync. With the anchor key correctly dropped this is
    // a full pull (flush=true) that rebuilds everything. With the bug
    // present, the server returns 0 events (everything is <= the stale
    // anchor) and the projection stays empty.
    app.sync().expect("post-clear sync");

    app.assert_commands(&[
        "contacts count 1",
        "transactions count 3",
        // Net: +1000 -300 +500 = +1200.
        "contact \"Alice\" balance 1200",
    ])
    .expect("post-clear sync must rebuild full state from server");
}

/// The exact public-API surface that broke the permissions tests:
/// `put_wallet_permission_matrix` calls `clear_wallet_and_resync`
/// internally whenever the matrix is set on the current wallet. After
/// that round-trip, every pre-permission event must still be in the
/// projection.
///
/// Pre-fix, the matrix-set call wiped local + did an incremental sync
/// against a stale anchor, losing the contact CREATE event (which lived
/// at a row_id smaller than the anchor's).
#[test]
#[ignore]
fn set_permission_matrix_preserves_pre_permission_events() {
    let app = make_app("clear-wallet-via-perms");

    app.run_commands(&[
        "contact create \"Alice\" alice",
        "transaction create alice owed 999 \"x\" t1",
    ])
    .expect("setup");
    app.sync().expect("sync 1");

    app.assert_commands(&["contacts count 1", "transactions count 1"])
        .expect("pre-matrix state");

    // Set a no-op permission matrix on the current wallet. The
    // `put_wallet_permission_matrix` server call followed by
    // `clear_wallet_and_resync` is what triggered the bug.
    let wallet_id = client::get_current_wallet_id()
        .expect("current_wallet_id present");
    let cg_all = {
        let groups_json = client::list_wallet_contact_groups(wallet_id.clone())
            .expect("list contact groups");
        let groups: Vec<serde_json::Value> =
            serde_json::from_str(&groups_json).expect("parse contact groups");
        groups
            .iter()
            .find(|g| g["name"] == "all_contacts")
            .and_then(|g| g["id"].as_str())
            .expect("all_contacts group exists")
            .to_string()
    };
    let ug_all = {
        let groups_json = client::list_wallet_user_groups(wallet_id.clone())
            .expect("list user groups");
        let groups: Vec<serde_json::Value> =
            serde_json::from_str(&groups_json).expect("parse user groups");
        groups
            .iter()
            .find(|g| g["name"] == "all_users")
            .and_then(|g| g["id"].as_str())
            .expect("all_users group exists")
            .to_string()
    };
    let entries = serde_json::json!([{
        "user_group_id": ug_all,
        "contact_group_id": cg_all,
        "allowed_actions": ["contact:read", "transaction:read"],
        "denied_actions": []
    }]);
    client::put_wallet_permission_matrix(wallet_id, entries.to_string())
        .expect("put matrix triggers clear_wallet_and_resync internally");

    // Pre-fix: the post-matrix sync returned an empty incremental from
    // the stale anchor, leaving the projection empty. Post-fix: the
    // anchor was cleared, the sync was a full pull with flush=true,
    // and every pre-matrix event is back in the projection.
    app.assert_commands(&[
        "contacts count 1",
        "transactions count 1",
        "contact \"Alice\" balance 999",
    ])
    .expect("set_permission_matrix must not lose pre-permission events");
}
