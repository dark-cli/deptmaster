//! Regression tests for contact-balance arithmetic.
//!
//! Bug being captured: the "give" direction (`lent` in the wire format)
//! is being silently ignored in the per-contact balance and the wallet
//! total_debt. Both `owed` and `lent` amounts get summed flat with
//! `SUM(amount)`, so a wallet with one give-1000 and one receive-1000
//! reports a balance of 2000 instead of 0.
//!
//! Convention (matches the dashboard chart + total_debt semantics):
//!   owed (received): the contact owes the wallet user → contributes +amount
//!   lent (give):     the wallet user owes the contact → contributes -amount
//!
//! Once the projection-side fix lands these tests should pass without
//! changes — they exercise the public assertion vocabulary, not the
//! storage internals.

use crate::common::app_instance::AppInstance;
use crate::common::test_helpers::test_server_url;

fn make_app() -> AppInstance {
    let server_url = test_server_url();
    let app = AppInstance::new("app", &server_url);
    app.initialize().expect("initialize");
    // signup() registers + auto-creates a wallet + selects it as current.
    app.signup().expect("signup");
    app
}

/// One contact, one received (`owed`) 1000, one give (`lent`) 1000.
/// Net balance should be 0. Bug: comes back as 2000 because both
/// directions sum positively.
#[test]
#[ignore]
fn balance_cancels_when_give_equals_received() {
    let app = make_app();
    app.run_commands(&[
        "contact create \"Alice\" alice",
        "transaction create alice owed 1000 \"received from alice\" t1",
        "transaction create alice lent 1000 \"give to alice\" t2",
    ])
    .expect("execute_commands");
    app.sync().expect("sync");

    app.assert_commands(&[
        "contacts count 1",
        "transactions count 2",
        "contact \"Alice\" balance 0",
    ])
    .expect("balance should net to 0");
}

/// One contact, several mixed-direction transactions. Net balance is
/// the signed sum: +1000 -300 +500 -200 = +1000 (Alice owes the user).
#[test]
#[ignore]
fn balance_signed_sum_across_mixed_directions() {
    let app = make_app();
    app.run_commands(&[
        "contact create \"Alice\" alice",
        "transaction create alice owed 1000 \"a\" t1",
        "transaction create alice lent 300  \"b\" t2",
        "transaction create alice owed 500  \"c\" t3",
        "transaction create alice lent 200  \"d\" t4",
    ])
    .expect("execute_commands");
    app.sync().expect("sync");

    app.assert_commands(&[
        "contacts count 1",
        "transactions count 4",
        "contact \"Alice\" balance 1000",
    ])
    .expect("net balance must respect give/received signs");
}

/// Two contacts, transactions to each — balances must be computed per
/// contact, not pooled. A give-only contact has a negative balance; a
/// received-only contact has a positive one.
#[test]
#[ignore]
fn balance_is_isolated_per_contact() {
    let app = make_app();
    app.run_commands(&[
        "contact create \"Alice\" alice",
        "contact create \"Bob\" bob",
        "transaction create alice owed 700 \"alice owes me\" t1",
        "transaction create bob   lent 400 \"I owe bob\"     t2",
    ])
    .expect("execute_commands");
    app.sync().expect("sync");

    app.assert_commands(&[
        "contacts count 2",
        "transactions count 2",
        "contact \"Alice\" balance 700",
        "contact \"Bob\" balance -400",
    ])
    .expect("per-contact balance");
}
