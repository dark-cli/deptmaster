# Permission Sync Flow

**Main question this file answers:** How do permission events flow through the system?

---

## Complete Flow: Permission Event from API to Database

### Example: WalletUserAdded Event

User requests to add Alice to their wallet as an admin.

```
1. POST /sync with:
   {
     "event_type": "WALLET_USER_ADDED",
     "aggregate_type": "permission",
     "event_data": { "user_id": "alice", "role": "admin" }
   }
```

### Step 1: Sync Handler Receives Request

```rust
pub async fn post_sync_events(
    State(state): State<AppState>,
    Json(events): Json<Vec<SyncEventRequest>>,
) -> Result<Json<SyncResponse>, Error> {
    // Process events...
}
```

### Step 2: Validate and Check Permissions

```rust
// Check if requesting user has permission to invite others
permission_model
    .check_permission(
        &wallet_context,
        Action::UserInvite,
        Resource::AllUsers,
    )
    .await?;
```

### Step 3: Store Event in Database

```rust
// INSERT into events table
let event_id = db.insert_event(
    wallet_id,
    "permission",           // aggregate_type
    "WALLET_USER_ADDED",    // event_type
    serde_json::json!({
        "user_id": "alice",
        "role": "admin"
    }),
).await?;
```

### Step 4: Apply Event to Database

```rust
// Deserialize into DomainEvent
let domain_event = DomainEvent::WalletUserAdded {
    user_id: Uuid::parse("alice")?,
    role: "admin".to_string(),
};

// Call event.apply_self()
domain_event.apply_self(&pool, wallet_id).await?;
```

### Step 5: Handler Processes Event

Type-driven handler for permission events:

```rust
impl DomainEvent {
    async fn apply_permission_event(
        &self,
        pool: &PgPool,
        wallet_id: Uuid,
    ) -> Result<(), sqlx::Error> {
        match self {
            DomainEvent::WalletUserAdded { user_id, role } => {
                sqlx::query(
                    "INSERT INTO wallet_users (wallet_id, user_id, role, created_at)
                     VALUES ($1, $2, $3, NOW())"
                )
                .bind(wallet_id)
                .bind(user_id)
                .bind(role)
                .execute(pool)
                .await?;
                Ok(())
            },
            // ... other permission events
            _ => Ok(()),
        }
    }
}
```

### Step 6: Permission Table Updated

```sql
INSERT INTO wallet_users (wallet_id, user_id, role, created_at)
VALUES ('wallet-123', 'alice', 'admin', NOW())
```

### Step 7: Create Snapshot (If Needed)

```rust
if event_count % 1000 == 0 {
    save_snapshot(
        wallet_id,
        AggregateType::Permission,
        last_event_id,
        current_permission_state,
    ).await?;
}
```

### Step 8: Return Success

```json
{
  "status": "ok",
  "last_event_id": 123,
  "wallet_users": [
    { "user_id": "owner", "role": "owner" },
    { "user_id": "alice", "role": "admin" }
  ]
}
```

## Multi-Event Sync Flow

What if the sync contains multiple events?

```
POST /sync with:
[
  { event_type: CONTACT_CREATED, aggregate_type: "contact" },
  { event_type: WALLET_USER_ADDED, aggregate_type: "permission" },
  { event_type: TRANSACTION_CREATED, aggregate_type: "transaction" }
]
```

Processing:

```
For each event:
  1. Deserialize into DomainEvent (compiler validates)
  2. Store in events table
  3. Call event.apply_self()
  4. Type-driven handler routes:
     - ContactCreated → apply_contact_event()
     - WalletUserAdded → apply_permission_event()
     - TransactionCreated → apply_transaction_event()
  5. Each handler updates its table
  6. Repeat until all events processed

Result: contacts_projection, wallet_users, transactions_projection all updated
```

## UNDO Flow with Permissions

When an UNDO event is present:

```
Events:
1. WalletUserAdded { user_id: alice, role: admin }  (Event 100)
2. ContactGroupCreated { group_id: group-1 }        (Event 101)
3. UNDO { undone_event_id: 100 }                    (Event 102)
         ↓
Detect UNDO (Event 102 has event_type == "UNDO")
         ↓
Clear permission tables (keep owner):
  DELETE FROM wallet_users WHERE role != 'owner'
  DELETE FROM user_groups WHERE system = false
  DELETE FROM contact_groups WHERE system = false
         ↓
Rebuild from scratch:
  Event 100: Skip (undone)
  Event 101: Apply (ContactGroupCreated → create group)
  Event 102: Skip (it's the UNDO itself)
         ↓
Result:
  - Alice is NOT in wallet_users (was undone)
  - Group 1 IS in contact_groups (not undone)
```

## Permission Event Batching with Phase 2

When using batch processing for large rebuilds:

```
Rebuild 500,000 permission events in batches of 1,000:

Batch 1: Load events 1-1000
  Process all 1000 permission events
  Memory: 10 MB
  Time: 100ms
  
Batch 2: Load events 1001-2000
  Process all 1000 permission events
  Memory: 10 MB
  Time: 100ms
  
... (500 batches) ...

Batch 500: Load events 499001-500000
  Process all 1000 permission events
  Memory: 10 MB ✅
  Time: 100ms

Total: 5 minutes, constant memory
```

## Snapshot Restore Flow

When restoring from permission snapshot:

```
1. Find latest permission snapshot
   SELECT * FROM snapshots
   WHERE wallet_id = ? AND aggregate_type = 'permission'
   LIMIT 1

2. Restore permissions from snapshot:
   TRUNCATE wallet_users, user_groups, contact_groups, ...
   Restore from snapshot JSON
   
3. Load recent events (since last snapshot)
   SELECT * FROM events
   WHERE id > snapshot.last_event_id
   AND aggregate_type = 'permission'
   
4. Apply recent events:
   for event in recent_events:
     event.apply_permission_event()
     
5. Done!
```

## Permission Event Guarantees

### All-or-Nothing
```
Sync contains 5 events:
  3 contact events
  2 permission events
         ↓
All 5 are applied (or none if error)
Partial syncs don't happen
```

### Idempotent
```
Sync the same events twice:
  First time: events applied
  Second time: same result (if using version field)
  No duplicates
```

### Ordered
```
Event 1: WalletUserAdded alice (Event 100)
Event 2: WalletUserRoleChanged alice admin → viewer (Event 101)
         ↓
Always applied in order
Result: Alice is viewer, not admin
```

## Permission Event Error Handling

### Missing User
```
Event: WalletUserAdded { user_id: nonexistent }
         ↓
Check if user exists?
  Option A: Yes - validate before storing event
  Option B: No - allow orphan record (permission to non-existent user)
```

Current implementation: **Option B** (allow orphan records, cleaned up when user is created)

### Duplicate Role Grant
```
Events:
1. WalletUserAdded { user_id: alice, role: admin }
2. WalletUserAdded { user_id: alice, role: admin }
         ↓
Unique constraint on (wallet_id, user_id):
  Event 1: INSERT alice as admin
  Event 2: INSERT fails (duplicate)
         ↓
Better: Use role change event instead
  Event 2 should be: WalletUserRoleChanged alice admin → admin (no-op)
```

### Invalid Role
```
Event: WalletUserAdded { user_id: alice, role: "superuser" }
         ↓
Invalid role (not owner, admin, or viewer)
         ↓
Validation layer rejects at boundary (deserialization)
Never reaches handler
```


Next: [../05-implementation-patterns/01-adding-new-event-type.md](../05-implementation-patterns/01-adding-new-event-type.md) — Learn how to add new event types to the system
