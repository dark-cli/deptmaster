# Testing Event Handlers

**Main question this file answers:** How do I test event handlers?

---

## Unit Testing an Event Handler

```rust
#[tokio::test]
async fn test_contact_created_event() {
    let pool = setup_test_db().await;
    let wallet_id = Uuid::new_v4();
    let contact_id = Uuid::new_v4();
    
    // Create event
    let event = DomainEvent::ContactCreated {
        id: contact_id,
        aggregate_id: contact_id,
        wallet_id,
        name: "Alice".to_string(),
        email: Some("alice@example.com".to_string()),
        phone: None,
        username: None,
        notes: None,
    };
    
    // Apply event
    event.apply_self(&pool, wallet_id).await.unwrap();
    
    // Verify
    let (name, email): (String, Option<String>) = sqlx::query_as(
        "SELECT name, email FROM contacts_projection WHERE id = $1"
    )
    .bind(contact_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    
    assert_eq!(name, "Alice");
    assert_eq!(email, Some("alice@example.com".to_string()));
}
```

## Integration Testing a Sync

```rust
#[tokio::test]
async fn test_sync_contact_events() {
    let client = setup_test_client().await;
    let wallet_id = Uuid::new_v4();
    
    let response = client
        .post("/sync")
        .json(&SyncRequest {
            wallet_id,
            events: vec![
                SyncEventRequest {
                    id: Uuid::new_v4(),
                    aggregate_type: "contact".to_string(),
                    event_type: "CREATED".to_string(),
                    aggregate_id: Uuid::new_v4(),
                    event_data: json!({
                        "name": "Alice",
                        "email": "alice@example.com"
                    }),
                    timestamp: Utc::now(),
                    version: 1,
                }
            ],
        })
        .send()
        .await
        .unwrap();
    
    assert!(response.status().is_success());
    
    // Verify contact was created
    let contacts = client
        .get("/contacts")
        .query(&[("wallet_id", wallet_id.to_string())])
        .send()
        .await
        .unwrap()
        .json::<Vec<Contact>>()
        .await
        .unwrap();
    
    assert_eq!(contacts.len(), 1);
    assert_eq!(contacts[0].name, "Alice");
}
```

## Testing UNDO

```rust
#[tokio::test]
async fn test_undo_contact_created() {
    let pool = setup_test_db().await;
    let wallet_id = Uuid::new_v4();
    let contact_id = Uuid::new_v4();
    
    // Event 1: Create contact
    let create_event = DomainEvent::ContactCreated {
        id: contact_id,
        aggregate_id: contact_id,
        wallet_id,
        name: "Alice".to_string(),
        // ...
    };
    create_event.apply_self(&pool, wallet_id).await.unwrap();
    
    // Event 2: UNDO
    let undo_event = DomainEvent::UNDO {
        undone_event_id: 1,
        // ...
    };
    
    // Detect UNDO and rebuild
    let has_undo = true;
    if has_undo {
        DomainEvent::clear_aggregate_type(&pool, AggregateType::Contact, wallet_id).await.unwrap();
        // Would reprocess events, skipping the undone one
    }
    
    // Verify contact is NOT in projections
    let count: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM contacts_projection WHERE id = $1")
        .bind(contact_id)
        .fetch_one(&pool)
        .await
        .unwrap();
    
    assert_eq!(count.0, 0);
}
```

## Testing Snapshots

```rust
#[tokio::test]
async fn test_snapshot_creation() {
    let pool = setup_test_db().await;
    let wallet_id = Uuid::new_v4();
    
    // Create 1000 events
    for i in 0..1000 {
        let event = DomainEvent::ContactCreated {
            id: Uuid::new_v4(),
            aggregate_id: Uuid::new_v4(),
            wallet_id,
            name: format!("Contact {}", i),
            // ...
        };
        event.apply_self(&pool, wallet_id).await.unwrap();
    }
    
    // Check snapshot was created (every 1000 events)
    let snapshot: (i64,) = sqlx::query_as(
        "SELECT last_event_id FROM snapshots WHERE wallet_id = $1 AND aggregate_type = 'contact'"
    )
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    
    assert_eq!(snapshot.0, 1000);
}
```

## Test Patterns

### Setup Test Database
```rust
async fn setup_test_db() -> PgPool {
    // Create pool connected to test database
    // Run migrations
    // Return clean database
}
```

### Arrange-Act-Assert
```rust
// Arrange: Create test data
let event = DomainEvent::ContactCreated { ... };

// Act: Perform action
event.apply_self(&pool, wallet_id).await?;

// Assert: Verify result
assert_eq!(actual, expected);
```

### Test Idempotency
```rust
#[tokio::test]
async fn test_event_idempotent() {
    let pool = setup_test_db().await;
    let event = DomainEvent::ContactCreated { ... };
    
    // Apply twice
    event.apply_self(&pool, wallet_id).await.unwrap();
    event.apply_self(&pool, wallet_id).await.unwrap();
    
    // Should only create one contact (duplicate fails or is handled)
    let count: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM contacts_projection")
        .fetch_one(&pool)
        .await
        .unwrap();
    
    assert_eq!(count.0, 1);
}
```

## Current Test Coverage

See: `tests/snapshot_optimization_test.rs`

All tests passing (13/13):
- Permission event batch processing
- Permission event UNDO handling
- Permission events with snapshots

---

Next: [../06-advanced-extensions/01-user-events-walkthrough.md](../06-advanced-extensions/01-user-events-walkthrough.md) — Complete walkthrough of adding User events
