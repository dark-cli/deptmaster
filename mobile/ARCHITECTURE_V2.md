# Simplified Client Architecture (KISS)

## Overview

This document describes the simplified client-side architecture that follows the KISS (Keep It Simple, Stupid) principle. The new architecture eliminates complex edge cases and makes the codebase easier to understand, test, and maintain.

## Core Principles

1. **Single Source of Truth**: Events are the only source of truth
2. **Pure Functions**: State building uses pure functions (no side effects)
3. **Hash-Based Sync**: Compare hashes, sync only differences
4. **Event-Driven**: Every action creates an event, state is rebuilt from events

## Architecture Components

### 1. EventStoreService
**Location**: `mobile/lib/services/event_store_service.dart`

Stores all events locally in Hive. Every action (create, update, delete) creates an event.

**Key Methods**:
- `appendEvent()` - Create a new event
- `getAllEvents()` - Get all events (sorted by timestamp)
- `getEventHash()` - Calculate hash of all events (for sync comparison)
- `getLastSyncTimestamp()` / `setLastSyncTimestamp()` - Track sync time
- `getEventsAfter()` - Get events after a timestamp (incremental sync)
- `getUnsyncedEvents()` - Get events not yet synced to server

### 2. StateBuilder
**Location**: `mobile/lib/services/state_builder.dart`

Pure functions that build application state from events. No side effects, easy to test.

**Key Methods**:
- `buildState(List<Event> events)` - Build full state from all events
- `applyEvents(AppState currentState, List<Event> newEvents)` - Incremental update
- `calculateTotalDebtAtTime(DateTime timestamp)` - Calculate total debt at a point in time

**How it works**:
1. Sorts events by timestamp
2. Applies events in order (CREATED, UPDATED, DELETED)
3. Calculates contact balances from transactions
4. Returns `AppState` with contacts and transactions

### 3. LocalDatabaseServiceV2
**Location**: `mobile/lib/services/local_database_service_v2.dart`

Simplified database service. All writes create events, then rebuild state.

**Read Operations**:
- Read directly from Hive boxes (projections)
- No rebuilding on read (fast, simple)

**Write Operations**:
- Create event using `EventStoreService.appendEvent()`
- Rebuild state using `StateBuilder.buildState()`
- Save state to Hive boxes

**Key Methods**:
- `getContacts()`, `getContact()`, `getTransactions()`, etc. - Read operations
- `createContact()`, `updateContact()`, `deleteContact()` - Write operations
- `createTransaction()`, `updateTransaction()`, `deleteTransaction()` - Write operations
- `initialize()` - Rebuilds state from events on startup

### 4. SyncServiceV2
**Location**: `mobile/lib/services/sync_service_v2.dart`

Hash-based sync service. Compares local and server hashes, syncs only differences.

**How Sync Works**:
1. Get server hash and event count
2. Get local hash and event count
3. If hashes match → already in sync
4. If different:
   - Pull new events from server (since last sync timestamp)
   - Insert missing events into local store
   - Get unsynced local events
   - Send unsynced events to server
   - Mark accepted events as synced
   - Rebuild state from all events

**Key Methods**:
- `sync()` - Perform full sync
- `manualSync()` - Manual sync trigger
- `initialize()` - Start periodic sync (every 30 seconds)

### 5. Server Sync Endpoints
**Location**: `backend/rust-api/src/handlers/sync.rs`

**Endpoints**:
- `GET /api/sync/hash` - Get hash of all server events
- `GET /api/sync/events?since=<timestamp>` - Get events since timestamp
- `POST /api/sync/events` - Send local events to server

## Data Flow

### Creating a Contact
```
User Action
  ↓
LocalDatabaseServiceV2.createContact()
  ↓
EventStoreService.appendEvent() [CREATED event]
  ↓
StateBuilder.buildState() [rebuild from all events]
  ↓
Save to Hive boxes
  ↓
SyncServiceV2 (background) syncs event to server
```

### Syncing
```
SyncServiceV2.sync()
  ↓
Compare local hash vs server hash
  ↓
If different:
  - Pull new events from server
  - Insert into local EventStore
  - Get unsynced local events
  - Send to server
  - Mark as synced
  ↓
StateBuilder.buildState() [rebuild from all events]
  ↓
Save to Hive boxes
```

## Benefits

1. **Simplicity**: No complex pending operations, no dual-write logic
2. **Testability**: Pure functions are easy to test
3. **Reliability**: Single source of truth (events), no state inconsistencies
4. **Performance**: Hash comparison is fast, only syncs what's needed
5. **Maintainability**: Clear data flow, easy to understand

## Migration from Old Architecture

The old services are still present but no longer used:
- `local_database_service.dart` → Replaced by `local_database_service_v2.dart`
- `sync_service.dart` → Replaced by `sync_service_v2.dart`
- `projection_service.dart` → Replaced by `state_builder.dart`
- `data_service.dart` → No longer needed

All screens have been updated to use the new services.

## Testing

The new architecture is designed to be easy to test:

1. **StateBuilder**: Pure functions, no dependencies → unit test easily
2. **EventStoreService**: Test event storage/retrieval
3. **SyncServiceV2**: Mock API calls, test sync logic
4. **LocalDatabaseServiceV2**: Test event creation and state rebuilding

## Future Improvements

1. Add unit tests for StateBuilder
2. Add integration tests for sync flow
3. Optimize state rebuilding (incremental updates for large datasets)
4. Add conflict resolution strategy
5. Add event compression/archiving for old events
