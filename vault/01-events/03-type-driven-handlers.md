# Type-Driven Handlers

**Main question this file answers:** How do handlers apply events to the database?

---

## The Problem: String-Based Handlers (Old)

Before, the system used strings to decide how to handle events:

```rust
match aggregate_type.as_str() {
    "contact" => match event_type.as_str() {
        "CREATED" => { /* 50 lines of logic */ }
        "UPDATED" => { /* 50 lines of logic */ }
        _ => {}
    },
    "transaction" => { /* another 150 lines */ },
    _ => {}
}
```

**Problems:**
- ❌ Error-prone (typos in strings cause silent failures)
- ❌ Scattered across multiple files
- ❌ Hard to add new event types (modify 5+ places)
- ❌ No compile-time validation
- ❌ Hard to test individual handlers

## The Solution: Type-Driven Handlers (IMPLEMENTED)

Instead, events know how to apply themselves using **Rust enums**:

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
        }
    }
    
    async fn apply_contact_event(&self, pool: &PgPool, wallet_id: Uuid) -> Result<(), sqlx::Error> {
        match self {
            DomainEvent::ContactCreated { id, name, email, .. } => {
                // INSERT into contacts_projection
                sqlx::query(
                    "INSERT INTO contacts_projection (id, wallet_id, name, email, ...) VALUES ($1, $2, $3, $4, ...)"
                )
                .bind(id)
                .bind(wallet_id)
                .bind(name)
                .bind(email)
                .execute(pool)
                .await?;
                Ok(())
            },
            DomainEvent::ContactUpdated { id, name, email, .. } => {
                // UPDATE contacts_projection
                sqlx::query(
                    "UPDATE contacts_projection SET name = $1, email = $2 WHERE id = $3"
                )
                .bind(name)
                .bind(email)
                .bind(id)
                .execute(pool)
                .await?;
                Ok(())
            },
            // ... other contact events
            _ => Ok(()),
        }
    }
}
```

## The Architecture

### 1. DomainEvent Enum

Strongly-typed events:

```rust
pub enum DomainEvent {
    ContactCreated { id: Uuid, name: String, email: Option<String>, ... },
    ContactUpdated { id: Uuid, name: String, email: Option<String>, ... },
    TransactionCreated { id: Uuid, amount: i64, direction: String, ... },
    WalletUserAdded { user_id: Uuid, role: String, ... },
    // ... 20+ more variants
}
```

**Benefits:**
- Compiler ensures only valid events exist
- All data is there (no null checking needed)
- Can't typo an event type (compiler catches it)

### 2. AggregateType Enum

Represents the three main types of things we track:

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AggregateType {
    Contact,
    Transaction,
    Permission,
    // Future: User, Team, Expense
}
```

**Benefits:**
- Compiler validates aggregate types
- Easy to extend (just add variant)
- No string matching needed

### 3. Handler Methods

Each aggregate type has a handler method:

```rust
impl DomainEvent {
    async fn apply_contact_event(&self, pool: &PgPool, wallet_id: Uuid) -> Result<(), sqlx::Error> {
        match self { /* handle all contact events */ }
    }
    
    async fn apply_transaction_event(&self, pool: &PgPool, wallet_id: Uuid) -> Result<(), sqlx::Error> {
        match self { /* handle all transaction events */ }
    }
    
    async fn apply_permission_event(&self, pool: &PgPool, wallet_id: Uuid) -> Result<(), sqlx::Error> {
        match self { /* handle all permission events */ }
    }
}
```

### 4. Main Entry Point: apply_self()

Events delegate to aggregate-specific handlers:

```rust
pub async fn apply_self(&self, pool: &PgPool, wallet_id: Uuid) -> Result<(), sqlx::Error> {
    match self.aggregate_type_enum() {
        AggregateType::Contact => self.apply_contact_event(pool, wallet_id).await,
        AggregateType::Transaction => self.apply_transaction_event(pool, wallet_id).await,
        AggregateType::Permission => self.apply_permission_event(pool, wallet_id).await,
    }
}
```

## The Flow

When an event arrives:

```
1. Sync endpoint receives event JSON
   ↓
2. Deserialize into DomainEvent enum
   (compiler ensures valid event)
   ↓
3. Call event.apply_self()
   ↓
4. Match on aggregate_type_enum()
   (compiler ensures valid type)
   ↓
5. Delegate to handler:
   - apply_contact_event()
   - apply_transaction_event()
   - apply_permission_event()
   ↓
6. Handler matches on event variant:
   DomainEvent::ContactCreated { ... } => INSERT
   DomainEvent::ContactUpdated { ... } => UPDATE
   DomainEvent::ContactDeleted => DELETE
   ↓
7. Execute SQL
   ↓
8. Return to caller
```

## Type Clearing for UNDO

When UNDO events are present, we need to clear projections before rebuilding:

```rust
pub async fn clear_aggregate_type(
    pool: &PgPool,
    agg_type: AggregateType,
    wallet_id: Uuid,
) -> Result<(), sqlx::Error> {
    match agg_type {
        AggregateType::Contact => {
            sqlx::query("DELETE FROM contacts_projection WHERE wallet_id = $1")
                .bind(wallet_id)
                .execute(pool)
                .await?;
            Ok(())
        },
        AggregateType::Transaction => {
            sqlx::query("DELETE FROM transactions_projection WHERE wallet_id = $1")
                .bind(wallet_id)
                .execute(pool)
                .await?;
            Ok(())
        },
        AggregateType::Permission => {
            // Clear permission tables (wallet_users, user_groups, etc.)
            sqlx::query("DELETE FROM wallet_users WHERE wallet_id = $1 AND role != 'owner'")
                .bind(wallet_id)
                .execute(pool)
                .await?;
            // ... clear other permission tables
            Ok(())
        },
    }
}
```

## Benefits of Type-Driven Handlers

| Aspect | String-Based | Type-Driven |
|---|---|---|
| **Add new event type** | Modify 5+ files, update strings | Add enum variant, write handler |
| **Type Safety** | Strings (error-prone) | Compiler-checked enums |
| **Typos** | "oops, CONTACT_CREATE is invalid" (silent) | Compiler error |
| **Code Location** | Scattered across handler files | All in domain/events.rs |
| **Testing** | Integration tests only | Can unit test handlers |
| **Refactoring** | Find-replace strings (fragile) | Compiler-guided changes |
| **Documentation** | Need separate wiki | Enum definition is self-documenting |

## Aggregate Type Extension Points

Adding a new aggregate type is straightforward:

```
Want to add User events?

Step 1: Add to AggregateType enum
    #[derive(Debug, Clone, Copy, ...)]
    pub enum AggregateType {
        Contact,
        Transaction,
        Permission,
        User,  // NEW
    }

Step 2: Add event variants
    pub enum DomainEvent {
        // existing...
        UserProfileUpdated { id: Uuid, bio: String, ... },
    }

Step 3: Implement handler
    async fn apply_user_event(&self, pool: &PgPool, wallet_id: Uuid) -> Result<(), sqlx::Error> {
        match self {
            DomainEvent::UserProfileUpdated { id, bio, ... } => {
                // UPDATE users_projection
                sqlx::query("UPDATE users SET bio = $1 WHERE id = $2")
                    .bind(bio)
                    .bind(id)
                    .execute(pool)
                    .await?;
                Ok(())
            },
            // ... other user events
            _ => Ok(()),
        }
    }

Step 4: Add to apply_self()
    AggregateType::User => self.apply_user_event(pool, wallet_id).await,

Step 5: Add clearing logic
    AggregateType::User => {
        sqlx::query("DELETE FROM users WHERE wallet_id = $1")
            .bind(wallet_id)
            .execute(pool)
            .await?;
        Ok(())
    }

Total new code: ~50 lines in ONE file
```

Compare to string-based (would need to add match cases in 5+ files).

## Where Handlers Live

**File:** `src/domain/events.rs`

- DomainEvent enum: Event definitions (20+ variants)
- AggregateType enum: Aggregate types
- apply_self(): Main entry point (routes to handlers)
- apply_contact_event(): Contact handler (50 lines)
- apply_transaction_event(): Transaction handler (50 lines)
- apply_permission_event(): Permission handler (50 lines)
- clear_aggregate_type(): Type-safe clearing (50 lines)

All in one place, so adding new events is easy.

---

Next: [../02-projections/01-what-are-projections.md](../02-projections/01-what-are-projections.md) — Understand what projections are and how handlers update them
