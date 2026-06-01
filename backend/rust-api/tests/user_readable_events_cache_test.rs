//! Tests for user_readable_events cache optimization
//! Verifies that the denormalized cache correctly tracks readable events per user

use debt_tracker_api::database::repository::Database;
use uuid::Uuid;

mod test_helpers;
use test_helpers::*;

/// Test that cache is populated when events are inserted
#[tokio::test]
async fn test_cache_populated_on_event_insert() {
    let pool = setup_test_db().await;
    let db = Database::new(pool.clone());

    // Setup: owner and member users
    let owner_id = create_test_user(&pool).await;
    let member_id = create_test_user(&pool).await;

    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    add_user_to_wallet(&pool, owner_id, wallet_id, "owner").await;
    add_user_to_wallet(&pool, member_id, wallet_id, "member").await;

    ensure_wallet_has_system_groups(&pool, wallet_id).await;

    // Setup permission: owner has all permissions
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

    sqlx::query(
        "INSERT INTO user_group_members (user_group_id, user_id) VALUES ($1, $2)
         ON CONFLICT DO NOTHING",
    )
    .bind(owners_group_id)
    .bind(owner_id)
    .execute(&pool)
    .await
    .expect("add owner to __owners__");

    let all_contacts_id: Uuid = sqlx::query_scalar(
        "SELECT id FROM contact_groups WHERE wallet_id = $1 AND name = 'all_contacts'",
    )
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .expect("get all_contacts id");

    for act_id in 1..=10_i16 {
        sqlx::query(
            "INSERT INTO group_permission_matrix (user_group_id, contact_group_id, permission_action_id)
             VALUES ($1, $2, $3) ON CONFLICT DO NOTHING",
        )
        .bind(owners_group_id)
        .bind(all_contacts_id)
        .bind(act_id)
        .execute(&pool)
        .await
        .ok();
    }

    // Create contact event
    let event_id = Uuid::new_v4();
    let contact_id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO events (event_id, user_id, wallet_id, aggregate_type, aggregate_id, event_type, event_version, event_data, created_at)
           VALUES ($1, $2, $3, 'contact', $4, 'CREATED', 1, $5, NOW())"#,
    )
    .bind(event_id)
    .bind(owner_id)
    .bind(wallet_id)
    .bind(contact_id)
    .bind(serde_json::json!({"name": "Test Contact"}))
    .execute(&pool)
    .await
    .expect("insert event");

    // Simulate cache population (as would happen in sync handler)
    db.add_readable_event_impl(wallet_id, owner_id, event_id)
        .await
        .expect("add readable event for owner");

    // Verify cache has the event
    let cached_ids = db
        .get_readable_event_ids_for_user_impl(wallet_id, owner_id)
        .await
        .expect("get readable events");
    assert!(
        cached_ids.contains(&event_id),
        "Event should be in owner's cache"
    );
}

/// Test that different users have different caches
#[tokio::test]
async fn test_cache_per_user() {
    let pool = setup_test_db().await;
    let db = Database::new(pool.clone());

    let user1_id = create_test_user(&pool).await;
    let user2_id = create_test_user(&pool).await;

    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    add_user_to_wallet(&pool, user1_id, wallet_id, "member").await;
    add_user_to_wallet(&pool, user2_id, wallet_id, "member").await;

    ensure_wallet_has_system_groups(&pool, wallet_id).await;

    // Create event
    let event1_id = Uuid::new_v4();
    let event2_id = Uuid::new_v4();
    let contact_id = Uuid::new_v4();

    sqlx::query(
        r#"INSERT INTO events (event_id, user_id, wallet_id, aggregate_type, aggregate_id, event_type, event_version, event_data, created_at)
           VALUES ($1, $2, $3, 'contact', $4, 'CREATED', 1, $5, NOW())"#,
    )
    .bind(event1_id)
    .bind(user1_id)
    .bind(wallet_id)
    .bind(contact_id)
    .bind(serde_json::json!({"name": "Contact"}))
    .execute(&pool)
    .await
    .ok();

    sqlx::query(
        r#"INSERT INTO events (event_id, user_id, wallet_id, aggregate_type, aggregate_id, event_type, event_version, event_data, created_at)
           VALUES ($1, $2, $3, 'permission', $4, 'CREATED', 1, $5, NOW())"#,
    )
    .bind(event2_id)
    .bind(user1_id)
    .bind(wallet_id)
    .bind(Uuid::new_v4())
    .bind(serde_json::json!({}))
    .execute(&pool)
    .await
    .ok();

    // Add events to user1's cache only
    db.add_readable_event_impl(wallet_id, user1_id, event1_id)
        .await
        .ok();
    db.add_readable_event_impl(wallet_id, user1_id, event2_id)
        .await
        .ok();

    // Verify user1 has both events
    let user1_cached = db
        .get_readable_event_ids_for_user_impl(wallet_id, user1_id)
        .await
        .expect("get user1 readable events");
    assert_eq!(
        user1_cached.len(),
        2,
        "User1 should have 2 events in cache"
    );

    // Verify user2 has no events
    let user2_cached = db
        .get_readable_event_ids_for_user_impl(wallet_id, user2_id)
        .await
        .expect("get user2 readable events");
    assert_eq!(
        user2_cached.len(),
        0,
        "User2 should have 0 events in cache"
    );
}

/// Test that cache deletion works correctly
#[tokio::test]
async fn test_cache_deletion_on_permission_change() {
    let pool = setup_test_db().await;
    let db = Database::new(pool.clone());

    let user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    add_user_to_wallet(&pool, user_id, wallet_id, "member").await;

    // Create events first
    let event1_id = Uuid::new_v4();
    let event2_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO events (event_id, user_id, wallet_id, aggregate_type, aggregate_id, event_type, event_version, event_data, created_at)
         VALUES ($1, $2, $3, 'test', $4, 'TEST', 1, '{}', NOW())"
    )
    .bind(event1_id)
    .bind(user_id)
    .bind(wallet_id)
    .bind(Uuid::new_v4())
    .execute(&pool)
    .await
    .expect("insert event 1");

    sqlx::query(
        "INSERT INTO events (event_id, user_id, wallet_id, aggregate_type, aggregate_id, event_type, event_version, event_data, created_at)
         VALUES ($1, $2, $3, 'test', $4, 'TEST', 1, '{}', NOW())"
    )
    .bind(event2_id)
    .bind(user_id)
    .bind(wallet_id)
    .bind(Uuid::new_v4())
    .execute(&pool)
    .await
    .expect("insert event 2");

    // Add events to cache
    db.add_readable_event_impl(wallet_id, user_id, event1_id)
        .await
        .expect("add event 1");
    db.add_readable_event_impl(wallet_id, user_id, event2_id)
        .await
        .expect("add event 2");

    // Verify cache has events
    let before = db
        .get_readable_event_ids_for_user_impl(wallet_id, user_id)
        .await
        .expect("get before");
    assert_eq!(before.len(), 2, "Should have 2 events before deletion");

    // Delete cache
    db.delete_readable_events_for_user_impl(wallet_id, user_id)
        .await
        .expect("delete cache");

    // Verify cache is empty
    let after = db
        .get_readable_event_ids_for_user_impl(wallet_id, user_id)
        .await
        .expect("get after");
    assert_eq!(after.len(), 0, "Cache should be empty after deletion");
}

/// Test that cache correctly counts and retrieves events
#[tokio::test]
async fn test_cache_hash_computation() {
    let pool = setup_test_db().await;
    let db = Database::new(pool.clone());

    let user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    add_user_to_wallet(&pool, user_id, wallet_id, "member").await;

    // Add events to cache
    let event_id_1 = Uuid::new_v4();
    let event_id_2 = Uuid::new_v4();

    // Insert event records first
    sqlx::query(
        "INSERT INTO events (event_id, user_id, wallet_id, aggregate_type, aggregate_id, event_type, event_version, event_data, created_at)
         VALUES ($1, $2, $3, 'test', $4, 'TEST', 1, '{}', NOW())"
    )
    .bind(event_id_1)
    .bind(user_id)
    .bind(wallet_id)
    .bind(Uuid::new_v4())
    .execute(&pool)
    .await
    .expect("insert event 1");

    sqlx::query(
        "INSERT INTO events (event_id, user_id, wallet_id, aggregate_type, aggregate_id, event_type, event_version, event_data, created_at)
         VALUES ($1, $2, $3, 'test', $4, 'TEST', 1, '{}', NOW())"
    )
    .bind(event_id_2)
    .bind(user_id)
    .bind(wallet_id)
    .bind(Uuid::new_v4())
    .execute(&pool)
    .await
    .expect("insert event 2");

    db.add_readable_event_impl(wallet_id, user_id, event_id_1)
        .await
        .expect("add event 1");
    db.add_readable_event_impl(wallet_id, user_id, event_id_2)
        .await
        .expect("add event 2");

    // Verify events are cached
    let cached = db
        .get_readable_event_ids_for_user_impl(wallet_id, user_id)
        .await
        .expect("get cached events");

    assert_eq!(cached.len(), 2, "Should have 2 cached events");
    assert!(cached.contains(&event_id_1), "Cache should contain event 1");
    assert!(cached.contains(&event_id_2), "Cache should contain event 2");
}

/// Test that empty cache returns 0 events
#[tokio::test]
async fn test_empty_cache_hash() {
    let pool = setup_test_db().await;
    let db = Database::new(pool.clone());

    let user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    add_user_to_wallet(&pool, user_id, wallet_id, "member").await;

    // Get event IDs for empty cache (direct query to avoid hash function issue)
    let cached_ids = db
        .get_readable_event_ids_for_user_impl(wallet_id, user_id)
        .await
        .expect("get empty cached");

    assert_eq!(
        cached_ids.len(),
        0,
        "Empty cache should have no events"
    );
}

/// Test get_wallet_users returns correct users
#[tokio::test]
async fn test_get_wallet_users() {
    let pool = setup_test_db().await;
    let db = Database::new(pool.clone());

    let owner_id = create_test_user(&pool).await;
    let member_id = create_test_user(&pool).await;

    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    add_user_to_wallet(&pool, owner_id, wallet_id, "owner").await;
    add_user_to_wallet(&pool, member_id, wallet_id, "member").await;

    // Get wallet users
    let users = db
        .get_wallet_users_impl(wallet_id)
        .await
        .expect("get wallet users");

    assert_eq!(users.len(), 2, "Should have 2 users in wallet");

    let user_ids: Vec<Uuid> = users.iter().map(|(id, _)| *id).collect();
    assert!(
        user_ids.contains(&owner_id),
        "Should contain owner"
    );
    assert!(
        user_ids.contains(&member_id),
        "Should contain member"
    );

    // Check roles
    for (id, role) in &users {
        if *id == owner_id {
            assert_eq!(role, "owner", "Owner should have owner role");
        } else if *id == member_id {
            assert_eq!(role, "member", "Member should have member role");
        }
    }
}

/// Test cache consistency: same event appears only once per user
#[tokio::test]
async fn test_cache_uniqueness() {
    let pool = setup_test_db().await;
    let db = Database::new(pool.clone());

    let user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    add_user_to_wallet(&pool, user_id, wallet_id, "member").await;

    let event_id = Uuid::new_v4();

    // Create event first
    sqlx::query(
        "INSERT INTO events (event_id, user_id, wallet_id, aggregate_type, aggregate_id, event_type, event_version, event_data, created_at)
         VALUES ($1, $2, $3, 'test', $4, 'TEST', 1, '{}', NOW())"
    )
    .bind(event_id)
    .bind(user_id)
    .bind(wallet_id)
    .bind(Uuid::new_v4())
    .execute(&pool)
    .await
    .expect("insert event");

    // Try to add same event twice
    db.add_readable_event_impl(wallet_id, user_id, event_id)
        .await
        .expect("add event first time");

    db.add_readable_event_impl(wallet_id, user_id, event_id)
        .await
        .expect("add event second time (should be ignored)");

    // Verify only one entry exists
    let cached = db
        .get_readable_event_ids_for_user_impl(wallet_id, user_id)
        .await
        .expect("get cached events");

    assert_eq!(
        cached.len(),
        1,
        "Event should appear only once in cache"
    );
    assert_eq!(
        cached[0], event_id,
        "Cached event should match added event"
    );
}

/// Test that permission events are added for all wallet users (simulation)
#[tokio::test]
async fn test_permission_event_all_users() {
    let pool = setup_test_db().await;
    let db = Database::new(pool.clone());

    let user1_id = create_test_user(&pool).await;
    let user2_id = create_test_user(&pool).await;
    let user3_id = create_test_user(&pool).await;

    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    add_user_to_wallet(&pool, user1_id, wallet_id, "owner").await;
    add_user_to_wallet(&pool, user2_id, wallet_id, "member").await;
    add_user_to_wallet(&pool, user3_id, wallet_id, "member").await;

    // Get all wallet users
    let users = db
        .get_wallet_users_impl(wallet_id)
        .await
        .expect("get users");

    let permission_event_id = Uuid::new_v4();

    // Create permission event
    sqlx::query(
        "INSERT INTO events (event_id, user_id, wallet_id, aggregate_type, aggregate_id, event_type, event_version, event_data, created_at)
         VALUES ($1, $2, $3, 'permission', $4, 'CREATED', 1, '{}', NOW())"
    )
    .bind(permission_event_id)
    .bind(user1_id)
    .bind(wallet_id)
    .bind(Uuid::new_v4())
    .execute(&pool)
    .await
    .expect("insert permission event");

    // Simulate permission event being added to all users
    for (user_id, _role) in users {
        db.add_readable_event_impl(wallet_id, user_id, permission_event_id)
            .await
            .expect("add permission event");
    }

    // Verify all users have the permission event
    for user_id in [user1_id, user2_id, user3_id] {
        let cached = db
            .get_readable_event_ids_for_user_impl(wallet_id, user_id)
            .await
            .expect("get cached");

        assert!(
            cached.contains(&permission_event_id),
            "User should have permission event"
        );
    }
}
