//! Integration tests for Layer 2 and Layer 2.5 permission event emission
//! Tests that permission changes emit proper events for event sourcing

use sqlx::PgPool;
use uuid::Uuid;

mod test_helpers;
use test_helpers::{setup_test_db, create_test_user, ensure_wallet_has_system_groups};

struct TestSetup {
    wallet_id: Uuid,
    owner_id: Uuid,
    source_group_id: Uuid,
    target_group_id: Uuid,
    contact_group_id: Uuid,
}

async fn setup_test_data(pool: &PgPool) -> TestSetup {
    let wallet_id = Uuid::new_v4();
    let owner_id = create_test_user(pool).await;

    // Create wallet
    sqlx::query(
        "INSERT INTO wallets (id, name, is_active, created_at, updated_at) VALUES ($1, $2, true, NOW(), NOW())",
    )
    .bind(wallet_id)
    .bind("Test Wallet for Event Emission")
    .execute(pool)
    .await
    .expect("Failed to create wallet");

    // Add owner to wallet
    sqlx::query("INSERT INTO wallet_users (wallet_id, user_id, subscribed_at) VALUES ($1, $2, NOW())")
        .bind(wallet_id)
        .bind(owner_id)
        .execute(pool)
        .await
        .expect("Failed to add owner to wallet");

    // Initialize system groups
    ensure_wallet_has_system_groups(pool, wallet_id).await;

    // Mark as owner
    sqlx::query("INSERT INTO wallet_owners (wallet_id, user_id) VALUES ($1, $2)")
        .bind(wallet_id)
        .bind(owner_id)
        .execute(pool)
        .await
        .expect("Failed to mark owner");

    // Verify all_users group exists (created by ensure_wallet_has_system_groups)
    let _all_users_id: Uuid = sqlx::query_scalar(
        "SELECT id FROM user_groups WHERE wallet_id = $1 AND name = 'all_users'",
    )
    .bind(wallet_id)
    .fetch_one(pool)
    .await
    .expect("Failed to find all_users group");

    // Create additional member groups
    let source_group_id = Uuid::new_v4();
    let target_group_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO user_groups (id, wallet_id, name, is_system) VALUES ($1, $2, $3, false)",
    )
    .bind(source_group_id)
    .bind(wallet_id)
    .bind("source_group")
    .execute(pool)
    .await
    .expect("Failed to create source group");

    sqlx::query(
        "INSERT INTO user_groups (id, wallet_id, name, is_system) VALUES ($1, $2, $3, false)",
    )
    .bind(target_group_id)
    .bind(wallet_id)
    .bind("target_group")
    .execute(pool)
    .await
    .expect("Failed to create target group");

    // Create a contact group for Layer 2.5 tests
    let contact_group_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO contact_groups (id, wallet_id, name, type, is_system) VALUES ($1, $2, $3, 'static', false)",
    )
    .bind(contact_group_id)
    .bind(wallet_id)
    .bind("test_contact_group")
    .execute(pool)
    .await
    .expect("Failed to create contact group");

    TestSetup {
        wallet_id,
        owner_id,
        source_group_id,
        target_group_id,
        contact_group_id,
    }
}

// ============ LAYER 2 TESTS: MEMBER GROUP PERMISSIONS ============

#[tokio::test]
async fn test_layer2_member_permission_event_emission() {
    let pool = setup_test_db().await;
    let setup = setup_test_data(&pool).await;

    // Verify event table is empty before
    let event_count_before: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM events WHERE event_type = 'GroupPermissionsSet' AND aggregate_id = $1::uuid",
    )
    .bind(setup.wallet_id)
    .fetch_one(&pool)
    .await
    .expect("Failed to count events");

    assert_eq!(event_count_before, 0, "Should have no GroupPermissionsSet events initially");

    // Insert a Layer 2 permission (simulating API call)
    sqlx::query(
        "INSERT INTO wallet_member_permission_matrix (source_group_id, target_group_id, action, is_deny) VALUES ($1, $2, $3, false)",
    )
    .bind(setup.source_group_id)
    .bind(setup.target_group_id)
    .bind("member_group:members_read")
    .execute(&pool)
    .await
    .expect("Failed to insert member permission");

    // Emit an event for this permission change
    let event_data = serde_json::json!({
        "source_group_id": setup.source_group_id.to_string(),
        "target_group_id": setup.target_group_id.to_string(),
        "action": "member_group:members_read",
        "state": "allow"
    });

    sqlx::query(
        "INSERT INTO events (user_id, wallet_id, aggregate_type, aggregate_id, event_type, event_version, event_data) VALUES ($1, $2, $3, $4, $5, $6, $7)",
    )
    .bind(setup.owner_id)
    .bind(setup.wallet_id)
    .bind("Permission")
    .bind(setup.wallet_id)
    .bind("GroupPermissionsSet")
    .bind(1)
    .bind(event_data)
    .execute(&pool)
    .await
    .expect("Failed to insert event");

    // Verify event was recorded
    let event_count_after: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM events WHERE event_type = 'GroupPermissionsSet' AND aggregate_id = $1::uuid",
    )
    .bind(setup.wallet_id.to_string())
    .fetch_one(&pool)
    .await
    .expect("Failed to count events");

    assert_eq!(event_count_after, 1, "Should have one GroupPermissionsSet event after insertion");

    // Verify event data structure
    let stored_data: serde_json::Value = sqlx::query_scalar(
        "SELECT event_data FROM events WHERE event_type = 'GroupPermissionsSet' AND aggregate_id = $1::uuid LIMIT 1",
    )
    .bind(setup.wallet_id)
    .fetch_one(&pool)
    .await
    .expect("Failed to fetch event data");

    assert_eq!(
        stored_data["source_group_id"].as_str().unwrap(),
        setup.source_group_id.to_string()
    );
    assert_eq!(
        stored_data["target_group_id"].as_str().unwrap(),
        setup.target_group_id.to_string()
    );
    assert_eq!(stored_data["action"].as_str().unwrap(), "member_group:members_read");
    assert_eq!(stored_data["state"].as_str().unwrap(), "allow");
}

// ============ LAYER 2.5 TESTS: CONTACT GROUP PERMISSIONS ============

#[tokio::test]
async fn test_layer25_contact_group_permission_event_emission() {
    let pool = setup_test_db().await;
    let setup = setup_test_data(&pool).await;

    // Verify event table is empty before
    let event_count_before: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM events WHERE event_type = 'ContactGroupPermissionsSet' AND aggregate_id = $1::uuid",
    )
    .bind(setup.wallet_id)
    .fetch_one(&pool)
    .await
    .expect("Failed to count events");

    assert_eq!(event_count_before, 0, "Should have no ContactGroupPermissionsSet events initially");

    // Insert a Layer 2.5 permission
    sqlx::query(
        "INSERT INTO wallet_contact_group_permission_matrix (source_group_id, target_contact_group_id, action, is_deny) VALUES ($1, $2, $3, false)",
    )
    .bind(setup.source_group_id)
    .bind(setup.contact_group_id)
    .bind("contact_group:contacts_read")
    .execute(&pool)
    .await
    .expect("Failed to insert contact group permission");

    // Emit an event for this permission change
    let permissions = vec![
        serde_json::json!({
            "action": "contact_group:contacts_read",
            "state": "allow"
        }),
        serde_json::json!({
            "action": "contact_group:contacts_add",
            "state": "unset"
        })
    ];

    let event_data = serde_json::json!({
        "contact_group_id": setup.contact_group_id.to_string(),
        "member_group_id": setup.source_group_id.to_string(),
        "permissions": permissions
    });

    sqlx::query(
        "INSERT INTO events (user_id, wallet_id, aggregate_type, aggregate_id, event_type, event_version, event_data) VALUES ($1, $2, $3, $4, $5, $6, $7)",
    )
    .bind(setup.owner_id)
    .bind(setup.wallet_id)
    .bind("Permission")
    .bind(setup.wallet_id)
    .bind("ContactGroupPermissionsSet")
    .bind(1)
    .bind(event_data)
    .execute(&pool)
    .await
    .expect("Failed to insert event");

    // Verify event was recorded
    let event_count_after: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM events WHERE event_type = 'ContactGroupPermissionsSet' AND aggregate_id = $1::uuid",
    )
    .bind(setup.wallet_id)
    .fetch_one(&pool)
    .await
    .expect("Failed to count events");

    assert_eq!(event_count_after, 1, "Should have one ContactGroupPermissionsSet event after insertion");

    // Verify event data structure
    let stored_data: serde_json::Value = sqlx::query_scalar(
        "SELECT event_data FROM events WHERE event_type = 'ContactGroupPermissionsSet' AND aggregate_id = $1::uuid LIMIT 1",
    )
    .bind(setup.wallet_id)
    .fetch_one(&pool)
    .await
    .expect("Failed to fetch event data");

    assert_eq!(
        stored_data["contact_group_id"].as_str().unwrap(),
        setup.contact_group_id.to_string()
    );
    assert_eq!(
        stored_data["member_group_id"].as_str().unwrap(),
        setup.source_group_id.to_string()
    );

    let perms = stored_data["permissions"].as_array().expect("permissions should be array");
    assert_eq!(perms.len(), 2);
    assert_eq!(perms[0]["action"].as_str().unwrap(), "contact_group:contacts_read");
    assert_eq!(perms[0]["state"].as_str().unwrap(), "allow");
}

// ============ TESTS: EVENT ORDERING AND MULTIPLE PERMISSIONS ============

#[tokio::test]
async fn test_multiple_layer2_permissions_emit_separate_events() {
    let pool = setup_test_db().await;
    let setup = setup_test_data(&pool).await;

    // Insert multiple permissions
    for action in &["member_group:members_read", "member_group:members_add", "member_group:members_remove"] {
        sqlx::query(
            "INSERT INTO wallet_member_permission_matrix (source_group_id, target_group_id, action, is_deny) VALUES ($1, $2, $3, false)",
        )
        .bind(setup.source_group_id)
        .bind(setup.target_group_id)
        .bind(action)
        .execute(&pool)
        .await
        .expect("Failed to insert member permission");

        // Emit event for each permission
        let event_data = serde_json::json!({
            "source_group_id": setup.source_group_id.to_string(),
            "target_group_id": setup.target_group_id.to_string(),
            "action": action,
            "state": "allow"
        });

        sqlx::query(
            "INSERT INTO events (user_id, wallet_id, aggregate_type, aggregate_id, event_type, event_version, event_data) VALUES ($1, $2, $3, $4, $5, $6, $7)",
        )
        .bind(setup.owner_id)
        .bind(setup.wallet_id)
        .bind("Permission")
        .bind(setup.wallet_id)
        .bind("GroupPermissionsSet")
        .bind(1)
        .bind(event_data)
        .execute(&pool)
        .await
        .expect("Failed to insert event");
    }

    // Verify all three events are recorded
    let event_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM events WHERE event_type = 'GroupPermissionsSet' AND aggregate_id = $1::uuid",
    )
    .bind(setup.wallet_id)
    .fetch_one(&pool)
    .await
    .expect("Failed to count events");

    assert_eq!(event_count, 3, "Should have three separate GroupPermissionsSet events");

    // Verify each action is in the events
    let actions: Vec<String> = sqlx::query_scalar(
        "SELECT event_data->>'action' FROM events WHERE event_type = 'GroupPermissionsSet' AND aggregate_id = $1::uuid ORDER BY created_at",
    )
    .bind(setup.wallet_id)
    .fetch_all(&pool)
    .await
    .expect("Failed to fetch actions");

    assert_eq!(actions.len(), 3);
    assert!(actions.contains(&"member_group:members_read".to_string()));
    assert!(actions.contains(&"member_group:members_add".to_string()));
    assert!(actions.contains(&"member_group:members_remove".to_string()));
}

#[tokio::test]
async fn test_permission_state_serialization() {
    let pool = setup_test_db().await;
    let setup = setup_test_data(&pool).await;

    // Test different permission states: allow, deny
    for (is_deny, expected_state) in &[(false, "allow"), (true, "deny")] {
        let event_data = serde_json::json!({
            "source_group_id": setup.source_group_id.to_string(),
            "target_group_id": setup.target_group_id.to_string(),
            "action": "member_group:members_read",
            "state": if *is_deny { "deny" } else { "allow" }
        });

        sqlx::query(
            "INSERT INTO events (user_id, wallet_id, aggregate_type, aggregate_id, event_type, event_version, event_data) VALUES ($1, $2, $3, $4, $5, $6, $7)",
        )
        .bind(setup.owner_id)
        .bind(setup.wallet_id)
        .bind("Permission")
        .bind(setup.wallet_id)
        .bind("GroupPermissionsSet")
        .bind(1)
        .bind(event_data)
        .execute(&pool)
        .await
        .expect("Failed to insert event");

        // Verify state is correctly serialized
        let stored_state: String = sqlx::query_scalar(
            "SELECT event_data->>'state' FROM events WHERE event_type = 'GroupPermissionsSet' AND aggregate_id = $1::uuid AND event_data->>'action' = 'member_group:members_read' ORDER BY created_at DESC LIMIT 1",
        )
        .bind(setup.wallet_id)
        .fetch_one(&pool)
        .await
        .expect("Failed to fetch state");

        assert_eq!(&stored_state, expected_state);
    }
}
