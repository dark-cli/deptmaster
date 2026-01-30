# Sync Architecture Documentation

## Overview

The sync system uses an event-driven architecture with separate local-to-server and server-to-local sync operations. It implements retry logic with exponential backoff and manages sync loops to ensure events are synchronized reliably.

## Core Components

### 1. RetryBackoff Class (`services/retry_backoff.dart`)

Manages retry delays using a predefined sequence: `[1, 1, 2, 5, 5, 5, 10]` seconds.

**Methods:**
- `getWaiting()`: Returns the current wait duration and advances to the next value. Stays on the last value (10s) after reaching the end.
- `reset()`: Resets to the first value (1s).

**Usage:**
```dart
final backoff = RetryBackoff();
Duration delay = backoff.getWaiting(); // Returns 1s, advances to index 1
delay = backoff.getWaiting(); // Returns 1s, advances to index 2
delay = backoff.getWaiting(); // Returns 2s, advances to index 3
// ... continues until 10s, then stays at 10s
backoff.reset(); // Back to 1s
```

### 2. SyncServiceV2 Class (`services/sync_service_v2.dart`)

Main sync service that handles all synchronization operations.

#### Pure Sync Functions (No Loops)

##### `syncLocalToServer() -> Future<SyncResult>`

Syncs local unsynced events to the server.

**Behavior:**
- Checks if unsynced events exist
- Checks if online (WebSocket connected)
- Converts events to server format
- Sends events to server via `ApiService.postSyncEvents()`
- Marks accepted events as synced
- Rebuilds state after sync
- Returns `SyncResult.done` on success, `SyncResult.failed` on failure

**Called by:**
- `startLocalToServerSync()` loop
- `onBackOnline()` handler

##### `syncServerToLocal() -> Future<SyncResult>`

Syncs server events to local storage.

**Behavior:**
- Checks if online (WebSocket connected)
- Compares local and server hashes
- Fetches missing events from server
- Inserts new events into local event store
- Rebuilds state from all events
- Updates last sync timestamp
- Returns `SyncResult.done` on success, `SyncResult.failed` on failure

**Called by:**
- `_handleServerToLocalSyncRequest()` (triggered by WebSocket notifications)
- `onBackOnline()` handler

#### Loop Functions

##### `startWebSocketNotificationListening()`

Permanent loop that manages retry logic for server-to-local sync failures.

**Behavior:**
- Runs continuously while app is running
- Checks if online (if offline, resets retry flag and returns)
- First run: no wait
- Subsequent runs: waits per RetryBackoff if retry is needed
- When `_needsServerToLocalRetry` is true:
  - Waits per backoff delay
  - Retries `syncServerToLocal()`
  - On success: resets retry flag and backoff
  - On failure: keeps retry flag set for next iteration

**Started:**
- On app initialization (`initialize()`)

##### `startLocalToServerSync()`

Temporary loop that syncs local events to server until success.

**Behavior:**
- Cancels existing loop if one is running
- Resets backoff for immediate sync
- First run: no wait
- Subsequent runs: waits per RetryBackoff on failure
- Checks if online (if offline, skips iteration)
- Checks if unsynced events exist (if none, stops loop)
- Runs `syncLocalToServer()` until it succeeds
- On success: stops loop and resets backoff
- On failure: continues loop with backoff delay

**Started:**
- When new event is created (via `LocalDatabaseServiceV2`)
- On pull-to-refresh (`onPullToRefresh()`)
- On coming back online (`onBackOnline()`)

#### Event Handlers

##### `onBackOnline()`

Called when WebSocket connection is restored.

**Behavior:**
- Resets backoff
- Checks if unsynced events exist
- If yes: starts local-to-server sync loop
- Triggers server-to-local sync (to get server updates)
- If server-to-local sync fails, sets retry flag for notification loop

**Called by:**
- `RealtimeService` when WebSocket connects

##### `onPullToRefresh()`

Called on pull-to-refresh (swipe down) action.

**Behavior:**
- Resets backoff
- Starts local-to-server sync loop

**Called by:**
- Pull-to-refresh handlers in screens (transactions, contacts, dashboard)

#### Internal Methods

##### `_handleServerToLocalSyncRequest()`

Handles server-to-local sync requests from WebSocket notifications.

**Behavior:**
- Runs `syncServerToLocal()`
- On success: resets retry flag and backoff
- On failure: sets retry flag for notification loop to handle retry

**Called by:**
- `RealtimeService._handleRealtimeUpdate()` on WebSocket notification

## Sync Flow Diagrams

### Local-to-Server Sync Flow

```
New Event Created
    ↓
startLocalToServerSync()
    ↓
Loop: Check online? → Check unsynced events? → syncLocalToServer()
    ↓
Success? → Stop loop
Failure? → Wait (backoff) → Retry
```

### Server-to-Local Sync Flow

```
WebSocket Notification
    ↓
_handleServerToLocalSyncRequest()
    ↓
syncServerToLocal()
    ↓
Success? → Done
Failure? → Set retry flag
    ↓
Notification Loop (permanent)
    ↓
Retry with backoff until success
```

### Back Online Flow

```
WebSocket Connected
    ↓
onBackOnline()
    ↓
Reset backoff
    ↓
┌─────────────────┬──────────────────┐
│                 │                  │
Unsynced events?  │  syncServerToLocal()
│                 │                  │
Yes → startLocal  │  Success → Done  │
ToServerSync()    │  Failure → Retry │
```

## Integration Points

### 1. Event Creation (`LocalDatabaseServiceV2`)

When events are created (contact/transaction create/update/delete):

```dart
await EventStoreService.appendEvent(...);
await _rebuildState();
SyncServiceV2.startLocalToServerSync(); // Immediate sync, resets backoff
```

### 2. WebSocket Notifications (`RealtimeService`)

When WebSocket receives notification:

```dart
_handleRealtimeUpdate(data) {
  SyncServiceV2._handleServerToLocalSyncRequest();
}
```

### 3. Connection Restored (`RealtimeService`)

When WebSocket connects:

```dart
if (!_isConnected) {
  _isConnected = true;
  SyncServiceV2.onBackOnline(); // Reset backoff and run both syncs
}
```

### 4. Pull-to-Refresh (Screens)

When user pulls to refresh:

```dart
RefreshIndicator(
  onRefresh: () => _loadData(sync: true),
)
// In _loadData:
if (sync) {
  SyncServiceV2.onPullToRefresh(); // Reset backoff and start sync
}
```

## State Management

### Sync States

- `_isLocalToServerSyncing`: Prevents concurrent local-to-server syncs
- `_isServerToLocalSyncing`: Prevents concurrent server-to-local syncs
- `_needsServerToLocalRetry`: Flag for notification loop to retry failed syncs
- `_firstWebSocketRun`: Ensures first run has no wait
- `_firstLocalToServerRun`: Ensures first run has no wait

### Timers

- `_webSocketNotificationTimer`: Permanent loop for retry management
- `_localToServerSyncTimer`: Temporary loop for local-to-server sync

## Error Handling

### Network Errors

Network errors (connection refused, timeout, etc.) are caught and return `SyncResult.failed`. The retry loops handle these automatically with backoff delays.

### Authentication Errors

Authentication errors (401, expired token) are caught and return `SyncResult.failed`. The sync loops will retry, but the user should re-login.

### Other Errors

Other errors are logged and return `SyncResult.failed`. The retry loops will attempt to sync again.

## Retry Logic

### Backoff Sequence

`[1, 1, 2, 5, 5, 5, 10]` seconds

- First retry: 1 second
- Second retry: 1 second
- Third retry: 2 seconds
- Fourth retry: 5 seconds
- Fifth retry: 5 seconds
- Sixth retry: 5 seconds
- Seventh+ retries: 10 seconds (stays at 10s)

### Reset Conditions

Backoff is reset when:
- Sync succeeds
- New event is created (immediate sync)
- Pull-to-refresh is triggered
- Coming back online

## Best Practices

1. **Always check online status**: Both sync functions check `RealtimeService.isConnected` before attempting sync.

2. **One sync at a time**: Guard flags prevent concurrent syncs of the same type.

3. **Immediate sync on user action**: New events and pull-to-refresh reset backoff for immediate sync.

4. **Automatic retry**: Failed syncs are automatically retried with backoff delays.

5. **State rebuild**: State is rebuilt after successful syncs to ensure UI consistency.

## Debugging

### Get Sync Status

```dart
final status = await SyncServiceV2.getSyncStatus();
// Returns:
// {
//   'is_local_to_server_syncing': bool,
//   'is_server_to_local_syncing': bool,
//   'local_event_count': int,
//   'unsynced_event_count': int,
//   'last_sync': String?,
//   'has_unsynced_events': bool,
// }
```

### Logs

The sync service logs all operations:
- `🔄 Starting sync...`
- `📤 Sending X unsynced events to server...`
- `✅ Server accepted X events`
- `⚠️ Sync failed due to network error`
- `❌ Sync error: ...`

## Future Improvements

1. **Conflict Resolution**: Currently conflicts are only logged. Implement merge strategy.

2. **Batch Size**: Consider batching large numbers of events for better performance.

3. **Sync Priority**: Prioritize critical events (e.g., deletions) over updates.

4. **Background Sync**: Use background tasks for sync when app is in background.

5. **Sync Progress**: Provide UI feedback for sync progress.
