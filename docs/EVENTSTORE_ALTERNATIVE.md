# EventStore Alternative Analysis

## What is EventStore?

EventStore is an open-source, purpose-built event store database designed for event sourcing. It's written in .NET but has excellent cross-platform support.

## Features That Match Your Needs

### ✅ Idempotency
- Built-in idempotency key support
- Automatic duplicate detection
- Returns existing result for duplicate requests

### ✅ Append-Only
- Events are immutable
- Never deleted or modified
- Complete audit trail

### ✅ Soft Deletes
- Events marked as deleted (not removed)
- Can restore deleted aggregates
- Full history preserved

### ✅ Versioned Updates
- Optimistic concurrency control
- Version tracking per stream
- Conflict detection built-in

### ✅ Sync Support
- Multi-device sync capabilities
- Event replay for clients
- Subscription API for real-time updates

## Architecture with EventStore

```
┌─────────────────────────────────────────┐
│         Flutter Mobile App              │
│  ┌──────────────────────────────────┐  │
│  │  WatermelonDB (Local)            │  │
│  │  - Fast local queries            │  │
│  │  - Sync adapter                  │  │
│  └──────────────┬───────────────────┘  │
└─────────────────┼──────────────────────┘
                  │
┌─────────────────▼──────────────────────┐
│         Rust Backend (Axum)              │
│  ┌──────────────────────────────────┐   │
│  │  EventStore Client              │   │
│  │  - Write events                 │   │
│  │  - Read projections             │   │
│  └──────────────┬──────────────────┘   │
└─────────────────┼───────────────────────┘
                  │
┌─────────────────▼──────────────────────┐
│         EventStore Database             │
│  ┌──────────────────────────────────┐   │
│  │  Event Streams                   │   │
│  │  - contact-{id}                 │   │
│  │  - transaction-{id}             │   │
│  │  - Append-only                  │   │
│  │  - Versioned                     │   │
│  └──────────────────────────────────┘   │
└──────────────────────────────────────────┘
                  │
┌─────────────────▼──────────────────────┐
│         PostgreSQL (Optional)          │
│  ┌──────────────────────────────────┐   │
│  │  Read Models / Projections       │   │
│  │  - Fast queries                  │   │
│  │  - Materialized views            │   │
│  └──────────────────────────────────┘   │
└──────────────────────────────────────────┘
```

## Pros

1. **Purpose-built** - Designed exactly for your use case
2. **Battle-tested** - Used in production by many companies
3. **Idempotency** - Built-in, no custom code needed
4. **Versioning** - Optimistic concurrency out of the box
5. **Performance** - Optimized for event streaming
6. **Sync** - Built-in multi-device sync support
7. **Open source** - Free, self-hostable
8. **Documentation** - Excellent docs and examples

## Cons

1. **Another service** - Need to run EventStore server
2. **Learning curve** - New concepts (streams, projections)
3. **Migration** - Need to migrate existing data
4. **Rust client** - May need to use HTTP API or find Rust client
5. **Deployment** - Another container/service to manage

## Rust Integration

### Option 1: HTTP API
EventStore has a RESTful HTTP API:
```rust
// Write event
POST /streams/contact-{id}
Headers: 
  ES-EventType: ContactCreated
  ES-EventId: {uuid}
  ES-ExpectedVersion: {version}
Body: { event data }
```

### Option 2: TCP Protocol
EventStore has a TCP protocol (more efficient):
- Need Rust client library
- Or use existing bindings

### Option 3: gRPC
EventStore 20+ has gRPC support:
- Better for Rust integration
- Type-safe
- Efficient

## Migration Path

1. **Phase 1**: Set up EventStore alongside PostgreSQL
2. **Phase 2**: Write new events to both (dual-write)
3. **Phase 3**: Migrate existing events to EventStore
4. **Phase 4**: Switch reads to EventStore
5. **Phase 5**: Remove PostgreSQL event store (keep for projections)

## Recommendation

**If your current solution keeps failing:**
- EventStore is a solid choice
- It solves all your requirements
- Well-documented and proven
- Worth the migration effort for reliability

**If you can fix current issues:**
- Improve PostgreSQL event sourcing first
- Add idempotency and versioning
- Only migrate if still having problems

## Resources

- **Website**: https://eventstore.com
- **GitHub**: https://github.com/EventStore/EventStore
- **Docs**: https://developers.eventstore.com
- **Docker**: `docker run -d -p 2113:2113 -p 1113:1113 eventstore/eventstore`
