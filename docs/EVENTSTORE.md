# EventStore Integration Guide

## Overview

EventStore is used for reliable, idempotent event sourcing in the Debt Tracker application. It provides append-only event storage with built-in versioning and idempotency support.

## Architecture

```
Flutter App → Rust Backend (HTTP API) → EventStore → PostgreSQL (Projections)
```

- **Flutter App**: No changes needed - continues using existing HTTP API
- **Rust Backend**: Writes events to EventStore
- **EventStore**: Stores all events (append-only, versioned, idempotent)
- **PostgreSQL**: Used for projections (read models) for fast queries

## Setup

### 1. Start EventStore

EventStore is configured in `docker-compose.yml`. Start it:

```bash
./manage.sh start-services eventstore
```

Or manually:
```bash
cd backend
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
./manage.sh build
./manage.sh start-server
```

The backend will automatically connect to EventStore using configuration from environment variables.

## Features

### Idempotency

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

### Version Tracking

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

### Append-Only

Events are never deleted or modified. All history is preserved.

### Soft Deletes

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

### Phase 1: Dual-Write (Completed)
- Write to both EventStore AND PostgreSQL events table
- Read from PostgreSQL (backward compatible)
- Allows gradual migration

### Phase 2: EventStore Primary (Current)
- Write only to EventStore
- Read events from EventStore
- Rebuild projections from EventStore events
- PostgreSQL only for projections

## API Usage

### Creating Contacts

**With idempotency:**
```http
POST /api/contacts
Idempotency-Key: {uuid}
Content-Type: application/json
```

The `Idempotency-Key` is optional. If not provided, a new UUID is generated.

### Updating Contacts

Updates use optimistic locking. The backend checks the stream version before updating.

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

### Reset EventStore

```bash
./manage.sh reset-eventstore
```

This will:
- Stop EventStore container
- Remove EventStore data volume
- Start fresh EventStore instance

## Configuration

Environment variables:
- `EVENTSTORE_URL` - EventStore HTTP API URL (default: http://localhost:2113)
- `EVENTSTORE_USERNAME` - EventStore username (default: admin)
- `EVENTSTORE_PASSWORD` - EventStore password (default: changeit)

## Related Documentation

- [Architecture](./ARCHITECTURE.md) - Overall system architecture
- [Event Audit Trail](./EVENT_AUDIT_TRAIL.md) - Event sourcing patterns
- [Real-Time Sync](./REALTIME.md) - WebSocket integration
