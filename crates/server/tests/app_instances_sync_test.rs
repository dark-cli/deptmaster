//! Simulate multiple app instances (different users) syncing against the same backend.
//! Tests that read-permission filtering and "full pull replaces local" work end-to-end.
//! Uses handler calls directly (no HTTP server) to avoid axum-test/axum version skew.
//!
//! Run with: cargo test --test app_instances_sync_test -- --ignored

use axum::extract::Query;
use chrono::Utc;
use domain::{DomainEvent, EventData};
use server::handlers::sync::{
    get_sync_events, get_sync_hash, post_sync_events, SyncEvent, SyncEventsQuery,
};
use server::middleware::auth::AuthUser;
use server::middleware::wallet_context::WalletContext;
use domain::WalletRole;
use server::{AppState, Config};
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
        json.0.events
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
async fn test_sync_read_permission_filter_and_full_pull() {
    let pool = setup_test_db().await;

    // Users: owner (full access), member (limited contact:read via group "Limited")
    let owner_id =
        create_test_user_with_email(&pool, &format!("owner-{}@test.local", Uuid::new_v4())).await;
    let member_id =
        create_test_user_with_email(&pool, &format!("member-{}@test.local", Uuid::new_v4())).await;

    let wallet_id = create_test_wallet(&pool, "Shared Wallet").await;
    add_user_to_wallet(&pool, owner_id, wallet_id, "owner").await;
    add_user_to_wallet(&pool, member_id, wallet_id, "member").await;

    ensure_wallet_has_system_groups(&pool, wallet_id).await;

    // Create __owners__ group with full permissions on all contacts
    sqlx::query(
        "INSERT INTO user_groups (wallet_id, name, is_system) VALUES ($1, '__owners__', true)
         ON CONFLICT (wallet_id, name) DO UPDATE SET is_system = true",
    )
    .bind(wallet_id)
    .execute(&pool)
    .await
    .expect("create __owners__");

    let owners_group_id: Uuid = sqlx::query_scalar(
        "SELECT id FROM user_groups WHERE wallet_id = $1 AND name = '__owners__'",
    )
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .expect("get __owners__ id");

    // Add owner to __owners__ group
    sqlx::query(
        "INSERT INTO user_group_members (user_group_id, user_id) VALUES ($1, $2)
         ON CONFLICT (user_group_id, user_id) DO NOTHING",
    )
    .bind(owners_group_id)
    .bind(owner_id)
    .execute(&pool)
    .await
    .expect("add owner to __owners__");

    // Contact group "Limited": only contact A will be in it. Member gets contact:read only for this group.
    sqlx::query(
        "INSERT INTO contact_groups (wallet_id, name, type, is_system) VALUES ($1, 'Limited', 'static', false)",
    )
    .bind(wallet_id)
    .execute(&pool)
    .await
    .expect("create Limited group");

    let limited_cg_id: Uuid = sqlx::query_scalar(
        "SELECT id FROM contact_groups WHERE wallet_id = $1 AND name = 'Limited'",
    )
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .expect("get Limited group id");

    // Add contact:read for (all_users, Limited) only. Remove full access from (all_users, all_contacts) so member is restricted.
    let all_users_id: Uuid = sqlx::query_scalar(
        "SELECT id FROM user_groups WHERE wallet_id = $1 AND name = 'all_users'",
    )
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .expect("all_users id");
    let all_contacts_id: Uuid = sqlx::query_scalar(
        "SELECT id FROM contact_groups WHERE wallet_id = $1 AND name = 'all_contacts'",
    )
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .expect("all_contacts id");

    sqlx::query(
        "DELETE FROM group_permission_matrix WHERE user_group_id = $1 AND contact_group_id = $2",
    )
    .bind(all_users_id)
    .bind(all_contacts_id)
    .execute(&pool)
    .await
    .ok();

    let contact_read_id: i16 =
        sqlx::query_scalar("SELECT id FROM permission_actions WHERE name = 'contact:read'")
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

    // Grant __owners__ group full permissions on all_contacts
    for act_id in 1..=10_i16 {
        sqlx::query(
            "INSERT INTO group_permission_matrix (user_group_id, contact_group_id, permission_action_id) VALUES ($1, $2, $3)
             ON CONFLICT (user_group_id, contact_group_id, permission_action_id) DO NOTHING",
        )
        .bind(owners_group_id)
        .bind(all_contacts_id)
        .bind(act_id)
        .execute(&pool)
        .await
        .ok();
    }

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

    // Create domain events for contacts A and B
    let event_a_id = Uuid::new_v4();
    let event_b_id = Uuid::new_v4();
    let event_a = DomainEvent {
        id: event_a_id,
        aggregate_id: contact_a_id,
        wallet_id,
        user_id: owner_id,
        created_at: Utc::now(),
        version: 1,
        event_data: EventData::ContactCreated {
            name: "Contact A".to_string(),
            username: None,
            phone: None,
            email: None,
            notes: None,
            group_ids: vec![],
        },
    };
    let event_b = DomainEvent {
        id: event_b_id,
        aggregate_id: contact_b_id,
        wallet_id,
        user_id: owner_id,
        created_at: Utc::now(),
        version: 1,
        event_data: EventData::ContactCreated {
            name: "Contact B".to_string(),
            username: None,
            phone: None,
            email: None,
            notes: None,
            group_ids: vec![],
        },
    };

    let config =
        Arc::new(Config::from_env().expect("Config::from_env (set TEST_DATABASE_URL etc.)"));
    let broadcast_tx = server::websocket::create_broadcast_channel();
    let app_state = create_test_app_state(pool, config, broadcast_tx);

    // Insert events using post_sync_events from owner (which populates user_readable_events)
    let instance_owner = AppInstance {
        auth_user: AuthUser {
            user_id: owner_id,
            username: "owner".to_string(),
            is_admin: false,
        },
        wallet_context: WalletContext::new(wallet_id, WalletRole::Owner),
    };
    let instance_member = AppInstance {
        auth_user: AuthUser {
            user_id: member_id,
            username: "member".to_string(),
            is_admin: false,
        },
        wallet_context: WalletContext::new(wallet_id, WalletRole::Member),
    };

    // Post the events through the sync API (which populates user_readable_events)
    let sync_result = post_sync_events(
        axum::extract::State(app_state.clone()),
        axum::extract::Extension(instance_owner.wallet_context.clone()),
        axum::extract::Extension(instance_owner.auth_user.clone()),
        axum::Json(vec![event_a, event_b]),
    )
    .await;
    assert!(sync_result.is_ok(), "post_sync_events should succeed");
    let response = sync_result.unwrap().0;
    assert_eq!(
        response.accepted.len(),
        2,
        "both events should be accepted, got {}",
        response.accepted.len()
    );

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
