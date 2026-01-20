# EventStore Quick Start

## What's Been Done

✅ **EventStore is now integrated!** Your backend now uses EventStore for reliable, idempotent event sourcing.

## Quick Test

### 1. Start Everything

```bash
docker-compose up -d
```

This starts:
- PostgreSQL (for projections)
- EventStore (for events)
- Redis (for caching)
- Your Rust API

### 2. Test Idempotency

```bash
# Create a contact with idempotency key
curl -X POST http://localhost:8000/api/contacts \
  -H "Idempotency-Key: my-unique-key-123" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "John Doe",
    "email": "john@example.com"
  }'

# Run the EXACT same request again
curl -X POST http://localhost:8000/api/contacts \
  -H "Idempotency-Key: my-unique-key-123" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "John Doe",
    "email": "john@example.com"
  }'
```

The second request should return the same contact (no duplicate created).

### 3. View Events

1. Open http://localhost:2113
2. Login: `admin` / `changeit`
3. Click "Streams" in the sidebar
4. Find stream: `contact-{uuid}`
5. See all events for that contact

## What Changed

### Backend (Rust)
- ✅ EventStore client service created
- ✅ `create_contact` now uses EventStore
- ✅ Idempotency key support added
- ✅ Dual-write to PostgreSQL (for backward compatibility)

### Flutter App
- ✅ **No changes needed!** Everything works as before.

## Architecture

```
┌─────────────┐
│ Flutter App │  (No changes)
└──────┬──────┘
       │ HTTP API
┌──────▼──────────────────┐
│ Rust Backend            │
│  ┌────────────────────┐  │
│  │ EventStore Client │  │  ← New!
│  └────────┬───────────┘  │
└───────────┼──────────────┘
            │
┌───────────▼──────────────┐
│ EventStore               │  ← New!
│ - Append-only events     │
│ - Idempotency           │
│ - Version tracking      │
└──────────────────────────┘
            │
┌───────────▼──────────────┐
│ PostgreSQL               │
│ - Projections (read)     │
└──────────────────────────┘
```

## Benefits

1. **Idempotency** - Duplicate requests are safe
2. **Version Tracking** - Optimistic locking prevents conflicts
3. **Append-Only** - Complete audit trail
4. **Reliability** - Battle-tested event store
5. **No Data Loss** - Events are never deleted

## Next Steps

1. **Test it** - Try creating contacts with the same idempotency key
2. **View events** - Check EventStore UI to see your events
3. **Continue development** - Other handlers will be updated next

## Troubleshooting

### EventStore not starting?

```bash
docker-compose logs eventstore
```

### Can't connect?

Check environment variables in `docker-compose.yml`:
- `EVENTSTORE_URL`: Should be `http://eventstore:2113`
- `EVENTSTORE_USERNAME`: `admin`
- `EVENTSTORE_PASSWORD`: `changeit`

### Events not showing?

1. Check Rust backend logs: `docker-compose logs api`
2. Check EventStore logs: `docker-compose logs eventstore`
3. Verify EventStore is healthy: `curl http://localhost:2113/health/live`

## Documentation

- [Full Setup Guide](EVENTSTORE_SETUP.md)
- [Implementation Status](EVENTSTORE_IMPLEMENTATION_STATUS.md)
- [EventStore Docs](https://developers.eventstore.com)
