# Design Decisions

## Event Sourcing

**Decision**: Store all changes as immutable events in PostgreSQL event log

**Why**: 
- Complete audit trail for compliance and debugging
- Time travel capability (reconstruct state at any point)
- Natural conflict resolution via version tracking
- Idempotency built-in (prevents duplicate operations)
- Resilience (no data loss, events are append-only)

**Trade-off**: Event logs grow over time; mitigated by snapshots for rebuild optimization

---

## Offline-First Architecture

**Decision**: Mobile app works fully offline; syncs bidirectionally with server

**Why**:
- User experience: No network delay, instant feedback
- Resilience: Works in areas with poor connectivity
- Battery efficiency: Periodic syncs rather than constant connections
- User control: Explicit sync when online

**Implementation**: Local Hive database mirrors server state; hash-based sync detects differences

---

## Hash-Based Sync (Not Event Replay)

**Decision**: Compare local/server event hashes before pulling/pushing events

**Why**:
- Efficient: Only syncs differences, not all events
- Minimal bandwidth: Don't re-transfer unchanged events
- Offline handling: Works when offline, no need for full history

**Algorithm**: Client compares hashes; if different, pulls new events since last sync timestamp

---

## Direct Projection Updates (Not Rebuilt)

**Decision**: Update projections directly on events; don't rebuild from events

**Why**:
- Fast reads: All GET requests query precomputed projections
- Fast writes: Direct INSERT/UPDATE is faster than event replay
- Simplicity: No rebuild overhead on every request

**Trade-off**: Projections must stay in sync; snapshots used only for rebuild optimization

---

## Two-Channel Communication (REST + WebSocket)

**Decision**: REST API for data transfer; WebSocket for lightweight notifications

**Why**:
- **REST API**: Reliable, bidirectional, handles large payloads, compatible with any HTTP client
- **WebSocket**: Lightweight notification to trigger sync immediately (no polling)
- **Separation**: Notifications don't carry full data (reduces bandwidth)

**Result**: Client pulls actual events via REST after WebSocket notification arrives

---

## Riverpod for UI State Only

**Decision**: Riverpod manages UI state (settings, toggles); not data operations

**Why**:
- Data consistency: All data operations go through LocalDatabaseServiceV2
- Simplicity: UI state separate from domain logic
- Testability: Data layer independent of UI framework

**Impact**: Screens read from Hive/database services, not Riverpod providers

---

## Idempotency Keys

**Decision**: Store idempotency key with each event in PostgreSQL

**Why**:
- Duplicate prevention: Client can retry requests safely
- Conflict resolution: Re-running same event is safe
- Network resilience: Handle network retries without corruption

**Implementation**: Events table has idempotency_key column; checked before insertion

---

## Version Tracking (Optimistic Locking)

**Decision**: Each event/projection has version column for conflict detection

**Why**:
- Concurrent modification safety: Detect when two clients update same entity
- Conflict resolution: Server can reject conflicting updates
- Data integrity: Prevent lost updates

**Current State**: Conflicts detected but merge strategy not yet implemented

---

## Related Notes
- [[architecture.md]] - How decisions are implemented
- [[conventions.md]] - Naming and code patterns
- [[todos.md]] - Incomplete aspects of decisions
