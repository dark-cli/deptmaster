# Consistency Verification

**Main question this file answers:** How do we ensure snapshots are always correct?

---

## The Challenge

Snapshots are precomputed state. If they become stale or corrupt, rebuilds use wrong data.

How do we prevent this?

## Verification Strategy

### 1. Snapshot Versioning

Include metadata in snapshots:

```json
{
  "wallet_id": "wallet-123",
  "aggregate_type": "contact",
  "last_event_id": 50000,
  "snapshot_version": 1,
  "created_at": "2024-06-01T10:00:00Z",
  "state": { ... }
}
```

Increment version when snapshot format changes. New version can handle both old and new formats.

### 2. Checksum Verification

Include checksum of projected state:

```json
{
  ...
  "state_checksum": "abc123def456",
  "state": { "contacts": [...] }
}
```

On restore, verify checksum matches:

```rust
let checksum = compute_checksum(&snapshot.state);
assert_eq!(checksum, snapshot.state_checksum)?;
```

### 3. Rebuild Verification

After rebuild, verify projections are consistent:

```rust
// After rebuild:
let events_count = get_total_events(wallet_id).await?;
let snapshot = get_latest_snapshot(wallet_id, AggregateType::Contact).await?;

if snapshot.last_event_id != events_count {
    // Snapshot is incomplete (events were added after snapshot)
    // Load new events since snapshot and apply
}
```

### 4. Test Suite

Verify consistency across operations:

```rust
#[test]
async fn test_snapshot_consistency_after_sync() {
    // 1. Create snapshot after 1000 events
    let snapshot1 = get_snapshot(wallet_id, "contact").await?;
    
    // 2. Add 100 more events
    sync_events(events_100).await?;
    
    // 3. Verify snapshot is still correct
    let projected_state = query_contacts(wallet_id).await?;
    let snapshot_state = snapshot1.state.contacts;
    
    assert_eq!(
        // Contacts from snapshot + new events = current state
        apply_events_to(snapshot_state, events_100),
        projected_state
    );
}

#[test]
async fn test_snapshot_correct_after_undo() {
    // Create snapshot
    let snapshot = get_snapshot(wallet_id, "contact").await?;
    
    // UNDO an old event
    sync_events(vec![undo_event]).await?;
    
    // Verify rebuild is correct
    let rebuilt_state = query_contacts(wallet_id).await?;
    
    // Should match snapshot with undone event removed
    assert_eq!(rebuilt_state, snapshot_minus_undone_event);
}
```

## Monitoring

Track snapshot health:

```
Metrics to monitor:
- Snapshot creation frequency (should be every 1000 events)
- Snapshot restore time (should be < 1 second)
- Rebuild time (should scale with batch count, not total events)
- Memory usage (should stay < 50 MB)
```

## Recovery

If snapshot becomes corrupt:

```
1. Detect corruption (checksum fails or rebuild is wrong)
2. Delete corrupt snapshot
3. Next rebuild starts from previous valid snapshot
4. Create new snapshot when rebuild completes
```

```rust
if snapshot.state_checksum != computed_checksum {
    // Corrupt snapshot
    delete_snapshot(wallet_id, aggregate_type).await?;
    
    // Next rebuild will use previous snapshot or start from beginning
    rebuild_projections(wallet_id, aggregate_type).await?;
}
```

---

Status: Implemented (tests passing, consistent behavior verified).

Next: [03-performance-benchmarks.md](03-performance-benchmarks.md) — Measure performance trade-offs
