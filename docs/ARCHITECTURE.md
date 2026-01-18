# Debt Tracker Architecture

## System Overview

Debt Tracker is a cross-platform debt management application built with:
- **Backend**: Rust (Axum web framework)
- **Frontend**: Flutter (Dart)
- **Database**: PostgreSQL with event sourcing
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
│  │  │ Event Store  │  │ Projections  │                   │  │
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

### Event Store
- **Write-only**: All changes stored as immutable events
- **Append-only**: Events never deleted or modified
- **Complete audit trail**: Full history of all changes

### Projections
- **Materialized views**: Derived from event store
- **Optimized for reads**: Fast querying of current state
- **Updated on events**: Automatically maintained

### Event Types
- `CONTACT_CREATED` - New contact added
- `TRANSACTION_CREATED` - New transaction added
- Future: `CONTACT_UPDATED`, `TRANSACTION_UPDATED`, `CONTACT_DELETED`, etc.

## Real-Time Updates

### WebSocket Flow
1. Client connects to `/ws` endpoint
2. Server subscribes client to broadcast channel
3. On data change, server broadcasts to all clients
4. Clients receive update and refresh data
5. UI updates automatically

### Broadcast Channel
- Tokio broadcast channel (100 message buffer)
- All connected clients receive updates
- Non-blocking, efficient distribution

## Offline-First Architecture

### Mobile/Desktop
- **Hive**: Local NoSQL database
- **Primary**: API for online data
- **Fallback**: Hive for offline data
- **Sync**: Automatic when connection restored

### Web
- **State**: In-memory state management
- **Primary**: API for data
- **No offline**: Web requires connection (by design)

## Data Flow

### Creating Contact
```
1. User fills form → Flutter UI
2. POST /api/contacts → Rust backend
3. Create CONTACT_CREATED event → Event store
4. Update contacts_projection → Projection
5. Broadcast via WebSocket → All clients
6. Clients fetch latest data → API
7. Update local state/Hive → Client storage
8. UI refreshes → Automatic update
```

### Reading Contacts
```
1. GET /api/contacts → Rust backend
2. Query contacts_projection → Fast read
3. Return JSON → Client
4. Update state/Hive → Client storage
5. Display in UI → Flutter widgets
```

## Technology Stack

### Backend
- **Rust**: Systems programming language
- **Axum**: Modern web framework
- **Tokio**: Async runtime
- **SQLx**: Type-safe SQL
- **PostgreSQL**: Relational database

### Frontend
- **Flutter**: Cross-platform UI framework
- **Dart**: Programming language
- **Riverpod**: State management
- **Hive**: Local storage
- **WebSocket**: Real-time communication

## Security (Future)

- JWT authentication
- Biometric authentication (mobile)
- Encrypted backups
- HTTPS/WSS for production

## Scalability

### Current
- Single server instance
- In-memory broadcast channel
- Direct database connections

### Future
- Redis for distributed broadcast
- Connection pooling
- Horizontal scaling support
