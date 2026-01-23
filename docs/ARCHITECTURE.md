# Debt Tracker Architecture

## System Overview

Debt Tracker is a cross-platform debt management application built with:
- **Backend**: Rust (Axum web framework)
- **Frontend**: Flutter (Dart)
- **Database**: PostgreSQL with event sourcing
- **Event Store**: EventStore DB
- **Real-time**: WebSocket connections

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                        Clients                                │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │   Web     │  │  Mobile  │  │ Desktop  │  │  Mobile  │   │
│  │ (Flutter) │  │(Flutter) │  │(Flutter) │  │(Flutter) │   │
│  └─────┬─────┘  └─────┬─────┘  └─────┬─────┘  └─────┬─────┘   │
│        │              │              │              │         │
│        └──────────────┴──────────────┴──────────────┘         │
│                    │                                            │
│            ┌───────▼────────┐                                   │
│            │  WebSocket    │                                   │
│            │  Connection   │                                   │
│            └───────┬───────┘                                   │
└────────────────────┼──────────────────────────────────────────┘
                     │
┌────────────────────▼──────────────────────────────────────────┐
│                    Backend (Rust)                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │              Axum Web Server                           │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │  │
│  │  │ HTTP Routes  │  │ WebSocket    │  │  Broadcast   │ │  │
│  │  │              │  │  Handler     │  │  Channel     │ │  │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘ │  │
│  │         │                 │                 │         │  │
│  │  ┌──────▼─────────────────▼─────────────────▼──────┐ │  │
│  │  │           Request Handlers                        │ │  │
│  │  │  - create_contact                                 │ │  │
│  │  │  - create_transaction                             │ │  │
│  │  │  - get_contacts                                   │ │  │
│  │  │  - get_transactions                                │ │  │
│  │  └──────┬───────────────────────────────────────────┘ │  │
│  └─────────┼──────────────────────────────────────────────┘  │
│            │                                                   │
│  ┌─────────▼──────────────────────────────────────────────┐  │
│  │         Event Sourcing Layer                          │  │
│  │  ┌──────────────┐  ┌──────────────┐                   │  │
│  │  │ EventStore  │  │ Projections  │                   │  │
│  │  │ (Write-only) │  │ (Read views) │                   │  │
│  │  └──────┬───────┘  └──────┬───────┘                   │  │
│  └─────────┼─────────────────┼───────────────────────────┘  │
└────────────┼───────────────────┼───────────────────────────────┘
             │                   │
┌────────────▼───────────────────▼───────────────────────────────┐
│                    PostgreSQL Database                          │
│  ┌──────────────────┐  ┌──────────────────┐                    │
│  │   events_table   │  │ contacts_projection│                  │
│  │   (Immutable)    │  │ transactions_projection│              │
│  └──────────────────┘  └──────────────────┘                    │
└────────────────────────────────────────────────────────────────┘
```

## Event Sourcing

### Event Store (EventStore DB)

EventStore provides reliable, idempotent event sourcing:

- **Append-only**: Events are never deleted or modified
- **Idempotency**: Built-in idempotency key support prevents duplicates
- **Version tracking**: Optimistic locking with stream versions
- **Complete audit trail**: Full history of all changes

#### Setup

```bash
./manage.sh start-services eventstore
```

EventStore is available at:
- **HTTP API**: http://localhost:2113
- **Web UI**: http://localhost:2113 (admin/changeit)

#### Features

**Idempotency**: Every write operation can include an `Idempotency-Key` header:
```http
POST /api/contacts
Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000
```

**Version Tracking**: Updates use optimistic locking:
```rust
let version = eventstore.get_stream_version("contact-{id}").await?;
eventstore.write_event("contact-{id}", "ContactUpdated", event_id, data, version).await?;
```

### Projections

- **Materialized views**: Derived from event store
- **Optimized for reads**: Fast querying of current state
- **Updated on events**: Automatically maintained
- **PostgreSQL**: Used for projections (read models)

### Event Types

- `CONTACT_CREATED` - New contact added
- `CONTACT_UPDATED` - Contact modified
- `CONTACT_DELETED` - Contact deleted (soft delete)
- `TRANSACTION_CREATED` - New transaction added
- `TRANSACTION_UPDATED` - Transaction modified
- `TRANSACTION_DELETED` - Transaction deleted (soft delete)

## Real-Time Updates

### WebSocket Flow

1. Client connects to `/ws` endpoint
2. Server subscribes client to broadcast channel
3. On data change, server broadcasts to all clients
4. Clients receive update and refresh data
5. UI updates automatically

### Implementation

**Backend (Rust)**:
- File: `backend/rust-api/src/websocket.rs`
- Endpoint: `ws://localhost:8000/ws`
- Technology: Axum WebSocket with Tokio broadcast channels
- Broadcast channel: 100 message buffer

**Frontend (Flutter)**:
- File: `mobile/lib/services/realtime_service.dart`
- Auto-connects on app start
- Auto-reconnects if connection drops (1-second delay)
- Platform-aware URL selection

### Broadcast Function

```rust
pub fn broadcast_change(channel: &BroadcastChannel, event_type: &str, data: &str) {
    let message = format!(r#"{{"type":"{}","data":{}}}"#, event_type, data);
    let _ = channel.send(message);
}
```

## Offline-First Architecture

### Mobile/Desktop
- **Hive**: Local NoSQL database
- **Primary**: API for online data
- **Fallback**: Hive for offline access
- **Sync**: Automatic sync when online

### Web
- **API**: Direct API calls
- **No offline storage**: Web requires internet connection

## Data Flow

### Creating a Contact

1. Client sends `POST /api/contacts`
2. Backend validates request
3. Backend writes `CONTACT_CREATED` event to EventStore
4. Backend updates `contacts_projection` in PostgreSQL
5. Backend broadcasts change via WebSocket
6. All connected clients receive update
7. Clients refresh data and update UI

### Reading Data

1. Client requests `GET /api/contacts`
2. Backend queries `contacts_projection` (fast read)
3. Backend returns current state
4. Client displays data

## Security

- **Authentication**: JWT tokens (planned)
- **Authorization**: User-scoped data access
- **Event Store**: Idempotency prevents duplicate operations
- **Version Tracking**: Prevents concurrent modification conflicts

## Related Documentation

- [API Reference](./API.md) - API endpoints
- [Development Guide](./DEVELOPMENT.md) - Development setup
- [Deployment Guide](./DEPLOYMENT.md) - Production deployment
