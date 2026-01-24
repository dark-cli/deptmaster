# Debt Tracker Architecture

## Overview

Debt Tracker is a debt management application with:
- **Local-first architecture**: Works offline, syncs when online
- **Event sourcing**: Complete audit trail with immutable events
- **Real-time sync**: Instant updates via WebSocket

**Tech Stack:**
- **Backend**: Rust (Axum web framework)
- **Frontend**: Flutter (Dart)
- **Database**: PostgreSQL (events and projections)
- **Real-time**: WebSocket with broadcast channels

---

## Application Flow

### User Creates a Contact

```
1. User fills form and taps "Save"
   ↓
2. Flutter App
   ├─ Creates contact via local database service
   ├─ Creates event: CONTACT_CREATED
   ├─ Stores event in local Hive (EventStoreService)
   ├─ Applies new event to last projection (incremental update)
   ├─ Updates local projections (contacts box)
   └─ UI updates immediately (instant feedback)
   ↓
3. Background Sync (SyncServiceV2)
   ├─ Detects unsynced event
   ├─ Sends event to server: POST /api/sync/events
   └─ Marks event as synced when accepted
   ↓
4. Backend Server (Rust)
   ├─ Receives event via sync endpoint
   ├─ Validates event
   ├─ Writes event to PostgreSQL events table (immutable)
   ├─ Updates PostgreSQL projection (contacts_projection)
   ├─ Broadcasts change via WebSocket
   └─ Returns success to client
   ↓
5. WebSocket Broadcast
   ├─ All connected clients receive notification
   ├─ Clients trigger sync automatically
   ├─ Clients pull new events from server
   ├─ Clients rebuild local state
   └─ All UIs update automatically
```

### User Views Contacts

```
1. User opens contacts screen
   ↓
2. Flutter App
   ├─ Reads from local Hive box (contacts projection)
   ├─ No network call needed (instant)
   └─ Displays contacts immediately
   ↓
3. Background Sync (if online)
   ├─ Compares local hash vs server hash
   ├─ If different: pulls new events
   ├─ Applies new events to last projection (incremental update)
   └─ UI updates if changes detected
```

### Real-Time Updates

```
1. User A creates a transaction
   ↓
2. Server processes and broadcasts via WebSocket
   ↓
3. User B's app receives WebSocket message
   ├─ Triggers immediate sync
   ├─ Pulls new events from server
   ├─ Rebuilds local state
   └─ UI updates automatically (no refresh needed)
```

---

## System Architecture

### High-Level Architecture

```mermaid
graph TD
    subgraph HLA ["High-Level Architecture"]
        direction TB

        %% CLIENTS SECTION
        subgraph Clients ["CLIENTS"]
            direction LR
            
            subgraph FlutterClient ["Flutter Client"]
                direction TB
                FA["Flutter App<br/>(Web/Mobile/Desktop)"]
                
                subgraph F_Protocols [" "]
                    direction TB
                    F_REST["REST API (Bidirectional)<br/>- Client → Server: POST events, POST contacts<br/>- Client ← Server: GET events, GET hash"]
                    F_WS["WebSocket (Notifications)<br/>- Server → Client: Notify changes"]
                end
                FA --> F_Protocols
            end

            subgraph AdminPanel ["Admin Panel (Web Browser)"]
                direction TB
                AW["Admin Web Interface<br/>(HTML/JavaScript)"]
                
                subgraph A_Protocols [" "]
                    direction TB
                    A_REST["REST API (Bidirectional)<br/>- Client → Server: GET /admin, GET /api/admin/events<br/>- Client ← Server: HTML page, JSON data"]
                    A_WS["WebSocket (Notifications)<br/>- Server → Client: Notify changes"]
                end
                AW --> A_Protocols
            end
        end

        %% BACKEND SECTION
        subgraph Backend ["BACKEND SERVICES"]
            direction LR
            
            subgraph API_Service ["Backend Service 1: API Service"]
                direction TB
                R1["REST API Routes<br/>- POST /api/sync/events<br/>- GET /api/sync/hash<br/>- POST /api/contacts<br/>- POST /api/auth/login"]
                WS1["WebSocket Handler<br/>- Accepts /ws<br/>- Tokio broadcast channel"]
                R1 --- WS1
            end

            subgraph Admin_Service ["Backend Service 2: Admin Service"]
                direction TB
                R2["Admin Routes<br/>- GET /admin (serves HTML)<br/>- GET /api/admin/events<br/>- POST /api/admin/projections/rebuild"]
                WS2["WebSocket Handler<br/>- Accepts /ws<br/>- Tokio broadcast channel"]
                R2 --- WS2
            end
        end

        %% STORAGE SECTION
        subgraph Storage ["DATA STORAGE"]
            direction TB
            
            subgraph Postgres ["PostgreSQL Database"]
                direction TB
                EL["events table (Event Log)<br/>- Immutable event log<br/>- Idempotency keys for duplicate prevention<br/>- Version tracking for optimistic locking<br/>- Indexed for fast queries"]
                PR["Projections (Read-Optimized)<br/>- contacts_projection, transactions_projection<br/>- Updated directly for fast GET reads<br/>- Version column for conflict detection"]
                EL --> PR
            end
        end

        %% Cross-Layer Connections
        F_Protocols --> API_Service
        A_Protocols --> Admin_Service
        API_Service --> Postgres
        Admin_Service --> Postgres
    end
```

### Client Architecture (Flutter)

```mermaid
graph LR
    subgraph Client_Arch ["Client Architecture (Flutter)"]
        direction LR

        %% UI LAYER
        subgraph UI_Layer ["UI Layer"]
            direction TB
            Screens["<b>Screens</b><br/>HomeScreen, Dashboard, Contacts, etc."]
            Providers["<b>Providers (Riverpod)</b><br/>UI State Only (Settings, Toggles)<br/><i>Not used for data operations</i>"]
            Screens --> Providers
        end

        %% LOCAL DATA LAYER
        subgraph Local_Data ["Local Data Layer"]
            direction TB
            DB_Service["<b>LocalDatabaseServiceV2</b>"]
            
            subgraph Paths [" "]
                direction LR
                ReadPath["<b>READ PATH</b><br/>Direct Hive access<br/>(Fast/Offline)"]
                WritePath["<b>WRITE PATH</b><br/>1. Create Event<br/>2. Rebuild Projections<br/>3. Save to Hive<br/>4. Trigger Sync"]
            end
            
            DB_Service --- Paths
        end

        %% STORAGE
        subgraph Hive_Storage ["Local Storage (Hive)"]
            direction TB
            EventsBox["Events Box<br/>Immutable Log"]
            ProjectionsBox["Projections Box<br/>Contacts, Trans."]
            EventsBox --- ProjectionsBox
        end

        %% BACKGROUND SERVICES
        subgraph Background_Services ["Background Services"]
            direction TB
            Realtime_Service["<b>RealtimeService</b><br/>WebSocket Listener<br/>Triggers SyncService"]
            Sync_Service["<b>SyncServiceV2</b><br/>Hash Comparison<br/>Push/Pull Events<br/>Projection Rebuild"]
            Api_Service["<b>ApiService</b><br/>REST HTTP Client"]
            
            Realtime_Service --> Sync_Service
            Sync_Service --> Api_Service
        end

        %% Flow Connections
        UI_Layer -->|Read/Write| Local_Data
        Local_Data -->|Store| Hive_Storage
        Hive_Storage <-->|Sync| Background_Services
    end
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

```
User Action
  ↓
Create Event (CONTACT_CREATED, TRANSACTION_UPDATED, etc.)
  ↓
Store Event (PostgreSQL / Local Hive)
  ↓
Apply Events to Last Projection (incremental update)
  ↓
Update Projections (PostgreSQL / Local Hive)
  ↓
Broadcast Change (WebSocket)
  ↓
All Clients Sync & Update
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
```
Client needs to sync
  ↓
Client calls GET /api/sync/hash (compare hashes)
  ↓
If different:
  ├─ Client calls GET /api/sync/events (pull new events)
  └─ Client calls POST /api/sync/events (push local events)
  ↓
Client applies new events to last projection (incremental update)
```

### WebSocket (One-way Notification)

**Purpose:** Receive lightweight notifications when server has changes

**Server → Client (Notifications Only):**
- Server broadcasts notification: `{"type": "contact_created", "data": {...}}`
- Client receives notification and triggers sync via REST API
- Client then pulls actual events using `GET /api/sync/events`

**Flow:**
```
Server processes change
  ↓
Server writes event to PostgreSQL events table
  ↓
Server updates PostgreSQL projection
  ↓
Server broadcasts notification via WebSocket
  ↓
All connected clients receive notification
  ↓
Clients trigger sync automatically
  ↓
Clients use REST API to pull events (GET /api/sync/events)
  ↓
Clients rebuild state and update UI
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
   - Apply new events to last projection (incremental update)

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
   ├─ Server writes event to PostgreSQL events table
   ├─ Server updates PostgreSQL projection
   ├─ Server broadcasts notification: {"type": "contact_created", "data": {...}}
   └─ All connected clients receive notification
   ↓
4. Clients receive notification:
   ├─ RealtimeService handles the notification
   ├─ Triggers sync automatically
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

The backend consists of **two separate services**:

### Backend Service 1: API Service (Request Handling)

**Purpose:** Handle requests from Flutter clients (mobile/web/desktop)

**Connects to:** Flutter clients via REST API and WebSocket

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

### Backend Service 2: Admin Service (Web Admin Panel)

**Purpose:** Serve the web-based admin panel for monitoring and debugging

**Connects to:** Admin Panel (Web Browser) via REST API and WebSocket

**Admin Routes:**
- `GET /admin` - Serves HTML admin panel page (`static/admin/index.html`)
- `GET /api/admin/events` - List events (with filters)
- `GET /api/admin/contacts` - List all contacts
- `GET /api/admin/transactions` - List all transactions
- `GET /api/admin/projections/status` - Get projection status
- `POST /api/admin/projections/rebuild` - Rebuild projections
- `DELETE /api/admin/events/:event_id` - Delete event (undo)

**WebSocket:**
- `WS /ws` - WebSocket connection for real-time notifications (same endpoint as Flutter clients)

**Access:** http://localhost:8000/admin

**Note:** 
- Flutter clients connect to **Backend Service 1** (API Service) using `/api/*` endpoints and `/ws` WebSocket
- Admin Panel connects to **Backend Service 2** (Admin Service) using `/admin` and `/api/admin/*` endpoints, and `/ws` WebSocket for real-time notifications
- Both services share the same Event Sourcing Layer, Data Storage, and WebSocket broadcast channel
- Both clients receive real-time notifications via WebSocket when data changes

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
```
Client connects to /ws
  ↓
WebSocket Handler accepts connection
  ↓
Subscribes client to broadcast channel
  ↓
Spawns tasks:
  - Send messages from channel → client
  - Receive messages from client (ping/pong)
  ↓
Client receives all broadcast messages
```

### Broadcast Channel

**Type:** Tokio broadcast channel (`broadcast::Sender<String>`)

**Functionality:**
- Created at server startup with 100 message buffer
- When data changes, handlers broadcast messages to all connected clients
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

```
HTTP Request
  ↓
Route Handler (contacts.rs, transactions.rs, sync.rs, admin.rs)
  ↓
Validate Request
  ↓
Check Idempotency (PostgreSQL events table)
  ↓
Update PostgreSQL Projection DIRECTLY (INSERT/UPDATE contacts_projection or transactions_projection)
  ↓
Write Event to PostgreSQL events table (immutable event log)
  ↓
Broadcast via Broadcast Channel
  ↓
Return Response
```

**Note:** Projections are updated directly (not rebuilt from events). This provides fast writes and reads.

### PostgreSQL Database

**Purpose:** Contains event log and read-optimized projections

#### events table (Event Log)

**What it does:**
- Stores all events as immutable append-only log
- Provides idempotency checking via `idempotency_key` column (prevents duplicate operations)
- Provides version tracking via `event_version` column (optimistic locking)
- Used for querying events (admin panel, debugging, sync)
- Indexed for fast queries by user, aggregate, type, timestamp
- Contains full event data in JSONB format
- Complete audit trail

**Features:**
- Append-only (events never deleted or modified)
- Idempotency key support (prevents duplicates)
- Version tracking (optimistic locking)
- Fast queries with proper indexes

#### Projections (Read-Optimized Tables)

**What they do:**
- Store current state of contacts and transactions
- Updated directly when operations occur (not rebuilt from events)
- Used for all read operations (GET requests)

**Tables:**
- `contacts_projection` - Current contact state (name, phone, email, etc.)
- `transactions_projection` - Current transaction state (amount, direction, date, etc.)
- `users_projection` - User accounts
- `user_settings` - User preferences

**How they work:**
- When you create a contact: INSERT directly into `contacts_projection`
- When you update a contact: UPDATE `contacts_projection` directly
- When you create a transaction: INSERT directly into `transactions_projection`
- All reads query these tables (fast, optimized queries)

**Why not rebuild from events?**
- Rebuilding from events would be slow for reads
- Direct updates provide instant consistency
- Events are still stored for audit trail and debugging

**Are projections actively used?**
- **Yes!** All GET requests query projections:
  - `GET /api/contacts` → queries `contacts_projection`
  - `GET /api/transactions` → queries `transactions_projection`
  - `GET /api/admin/contacts` → queries `contacts_projection`
- Projections are the source of truth for current state

### Projection Rebuilding Algorithm

When projections need to be rebuilt (e.g., after UNDO events or manual rebuild), the system uses an optimized algorithm that leverages snapshots and handles UNDO events efficiently.

#### Algorithm Overview

1. **Snapshot Creation:**
   - Snapshots are created every 10 events or after each UNDO event
   - Each snapshot stores the complete state of contacts and transactions at that point
   - Snapshots include: `event_count`, `last_event_id`, and JSON data of all projections

2. **Rebuilding with UNDO Events:**
   - When UNDO events are present:
     a. Collect all undone event IDs (events that were undone by UNDO events)
     b. Find the earliest undone event's position (event_count)
     c. Search for a snapshot created before that undone event
     d. If found: restore from snapshot, then apply cleaned events after snapshot
     e. If not found: rebuild from scratch with cleaned events
   - **Cleaned event list:** Excludes all UNDO events and all undone events

3. **Rebuilding without UNDO Events:**
   - Use snapshot optimization if available
   - Restore from most recent snapshot, then apply events after snapshot

4. **Snapshot Restoration:**
   - When restoring from a snapshot, filter out any undone events that may be in the snapshot
   - This ensures undone transactions/contacts are not accidentally restored

#### Key Optimizations

- **Fast Lookup:** Uses event ID → position mapping for O(1) lookup of undone event positions
- **Snapshot Optimization:** Avoids reprocessing all events by using snapshots
- **UNDO Handling:** Efficiently excludes undone events without searching one-by-one
- **Consistency:** Ensures undone events are never included in projections, even when restoring from snapshots

#### Example Flow

```
1. Events 1-10: Normal events → Snapshot at event 10
2. Event 11: CREATED transaction (+300,000)
3. Event 12: UNDO (undoes event 11)
   → Snapshot saved (excludes event 11's transaction)
4. Event 13: Another event
5. Rebuild triggered:
   → Finds undone event 11 at position 11
   → Finds snapshot at event 10 (before position 11)
   → Restores snapshot (already excludes undone transaction)
   → Applies cleaned events after snapshot (excludes UNDO and undone events)
   → Result: Correct state without undone transaction
```

#### Implementation Details

- **Location:** `backend/rust-api/src/handlers/sync.rs` - `rebuild_projections_from_events()`
- **Snapshot Service:** `backend/rust-api/src/services/projection_snapshot_service.rs`
- **Snapshot Table:** `projection_snapshots` (stores snapshot JSON and metadata)

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
