# Debt Tracker Architecture

## Overview

Debt Tracker is a debt management application with:
- **Local-first architecture**: Works offline, syncs when online
- **Event sourcing**: Complete audit trail with immutable events
- **Real-time sync**: Instant updates via WebSocket

**Tech Stack:**
- **Backend**: Rust (Axum web framework)
- **Frontend**: Flutter (Dart)
- **Database**: PostgreSQL (projections) + EventStore DB (events)
- **Real-time**: WebSocket with broadcast channels

---

## Application Flow

### User Creates a Contact

```mermaid
flowchart TD
    A[User fills form and taps Save] --> B[Flutter App]
    B --> B1[LocalDatabaseServiceV2.createContact]
    B --> B2[Creates event: CONTACT_CREATED]
    B --> B3[Stores event in local Hive]
    B --> B4[Rebuilds state from all events]
    B --> B5[Updates local projections]
    B --> B6[UI updates immediately]
    
    B6 --> C[Background Sync]
    C --> C1[Detects unsynced event]
    C --> C2[POST /api/sync/events]
    C --> C3[Marks event as synced]
    
    C3 --> D[Backend Server]
    D --> D1[Receives event via sync endpoint]
    D --> D2[Validates event]
    D --> D3[Writes event to EventStore DB]
    D --> D4[Updates PostgreSQL projection]
    D --> D5[Broadcasts change via WebSocket]
    D --> D6[Returns success]
    
    D5 --> E[WebSocket Broadcast]
    E --> E1[All clients receive notification]
    E --> E2[Clients trigger sync]
    E --> E3[Clients pull new events]
    E --> E4[Clients rebuild local state]
    E --> E5[All UIs update automatically]
```

### User Views Contacts

```mermaid
flowchart TD
    A[User opens contacts screen] --> B[Flutter App]
    B --> B1[Reads from local Hive box<br/>contacts projection]
    B --> B2[No network call needed<br/>instant]
    B --> B3[Displays contacts immediately]
    
    B3 --> C{Online?}
    C -->|Yes| D[Background Sync]
    C -->|No| E[Display local data]
    
    D --> D1[Compare local hash vs<br/>server hash]
    D1 --> D2{Hash different?}
    D2 -->|Yes| D3[Pull new events]
    D2 -->|No| F[Already in sync]
    D3 --> D4[Rebuild state from<br/>all events]
    D4 --> D5[UI updates if<br/>changes detected]
```

### Real-Time Updates

```mermaid
flowchart TD
    A[User A creates transaction] --> B[Server processes change]
    B --> C[Server broadcasts via WebSocket]
    C --> D[User B's app receives<br/>WebSocket message]
    D --> D1[Triggers immediate sync]
    D --> D2[Pulls new events from server]
    D --> D3[Rebuilds local state]
    D --> D4[UI updates automatically<br/>no refresh needed]
```

---

## System Architecture

### High-Level Architecture

```mermaid
graph TB
    subgraph FlutterClient["Flutter Client"]
        FlutterApp[Flutter App]
        RESTAPI[REST API<br/>Bidirectional]
        WebSocket[WebSocket<br/>Notifications]
    end
    
    subgraph AdminPanel["Admin Panel"]
        Browser[Web Browser]
    end
    
    subgraph Backend["Backend Server (Rust)"]
        subgraph Part1["Part 1: API Handling"]
            RESTRoutes[REST API Routes<br/>/api/sync/*<br/>/api/contacts<br/>/api/transactions]
            WSHandler[WebSocket Handler<br/>/ws]
            Broadcast[Broadcast Channel<br/>Tokio 100 buffer]
        end
        
        subgraph Part2["Part 2: Admin Page Serving"]
            AdminRoutes[Admin Routes<br/>/admin<br/>/api/admin/*]
        end
        
        EventSourcing[Event Sourcing Layer]
    end
    
    subgraph Storage["Data Storage"]
        EventStoreDB[EventStore DB<br/>Immutable Events]
        PostgreSQL[PostgreSQL<br/>events table<br/>projections]
    end
    
    FlutterApp --> RESTAPI
    FlutterApp --> WebSocket
    RESTAPI -->|"POST/GET"| RESTRoutes
    WebSocket -->|"WS /ws"| WSHandler
    WSHandler --> Broadcast
    
    Browser -->|"GET /admin"| AdminRoutes
    Browser -->|"GET /api/admin/*"| AdminRoutes
    
    RESTRoutes --> EventSourcing
    WSHandler --> EventSourcing
    AdminRoutes --> EventSourcing
    
    EventSourcing --> EventStoreDB
    EventSourcing --> PostgreSQL
```

### Client Architecture (Flutter)

```mermaid
graph TB
    subgraph UI["UI Layer"]
        Screens[Screens<br/>HomeScreen<br/>DashboardScreen<br/>ContactsScreen<br/>TransactionsScreen<br/>AddContactScreen<br/>AddTransactionScreen<br/>LoginScreen<br/>SettingsScreen<br/>EventsLogScreen<br/>BackendSetupScreen]
    end
    
    subgraph Services["Service Layer"]
        LocalDB[LocalDatabaseServiceV2<br/>getContacts<br/>createContact]
        EventStore[EventStoreService<br/>appendEvent<br/>getAllEvents<br/>getEventHash]
        StateBuilder[StateBuilder<br/>buildState<br/>Pure functions]
        SyncService[SyncServiceV2<br/>sync<br/>hash-based comparison]
        Realtime[RealtimeService<br/>WebSocket connection]
    end
    
    subgraph Storage["Local Storage (Hive)"]
        EventsBox[Events Box<br/>Immutable]
        Projections[Projections<br/>contacts<br/>transactions]
    end
    
    Screens --> LocalDB
    LocalDB --> EventStore
    EventStore --> StateBuilder
    StateBuilder --> SyncService
    SyncService --> Realtime
    
    EventStore --> EventsBox
    StateBuilder --> Projections
```

---

## Event Sourcing

### Core Concept

All changes are stored as **immutable events**. Current state is derived by replaying events.

**Benefits:**
- Complete audit trail (who did what, when, why)
- Time travel (reconstruct state at any point in time)
- No data loss (events are append-only)
- Conflict resolution (version tracking)

### Event Flow

```mermaid
flowchart TD
    A[User Action] --> B[Create Event]
    B --> C[Store Event<br/>EventStore DB / Local Hive]
    C --> D[Rebuild State<br/>from all events]
    D --> E[Update Projections<br/>PostgreSQL / Local Hive]
    E --> F[Broadcast Change<br/>WebSocket]
    F --> G[All Clients Sync & Update]
```

### Event Types

- `CONTACT_CREATED` - New contact added
- `CONTACT_UPDATED` - Contact modified
- `CONTACT_DELETED` - Contact deleted (soft delete)
- `TRANSACTION_CREATED` - New transaction added
- `TRANSACTION_UPDATED` - Transaction modified
- `TRANSACTION_DELETED` - Transaction deleted (soft delete)

### Event Structure

```json
{
  "id": "uuid",
  "aggregate_type": "contact" | "transaction",
  "aggregate_id": "uuid",
  "event_type": "CREATED" | "UPDATED" | "DELETED",
  "event_data": {
    "name": "John Doe",
    "phone": "+1234567890",
    "comment": "Added from mobile app"
  },
  "timestamp": "2026-01-18T00:00:00Z",
  "version": 1
}
```

---

## Backend-Frontend Communication

The Flutter app communicates with the backend through two distinct channels:

### REST API (Bidirectional Data Transfer)

**Purpose:** Send and receive events, sync data, make requests

**Client → Server (Send Data):**
- `POST /api/sync/events` - Send local events to server
- `POST /api/contacts` - Create contact (direct API, used by web)
- `POST /api/transactions` - Create transaction (direct API, used by web)
- `PUT /api/contacts/:id` - Update contact
- `DELETE /api/contacts/:id` - Delete contact

**Client ← Server (Receive Data):**
- `GET /api/sync/hash` - Get server event hash and count (for comparison)
- `GET /api/sync/events?since=<timestamp>` - Pull new events from server
- `GET /api/contacts` - Get contacts (used by web)
- `GET /api/transactions` - Get transactions (used by web)

**Flow:**

```mermaid
flowchart TD
    A[Client needs to sync] --> B[GET /api/sync/hash<br/>compare hashes]
    B --> C{Hash different?}
    C -->|Yes| D[GET /api/sync/events<br/>pull new events]
    C -->|Yes| E[POST /api/sync/events<br/>push local events]
    C -->|No| F[Already in sync]
    D --> G[Client rebuilds state<br/>from all events]
    E --> G
```

### WebSocket (One-way Notification)

**Purpose:** Receive lightweight notifications when server has changes

**Server → Client (Notifications Only):**
- Server broadcasts notification: `{"type": "contact_created", "data": {...}}`
- Client receives notification and triggers sync via REST API
- Client then pulls actual events using `GET /api/sync/events`

**Flow:**

```mermaid
flowchart TD
    A[Server processes change] --> B[Write event to EventStore DB]
    B --> C[Update PostgreSQL projection]
    C --> D[Broadcast notification<br/>via WebSocket]
    D --> E[All connected clients<br/>receive notification]
    E --> F[Clients trigger<br/>SyncServiceV2.manualSync]
    F --> G[Clients use REST API<br/>GET /api/sync/events]
    G --> H[Clients rebuild state<br/>and update UI]
```

**Why Two Channels?**
- **REST API**: Reliable bidirectional data transfer, handles large payloads, works with any HTTP client
- **WebSocket**: Lightweight notification to trigger sync immediately (no polling needed), reduces server load

---

## Data Synchronization

### Sync Strategy

**Hash-based comparison:**
1. Compare local event hash vs server event hash
2. If hashes match → already in sync
3. If different:
   - Pull new events from server (since last sync timestamp)
   - Push unsynced local events to server
   - Rebuild state from all events

**Benefits:**
- Efficient (only syncs differences)
- Handles offline gracefully
- Prevents duplicate events (idempotency)

### Sync Endpoints

- `GET /api/sync/hash` - Get server event hash and count
- `GET /api/sync/events?since=<timestamp>` - Get events since timestamp
- `POST /api/sync/events` - Send local events to server

### Conflict Resolution

- Server uses **version tracking** (optimistic locking)
- Conflicts detected by version mismatch
- Server rejects conflicting events
- Client handles conflicts (currently logged, merge strategy TODO)

---

## Real-Time Updates

### WebSocket Flow

```
1. Client connects to ws://localhost:8000/ws
   ↓
2. Server subscribes client to broadcast channel
   ↓
3. On data change:
   ├─ Server writes event to EventStore DB
   ├─ Server writes event to PostgreSQL events table
   ├─ Server updates PostgreSQL projection
   ├─ Server broadcasts notification: {"type": "contact_created", "data": {...}}
   └─ All connected clients receive notification
   ↓
4. Clients receive notification:
   ├─ RealtimeService._handleRealtimeUpdate() called
   ├─ Triggers SyncServiceV2.manualSync()
   ├─ SyncServiceV2 uses REST API (GET /api/sync/events) to pull events
   ├─ StateBuilder rebuilds state from events
   └─ UI updates automatically
```

**Note:** WebSocket only sends notifications. The actual event data is transferred via REST API.

### Implementation

**Backend (Rust):**
- File: `backend/rust-api/src/websocket.rs`
- Technology: Axum WebSocket with Tokio broadcast channels
- Broadcast channel: 100 message buffer

**Frontend (Flutter):**
- File: `mobile/lib/services/realtime_service.dart`
- Auto-connects on app start
- Auto-reconnects if connection drops (1-second delay)
- Triggers sync immediately on any WebSocket message

---

## Offline-First Architecture

### Mobile/Desktop (Local-First)

**Local-first:**
- All reads/writes happen on local Hive database first
- Instant UI updates (no network delay)
- Background sync when online
- Works fully offline

**Components:**
- **Hive**: Local NoSQL database
- **EventStoreService**: Stores events locally
- **StateBuilder**: Rebuilds state from events
- **SyncServiceV2**: Handles bidirectional sync

### Web (API-First)

**API-first:**
- Direct API calls (no local storage)
- Requires internet connection
- Real-time updates via WebSocket
- Sync happens via API endpoints

---

## Backend Architecture

The backend server consists of two distinct parts:

### Part 1: API Handling (REST API + WebSocket)

**Purpose:** Handle requests from Flutter clients (mobile/web/desktop)

**REST API Endpoints:**
- **Sync:**
  - `GET /api/sync/hash` - Get server event hash and count
  - `GET /api/sync/events` - Get events (with optional `since` parameter)
  - `POST /api/sync/events` - Send local events to server

- **Contacts:**
  - `POST /api/contacts` - Create contact
  - `PUT /api/contacts/:id` - Update contact
  - `DELETE /api/contacts/:id` - Delete contact

- **Transactions:**
  - `GET /api/transactions` - List transactions
  - `POST /api/transactions` - Create transaction
  - `PUT /api/transactions/:id` - Update transaction
  - `DELETE /api/transactions/:id` - Delete transaction

- **Other:**
  - `GET /api/settings` - Get user settings
  - `PUT /api/settings/:key` - Update setting
  - `POST /api/auth/login` - Authenticate user
  - `GET /health` - Health check

**WebSocket:**
- `WS /ws` - WebSocket connection for real-time notifications

### Part 2: Admin Page Serving

**Purpose:** Serve the web-based admin panel for monitoring and debugging

**Admin Routes:**
- `GET /admin` - Serves HTML admin panel page (`static/admin/index.html`)
- `GET /api/admin/events` - List events (with filters)
- `GET /api/admin/contacts` - List all contacts
- `GET /api/admin/transactions` - List all transactions
- `GET /api/admin/projections/status` - Get projection status
- `POST /api/admin/projections/rebuild` - Rebuild projections
- `DELETE /api/admin/events/:event_id` - Delete event (undo)

**Access:** http://localhost:8000/admin

**Note:** The admin panel uses `/api/admin/*` endpoints, while Flutter clients use `/api/*` endpoints (without `/admin` prefix).

---

### HTTP Routes Summary

The backend exposes REST API endpoints organized by functionality:

*(See Part 1 and Part 2 sections above for complete endpoint listing)*

### WebSocket Handler

**Location:** `backend/rust-api/src/websocket.rs`

**Functionality:**
- Accepts WebSocket connections at `/ws` endpoint
- When a client connects, subscribes them to the broadcast channel
- Sends messages from the broadcast channel to the connected client
- Handles connection lifecycle (connect, disconnect, errors)

**Flow:**

```mermaid
flowchart TD
    A[Client connects to /ws] --> B[WebSocket Handler<br/>accepts connection]
    B --> C[Subscribe client to<br/>broadcast channel]
    C --> D[Spawn tasks]
    D --> E[Send messages<br/>channel → client]
    D --> F[Receive messages<br/>client ping/pong]
    E --> G[Client receives<br/>all broadcast messages]
```

### Broadcast Channel

**Type:** Tokio broadcast channel (`broadcast::Sender<String>`)

**Functionality:**
- Created at server startup with 100 message buffer
- When data changes, handlers call `broadcast_change()` to send messages
- All connected WebSocket clients receive the message automatically
- Messages are JSON strings: `{"type": "contact_created", "data": {...}}`

**Usage:**
```rust
broadcast_change(&broadcast_tx, "contact_created", &json_data);
```

### Admin Panel

**Route:** `GET /admin`

**Functionality:**
- Serves HTML page from `backend/rust-api/static/admin/index.html`
- Web-based monitoring and debugging interface
- Features:
  - View events with filtering and search
  - View contacts and transactions
  - Monitor projection status
  - Rebuild projections
  - Delete recent events (undo functionality)

**Access:** http://localhost:8000/admin

### Request Handling Flow

```mermaid
flowchart TD
    A[HTTP Request] --> B[Route Handler<br/>contacts.rs<br/>transactions.rs<br/>sync.rs<br/>admin.rs]
    B --> C[Validate Request]
    C --> D[Write Event to<br/>EventStore DB]
    D --> E[Write Event to<br/>PostgreSQL events table]
    E --> F[Update PostgreSQL<br/>Projection]
    F --> G[Broadcast via<br/>Broadcast Channel]
    G --> H[Return Response]
```

### Event Store (EventStore DB)

**Purpose:** External database for immutable event storage (write-only)

**Features:**
- Append-only (events never deleted or modified)
- Idempotency key support (prevents duplicates)
- Version tracking (optimistic locking)
- Complete audit trail
- Primary event store for the system

**Setup:**
```bash
./scripts/manage.sh start-services eventstore
```

**Access:**
- HTTP API: http://localhost:2113
- Web UI: http://localhost:2113 (admin/changeit)

### PostgreSQL Database

**Purpose:** Contains both event log and materialized projections

**Event Log:**
- `events` table - Stores all events (for debugging and querying)
- Indexed for fast queries by user, aggregate, type, timestamp
- Contains full event data in JSONB format

**Projections (Materialized Views):**
- `contacts_projection` - Current contact state (optimized for reads)
- `transactions_projection` - Current transaction state
- `users_projection` - User accounts
- `user_settings` - User preferences
- Automatically updated when events are written

**Why Both EventStore DB and PostgreSQL?**
- **EventStore DB**: Primary event store, optimized for append-only writes
- **PostgreSQL events table**: Queryable event log for debugging/admin
- **PostgreSQL projections**: Fast read-optimized views of current state

---

## Security

### Current State

- **Authentication**: Not yet implemented (planned: JWT tokens)
- **Authorization**: User-scoped data access (single user for now)
- **Event Store**: Idempotency prevents duplicate operations
- **Version Tracking**: Prevents concurrent modification conflicts

### Planned

- JWT token authentication
- Multi-user support
- Role-based access control
- Rate limiting

---

## Related Documentation

- [API Reference](./API.md) - Complete API endpoint documentation
- [Development Guide](./DEVELOPMENT.md) - Development setup and workflow
- [Deployment Guide](./DEPLOYMENT.md) - Production deployment instructions
