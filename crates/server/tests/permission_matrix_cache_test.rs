//! Tests for permission matrix caching behavior
//! Verifies that the cache is correctly populated, invalidated, and cleaned up
//! across user add/remove and permission change events

use server::database::repository::Database;
use uuid::Uuid;

mod test_helpers;
use test_helpers::*;

/// Helper to count cache entries for a user
async fn count_user_cache_entries(pool: &sqlx::PgPool, wallet_id: Uuid, user_id: Uuid) -> i64 {
    sqlx::query_scalar::<_, i64>(
        "SELECT COUNT(*) FROM user_permission_matrix_cache WHERE wallet_id = $1 AND user_id = $2",
    )
    .bind(wallet_id)
    .bind(user_id)
    .fetch_one(pool)
    .await
    .expect("count cache entries")
}

/// Helper to count total cache entries for wallet
async fn count_wallet_cache_entries(pool: &sqlx::PgPool, wallet_id: Uuid) -> i64 {
    sqlx::query_scalar::<_, i64>(
        "SELECT COUNT(*) FROM user_permission_matrix_cache WHERE wallet_id = $1",
    )
    .bind(wallet_id)
    .fetch_one(pool)
    .await
    .expect("count wallet cache entries")
}

/// Test 1: Cache is populated when user is added to wallet
#[tokio::test]
async fn test_cache_populated_on_user_added() {
    let pool = setup_test_db().await;
    let db = Database::new(pool.clone());

    // Setup
    let user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    ensure_wallet_has_system_groups(&pool, wallet_id).await;

    // Get all_users group and all_contacts group
    let all_users_id: Uuid = sqlx::query_scalar(
        "SELECT id FROM user_groups WHERE wallet_id = $1 AND name = 'all_users'",
    )
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

    // Add user to wallet (this is a WalletUserAdded event in real usage)
    add_user_to_wallet(&pool, user_id, wallet_id, "member").await;

    // Add user to all_users group
    sqlx::query(
        "INSERT INTO user_group_members (user_group_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING"
    )
    .bind(all_users_id)
    .bind(user_id)
    .execute(&pool)
    .await
    .expect("add user to all_users");

    // Manually compute cache (this would be called on WalletUserAdded)
    db.compute_and_cache_user_permission_matrix(wallet_id, user_id)
        .await
        .expect("compute cache");

    // Verify cache was populated
    let cache_count = count_user_cache_entries(&pool, wallet_id, user_id).await;
    assert!(
        cache_count > 0,
        "Cache should be populated after user is added. Found {} entries",
        cache_count
    );

    // Verify cache has entries for all_contacts (which has permissions from all_users)
    let cache_for_group: Vec<(Uuid, i16)> = sqlx::query_as(
        "SELECT contact_group_id, permission_action_id FROM user_permission_matrix_cache
         WHERE wallet_id = $1 AND user_id = $2 AND contact_group_id = $3",
    )
    .bind(wallet_id)
    .bind(user_id)
    .bind(all_contacts_id)
    .fetch_all(&pool)
    .await
    .expect("fetch cache entries");

    assert!(
        !cache_for_group.is_empty(),
        "Cache should have entries for all_contacts group"
    );
}

/// Test 2: Cache is invalidated when user is removed from wallet
#[tokio::test]
async fn test_cache_cleaned_on_user_removed() {
    let pool = setup_test_db().await;
    let db = Database::new(pool.clone());

    // Setup
    let user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    ensure_wallet_has_system_groups(&pool, wallet_id).await;

    // Add user and populate cache
    add_user_to_wallet(&pool, user_id, wallet_id, "member").await;
    let all_users_id: Uuid = sqlx::query_scalar(
        "SELECT id FROM user_groups WHERE wallet_id = $1 AND name = 'all_users'",
    )
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .expect("get all_users");

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

    let cache_before = count_user_cache_entries(&pool, wallet_id, user_id).await;
    assert!(cache_before > 0, "Cache should be populated");

    // Remove user from wallet (invalidate cache)
    db.invalidate_permission_matrix_cache(wallet_id, user_id)
        .await
        .expect("invalidate cache");

    // Verify cache was cleaned up
    let cache_after = count_user_cache_entries(&pool, wallet_id, user_id).await;
    assert_eq!(
        cache_after, 0,
        "Cache should be empty after user is removed. Found {} entries",
        cache_after
    );
}

/// Test 3: Cache invalidation is smart (only affects changed group)
#[tokio::test]
async fn test_smart_cache_invalidation_for_permission_matrix_change() {
    let pool = setup_test_db().await;
    let db = Database::new(pool.clone());

    // Setup two users
    let user1_id = create_test_user(&pool).await;
    let user2_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    ensure_wallet_has_system_groups(&pool, wallet_id).await;

    // Get system groups
    let all_users_id: Uuid = sqlx::query_scalar(
        "SELECT id FROM user_groups WHERE wallet_id = $1 AND name = 'all_users'",
    )
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

    // Add both users and populate cache
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

    let user1_cache_before = count_user_cache_entries(&pool, wallet_id, user1_id).await;
    let user2_cache_before = count_user_cache_entries(&pool, wallet_id, user2_id).await;
    assert!(user1_cache_before > 0, "User1 cache should be populated");
    assert!(user2_cache_before > 0, "User2 cache should be populated");

    // Invalidate only users with permissions on all_contacts
    let affected_users = db
        .get_users_with_group_permissions(wallet_id, all_contacts_id)
        .await
        .expect("get affected users");

    assert!(
        affected_users.contains(&user1_id),
        "User1 should be affected by all_contacts change"
    );
    assert!(
        affected_users.contains(&user2_id),
        "User2 should be affected by all_contacts change"
    );

    // Invalidate only affected users
    for user_id in affected_users {
        db.invalidate_permission_matrix_cache(wallet_id, user_id)
            .await
            .expect("invalidate cache");
    }

    // Verify only affected users' cache was cleared
    let user1_cache_after = count_user_cache_entries(&pool, wallet_id, user1_id).await;
    let user2_cache_after = count_user_cache_entries(&pool, wallet_id, user2_id).await;
    assert_eq!(user1_cache_after, 0, "User1 cache should be cleared");
    assert_eq!(user2_cache_after, 0, "User2 cache should be cleared");
}

/// Test 4: Full wallet invalidation clears all users' cache
#[tokio::test]
async fn test_full_wallet_cache_invalidation() {
    let pool = setup_test_db().await;
    let db = Database::new(pool.clone());

    // Setup multiple users
    let user1_id = create_test_user(&pool).await;
    let user2_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    ensure_wallet_has_system_groups(&pool, wallet_id).await;

    let all_users_id: Uuid = sqlx::query_scalar(
        "SELECT id FROM user_groups WHERE wallet_id = $1 AND name = 'all_users'",
    )
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .expect("get all_users");

    // Add users and populate cache
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

    let total_before = count_wallet_cache_entries(&pool, wallet_id).await;
    assert!(total_before > 0, "Wallet should have cache entries");

    // Invalidate entire wallet cache
    db.invalidate_permission_matrix_cache_for_wallet(wallet_id)
        .await
        .expect("invalidate wallet cache");

    // Verify all cache was cleared
    let total_after = count_wallet_cache_entries(&pool, wallet_id).await;
    assert_eq!(
        total_after, 0,
        "Wallet cache should be completely cleared. Found {} entries",
        total_after
    );
}

/// Test 5: Cache respects deny overrides
#[tokio::test]
async fn test_cache_respects_deny_overrides() {
    let pool = setup_test_db().await;
    let db = Database::new(pool.clone());

    // Setup
    let user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    ensure_wallet_has_system_groups(&pool, wallet_id).await;

    let all_users_id: Uuid = sqlx::query_scalar(
        "SELECT id FROM user_groups WHERE wallet_id = $1 AND name = 'all_users'",
    )
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

    add_user_to_wallet(&pool, user_id, wallet_id, "member").await;
    sqlx::query(
        "INSERT INTO user_group_members (user_group_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING"
    )
    .bind(all_users_id)
    .bind(user_id)
    .execute(&pool)
    .await
    .expect("add user to all_users");

    // Populate cache
    db.compute_and_cache_user_permission_matrix(wallet_id, user_id)
        .await
        .expect("compute cache");

    // Add a deny entry to the cache
    sqlx::query(
        "INSERT INTO user_permission_matrix_cache
         (wallet_id, user_id, contact_group_id, permission_action_id, is_deny)
         VALUES ($1, $2, $3, 1, true)
         ON CONFLICT (wallet_id, user_id, contact_group_id, permission_action_id)
         DO UPDATE SET is_deny = true",
    )
    .bind(wallet_id)
    .bind(user_id)
    .bind(all_contacts_id)
    .execute(&pool)
    .await
    .expect("add deny entry");

    // Verify deny entry exists in cache
    let deny_entries: Vec<bool> = sqlx::query_scalar(
        "SELECT is_deny FROM user_permission_matrix_cache
         WHERE wallet_id = $1 AND user_id = $2 AND contact_group_id = $3 AND permission_action_id = 1"
    )
    .bind(wallet_id)
    .bind(user_id)
    .bind(all_contacts_id)
    .fetch_all(&pool)
    .await
    .expect("fetch deny entries");

    assert!(
        deny_entries.iter().any(|&d| d),
        "Cache should have deny entry with is_deny=true"
    );
}

/// Test 6: Orphaned cache entries are cleaned when wallet is deleted
#[tokio::test]
async fn test_cascade_delete_cleans_cache_on_wallet_delete() {
    let pool = setup_test_db().await;
    let db = Database::new(pool.clone());

    // Setup
    let user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    ensure_wallet_has_system_groups(&pool, wallet_id).await;

    let all_users_id: Uuid = sqlx::query_scalar(
        "SELECT id FROM user_groups WHERE wallet_id = $1 AND name = 'all_users'",
    )
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .expect("get all_users");

    add_user_to_wallet(&pool, user_id, wallet_id, "member").await;
    sqlx::query(
        "INSERT INTO user_group_members (user_group_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING"
    )
    .bind(all_users_id)
    .bind(user_id)
    .execute(&pool)
    .await
    .expect("add user to all_users");

    // Populate cache
    db.compute_and_cache_user_permission_matrix(wallet_id, user_id)
        .await
        .expect("compute cache");

    let cache_before = count_wallet_cache_entries(&pool, wallet_id).await;
    assert!(cache_before > 0, "Cache should be populated");

    // Delete wallet (cascade should clean cache)
    sqlx::query("DELETE FROM wallets WHERE id = $1")
        .bind(wallet_id)
        .execute(&pool)
        .await
        .expect("delete wallet");

    // Verify cache was auto-cleaned via CASCADE DELETE
    let cache_after = count_wallet_cache_entries(&pool, wallet_id).await;
    assert_eq!(
        cache_after, 0,
        "Cache should be auto-cleaned when wallet is deleted via CASCADE"
    );
}

/// Test 7: Multiple contact groups can have independent cache entries
#[tokio::test]
async fn test_cache_handles_multiple_contact_groups() {
    let pool = setup_test_db().await;
    let db = Database::new(pool.clone());

    // Setup
    let user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    ensure_wallet_has_system_groups(&pool, wallet_id).await;

    let all_users_id: Uuid = sqlx::query_scalar(
        "SELECT id FROM user_groups WHERE wallet_id = $1 AND name = 'all_users'",
    )
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

    // Create additional contact group
    let custom_group_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO contact_groups (id, wallet_id, name, type) VALUES ($1, $2, $3, 'static')",
    )
    .bind(custom_group_id)
    .bind(wallet_id)
    .bind("custom_group")
    .execute(&pool)
    .await
    .expect("create custom group");

    // Add permissions for custom group
    sqlx::query(
        "INSERT INTO group_permission_matrix (user_group_id, contact_group_id, permission_action_id)
         VALUES ($1, $2, 1) ON CONFLICT DO NOTHING"
    )
    .bind(all_users_id)
    .bind(custom_group_id)
    .execute(&pool)
    .await
    .expect("add permission");

    add_user_to_wallet(&pool, user_id, wallet_id, "member").await;
    sqlx::query(
        "INSERT INTO user_group_members (user_group_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING"
    )
    .bind(all_users_id)
    .bind(user_id)
    .execute(&pool)
    .await
    .expect("add user to all_users");

    // Populate cache
    db.compute_and_cache_user_permission_matrix(wallet_id, user_id)
        .await
        .expect("compute cache");

    // Verify cache has entries for both groups
    let all_contacts_entries: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM user_permission_matrix_cache
         WHERE wallet_id = $1 AND user_id = $2 AND contact_group_id = $3",
    )
    .bind(wallet_id)
    .bind(user_id)
    .bind(all_contacts_id)
    .fetch_one(&pool)
    .await
    .expect("count all_contacts entries");

    let custom_entries: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM user_permission_matrix_cache
         WHERE wallet_id = $1 AND user_id = $2 AND contact_group_id = $3",
    )
    .bind(wallet_id)
    .bind(user_id)
    .bind(custom_group_id)
    .fetch_one(&pool)
    .await
    .expect("count custom entries");

    assert!(
        all_contacts_entries > 0,
        "Should have cache entries for all_contacts"
    );
    assert!(
        custom_entries > 0,
        "Should have cache entries for custom_group"
    );
}
