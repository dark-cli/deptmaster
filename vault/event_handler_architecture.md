# Type-Driven Event Handler Architecture

## Overview

This document describes the **type-driven event handler architecture** for managing domain events in the debt tracker. This architecture replaces string-based event type matching with strongly-typed Rust enums, making it trivial to add new event types without modifying core handler logic.

## Problem: String-Based Event Handling

### The Old Pattern

```rust
match aggregate_type.as_str() {
    "contact" => match event_type.as_str() {
        "CREATED" => { /* 50 lines of contact creation logic */ }
        "UPDATED" => { /* 50 lines of update logic */ }
        "DELETED" => { /* 50 lines of delete logic */ }
        _ => {}
    },
    "transaction" => { /* another 150 lines */ },
    "permission" => { /* another 150 lines */ },
    _ => {}
}
```

### Problems

- ❌ String matching everywhere (error-prone)
- ❌ Adding new event types requires changes in multiple places
- ❌ No compile-time validation of event type names
- ❌ Business logic scattered across handler files
- ❌ Hard to understand which events go where
- ❌ Difficult to test individual event handlers

## Solution: Type-Driven Event Handlers

### The New Pattern

Events know how to apply themselves via impl blocks in `src/domain/events.rs`:

```rust
impl DomainEvent {
    // Events delegate to aggregate-specific handlers
    pub async fn apply_self(
        &self,
        pool: &PgPool,
        wallet_id: Uuid,
        user_id: Uuid,
        event_db_id: i64,
        created_at: NaiveDateTime,
    ) -> Result<(), sqlx::Error> {
        match self.aggregate_type_enum() {
            AggregateType::Contact => self.apply_contact_event(...).await,
            AggregateType::Transaction => self.apply_transaction_event(...).await,
            AggregateType::Permission => self.apply_permission_event(...).await,
        }
    }
    
    // Each aggregate type implements its own handler
    async fn apply_contact_event(&self, ...) -> Result<(), sqlx::Error> {
        match self {
            DomainEvent::ContactCreated { ... } => {
                // INSERT into contacts_projection
            }
            DomainEvent::ContactUpdated { ... } => {
                // UPDATE contacts_projection
            }
            // ... etc
        }
    }
}
```

## Architecture

### 1. AggregateType Enum

Strongly-typed representation of aggregate types:

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AggregateType {
    Contact,
    Transaction,
    Permission,
    // Future: User, Team, Expense
}
```

**Advantages:**
- Compiler catches typos and invalid types
- Easy to add new types (just add enum variant)
- Functions can accept `AggregateType` instead of `&str`

### 2. DomainEvent Enum

Each variant represents a complete event with all required data:

```rust
pub enum DomainEvent {
    ContactCreated {
        id: Uuid,
        aggregate_id: Uuid,
        wallet_id: Uuid,
        name: String,
        username: Option<String>,
        // ... other fields
    },
    ContactUpdated { /* ... */ },
    WalletUserAdded { /* ... */ },
    // ... 20+ event types
}
```

**Key Methods:**
- `aggregate_type_enum()` - Returns strongly-typed `AggregateType`
- `apply_self()` - Applies this event to the database
- `clear_aggregate_type()` - Clears all data for an aggregate type (for rebuilds)

### 3. Event Application Flow

```
┌─────────────────────────────────────────┐
│ Sync arrives or Rebuild starts          │
└────────────┬────────────────────────────┘
             │
             ├─→ Load event rows from database
             │
             ├─→ Deserialize into DomainEvent
             │
             ├─→ Call event.apply_self()
             │   ├─→ Match on aggregate_type_enum()
             │   ├─→ Delegate to apply_contact_event()
             │   │   └─→ Match on event variant
             │   │       └─→ Execute INSERT/UPDATE/DELETE
             │   ├─→ Delegate to apply_transaction_event()
             │   └─→ Delegate to apply_permission_event()
             │
             └─→ Update projections
```

### 4. Event Clearing for UNDO

When UNDO events are present, projections must be rebuilt from scratch:

```rust
// Type-driven clearing
DomainEvent::clear_aggregate_type(pool, AggregateType::Contact, wallet_id).await?;
DomainEvent::clear_aggregate_type(pool, AggregateType::Transaction, wallet_id).await?;
DomainEvent::clear_aggregate_type(pool, AggregateType::Permission, wallet_id).await?;
```

## Adding a New Event Type

### Step 1: Define the Event Variant

In `src/domain/events.rs`, add variant to `DomainEvent`:

```rust
pub enum DomainEvent {
    // Existing events...
    
    // New User events
    UserProfileUpdated {
        id: Uuid,
        aggregate_id: Uuid,  // user_id
        wallet_id: Uuid,
        user_id: Uuid,
        created_at: DateTime<Utc>,
        bio: String,
        avatar_url: Option<String>,
        // ... other fields
    },
}
```

### Step 2: Update AggregateType

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AggregateType {
    Contact,
    Transaction,
    Permission,
    User,  // NEW
}
```

### Step 3: Implement the Handler

In `src/domain/events.rs`, add handler method:

```rust
async fn apply_user_event(
    &self,
    pool: &PgPool,
    wallet_id: Uuid,
    user_id: Uuid,
    event_db_id: i64,
    created_at: NaiveDateTime,
) -> Result<(), sqlx::Error> {
    match self {
        DomainEvent::UserProfileUpdated {
            aggregate_id,
            bio,
            avatar_url,
            ..
        } => {
            sqlx::query(
                "UPDATE users SET bio = $1, avatar_url = $2 WHERE id = $3"
            )
            .bind(bio)
            .bind(avatar_url)
            .bind(aggregate_id)
            .execute(pool)
            .await?;
            Ok(())
        }
        // ... other user events
    }
}
```

### Step 4: Add Delegation in apply_self()

```rust
pub async fn apply_self(&self, ...) -> Result<(), sqlx::Error> {
    match self.aggregate_type_enum() {
        AggregateType::Contact => self.apply_contact_event(...).await,
        AggregateType::Transaction => self.apply_transaction_event(...).await,
        AggregateType::Permission => self.apply_permission_event(...).await,
        AggregateType::User => self.apply_user_event(...).await,  // NEW
    }
}
```

### Step 5: Add Clearing Logic

```rust
pub async fn clear_aggregate_type(
    pool: &PgPool,
    agg_type: AggregateType,
    wallet_id: Uuid,
) -> Result<(), sqlx::Error> {
    match agg_type {
        // ... existing cases ...
        AggregateType::User => {
            sqlx::query("DELETE FROM user_profiles WHERE wallet_id = $1")
                .bind(wallet_id)
                .execute(pool)
                .await?;
            Ok(())
        }
    }
}
```

**Total new code: ~50 lines** (mostly boilerplate that the compiler helps write)

## Benefits

| Aspect | String-Based | Type-Driven |
|--------|--------------|-------------|
| **Add new event type** | Modify 5+ files, add string cases everywhere | Add variant, implement handler, done |
| **Type Safety** | Strings everywhere, runtime errors | Compiler-checked, zero strings |
| **Error Handling** | "Invalid event_type: CREATED_CONTACT" | Compiler error if typo in variant |
| **Future Scalability** | Each new type requires more refactoring | Each type is isolated in handlers |
| **Testing** | Integration tests only | Can unit test handlers directly |
| **Documentation** | Need to maintain wiki of valid types | Enum definition is self-documenting |
| **Refactoring** | Find-replace strings (fragile) | Compiler guided refactoring |

## Current Implementation Status

### Complete ✅
- ✅ `AggregateType` enum with Contact, Transaction, Permission
- ✅ `apply_contact_event()` handler (full implementation)
- ✅ `apply_permission_event()` handler (full implementation)
- ✅ `aggregate_type_enum()` method on DomainEvent
- ✅ `clear_aggregate_type()` method for type-safe clearing
- ✅ `apply_event_batch_type_driven()` ready for migration
- ✅ All tests passing with old apply_event_batch

### In Progress 🔄
- 🔄 Complete `apply_transaction_event()` handler
- 🔄 Migrate apply_event_batch to use apply_event_batch_type_driven
- 🔄 Remove old apply_event_batch string-matching code

### Future 📅
- 📅 Add User events (UserProfileUpdated, etc.)
- 📅 Add Team events (TeamCreated, TeamMemberAdded, etc.)
- 📅 Add Expense events for more complex scenarios
- 📅 Create EventApplier trait for trait-based dispatch (optional optimization)

## Migration Path

### Phase 1: Foundation (Complete) ✅
- Add AggregateType enum
- Add apply_self() and aggregate_type_enum() methods
- Implement apply_contact_event() and apply_permission_event()

### Phase 2: Complete Handlers
1. Finish apply_transaction_event() with all event types
2. Write tests for individual handlers
3. Benchmark against old string-based approach

### Phase 3: Migrate Code
1. Update apply_event_batch_type_driven() to be production-ready
2. Gradually migrate call sites to use new method
3. Run full test suite after each migration

### Phase 4: Cleanup
1. Remove old apply_event_batch (if no longer needed)
2. Simplify handler code without string matching
3. Add EventApplier trait for optional trait-based dispatch

## Code Location

### Event Definitions & Handlers
- **File:** `src/domain/events.rs`
- **Size:** ~800 lines (event definitions + handlers)
- **Key Methods:**
  - `DomainEvent::apply_self()` - Main entry point
  - `DomainEvent::aggregate_type_enum()` - Type safety
  - `DomainEvent::clear_aggregate_type()` - Clearing for rebuilds
  - `DomainEvent::apply_contact_event()` - Contact handler
  - `DomainEvent::apply_permission_event()` - Permission handler

### Event Application
- **File:** `src/database/repository/events.rs`
- **Methods:**
  - `apply_event_batch()` - Old string-based (deprecated)
  - `apply_event_batch_type_driven()` - New type-driven (in progress)
  - `apply_event_to_projections()` - Single event application

### Projection Rebuilds
- **File:** `src/services/projections.rs`
- **Usage:** Uses DomainEvent::clear_aggregate_type() for clearing

## Example: Permission Event Flow

How a WALLET_USER_ADDED event is handled:

```
1. POST /sync with WALLET_USER_ADDED event
   ↓
2. post_sync_events() receives SyncEventRequest
   ↓
3. Event inserted into events table as:
   {
     "event_type": "WALLET_USER_ADDED",
     "aggregate_type": "permission",
     "aggregate_id": "group-123",
     "event_data": {
       "user_id": "user-456",
       "role": "admin"
     }
   }
   ↓
4. apply_event_to_projections() fetches event row
   ↓
5. Row deserialized into:
   DomainEvent::WalletUserAdded {
     aggregate_id: Uuid,
     data: {"user_id": "...", "role": "admin"}
   }
   ↓
6. event.apply_self() called
   ↓
7. Matches on aggregate_type_enum() → AggregateType::Permission
   ↓
8. Delegates to apply_permission_event()
   ↓
9. Matches on DomainEvent::WalletUserAdded variant
   ↓
10. Executes INSERT into wallet_users
    ↓
11. wallet_users table updated with user-456 as admin
```

## Testing

### Unit Test Example

```rust
#[tokio::test]
async fn test_contact_created_event() {
    let pool = setup_test_db().await;
    let event = DomainEvent::ContactCreated {
        id: Uuid::new_v4(),
        aggregate_id: contact_id,
        wallet_id: wallet_id,
        user_id: user_id,
        created_at: Utc::now(),
        version: 1,
        idempotency_key: None,
        name: "Alice".to_string(),
        username: None,
        phone: None,
        email: None,
        notes: None,
    };
    
    // Apply the event
    event.apply_self(&pool, wallet_id, user_id, 1, created_at).await.unwrap();
    
    // Verify contact was created
    let contact: (String,) = sqlx::query_as(
        "SELECT name FROM contacts_projection WHERE id = $1"
    )
    .bind(contact_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    
    assert_eq!(contact.0, "Alice");
}
```

## Best Practices

1. **Keep handlers focused** - Each event type has one matching arm
2. **Use aggregate_type_enum()** - Never string-match aggregate types
3. **Delegate in apply_self()** - Don't add new match arms outside
4. **Document event data** - Include field descriptions in variant
5. **Test handlers independently** - Don't rely on full sync test for each type

## Future Considerations

### EventApplier Trait

Once all handlers are complete, could add trait-based dispatch (optional):

```rust
#[async_trait]
pub trait EventApplier {
    async fn apply(&self, pool: &PgPool, wallet_id: Uuid, ...) -> Result<(), sqlx::Error>;
    async fn clear_aggregate(&self, pool: &PgPool, wallet_id: Uuid) -> Result<(), sqlx::Error>;
}

// Implement for each aggregate type
impl EventApplier for ContactEvent { ... }
impl EventApplier for PermissionEvent { ... }
```

Benefits: Smaller DomainEvent match statements, trait-based handler registry

### Event Streaming

With this architecture, adding real-time event streaming is trivial:

```rust
// Broadcast each event after applying
event.apply_self(pool, ...).await?;
broadcast_tx.send(event)?;  // Notify subscribers
```

## References

- `src/domain/events.rs` - Event definitions and handlers
- `src/database/repository/events.rs` - Event application logic
- `src/services/projections.rs` - Projection rebuild logic
- `vault/projections_and_snapshots.md` - Projection architecture
- Tests: `tests/snapshot_optimization_test.rs`
