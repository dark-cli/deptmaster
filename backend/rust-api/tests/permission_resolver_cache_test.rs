//! Tests for resolver integration with permission matrix cache
//! Verifies that the resolver correctly uses the cached permissions for ContactGroup lookups

use debt_tracker_api::database::repository::Database;
use debt_tracker_api::permissions::{Action, PermissionContext, PermissionModel, Resource, WalletRole};
use uuid::Uuid;

mod test_helpers;
use test_helpers::*;

/// Helper to check if action is in permission results
fn has_action(actions: &std::collections::HashSet<Action>, action: Action) -> bool {
    actions.contains(&action)
}

/// Test 1: Resolver uses cache for ContactGroup permissions (fast path)
#[tokio::test]
async fn test_resolver_uses_cache_for_contact_group_permissions() {
    let pool = setup_test_db().await;
    let db = Database::new(pool.clone());
    let perm_model = PermissionModel::new(pool.clone());

    // Setup
    let user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    ensure_wallet_has_system_groups(&pool, wallet_id).await;

    let all_users_id: Uuid =
        sqlx::query_scalar("SELECT id FROM user_groups WHERE wallet_id = $1 AND name = 'all_users'")
            .bind(wallet_id)
            .fetch_one(&pool)
            .await
            .expect("get all_users");

    let all_contacts_id: Uuid = sqlx::query_scalar(
        "SELECT id FROM contact_groups WHERE wallet_id = $1 AND name = 'all_contacts'",
    )
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .expect("get all_contacts");

    // Setup user and populate cache
    add_user_to_wallet(&pool, user_id, wallet_id, "member").await;
    sqlx::query(
        "INSERT INTO user_group_members (user_group_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING"
    )
    .bind(all_users_id)
    .bind(user_id)
    .execute(&pool)
    .await
    .expect("add user to all_users");

    db.compute_and_cache_user_permission_matrix(wallet_id, user_id)
        .await
        .expect("compute cache");

    // Query permissions for ContactGroup using resolver (uses cache)
    let ctx = PermissionContext::new(wallet_id, user_id, WalletRole::Member);
    let resource = Resource::ContactGroup(all_contacts_id);

    let actions = perm_model
        .resolve_actions(&ctx, &resource)
        .await
        .expect("resolve actions");

    // Verify we got permissions from cache (should have contact:read at minimum)
    assert!(
        !actions.is_empty(),
        "Should have permissions for all_contacts from cache"
    );
    assert!(
        has_action(&actions, Action::ContactRead),
        "Should have contact:read permission from cache"
    );
}

/// Test 2: Cache is used even with deny entries
#[tokio::test]
async fn test_resolver_respects_cache_deny_entries() {
    let pool = setup_test_db().await;
    let db = Database::new(pool.clone());
    let perm_model = PermissionModel::new(pool.clone());

    // Setup
    let user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    ensure_wallet_has_system_groups(&pool, wallet_id).await;

    let all_users_id: Uuid =
        sqlx::query_scalar("SELECT id FROM user_groups WHERE wallet_id = $1 AND name = 'all_users'")
            .bind(wallet_id)
            .fetch_one(&pool)
            .await
            .expect("get all_users");

    let all_contacts_id: Uuid = sqlx::query_scalar(
        "SELECT id FROM contact_groups WHERE wallet_id = $1 AND name = 'all_contacts'",
    )
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .expect("get all_contacts");

    // Setup user and populate cache
    add_user_to_wallet(&pool, user_id, wallet_id, "member").await;
    sqlx::query(
        "INSERT INTO user_group_members (user_group_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING"
    )
    .bind(all_users_id)
    .bind(user_id)
    .execute(&pool)
    .await
    .expect("add user to all_users");

    db.compute_and_cache_user_permission_matrix(wallet_id, user_id)
        .await
        .expect("compute cache");

    // Add a deny entry to cache (contact:read is denied)
    sqlx::query(
        "INSERT INTO user_permission_matrix_cache
         (wallet_id, user_id, contact_group_id, permission_action_id, is_deny)
         VALUES ($1, $2, $3, 2, true)
         ON CONFLICT (wallet_id, user_id, contact_group_id, permission_action_id)
         DO UPDATE SET is_deny = true"
    )
    .bind(wallet_id)
    .bind(user_id)
    .bind(all_contacts_id)
    .execute(&pool)
    .await
    .expect("add deny entry for contact:read");

    // Query permissions - resolver should respect deny
    let ctx = PermissionContext::new(wallet_id, user_id, WalletRole::Member);
    let resource = Resource::ContactGroup(all_contacts_id);

    let actions = perm_model
        .resolve_actions(&ctx, &resource)
        .await
        .expect("resolve actions");

    // Verify contact:read is NOT in results (denied)
    assert!(
        !has_action(&actions, Action::ContactRead),
        "contact:read should be denied (not in results)"
    );
}

/// Test 3: Cache performance - multiple queries use same cached data
#[tokio::test]
async fn test_resolver_cache_performance_multiple_queries() {
    let pool = setup_test_db().await;
    let db = Database::new(pool.clone());
    let perm_model = PermissionModel::new(pool.clone());

    // Setup
    let user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    ensure_wallet_has_system_groups(&pool, wallet_id).await;

    let all_users_id: Uuid =
        sqlx::query_scalar("SELECT id FROM user_groups WHERE wallet_id = $1 AND name = 'all_users'")
            .bind(wallet_id)
            .fetch_one(&pool)
            .await
            .expect("get all_users");

    let all_contacts_id: Uuid = sqlx::query_scalar(
        "SELECT id FROM contact_groups WHERE wallet_id = $1 AND name = 'all_contacts'",
    )
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .expect("get all_contacts");

    // Setup and cache
    add_user_to_wallet(&pool, user_id, wallet_id, "member").await;
    sqlx::query(
        "INSERT INTO user_group_members (user_group_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING"
    )
    .bind(all_users_id)
    .bind(user_id)
    .execute(&pool)
    .await
    .expect("add user to all_users");

    db.compute_and_cache_user_permission_matrix(wallet_id, user_id)
        .await
        .expect("compute cache");

    let ctx = PermissionContext::new(wallet_id, user_id, WalletRole::Member);
    let resource = Resource::ContactGroup(all_contacts_id);

    // Multiple queries should all use the same cached data
    let results1 = perm_model
        .resolve_actions(&ctx, &resource)
        .await
        .expect("first query");
    let results2 = perm_model
        .resolve_actions(&ctx, &resource)
        .await
        .expect("second query");
    let results3 = perm_model
        .resolve_actions(&ctx, &resource)
        .await
        .expect("third query");

    // All results should be identical (same cache used)
    assert_eq!(
        results1, results2,
        "First and second queries should return same cached results"
    );
    assert_eq!(
        results2, results3,
        "Second and third queries should return same cached results"
    );
}

/// Test 4: Cache is invalidated and repopulated correctly
#[tokio::test]
async fn test_resolver_cache_invalidation_and_repopulation() {
    let pool = setup_test_db().await;
    let db = Database::new(pool.clone());
    let perm_model = PermissionModel::new(pool.clone());

    // Setup
    let user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    ensure_wallet_has_system_groups(&pool, wallet_id).await;

    let all_users_id: Uuid =
        sqlx::query_scalar("SELECT id FROM user_groups WHERE wallet_id = $1 AND name = 'all_users'")
            .bind(wallet_id)
            .fetch_one(&pool)
            .await
            .expect("get all_users");

    let all_contacts_id: Uuid = sqlx::query_scalar(
        "SELECT id FROM contact_groups WHERE wallet_id = $1 AND name = 'all_contacts'",
    )
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .expect("get all_contacts");

    // Initial setup and cache
    add_user_to_wallet(&pool, user_id, wallet_id, "member").await;
    sqlx::query(
        "INSERT INTO user_group_members (user_group_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING"
    )
    .bind(all_users_id)
    .bind(user_id)
    .execute(&pool)
    .await
    .expect("add user to all_users");

    db.compute_and_cache_user_permission_matrix(wallet_id, user_id)
        .await
        .expect("compute initial cache");

    let ctx = PermissionContext::new(wallet_id, user_id, WalletRole::Member);
    let resource = Resource::ContactGroup(all_contacts_id);

    let actions_before = perm_model
        .resolve_actions(&ctx, &resource)
        .await
        .expect("query before invalidation");

    // Invalidate cache
    db.invalidate_permission_matrix_cache(wallet_id, user_id)
        .await
        .expect("invalidate cache");

    // After invalidation, cache is empty
    let cache_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM user_permission_matrix_cache WHERE wallet_id = $1 AND user_id = $2"
    )
    .bind(wallet_id)
    .bind(user_id)
    .fetch_one(&pool)
    .await
    .expect("count cache after invalidation");

    assert_eq!(cache_count, 0, "Cache should be empty after invalidation");

    // Repopulate cache
    db.compute_and_cache_user_permission_matrix(wallet_id, user_id)
        .await
        .expect("recompute cache");

    let actions_after = perm_model
        .resolve_actions(&ctx, &resource)
        .await
        .expect("query after repopulation");

    // Results should be identical before and after
    assert_eq!(
        actions_before, actions_after,
        "Results should be identical after cache invalidation and repopulation"
    );
}

/// Test 5: Different users have independent cache entries
#[tokio::test]
async fn test_resolver_cache_independent_per_user() {
    let pool = setup_test_db().await;
    let db = Database::new(pool.clone());
    let perm_model = PermissionModel::new(pool.clone());

    // Setup two users
    let user1_id = create_test_user(&pool).await;
    let user2_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    ensure_wallet_has_system_groups(&pool, wallet_id).await;

    let all_users_id: Uuid =
        sqlx::query_scalar("SELECT id FROM user_groups WHERE wallet_id = $1 AND name = 'all_users'")
            .bind(wallet_id)
            .fetch_one(&pool)
            .await
            .expect("get all_users");

    let all_contacts_id: Uuid = sqlx::query_scalar(
        "SELECT id FROM contact_groups WHERE wallet_id = $1 AND name = 'all_contacts'",
    )
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .expect("get all_contacts");

    // Setup both users
    for user_id in [user1_id, user2_id] {
        add_user_to_wallet(&pool, user_id, wallet_id, "member").await;
        sqlx::query(
            "INSERT INTO user_group_members (user_group_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING"
        )
        .bind(all_users_id)
        .bind(user_id)
        .execute(&pool)
        .await
        .expect("add user to all_users");

        db.compute_and_cache_user_permission_matrix(wallet_id, user_id)
            .await
            .expect("compute cache");
    }

    // Add deny for user1 only
    sqlx::query(
        "INSERT INTO user_permission_matrix_cache
         (wallet_id, user_id, contact_group_id, permission_action_id, is_deny)
         VALUES ($1, $2, $3, 2, true)
         ON CONFLICT (wallet_id, user_id, contact_group_id, permission_action_id)
         DO UPDATE SET is_deny = true"
    )
    .bind(wallet_id)
    .bind(user1_id)
    .bind(all_contacts_id)
    .execute(&pool)
    .await
    .expect("add deny for user1");

    let resource = Resource::ContactGroup(all_contacts_id);

    // Query both users
    let ctx1 = PermissionContext::new(wallet_id, user1_id, WalletRole::Member);
    let ctx2 = PermissionContext::new(wallet_id, user2_id, WalletRole::Member);

    let actions1 = perm_model
        .resolve_actions(&ctx1, &resource)
        .await
        .expect("resolve for user1");
    let actions2 = perm_model
        .resolve_actions(&ctx2, &resource)
        .await
        .expect("resolve for user2");

    // User1 should NOT have contact:read (denied)
    assert!(
        !has_action(&actions1, Action::ContactRead),
        "User1 should have contact:read denied"
    );

    // User2 should have contact:read (not denied)
    assert!(
        has_action(&actions2, Action::ContactRead),
        "User2 should have contact:read allowed"
    );
}
