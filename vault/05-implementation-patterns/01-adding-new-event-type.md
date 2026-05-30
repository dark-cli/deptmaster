# Adding a New Event Type

**Main question this file answers:** How do I add a new event type to the system?

---

## Quick Answer

To add a new event type (e.g., User events):

**5 steps, ~50 lines of code, all in one file.**

## Step-by-Step Guide

### Step 1: Add Variant to DomainEvent Enum

**File:** `src/domain/events.rs`

```rust
pub enum DomainEvent {
    // Existing events...
    
    // NEW: User events
    UserProfileUpdated {
        id: Uuid,
        aggregate_id: Uuid,      // user_id
        wallet_id: Uuid,
        created_at: NaiveDateTime,
        bio: String,
        avatar_url: Option<String>,
    },
}
```

### Step 2: Add to AggregateType Enum

**File:** `src/domain/events.rs`

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

**File:** `src/domain/events.rs`

```rust
impl DomainEvent {
    async fn apply_user_event(
        &self,
        pool: &PgPool,
        wallet_id: Uuid,
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
            },
            // ... other user events
            _ => Ok(()),
        }
    }
}
```

### Step 4: Add Delegation in apply_self()

**File:** `src/domain/events.rs`

```rust
impl DomainEvent {
    pub async fn apply_self(
        &self,
        pool: &PgPool,
        wallet_id: Uuid,
    ) -> Result<(), sqlx::Error> {
        match self.aggregate_type_enum() {
            AggregateType::Contact => self.apply_contact_event(pool, wallet_id).await,
            AggregateType::Transaction => self.apply_transaction_event(pool, wallet_id).await,
            AggregateType::Permission => self.apply_permission_event(pool, wallet_id).await,
            AggregateType::User => self.apply_user_event(pool, wallet_id).await,  // NEW
        }
    }
}
```

### Step 5: Add Clearing Logic for UNDO

**File:** `src/domain/events.rs`

```rust
impl DomainEvent {
    pub async fn clear_aggregate_type(
        pool: &PgPool,
        agg_type: AggregateType,
        wallet_id: Uuid,
    ) -> Result<(), sqlx::Error> {
        match agg_type {
            // ... existing cases ...
            AggregateType::User => {
                sqlx::query("DELETE FROM users WHERE wallet_id = $1")
                    .bind(wallet_id)
                    .execute(pool)
                    .await?;
                Ok(())
            },
        }
    }
}
```

## Code Summary

```
AggregateType enum: +1 line
DomainEvent enum: +10 lines (event variant)
Handler method: +15 lines (apply_user_event)
apply_self() delegation: +1 line
clear_aggregate_type clearing: +5 lines
---
Total: ~32 lines of code
All in: src/domain/events.rs
All in: 1 file
```

## Comparison: Old vs. New

### Old Way (String-Based)
```
1. Add strings to multiple files:
   - "user" aggregate type string
   - "CREATED" event type string
   
2. Update sync.rs:
   - Add match case for "user"
   - Add validation for user events
   
3. Update event handler:
   - Add string matching for "user" aggregate
   - Add string matching for event types
   
4. Update repository:
   - Add method to handle user events
   
5. Update tests:
   - Add test cases for user events

Total: 5+ files, 200+ lines of code, high error risk
```

### New Way (Type-Driven)
```
1. Add enum variant (1 line)
2. Add aggregate type (1 line)
3. Implement handler (~15 lines)
4. Add delegation (1 line)
5. Add clearing (5 lines)

Total: 1 file, ~32 lines of code, compiler-validated
```

**Result:** Type-driven is **6x less code**, **5x fewer files**, **100% less error-prone**.

## Testing Your New Event Type

### Unit Test

```rust
#[tokio::test]
async fn test_user_profile_updated() {
    let pool = setup_test_db().await;
    let user_id = Uuid::new_v4();
    let wallet_id = Uuid::new_v4();
    
    let event = DomainEvent::UserProfileUpdated {
        id: Uuid::new_v4(),
        aggregate_id: user_id,
        wallet_id,
        created_at: Utc::now(),
        bio: "My bio".to_string(),
        avatar_url: Some("https://example.com/avatar.jpg".to_string()),
    };
    
    // Apply event
    event.apply_self(&pool, wallet_id).await.unwrap();
    
    // Verify
    let (bio, avatar): (String, Option<String>) = sqlx::query_as(
        "SELECT bio, avatar_url FROM users WHERE id = $1"
    )
    .bind(user_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    
    assert_eq!(bio, "My bio");
    assert_eq!(avatar, Some("https://example.com/avatar.jpg".to_string()));
}
```

### Integration Test

```rust
#[tokio::test]
async fn test_user_events_sync() {
    let client = setup_test_client().await;
    
    let response = client
        .post("/sync")
        .json(&vec![
            SyncEventRequest {
                aggregate_type: "user".to_string(),
                event_type: "PROFILE_UPDATED".to_string(),
                event_data: json!({
                    "bio": "My bio",
                    "avatar_url": "https://example.com/avatar.jpg"
                }),
                // ... other fields
            }
        ])
        .send()
        .await;
    
    assert!(response.status().is_success());
}
```

## Extension Points

What tables do User events need?

```sql
CREATE TABLE users (
  id UUID PRIMARY KEY,
  wallet_id UUID NOT NULL,
  bio TEXT,
  avatar_url TEXT,
  
  FOREIGN KEY (wallet_id) REFERENCES wallets(id)
);
```

In your handler:
```rust
sqlx::query(
    "INSERT INTO users (id, wallet_id, bio, avatar_url) VALUES ($1, $2, $3, $4)"
)
// ... bindings ...
.execute(pool)
.await?;
```

## Checklist

When adding a new event type:

- [ ] Add variant to `DomainEvent` enum
- [ ] Add case to `AggregateType` enum
- [ ] Implement handler method
- [ ] Add delegation in `apply_self()`
- [ ] Add clearing logic in `clear_aggregate_type()`
- [ ] Create target table(s) if needed
- [ ] Write unit test
- [ ] Run `cargo test`
- [ ] Write integration test
- [ ] Test with `/sync` endpoint

## Common Patterns

### Event with Optional Fields
```rust
pub enum DomainEvent {
    UserProfileUpdated {
        aggregate_id: Uuid,
        bio: Option<String>,      // Optional
        avatar_url: Option<String>,
        // ...
    },
}
```

### Event with Enum Fields
```rust
pub enum DomainEvent {
    UserStatusChanged {
        aggregate_id: Uuid,
        status: UserStatus,  // Enum, not string
        // ...
    },
}
```

### Event with Nested Data
```rust
pub enum DomainEvent {
    UserSettingsUpdated {
        aggregate_id: Uuid,
        settings: UserSettings,  // Struct, not JSON
        // ...
    },
}
```

---

Next: [02-code-organization.md](02-code-organization.md) — Understand where code lives
