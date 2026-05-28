---
tags:
  - architecture
  - design
---

# Architecture

**Debt Tracker** is an offline-first debt management app with event-sourced architecture, real-time sync, and cross-platform support (iOS, Android, Web, Linux Desktop).

## Project Overview

## Tech Stack

### Backend
- **Framework**: Rust + Axum web framework
- **Runtime**: Tokio async runtime
- **Database**: PostgreSQL (events log + projections)
- **Real-time**: WebSocket with broadcast channels
- **Task Scheduler**: Tokio-cron-scheduler
- **Email**: Lettre

### Mobile/Web Frontend
- **Framework**: Flutter (Dart)
- **State Management**: Riverpod
- **Local Storage**: Hive (NoSQL, offline-first)
- **HTTP Client**: Dio + web_socket_channel
- **Charts**: Syncfusion Flutter Charts

## Communication Patterns

### REST API (Bidirectional Data Transfer)
- Clients send events: `POST /api/sync/events`
- Clients pull events: `GET /api/sync/events?since=<timestamp>`
- Hash comparison for efficient sync: `GET /api/sync/hash`
- Direct CRUD endpoints: `/api/contacts`, `/api/transactions`

### WebSocket (Notification Only)
- Server broadcasts lightweight notifications when data changes
- Clients trigger sync automatically (don't receive full data via WebSocket)
- Uses Tokio broadcast channel with 100-message buffer

## Core Data Flow

```
User Action (Mobile/Web)
  → Create Event (CONTACT_CREATED, TRANSACTION_UPDATED, etc.)
  → Store in Local Hive (offline)
  → Update Local Projections (instant UI update)
  → Background Sync Service detects change
  → POST /api/sync/events to server
  → Server validates + stores in PostgreSQL + broadcasts
  → WebSocket notifies all clients
  → Clients pull events via GET /api/sync/events
  → Clients rebuild state + UI updates
```

## Backend Services

### Service 1: API Service
Handles Flutter client requests: sync, contacts, transactions, auth, settings

### Service 2: Admin Service
Web-based monitoring panel at `/admin` for event inspection and projection rebuilding

Both services share PostgreSQL, broadcast channel, and event sourcing layer.

## Storage Architecture

### PostgreSQL
- **events table**: Immutable append-only event log with idempotency keys + version tracking
- **Projections**: contacts_projection, transactions_projection, users_projection (directly updated, not rebuilt)
- **Snapshots**: projection_snapshots (for efficient rebuild optimization)

### Mobile Local Storage (Hive)
- Events Box: Immutable local event log
- Projections Box: Current state (contacts, transactions)
- Syncs bidirectionally with server

## Key Design Decisions

- **Event Sourcing**: Complete audit trail, no data loss, conflict resolution via version tracking
- **Offline-First**: Mobile works fully offline, syncs when online; web requires connection
- **Hash-Based Sync**: Only syncs differences (compare hashes before pull/push)
- **Direct Projections**: Not rebuilt from events (too slow); directly updated for fast reads
- **WebSocket Notifications**: Lightweight trigger-only (full data via REST API)
- **Idempotency**: Prevent duplicate operations via idempotency keys

## Related Notes
- [[backend-reader-guide.md]] - Step-by-step guide to reading the backend code
- [[auth.md]] - JWT authentication and middleware
- [[middleware-architecture.md]] - Complete middleware chain, responsibilities, and issues
- [[permission-system-deep-dive.md]] - Group-based permissions and access control
- [[idempotency-keys.md]] - How duplicate operations are prevented
- [[sync-architecture.md]] - REST vs WebSocket sync design analysis
- [[client-backend-security.md]] - Client-to-backend connection security analysis
- [[code-cleanup.md]] - Dead code, unused dependencies, and technical debt
- [[conventions.md]] - Coding patterns and naming
- [[decisions.md]] - Why certain patterns were chosen
- [[todos.md]] - Incomplete features and gaps
