# Sync Architecture

## Current Design: REST + WebSocket

**Two separate channels**:
- **REST API** (`/api/sync/*`) — Data transfer (pull/push events)
- **WebSocket** (`/ws`) — Notifications only (triggers sync)

### Flow
```
1. Client action → Local event (Hive) → Background sync detects
2. POST /api/sync/events (REST) → Server stores + broadcasts
3. Server sends notification via WebSocket
4. Client GET /api/sync/events (REST) → Pulls events
5. Client updates local state
```

### Why Two Channels?

| Need | REST | WebSocket |
|------|------|-----------|
| Large payloads | ✅ | ❌ |
| Push notifications | ❌ | ✅ |
| Offline support | ✅ | ❌ |
| Simplicity | ✅ | ⚠️ Complex |

**Rationale**: REST for reliability + data, WebSocket for lightweight notifications (avoids polling)

---

## Optional Plan: WebSocket-Only Sync

### Why Consider It?

**Real issues with current approach**:
- ❌ Glitches when app goes offline → online
- ❌ No clean way to enforce sync in Flutter
- ❌ Two channels = larger attack surface
- ❌ Complex state reconciliation logic

**Benefits if consolidated**:
- ✅ Single connection = simpler offline handling
- ✅ Automatic sync on reconnect (no edge cases)
- ✅ WSS encryption (smaller attack surface)
- ✅ Cleaner code (one protocol, one auth)

### How It Would Work

```
Offline: Local buffer queue
        ↓
App reconnects → WebSocket connects
        ↓
Flush buffer → Send all events at once
        ↓
Receive server state → Update local
        ↓
Done: Sync is atomic and clear
```

### Implementation Phases

| Phase | What | Effort |
|-------|------|--------|
| 1 | Add WebSocket sync channel (keep REST) | Medium |
| 2 | Migrate mobile app to use WSS-only | High |
| 3 | Deprecate + remove REST sync endpoints | Low |

### Concerns to Solve

1. **Message Framing** — Need protocol for streaming events
2. **Offline Buffer** — Max size? Overflow handling?
3. **Reconnection** — Backoff strategy, user notification
4. **Server Load** — Persistent connections + load balancing
5. **Backward Compatibility** — Gradual migration needed

### When to Do This

**Good timing**:
- Offline→online issues reported by users
- Security audit flags multiple connection types
- Team bandwidth available

**Not urgent**:
- Current system working well
- Other priorities first

---

## Current State

| Feature | Status |
|---------|--------|
| REST sync endpoints | ✅ Working |
| WebSocket notifications | ✅ Working |
| WebSocket data transfer | ❌ Not implemented |
| Consolidation plan | 📋 Optional (this doc) |
| Code TODOs about this | ❌ None |

---

## Files to Know

**Backend**:
- REST: `backend/rust-api/src/handlers/sync.rs`
- WebSocket: `backend/rust-api/src/websocket.rs`

**Mobile**:
- Sync service: `mobile/lib/services/sync_service_v2.dart`
- Config: `mobile/lib/services/backend_config_service.dart`

---

## Related
- [[architecture.md]] — Full system overview
- [[decisions.md]] — Design rationale
- [[client-backend-security.md]] — Connection security
