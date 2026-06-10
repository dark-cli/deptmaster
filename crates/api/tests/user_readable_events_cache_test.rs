//! Tests for user_readable_events cache optimization
//! Verifies that the denormalized cache correctly tracks readable events per user
//! Uses the sync API (post_sync_events) to populate cache realistically

use axum::extract::{Extension, Json, State};
use chrono::Utc;
use api::database::repository::Database;
use api::domain::events::{DomainEvent, EventData};
use api::handlers::sync::post_sync_events;
use api::middleware::auth::AuthUser;
use api::middleware::wallet_context::WalletContext;
use api::permissions::WalletRole;
use api::websocket;
use api::Config;
use std::sync::Arc;
use uuid::Uuid;

mod test_helpers;
use test_helpers::*;

/// Test that cache is populated when events are synced
#[tokio::test]
async fn test_cache_populated_via_sync_api() {
    let pool = setup_test_db().await;
    let db = Database::new(pool.clone());

    // Setup: owner and member users
    let owner_id = create_test_user(&pool).await;
    let member_id = create_test_user(&pool).await;

    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    ensure_wallet_has_system_groups(&pool, wallet_id).await;
    add_user_to_wallet(&pool, owner_id, wallet_id, "owner").await;
    add_user_to_wallet(&pool, member_id, wallet_id, "member").await;

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

    // Create and sync a contact event
    let event_id = Uuid::new_v4();
    let contact_id = Uuid::new_v4();

    // Setup contact in projection (required for permission checks)
    setup_contact_for_wallet(&pool, wallet_id, owner_id, contact_id, "Test Contact").await;

    let event = DomainEvent {
        id: event_id,
        aggregate_id: contact_id,
        wallet_id,
        user_id: owner_id,
        created_at: Utc::now(),
        version: 1,
        event_data: EventData::ContactCreated {
            name: "Test Contact".to_string(),
            username: None,
            phone: None,
            email: None,
            notes: None,
            group_ids: vec![],
        },
    };

    // Sync the event (this populates cache as part of post_sync_events)
    let config = Arc::new(Config::from_env().expect("Config::from_env"));
    let broadcast_tx = websocket::create_broadcast_channel();
    let state = create_test_app_state(pool.clone(), config, broadcast_tx);
    let wallet_ctx = WalletContext::new(wallet_id, WalletRole::Owner);
    let auth_user = AuthUser {
        user_id: owner_id,
        username: "owner".to_string(),
        is_admin: false,
    };

    let result = post_sync_events(
        State(state),
        Extension(wallet_ctx),
        Extension(auth_user),
        Json(vec![event.clone()]),
    )
    .await;

    assert!(result.is_ok(), "post_sync_events should succeed");

    // Verify cache has the event
    let cached_ids = db
        .get_readable_event_ids_for_user_impl(wallet_id, owner_id)
        .await
        .expect("get readable events");

    assert!(
        cached_ids.contains(&event_id),
        "Event should be in owner's cache after sync"
    );
}

/// Test that different users have different caches
#[tokio::test]
async fn test_cache_per_user_via_sync() {
    let pool = setup_test_db().await;
    let db = Database::new(pool.clone());

    let user1_id = create_test_user(&pool).await;
    let user2_id = create_test_user(&pool).await;

    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    ensure_wallet_has_system_groups(&pool, wallet_id).await;
    add_user_to_wallet(&pool, user1_id, wallet_id, "member").await;
    add_user_to_wallet(&pool, user2_id, wallet_id, "member").await;

    // Create two contact events
    let event1_id = Uuid::new_v4();
    let event2_id = Uuid::new_v4();
    let contact1_id = Uuid::new_v4();
    let contact2_id = Uuid::new_v4();

    // Setup contacts in projection
    setup_contact_for_wallet(&pool, wallet_id, user1_id, contact1_id, "Contact 1").await;
    setup_contact_for_wallet(&pool, wallet_id, user2_id, contact2_id, "Contact 2").await;

    let event1 = DomainEvent {
        id: event1_id,
        aggregate_id: contact1_id,
        wallet_id,
        user_id: user1_id,
        created_at: Utc::now(),
        version: 1,
        event_data: EventData::ContactCreated {
            name: "Contact 1".to_string(),
            username: None,
            phone: None,
            email: None,
            notes: None,
            group_ids: vec![],
        },
    };

    let event2 = DomainEvent {
        id: event2_id,
        aggregate_id: contact2_id,
        wallet_id,
        user_id: user2_id,
        created_at: Utc::now(),
        version: 1,
        event_data: EventData::ContactCreated {
            name: "Contact 2".to_string(),
            username: None,
            phone: None,
            email: None,
            notes: None,
            group_ids: vec![],
        },
    };

    let config = Arc::new(Config::from_env().expect("Config::from_env"));
    let broadcast_tx = websocket::create_broadcast_channel();
    let state = create_test_app_state(pool.clone(), config, broadcast_tx);

    // Sync both events as user1
    let wallet_ctx = WalletContext::new(wallet_id, WalletRole::Member);
    let auth_user = AuthUser {
        user_id: user1_id,
        username: "user1".to_string(),
        is_admin: false,
    };

    let _ = post_sync_events(
        State(state.clone()),
        Extension(wallet_ctx),
        Extension(auth_user),
        Json(vec![event1.clone(), event2.clone()]),
    )
    .await;

    // User1 should see both events (they can read their own + others')
    let user1_cached = db
        .get_readable_event_ids_for_user_impl(wallet_id, user1_id)
        .await
        .expect("get user1 readable events");

    assert!(user1_cached.contains(&event1_id), "User1 should see event1");
    assert!(user1_cached.contains(&event2_id), "User1 should see event2");

    // User2 should also see both events (they can read them since they're a member with default permissions)
    // The cache is populated for all users who can read the event when it's synced
    let user2_cached = db
        .get_readable_event_ids_for_user_impl(wallet_id, user2_id)
        .await
        .expect("get user2 readable events");

    assert_eq!(
        user2_cached.len(),
        2,
        "User2 should see both events (members have read permissions)"
    );
    assert!(user2_cached.contains(&event1_id), "User2 should see event1");
    assert!(user2_cached.contains(&event2_id), "User2 should see event2");
}

/// Test that cache deletion works correctly (for permission rebuilds)
#[tokio::test]
async fn test_cache_deletion_on_permission_change() {
    let pool = setup_test_db().await;
    let db = Database::new(pool.clone());

    let user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    ensure_wallet_has_system_groups(&pool, wallet_id).await;
    add_user_to_wallet(&pool, user_id, wallet_id, "member").await;

    // Create and sync events
    let event1_id = Uuid::new_v4();
    let event2_id = Uuid::new_v4();
    let contact1_id = Uuid::new_v4();
    let contact2_id = Uuid::new_v4();

    // Setup contacts in projection
    setup_contact_for_wallet(&pool, wallet_id, user_id, contact1_id, "Contact 1").await;
    setup_contact_for_wallet(&pool, wallet_id, user_id, contact2_id, "Contact 2").await;

    let event1 = DomainEvent {
        id: event1_id,
        aggregate_id: contact1_id,
        wallet_id,
        user_id,
        created_at: Utc::now(),
        version: 1,
        event_data: EventData::ContactCreated {
            name: "Contact 1".to_string(),
            username: None,
            phone: None,
            email: None,
            notes: None,
            group_ids: vec![],
        },
    };

    let event2 = DomainEvent {
        id: event2_id,
        aggregate_id: contact2_id,
        wallet_id,
        user_id,
        created_at: Utc::now(),
        version: 1,
        event_data: EventData::ContactCreated {
            name: "Contact 2".to_string(),
            username: None,
            phone: None,
            email: None,
            notes: None,
            group_ids: vec![],
        },
    };

    let config = Arc::new(Config::from_env().expect("Config::from_env"));
    let broadcast_tx = websocket::create_broadcast_channel();
    let state = create_test_app_state(pool.clone(), config, broadcast_tx);
    let wallet_ctx = WalletContext::new(wallet_id, WalletRole::Member);
    let auth_user = AuthUser {
        user_id,
        username: "user".to_string(),
        is_admin: false,
    };

    let _ = post_sync_events(
        State(state),
        Extension(wallet_ctx),
        Extension(auth_user),
        Json(vec![event1, event2]),
    )
    .await;

    // Verify cache has events
    let before = db
        .get_readable_event_ids_for_user_impl(wallet_id, user_id)
        .await
        .expect("get before");
    assert_eq!(before.len(), 2, "Should have 2 events before deletion");

    // Delete cache (simulates permission change requiring rebuild)
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

/// Test that cache is correctly isolated per user
#[tokio::test]
async fn test_cache_uniqueness_per_user() {
    let pool = setup_test_db().await;
    let db = Database::new(pool.clone());

    let user1_id = create_test_user(&pool).await;
    let user2_id = create_test_user(&pool).await;

    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    ensure_wallet_has_system_groups(&pool, wallet_id).await;
    add_user_to_wallet(&pool, user1_id, wallet_id, "member").await;
    add_user_to_wallet(&pool, user2_id, wallet_id, "member").await;

    // Create event that both will sync
    let event_id = Uuid::new_v4();
    let contact_id = Uuid::new_v4();

    // Setup contact in projection
    setup_contact_for_wallet(&pool, wallet_id, user1_id, contact_id, "Shared Contact").await;

    let event = DomainEvent {
        id: event_id,
        aggregate_id: contact_id,
        wallet_id,
        user_id: user1_id,
        created_at: Utc::now(),
        version: 1,
        event_data: EventData::ContactCreated {
            name: "Shared Contact".to_string(),
            username: None,
            phone: None,
            email: None,
            notes: None,
            group_ids: vec![],
        },
    };

    let config = Arc::new(Config::from_env().expect("Config::from_env"));
    let broadcast_tx = websocket::create_broadcast_channel();
    let state = create_test_app_state(pool.clone(), config, broadcast_tx);

    // User1 syncs the event
    let wallet_ctx = WalletContext::new(wallet_id, WalletRole::Member);
    let auth_user = AuthUser {
        user_id: user1_id,
        username: "user1".to_string(),
        is_admin: false,
    };

    let _ = post_sync_events(
        State(state.clone()),
        Extension(wallet_ctx),
        Extension(auth_user),
        Json(vec![event.clone()]),
    )
    .await;

    // User2 also syncs the event
    let wallet_ctx = WalletContext::new(wallet_id, WalletRole::Member);
    let auth_user = AuthUser {
        user_id: user2_id,
        username: "user2".to_string(),
        is_admin: false,
    };

    let _ = post_sync_events(
        State(state),
        Extension(wallet_ctx),
        Extension(auth_user),
        Json(vec![event]),
    )
    .await;

    // Both should have exactly one copy of the event (no duplicates)
    let user1_cached = db
        .get_readable_event_ids_for_user_impl(wallet_id, user1_id)
        .await
        .expect("get user1 cached");
    assert_eq!(user1_cached.len(), 1, "User1 should have exactly 1 event");

    let user2_cached = db
        .get_readable_event_ids_for_user_impl(wallet_id, user2_id)
        .await
        .expect("get user2 cached");
    assert_eq!(user2_cached.len(), 1, "User2 should have exactly 1 event");
}

/// Test that get_wallet_users returns correct users
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
    assert!(user_ids.contains(&owner_id), "Should contain owner");
    assert!(user_ids.contains(&member_id), "Should contain member");

    // Check roles
    for (id, role) in &users {
        if *id == owner_id {
            assert_eq!(role, "owner", "Owner should have owner role");
        } else if *id == member_id {
            assert_eq!(role, "member", "Member should have member role");
        }
    }
}

/// Test that multiple events accumulate in cache
#[tokio::test]
async fn test_cache_accumulates_multiple_events() {
    let pool = setup_test_db().await;
    let db = Database::new(pool.clone());

    let user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    ensure_wallet_has_system_groups(&pool, wallet_id).await;
    add_user_to_wallet(&pool, user_id, wallet_id, "member").await;

    let config = Arc::new(Config::from_env().expect("Config::from_env"));
    let broadcast_tx = websocket::create_broadcast_channel();
    let state = create_test_app_state(pool.clone(), config, broadcast_tx);
    let wallet_ctx = WalletContext::new(wallet_id, WalletRole::Member);
    let auth_user = AuthUser {
        user_id,
        username: "user".to_string(),
        is_admin: false,
    };

    // Create contacts for batch 1 and set them up in projections
    let batch1_contact_ids: Vec<Uuid> = (0..3).map(|_| Uuid::new_v4()).collect();
    for (i, &contact_id) in batch1_contact_ids.iter().enumerate() {
        setup_contact_for_wallet(
            &pool,
            wallet_id,
            user_id,
            contact_id,
            &format!("Contact {}", i),
        )
        .await;
    }

    // Sync first batch of events
    let batch1: Vec<DomainEvent> = (0..3)
        .map(|i| DomainEvent {
            id: Uuid::new_v4(),
            aggregate_id: batch1_contact_ids[i],
            wallet_id,
            user_id,
            created_at: Utc::now(),
            version: 1,
            event_data: EventData::ContactCreated {
                name: format!("Contact {}", i),
                username: None,
                phone: None,
                email: None,
                notes: None,
                group_ids: vec![],
            },
        })
        .collect();

    let batch1_ids: Vec<Uuid> = batch1.iter().map(|e| e.id).collect();

    let _ = post_sync_events(
        State(state.clone()),
        Extension(wallet_ctx.clone()),
        Extension(auth_user.clone()),
        Json(batch1),
    )
    .await;

    // Verify batch 1 in cache
    let cached_after_batch1 = db
        .get_readable_event_ids_for_user_impl(wallet_id, user_id)
        .await
        .expect("get after batch 1");
    assert_eq!(
        cached_after_batch1.len(),
        3,
        "Should have 3 events after batch 1"
    );

    // Create contacts for batch 2 and set them up in projections
    let batch2_contact_ids: Vec<Uuid> = (0..2).map(|_| Uuid::new_v4()).collect();
    for (i, &contact_id) in batch2_contact_ids.iter().enumerate() {
        setup_contact_for_wallet(
            &pool,
            wallet_id,
            user_id,
            contact_id,
            &format!("Contact {}", i + 3),
        )
        .await;
    }

    // Sync second batch
    let batch2: Vec<DomainEvent> = (0..2)
        .map(|i| DomainEvent {
            id: Uuid::new_v4(),
            aggregate_id: batch2_contact_ids[i],
            wallet_id,
            user_id,
            created_at: Utc::now(),
            version: 1,
            event_data: EventData::ContactCreated {
                name: format!("Contact {}", i + 3),
                username: None,
                phone: None,
                email: None,
                notes: None,
                group_ids: vec![],
            },
        })
        .collect();

    let _ = post_sync_events(
        State(state),
        Extension(wallet_ctx),
        Extension(auth_user),
        Json(batch2),
    )
    .await;

    // Verify batch 1 + batch 2 in cache
    let cached_after_batch2 = db
        .get_readable_event_ids_for_user_impl(wallet_id, user_id)
        .await
        .expect("get after batch 2");
    assert_eq!(
        cached_after_batch2.len(),
        5,
        "Should have 5 events after batch 2"
    );

    // Verify batch 1 events still there
    for event_id in batch1_ids {
        assert!(
            cached_after_batch2.contains(&event_id),
            "Batch 1 event should still be in cache"
        );
    }
}
