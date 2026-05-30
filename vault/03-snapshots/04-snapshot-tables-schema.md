# Snapshot Tables Schema

**Main question this file answers:** How is snapshot data stored in the database?

---

## The Snapshots Table

Snapshots are stored in a simple table:

```sql
CREATE TABLE snapshots (
  wallet_id UUID NOT NULL,
  aggregate_type TEXT NOT NULL,
  last_event_id BIGINT NOT NULL,
  state JSONB NOT NULL,
  created_at TIMESTAMP NOT NULL,
  
  PRIMARY KEY (wallet_id, aggregate_type),
  FOREIGN KEY (wallet_id) REFERENCES wallets(id)
);
```

**Fields:**
- `wallet_id`: Which wallet this snapshot is for
- `aggregate_type`: "contact", "transaction", or "permission"
- `last_event_id`: Last event ID included in this snapshot
- `state`: JSON data of the entire projection at this point
- `created_at`: When the snapshot was created

## Example Snapshots

### Contact Snapshot

```json
{
  "wallet_id": "wallet-123",
  "aggregate_type": "contact",
  "last_event_id": 50000,
  "state": {
    "contacts": [
      {
        "id": "contact-1",
        "name": "Alice",
        "email": "alice@example.com",
        "phone": "555-1234"
      },
      {
        "id": "contact-2",
        "name": "Bob",
        "email": "bob@example.com",
        "phone": null
      }
    ]
  },
  "created_at": "2024-06-01T10:00:00Z"
}
```

### Transaction Snapshot

```json
{
  "wallet_id": "wallet-123",
  "aggregate_type": "transaction",
  "last_event_id": 50000,
  "state": {
    "transactions": [
      {
        "id": "tx-100",
        "contact_id": "contact-1",
        "amount": 5000,
        "direction": "owed",
        "description": "Dinner"
      },
      {
        "id": "tx-101",
        "contact_id": "contact-2",
        "amount": 3000,
        "direction": "lent",
        "description": "Gas"
      }
    ]
  },
  "created_at": "2024-06-01T10:00:00Z"
}
```

### Permission Snapshot

```json
{
  "wallet_id": "wallet-123",
  "aggregate_type": "permission",
  "last_event_id": 50000,
  "state": {
    "wallet_users": [
      {
        "wallet_id": "wallet-123",
        "user_id": "user-1",
        "role": "owner"
      },
      {
        "wallet_id": "wallet-123",
        "user_id": "user-2",
        "role": "admin"
      }
    ],
    "user_groups": [
      {
        "id": "group-1",
        "name": "Managers",
        "system": false
      }
    ],
    "contact_groups": [...]
  },
  "created_at": "2024-06-01T10:00:00Z"
}
```

## Snapshot Lifecycle

### Creating Snapshots

Snapshots are created **every 1,000 events** (configurable):

```rust
const SNAPSHOT_FREQUENCY = 1000;  // events between snapshots

if events_processed % SNAPSHOT_FREQUENCY == 0 {
    create_snapshot(wallet_id, aggregate_type, last_event_id, current_state).await?;
}
```

### Snapshot Storage Size

**Per wallet:**
```
Contacts projection: ~100 KB (100 contacts × 1 KB each)
Transactions projection: ~200 KB (1000 transactions × 200 bytes each)
Permissions: ~50 KB (users, groups, memberships)
Total per snapshot: ~350 KB
Total per wallet (3 aggregate types): ~1 MB
```

**Scaling:**
```
10 wallets: 10 MB
100 wallets: 100 MB
1000 wallets: 1 GB
```

Acceptable for the memory savings (10x reduction).

### Loading Snapshots

When rebuilding, find the latest snapshot:

```sql
SELECT * FROM snapshots
WHERE wallet_id = $1
AND aggregate_type = $2
ORDER BY created_at DESC
LIMIT 1
```

### Updating Snapshots

After each batch of events:

```sql
INSERT INTO snapshots (wallet_id, aggregate_type, last_event_id, state, created_at)
VALUES ($1, $2, $3, $4, NOW())
ON CONFLICT (wallet_id, aggregate_type) DO UPDATE
SET last_event_id = $3, state = $4, created_at = NOW()
```

## Snapshot vs. Projection Tables

| Aspect | Projection Table | Snapshot |
|---|---|---|
| **Purpose** | Current state (for queries) | Checkpoint (for rebuilds) |
| **Updated** | Every event sync | Every 1,000 events |
| **Used by** | Application queries | Rebuild process |
| **Size** | Small (10-100 MB) | Large (hundreds of MB, growing) |
| **Required** | Yes (always) | Optional (optimization) |
| **Consistency** | Must match events after rebuild | Doesn't need to match (can be rebuilt) |

## Schema for Historical Snapshots (Optional)

You might keep a history of old snapshots for auditing:

```sql
CREATE TABLE snapshot_history (
  id BIGSERIAL PRIMARY KEY,
  wallet_id UUID NOT NULL,
  aggregate_type TEXT NOT NULL,
  last_event_id BIGINT NOT NULL,
  state JSONB NOT NULL,
  created_at TIMESTAMP NOT NULL,
  
  FOREIGN KEY (wallet_id) REFERENCES wallets(id)
);
```

But the main `snapshots` table (with PRIMARY KEY on wallet_id, aggregate_type) is sufficient for normal operation.

## Snapshot Compression (Optional)

For very large snapshots, you could compress the JSON:

```sql
CREATE TABLE snapshots (
  wallet_id UUID NOT NULL,
  aggregate_type TEXT NOT NULL,
  last_event_id BIGINT NOT NULL,
  state BYTEA NOT NULL,  -- Compressed JSON
  compression_type TEXT DEFAULT 'gzip',
  created_at TIMESTAMP NOT NULL,
  
  PRIMARY KEY (wallet_id, aggregate_type)
);
```

Then:
```rust
let compressed_state = compress_gzip(state_json)?;
db.save_snapshot(wallet_id, agg_type, last_event_id, compressed_state).await?;

// On load:
let state_json = decompress_gzip(snapshot.state)?;
```

This reduces snapshot size by ~5-10x but adds CPU overhead. Trade-off depends on your needs.

## Snapshot Cleanup (Optional)

Over time, snapshots accumulate. You might delete old ones:

```sql
DELETE FROM snapshots
WHERE wallet_id = $1
AND created_at < NOW() - INTERVAL '30 days'
AND aggregate_type = $2
```

But keep recent ones (last 1-2 weeks) for fast rebuilds.

## Performance Indexes

For efficient snapshot queries:

```sql
CREATE INDEX idx_snapshots_wallet_agg 
  ON snapshots(wallet_id, aggregate_type, created_at DESC);
```

This allows quick lookup of latest snapshots:

```sql
SELECT * FROM snapshots
WHERE wallet_id = $1 AND aggregate_type = $2
ORDER BY created_at DESC
LIMIT 1  -- Uses index
```

---

Next: [../04-permissions-and-undo/01-undo-events.md](../04-permissions-and-undo/01-undo-events.md) — Understand UNDO events and how they trigger rebuilds
