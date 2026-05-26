//! Stage 2.a wallet permission regression test.
//!
//! Goal (current stage):
//! - Users may *view* other wallets (GET wallet details is not membership-gated yet)
//! - Users must NOT be able to *edit* wallets they are not a member of
//! - Users must be able to edit their *own* wallet (owner/admin)
//!
//! Note: This test is ignored by default because it requires a running test database.

use debt_tracker_api::handlers::wallets;
use debt_tracker_api::middleware::auth::AuthUser;

mod test_helpers;
use test_helpers::*;

#[tokio::test]
#[ignore]
async fn stage2a_cannot_edit_wallet_you_are_not_in_but_can_view_it() {
    let pool = setup_test_db().await;

    // Two users, two wallets.
    let user_a = create_test_user_with_email(&pool, "user_a@example.com").await;
    let user_b = create_test_user_with_email(&pool, "user_b@example.com").await;

    let wallet_a = create_test_wallet(&pool, "Wallet A").await;
    let wallet_b = create_test_wallet(&pool, "Wallet B").await;

    // Membership: user A owns wallet A, user B owns wallet B.
    add_user_to_wallet(&pool, user_a, wallet_a, "owner").await;
    add_user_to_wallet(&pool, user_b, wallet_b, "owner").await;

    let config = std::sync::Arc::new(debt_tracker_api::config::Config::from_env().unwrap());
    let broadcast_tx = debt_tracker_api::websocket::create_broadcast_channel();
    let app_state = test_helpers::create_test_app_state(pool.clone(), config, broadcast_tx);

    // Control: user A edits wallet A (should succeed).
    let update_request = wallets::UpdateWalletRequest {
        name: Some("Wallet A (edited)".to_string()),
        description: None,
        is_active: None,
    };
    let ok = wallets::update_wallet(
        axum::extract::Path(wallet_a.to_string()),
        axum::extract::State(app_state.clone()),
        axum::extract::Extension(AuthUser { user_id: user_a, email: "user_a@example.com".to_string(), is_admin: false }),
        axum::Json(update_request),
    )
    .await;
    assert!(ok.is_ok(), "expected user A to edit their own wallet");

    // View: user A can view wallet B (allowed at this stage).
    let view = wallets::get_wallet(
        axum::extract::Path(wallet_b.to_string()),
        axum::extract::State(app_state.clone()),
    )
    .await;
    assert!(view.is_ok(), "expected to be able to view wallet B at this stage");

    // Deny: user A cannot edit wallet B.
    let update_other = wallets::UpdateWalletRequest {
        name: Some("Wallet B (hacked)".to_string()),
        description: None,
        is_active: None,
    };
    let denied = wallets::update_wallet(
        axum::extract::Path(wallet_b.to_string()),
        axum::extract::State(app_state),
        axum::extract::Extension(AuthUser { user_id: user_a, email: "user_a@example.com".to_string(), is_admin: false }),
        axum::Json(update_other),
    )
    .await;
    assert!(denied.is_err(), "expected edit of other user's wallet to be denied");
    let (status, _body) = denied.err().unwrap();
    assert_eq!(status, axum::http::StatusCode::FORBIDDEN);
}

