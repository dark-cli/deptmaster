# EventStore Setup and Integration Guide

## Overview

This guide explains how to set up and use EventStore for reliable, idempotent event sourcing in the Debt Tracker application.

## Architecture

```
Flutter App → Rust Backend (HTTP API) → EventStore → PostgreSQL (Projections)
```

- **Flutter App**: No changes needed - continues using existing HTTP API
- **Rust Backend**: Now writes events to EventStore instead of direct PostgreSQL
- **EventStore**: Stores all events (append-only, versioned, idempotent)
- **PostgreSQL**: Still used for projections (read models) for fast queries

## Setup

### 1. Start EventStore

EventStore is already configured in `docker-compose.yml`. Start it:

```bash
docker-compose up -d eventstore
```

EventStore will be available at:
- **HTTP API**: http://localhost:2113
- **Web UI**: http://localhost:2113 (admin/changeit)

### 2. Verify EventStore is Running

```bash
curl http://localhost:2113/health/live
```

Should return HTTP 200.

### 3. Build and Run Rust Backend

```bash
cd backend/rust-api
cargo build
cargo run
```

The backend will automatically connect to EventStore using the configuration from environment variables.

## Features

### ✅ Idempotency

Every write operation can include an `Idempotency-Key` header:

```http
POST /api/contacts
Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000
Content-Type: application/json

{
  "name": "John Doe",
  "email": "john@example.com"
}
```

If the same key is used again, EventStore returns the existing result (no duplicate creation).

### ✅ Version Tracking

EventStore automatically tracks stream versions. Updates use optimistic locking:

```rust
// Get current version
let version = eventstore.get_stream_version("contact-{id}").await?;

// Update with expected version
eventstore.write_event(
    "contact-{id}",
    "ContactUpdated",
    event_id,
    data,
    version, // Must match current version
).await?;
```

If version doesn't match, EventStore returns a conflict error.

### ✅ Append-Only

Events are never deleted or modified. All history is preserved.

### ✅ Soft Deletes

Deletes are implemented as events:

```rust
eventstore.write_event(
    "contact-{id}",
    "ContactDeleted",
    event_id,
    json!({"deleted_at": "2024-01-01T00:00:00Z"}),
    expected_version,
).await?;
```

The projection marks `is_deleted = true` but the event remains in EventStore.

## Migration Strategy

### Phase 1: Dual-Write (Current)

- Write to both EventStore AND PostgreSQL events table
- Read from PostgreSQL (backward compatible)
- Allows gradual migration

### Phase 2: EventStore Primary

- Write only to EventStore
- Read events from EventStore
- Rebuild projections from EventStore events
- Remove PostgreSQL events table

### Phase 3: Full Migration

- All event operations use EventStore
- PostgreSQL only for projections
- Event replay for sync

## API Changes

### Creating Contacts

**Before:**
```http
POST /api/contacts
Content-Type: application/json
```

**After (with idempotency):**
```http
POST /api/contacts
Idempotency-Key: {uuid}
Content-Type: application/json
```

The `Idempotency-Key` is optional. If not provided, a new UUID is generated.

### Updating Contacts

Updates now use optimistic locking. The backend checks the stream version before updating.

## Flutter Client

**No changes needed!** The Flutter app continues to work exactly as before:

```dart
// Existing code still works
await ApiService.createContact(contact);
```

The Rust backend handles all EventStore integration transparently.

## Testing

### Test Idempotency

```bash
# First request
curl -X POST http://localhost:8000/api/contacts \
  -H "Idempotency-Key: test-key-123" \
  -H "Content-Type: application/json" \
  -d '{"name": "Test Contact"}'

# Same request again (should return same result)
curl -X POST http://localhost:8000/api/contacts \
  -H "Idempotency-Key: test-key-123" \
  -H "Content-Type: application/json" \
  -d '{"name": "Test Contact"}'
```

### View Events in EventStore

1. Open http://localhost:2113
2. Login: admin / changeit
3. Navigate to "Streams"
4. Find stream: `contact-{id}` or `transaction-{id}`
5. View all events for that aggregate

## Troubleshooting

### EventStore Not Starting

```bash
# Check logs
docker-compose logs eventstore

# Check if port is in use
lsof -i :2113
```

### Connection Errors

Check environment variables:
- `EVENTSTORE_URL`: Should be `http://eventstore:2113` (in Docker) or `http://localhost:2113` (local)
- `EVENTSTORE_USERNAME`: Default is `admin`
- `EVENTSTORE_PASSWORD`: Default is `changeit`

### Event Write Failures

Check EventStore logs:
```bash
docker-compose logs -f eventstore
```

Common issues:
- Stream already exists (use correct expected version)
- Authentication failed (check credentials)
- Network issues (check Docker network)

## Next Steps

1. ✅ EventStore Docker setup - DONE
2. ✅ Rust EventStore client - DONE
3. 🔄 Update all handlers to use EventStore - IN PROGRESS
4. ⏳ Add idempotency to all endpoints
5. ⏳ Update sync protocol
6. ⏳ Migrate existing events
7. ⏳ Remove dual-write (PostgreSQL events table)

## Resources

- [EventStore Documentation](https://developers.eventstore.com)
- [EventStore HTTP API](https://developers.eventstore.com/server/v23.10/http-api/)
- [EventStore Docker](https://hub.docker.com/r/eventstore/eventstore)
