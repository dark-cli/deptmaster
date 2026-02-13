//! Simulate multiple app instances (different users) syncing against the same backend.
//! Tests that read-permission filtering and "full pull replaces local" work end-to-end.
//! Uses handler calls directly (no HTTP server) to avoid axum-test/axum version skew.
//!
//! Run with: cargo test --test app_instances_sync_test -- --ignored

use axum::extract::Query;
use debt_tracker_api::handlers::sync::{get_sync_events, get_sync_hash, SyncEvent, SyncEventsQuery};
use debt_tracker_api::middleware::auth::AuthUser;
use debt_tracker_api::middleware::wallet_context::WalletContext;
use debt_tracker_api::{AppState, Config};
use std::sync::Arc;
use uuid::Uuid;

mod test_helpers;
use test_helpers::*;

/// Simulated app instance: auth user + wallet context. "Full sync" = get_sync_events with no since.
struct AppInstance {
    auth_user: AuthUser,
    wallet_context: WalletContext,
}

impl AppInstance {
    /// Call get_sync_events (no since = full pull). Returns events (owned).
    async fn get_sync_events(&self, state: &AppState, since: Option<String>) -> Vec<SyncEvent> {
        let query = SyncEventsQuery { since };
        let result = get_sync_events(
            Query(query),
            axum::extract::State(state.clone()),
            axum::extract::Extension(self.wallet_context.clone()),
            axum::extract::Extension(self.auth_user.clone()),
        )
        .await;
        let json = result.expect("get_sync_events");
        json.0
    }

    /// Call get_sync_hash.
    async fn get_sync_hash(&self, state: &AppState) -> (String, i64) {
        let result = get_sync_hash(
            axum::extract::State(state.clone()),
            axum::extract::Extension(self.wallet_context.clone()),
            axum::extract::Extension(self.auth_user.clone()),
        )
        .await;
        let json = result.expect("get_sync_hash");
        (json.hash.clone(), json.event_count)
    }
}

#[tokio::test]
#[ignore] // requires test DB: cargo test --ignored app_instances
async fn test_sync_read_permission_filter_and_full_pull() {
    let pool = setup_test_db().await;

    // Users: owner (full access), member (limited contact:read via group "Limited")
    let owner_id = create_test_user_with_email(&pool, "owner@test.local").await;
    let member_id = create_test_user_with_email(&pool, "member@test.local").await;

    let wallet_id = create_test_wallet(&pool, "Shared Wallet").await;
    add_user_to_wallet(&pool, owner_id, wallet_id, "owner").await;
    add_user_to_wallet(&pool, member_id, wallet_id, "member").await;

    ensure_wallet_has_system_groups(&pool, wallet_id).await;

    // Contact group "Limited": only contact A will be in it. Member gets contact:read only for this group.
    sqlx::query(
        "INSERT INTO contact_groups (wallet_id, name, type, is_system) VALUES ($1, 'Limited', 'static', false)",
    )
    .bind(wallet_id)
    .execute(&pool)
    .await
    .expect("create Limited group");

    let limited_cg_id: Uuid = sqlx::query_scalar("SELECT id FROM contact_groups WHERE wallet_id = $1 AND name = 'Limited'")
        .bind(wallet_id)
        .fetch_one(&pool)
        .await
        .expect("get Limited group id");

    // Add contact:read for (all_users, Limited) only. Remove full access from (all_users, all_contacts) so member is restricted.
    let all_users_id: Uuid = sqlx::query_scalar("SELECT id FROM user_groups WHERE wallet_id = $1 AND name = 'all_users'")
        .bind(wallet_id)
        .fetch_one(&pool)
        .await
        .expect("all_users id");
    let all_contacts_id: Uuid = sqlx::query_scalar("SELECT id FROM contact_groups WHERE wallet_id = $1 AND name = 'all_contacts'")
        .bind(wallet_id)
        .fetch_one(&pool)
        .await
        .expect("all_contacts id");

    sqlx::query("DELETE FROM group_permission_matrix WHERE user_group_id = $1 AND contact_group_id = $2")
        .bind(all_users_id)
        .bind(all_contacts_id)
        .execute(&pool)
        .await
        .ok();

    let contact_read_id: i16 = sqlx::query_scalar("SELECT id FROM permission_actions WHERE name = 'contact:read'")
        .fetch_one(&pool)
        .await
        .expect("contact:read action id");
    sqlx::query(
        "INSERT INTO group_permission_matrix (user_group_id, contact_group_id, permission_action_id) VALUES ($1, $2, $3)",
    )
    .bind(all_users_id)
    .bind(limited_cg_id)
    .bind(contact_read_id)
    .execute(&pool)
    .await
    .expect("grant contact:read on Limited");

    // Create two contacts in projection (so contact_group_members can reference them)
    let contact_a_id = Uuid::new_v4();
    let contact_b_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO contacts_projection (id, user_id, wallet_id, name, is_deleted, created_at, updated_at, last_event_id) VALUES ($1, $2, $3, 'Contact A', false, NOW(), NOW(), 0)",
    )
    .bind(contact_a_id)
    .bind(owner_id)
    .bind(wallet_id)
    .execute(&pool)
    .await
    .expect("insert contact A");
    sqlx::query(
        "INSERT INTO contacts_projection (id, user_id, wallet_id, name, is_deleted, created_at, updated_at, last_event_id) VALUES ($1, $2, $3, 'Contact B', false, NOW(), NOW(), 0)",
    )
    .bind(contact_b_id)
    .bind(owner_id)
    .bind(wallet_id)
    .execute(&pool)
    .await
    .expect("insert contact B");

    sqlx::query("INSERT INTO contact_group_members (contact_id, contact_group_id) VALUES ($1, $2)")
        .bind(contact_a_id)
        .bind(limited_cg_id)
        .execute(&pool)
        .await
        .expect("add contact A to Limited");

    // Insert two contact events (CREATED) so owner sees both, member should see only A's
    let event_a_id = Uuid::new_v4();
    let event_b_id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO events (event_id, user_id, wallet_id, aggregate_type, aggregate_id, event_type, event_version, event_data, created_at)
           VALUES ($1, $2, $3, 'contact', $4, 'CREATED', 1, $5, NOW())"#,
    )
    .bind(event_a_id)
    .bind(owner_id)
    .bind(wallet_id)
    .bind(contact_a_id)
    .bind(serde_json::json!({"name": "Contact A"}))
    .execute(&pool)
    .await
    .expect("insert event A");
    sqlx::query(
        r#"INSERT INTO events (event_id, user_id, wallet_id, aggregate_type, aggregate_id, event_type, event_version, event_data, created_at)
           VALUES ($1, $2, $3, 'contact', $4, 'CREATED', 1, $5, NOW())"#,
    )
    .bind(event_b_id)
    .bind(owner_id)
    .bind(wallet_id)
    .bind(contact_b_id)
    .bind(serde_json::json!({"name": "Contact B"}))
    .execute(&pool)
    .await
    .expect("insert event B");

    let config = Arc::new(Config::from_env().expect("Config::from_env (set TEST_DATABASE_URL etc.)"));
    let broadcast_tx = debt_tracker_api::websocket::create_broadcast_channel();
    let app_state = create_test_app_state(pool, config, broadcast_tx);

    let instance_owner = AppInstance {
        auth_user: AuthUser {
            user_id: owner_id,
            username: "owner".to_string(),
            is_admin: false,
        },
        wallet_context: WalletContext::new(wallet_id, "owner".to_string()),
    };
    let instance_member = AppInstance {
        auth_user: AuthUser {
            user_id: member_id,
            username: "member".to_string(),
            is_admin: false,
        },
        wallet_context: WalletContext::new(wallet_id, "member".to_string()),
    };

    // Owner: full pull sees both events
    let owner_events = instance_owner.get_sync_events(&app_state, None).await;
    assert!(
        owner_events.len() >= 2,
        "owner should see at least 2 contact events, got {}",
        owner_events.len()
    );

    // Member: full pull sees only contact A's event (read permission filtered)
    let member_events = instance_member.get_sync_events(&app_state, None).await;
    assert_eq!(
        member_events.len(),
        1,
        "member should see exactly 1 event (contact A), got {}",
        member_events.len()
    );
    assert_eq!(
        member_events[0].aggregate_id,
        contact_a_id.to_string(),
        "member event should be contact A"
    );

    // Simulate "clear local and full fetch" for member: call again with no since -> same filtered set
    let member_events_again = instance_member.get_sync_events(&app_state, None).await;
    assert_eq!(
        member_events_again.len(),
        1,
        "member full pull again should still see 1 event"
    );
    assert_eq!(
        member_events_again[0].aggregate_id,
        contact_a_id.to_string()
    );

    // Hash for member should reflect only 1 event
    let (_hash_member, count_member) = instance_member.get_sync_hash(&app_state).await;
    assert_eq!(count_member, 1, "member sync hash event_count should be 1");
}
