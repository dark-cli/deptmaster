# User Events Walkthrough

**Main question this file answers:** How do I add User events from start to finish?

---

## Overview

This is a complete walkthrough of adding a new aggregate type (User) to the system.

Following Chapter 05 (Implementation Patterns), but with all the details filled in.

## The Five Steps

### Step 1: Add Event Variants

**File:** `src/domain/events.rs`

```rust
pub enum DomainEvent {
    // ... existing events ...
    
    UserProfileUpdated {
        id: Uuid,
        aggregate_id: Uuid,              // user_id
        wallet_id: Uuid,
        created_at: NaiveDateTime,
        bio: String,
        avatar_url: Option<String>,
        display_name: Option<String>,
    },
    
    UserPreferencesUpdated {
        id: Uuid,
        aggregate_id: Uuid,              // user_id
        wallet_id: Uuid,
        created_at: NaiveDateTime,
        theme: String,                   // "light" | "dark"
        notifications_enabled: bool,
    },
}
```

### Step 2: Add Aggregate Type

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AggregateType {
    Contact,
    Transaction,
    Permission,
    User,  // NEW
}
```

### Step 3: Create User Tables

**Migration:** `migrations/[timestamp]_create_user_tables.sql`

```sql
CREATE TABLE users (
    id UUID PRIMARY KEY,
    wallet_id UUID NOT NULL,
    bio TEXT,
    avatar_url TEXT,
    display_name TEXT,
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP,
    
    FOREIGN KEY (wallet_id) REFERENCES wallets(id)
);

CREATE TABLE user_preferences (
    user_id UUID PRIMARY KEY,
    wallet_id UUID NOT NULL,
    theme TEXT DEFAULT 'light',
    notifications_enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP,
    
    FOREIGN KEY (user_id) REFERENCES users(id),
    FOREIGN KEY (wallet_id) REFERENCES wallets(id)
);
```

### Step 4: Implement Handler

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
                display_name,
                ..
            } => {
                sqlx::query(
                    "INSERT INTO users (id, wallet_id, bio, avatar_url, display_name, created_at, updated_at)
                     VALUES ($1, $2, $3, $4, $5, NOW(), NOW())
                     ON CONFLICT (id) DO UPDATE SET
                        bio = $3, avatar_url = $4, display_name = $5, updated_at = NOW()"
                )
                .bind(aggregate_id)
                .bind(wallet_id)
                .bind(bio)
                .bind(avatar_url)
                .bind(display_name)
                .execute(pool)
                .await?;
                Ok(())
            },
            
            DomainEvent::UserPreferencesUpdated {
                aggregate_id,
                theme,
                notifications_enabled,
                ..
            } => {
                sqlx::query(
                    "INSERT INTO user_preferences (user_id, wallet_id, theme, notifications_enabled, created_at, updated_at)
                     VALUES ($1, $2, $3, $4, NOW(), NOW())
                     ON CONFLICT (user_id) DO UPDATE SET
                        theme = $3, notifications_enabled = $4, updated_at = NOW()"
                )
                .bind(aggregate_id)
                .bind(wallet_id)
                .bind(theme)
                .bind(notifications_enabled)
                .execute(pool)
                .await?;
                Ok(())
            },
            
            _ => Ok(()),
        }
    }
}
```

### Step 5: Update apply_self()

```rust
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
```

### Step 6: Add Clearing Logic

```rust
pub async fn clear_aggregate_type(
    pool: &PgPool,
    agg_type: AggregateType,
    wallet_id: Uuid,
) -> Result<(), sqlx::Error> {
    match agg_type {
        // ... existing cases ...
        
        AggregateType::User => {
            sqlx::query("DELETE FROM user_preferences WHERE wallet_id = $1")
                .bind(wallet_id)
                .execute(pool)
                .await?;
            
            sqlx::query("DELETE FROM users WHERE wallet_id = $1")
                .bind(wallet_id)
                .execute(pool)
                .await?;
            
            Ok(())
        },
    }
}
```

## Testing

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
        display_name: Some("Alice".to_string()),
    };
    
    event.apply_self(&pool, wallet_id).await.unwrap();
    
    let (bio,): (String,) = sqlx::query_as("SELECT bio FROM users WHERE id = $1")
        .bind(user_id)
        .fetch_one(&pool)
        .await
        .unwrap();
    
    assert_eq!(bio, "My bio");
}
```

### Integration Test
Test via `/sync` endpoint with user events.

## Summary

Total code added:
- Event variants: 20 lines
- AggregateType: 1 line
- Handler: 40 lines
- apply_self: 1 line
- clear_aggregate_type: 10 lines
- Tests: 50+ lines
- **Total: ~120 lines in src/domain/events.rs + tests**

All in one focused location.

---

Next: [../07-advanced-topics/01-memory-bounds-analysis.md](../07-advanced-topics/01-memory-bounds-analysis.md) — Understand memory optimization in depth
