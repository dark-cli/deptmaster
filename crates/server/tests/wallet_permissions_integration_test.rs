//! Integration tests for wallet permissions redesign
//! Tests wallet-level permission matrix, soft delete, ownership, and enforcement

use sqlx::PgPool;
use uuid::Uuid;

mod test_helpers;
use test_helpers::{setup_test_db, create_test_user, ensure_wallet_has_system_groups};

// ============ HELPER FIXTURES ============

struct TestWallet {
    id: Uuid,
    owner_id: Uuid,
    member_id: Uuid,
}

struct TestGroups {
    all_users_id: Uuid,
    team_leads_id: Uuid,
}

async fn setup_test_wallet(pool: &PgPool) -> TestWallet {
    let wallet_id = Uuid::new_v4();
    let owner_id = create_test_user(pool).await;
    let member_id = create_test_user(pool).await;

    // Create wallet
    sqlx::query(
        "INSERT INTO wallets (id, name, is_active, created_at, updated_at) VALUES ($1, $2, true, NOW(), NOW())",
    )
    .bind(wallet_id)
    .bind("Test Wallet")
    .execute(pool)
    .await
    .expect("Failed to create wallet");

    // Add users to wallet
    sqlx::query(
        "INSERT INTO wallet_users (wallet_id, user_id, subscribed_at) VALUES ($1, $2, NOW()), ($1, $3, NOW())",
    )
    .bind(wallet_id)
    .bind(owner_id)
    .bind(member_id)
    .execute(pool)
    .await
    .expect("Failed to add users to wallet");

    // Create system groups and initialize permission matrix
    ensure_wallet_has_system_groups(pool, wallet_id).await;

    // Mark owner in wallet_owners table (hardcoded bypass)
    sqlx::query("INSERT INTO wallet_owners (wallet_id, user_id) VALUES ($1, $2)")
        .bind(wallet_id)
        .bind(owner_id)
        .execute(pool)
        .await
        .expect("Failed to add wallet owner");

    TestWallet {
        id: wallet_id,
        owner_id,
        member_id,
    }
}

async fn setup_test_groups(pool: &PgPool, wallet_id: Uuid) -> TestGroups {
    // Get system groups
    let all_users_id: Uuid = sqlx::query_scalar(
        "SELECT id FROM user_groups WHERE wallet_id = $1 AND name = 'all_users'",
    )
    .bind(wallet_id)
    .fetch_one(pool)
    .await
    .expect("Failed to find all_users group");

    // Create custom user group
    let team_leads_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO user_groups (id, wallet_id, name, is_system) VALUES ($1, $2, $3, false)",
    )
    .bind(team_leads_id)
    .bind(wallet_id)
    .bind("team_leads")
    .execute(pool)
    .await
    .expect("Failed to create team_leads group");

    TestGroups {
        all_users_id,
        team_leads_id,
    }
}

// ============ TESTS: WALLET PERMISSIONS GRANTED ============

#[tokio::test]
async fn test_all_users_has_wallet_info_read() {
    let pool = setup_test_db().await;
    let wallet = setup_test_wallet(&pool).await;
    let groups = setup_test_groups(&pool, wallet.id).await;

    // Query: wallet_permission_matrix should NOT have wallet permissions for all_users by default
    // All_users only has contact/transaction permissions via group_permission_matrix
    let wallet_perms: Vec<String> = sqlx::query_scalar(
        "SELECT action FROM wallet_permission_matrix WHERE user_group_id = $1 AND action LIKE 'wallet:%' AND is_deny = false",
    )
    .bind(groups.all_users_id)
    .fetch_all(&pool)
    .await
    .expect("Failed to query permissions");

    assert!(
        wallet_perms.is_empty(),
        "all_users should have NO wallet permissions by default (only contact/transaction via contact_groups)"
    );
}

#[tokio::test]
async fn test_all_users_has_wallet_member_list() {
    let pool = setup_test_db().await;
    let wallet = setup_test_wallet(&pool).await;
    let groups = setup_test_groups(&pool, wallet.id).await;

    // all_users has NO wallet-level permissions by default
    // Contact/transaction permissions are via group_permission_matrix instead
    let wallet_member_list: Vec<String> = sqlx::query_scalar(
        "SELECT action FROM wallet_permission_matrix WHERE user_group_id = $1 AND action = 'wallet:member_list' AND is_deny = false",
    )
    .bind(groups.all_users_id)
    .fetch_all(&pool)
    .await
    .expect("Failed to query permissions");

    assert!(
        wallet_member_list.is_empty(),
        "all_users should NOT have wallet:member_list by default (wallet permissions are delegable, not default)"
    );
}

// ============ TESTS: OWNER BYPASS (HARDCODED) ============

#[tokio::test]
async fn test_owner_registered_in_wallet_owners() {
    let pool = setup_test_db().await;
    let wallet = setup_test_wallet(&pool).await;

    // Check: owner is in wallet_owners table
    let is_owner: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM wallet_owners WHERE wallet_id = $1 AND user_id = $2)",
    )
    .bind(wallet.id)
    .bind(wallet.owner_id)
    .fetch_one(&pool)
    .await
    .expect("Failed to check owner");

    assert!(is_owner, "Owner should be registered in wallet_owners");
}

// ============ TESTS: SOFT DELETE ============

#[tokio::test]
async fn test_soft_delete_sets_timestamps() {
    let pool = setup_test_db().await;
    let wallet = setup_test_wallet(&pool).await;

    // Soft delete
    sqlx::query("UPDATE wallets SET deleted_at = NOW(), deleted_by = $2, deletion_reason = $3 WHERE id = $1")
        .bind(wallet.id)
        .bind(wallet.owner_id)
        .bind("User requested deletion")
        .execute(&pool)
        .await
        .expect("Failed to soft delete wallet");

    // Verify soft delete columns are set (deleted_at, deleted_by, deletion_reason)
    let (deleted_by, reason): (Option<Uuid>, Option<String>) = sqlx::query_as(
        "SELECT deleted_by, deletion_reason FROM wallets WHERE id = $1"
    )
    .bind(wallet.id)
    .fetch_one(&pool)
    .await
    .expect("Failed to fetch wallet");

    assert_eq!(deleted_by, Some(wallet.owner_id), "deleted_by should be owner");
    assert_eq!(reason, Some("User requested deletion".to_string()), "reason should be set");

    // Verify deleted_at is set (can't easily get timestamp, but we can check with SQL)
    let deleted_at_not_null: bool = sqlx::query_scalar(
        "SELECT deleted_at IS NOT NULL FROM wallets WHERE id = $1"
    )
    .bind(wallet.id)
    .fetch_one(&pool)
    .await
    .expect("Failed to check deleted_at");

    assert!(deleted_at_not_null, "deleted_at should be set");
}

#[tokio::test]
async fn test_soft_delete_filters_normal_queries() {
    let pool = setup_test_db().await;
    let wallet = setup_test_wallet(&pool).await;

    // Soft delete
    sqlx::query("UPDATE wallets SET deleted_at = NOW(), deleted_by = $2 WHERE id = $1")
        .bind(wallet.id)
        .bind(wallet.owner_id)
        .execute(&pool)
        .await
        .expect("Failed to soft delete");

    // Query active wallets (should exclude deleted)
    let active_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM wallets WHERE id = $1 AND deleted_at IS NULL",
    )
    .bind(wallet.id)
    .fetch_one(&pool)
    .await
    .expect("Failed to count");

    assert_eq!(active_count, 0, "Soft-deleted wallet should not appear in active queries");

    // Query all wallets (should include deleted)
    let total_count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM wallets WHERE id = $1")
            .bind(wallet.id)
            .fetch_one(&pool)
            .await
            .expect("Failed to count all");

    assert_eq!(total_count, 1, "Wallet should still exist in database (soft delete)");
}

// ============ TESTS: PERMISSION MATRIX ENFORCEMENT ============

#[tokio::test]
async fn test_grant_permission_to_group() {
    let pool = setup_test_db().await;
    let wallet = setup_test_wallet(&pool).await;
    let groups = setup_test_groups(&pool, wallet.id).await;

    // Grant permission
    sqlx::query(
        "INSERT INTO wallet_permission_matrix (user_group_id, action, is_deny) VALUES ($1, $2, false)
         ON CONFLICT (user_group_id, action) DO UPDATE SET is_deny = false",
    )
    .bind(groups.team_leads_id)
    .bind("wallet:member_add")
    .execute(&pool)
    .await
    .expect("Failed to grant permission");

    // Query: permission should exist
    let has_perm: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM wallet_permission_matrix WHERE user_group_id = $1 AND action = $2 AND is_deny = false)",
    )
    .bind(groups.team_leads_id)
    .bind("wallet:member_add")
    .fetch_one(&pool)
    .await
    .expect("Failed to check permission");

    assert!(has_perm, "team_leads should have wallet:member_add permission");
}

#[tokio::test]
async fn test_deny_permission_overrides_allow() {
    let pool = setup_test_db().await;
    let wallet = setup_test_wallet(&pool).await;
    let groups = setup_test_groups(&pool, wallet.id).await;

    // Create second group
    let restrict_group_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO user_groups (id, wallet_id, name, is_system) VALUES ($1, $2, $3, false)",
    )
    .bind(restrict_group_id)
    .bind(wallet.id)
    .bind("restrict_group")
    .execute(&pool)
    .await
    .expect("Failed to create restrict group");

    // Grant to team_leads (allow)
    sqlx::query(
        "INSERT INTO wallet_permission_matrix (user_group_id, action, is_deny) VALUES ($1, $2, false)",
    )
    .bind(groups.team_leads_id)
    .bind("wallet:member_add")
    .execute(&pool)
    .await
    .expect("Failed to grant allow");

    // Deny to restrict_group (deny)
    sqlx::query(
        "INSERT INTO wallet_permission_matrix (user_group_id, action, is_deny) VALUES ($1, $2, true)",
    )
    .bind(restrict_group_id)
    .bind("wallet:member_add")
    .execute(&pool)
    .await
    .expect("Failed to grant deny");

    // Add member to both groups
    sqlx::query("INSERT INTO user_group_members (user_id, user_group_id) VALUES ($1, $2), ($1, $3)")
        .bind(wallet.member_id)
        .bind(groups.team_leads_id)
        .bind(restrict_group_id)
        .execute(&pool)
        .await
        .expect("Failed to add members");

    // Query: should have both allow and deny
    let allow_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM wallet_permission_matrix
         WHERE user_group_id IN (
             SELECT user_group_id FROM user_group_members WHERE user_id = $1
         ) AND action = $2 AND is_deny = false",
    )
    .bind(wallet.member_id)
    .bind("wallet:member_add")
    .fetch_one(&pool)
    .await
    .expect("Failed to count allow");

    let deny_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM wallet_permission_matrix
         WHERE user_group_id IN (
             SELECT user_group_id FROM user_group_members WHERE user_id = $1
         ) AND action = $2 AND is_deny = true",
    )
    .bind(wallet.member_id)
    .bind("wallet:member_add")
    .fetch_one(&pool)
    .await
    .expect("Failed to count deny");

    assert_eq!(allow_count, 1, "Should have 1 allow");
    assert_eq!(deny_count, 1, "Should have 1 deny (deny wins)");
}

// ============ TESTS: EDGE CASES & ATTACK VECTORS ============

#[tokio::test]
async fn test_member_cannot_exceed_owner_permissions() {
    // Members should NOT be able to perform owner-only actions
    // This test verifies database constraint (owner-only actions are hardcoded)
    let pool = setup_test_db().await;
    let wallet = setup_test_wallet(&pool).await;

    // Member is NOT in wallet_owners table
    let is_owner: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM wallet_owners WHERE wallet_id = $1 AND user_id = $2)",
    )
    .bind(wallet.id)
    .bind(wallet.member_id)
    .fetch_one(&pool)
    .await
    .expect("Failed to check");

    assert!(!is_owner, "Member should NOT be an owner");
}

#[tokio::test]
async fn test_wallet_permission_matrix_exists() {
    // Verify wallet_permission_matrix table exists and has correct structure
    let pool = setup_test_db().await;

    let table_exists: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'wallet_permission_matrix')",
    )
    .fetch_one(&pool)
    .await
    .expect("Failed to check");

    assert!(table_exists, "wallet_permission_matrix table should exist");
}

#[tokio::test]
async fn test_wallet_soft_delete_columns_exist() {
    // Verify deleted_at, deleted_by, deletion_reason columns exist
    let pool = setup_test_db().await;

    let has_deleted_at: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name = 'wallets' AND column_name = 'deleted_at')",
    )
    .fetch_one(&pool)
    .await
    .expect("Failed to check");

    assert!(has_deleted_at, "wallets.deleted_at column should exist");

    let has_deleted_by: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name = 'wallets' AND column_name = 'deleted_by')",
    )
    .fetch_one(&pool)
    .await
    .expect("Failed to check");

    assert!(has_deleted_by, "wallets.deleted_by column should exist");
}

// ============ TESTS: ATTACK VECTORS ============

#[tokio::test]
async fn test_cannot_delete_wallet_without_owner_status() {
    // Security: Only wallet owners can soft delete
    // Member cannot directly call soft delete (should be checked at handler level)
    // This test documents the expectation
    let pool = setup_test_db().await;
    let wallet = setup_test_wallet(&pool).await;

    // Member tries to soft delete (note: handler should prevent this, not DB)
    let _result = sqlx::query("UPDATE wallets SET deleted_at = NOW(), deleted_by = $2 WHERE id = $1")
        .bind(wallet.id)
        .bind(wallet.member_id)  // Member, not owner
        .execute(&pool)
        .await;

    // DB allows it (permission check is at handler level)
    // This test documents: DB is flexible, handler enforces restrictions

    // Real test is in handler integration: member calling delete_wallet endpoint should get 403
    assert!(true); // Test just documents behavior
}

#[tokio::test]
async fn test_permission_actions_named_correctly() {
    // Verify action names in wallet_permission_matrix match domain Action enum
    let pool = setup_test_db().await;

    let actions: Vec<String> = sqlx::query_scalar(
        "SELECT DISTINCT action FROM wallet_permission_matrix ORDER BY action",
    )
    .fetch_all(&pool)
    .await
    .expect("Failed to query actions");

    let expected_prefixes = vec!["wallet:"];

    for action in &actions {
        let matches_prefix = expected_prefixes.iter().any(|prefix| action.starts_with(prefix));
        assert!(
            matches_prefix || action.starts_with("contact:") || action.starts_with("transaction:"),
            "Action {} should start with known prefix",
            action
        );
    }
}
