# Real-Time Updates & Offline Sync Implementation

**Date**: January 2026  
**Feature**: Firebase-like real-time updates with offline-first support

## Overview

Implemented real-time data synchronization using WebSockets, similar to Firebase's real-time database. The system provides instant updates across all connected clients and works offline with automatic sync when connection is restored.

## Architecture

### Backend (Rust)

#### WebSocket Server
- **File**: `backend/rust-api/src/websocket.rs`
- **Endpoint**: `ws://localhost:8000/ws`
- **Technology**: Axum WebSocket with Tokio broadcast channels

#### Key Components

1. **Broadcast Channel**
   ```rust
   pub type BroadcastChannel = broadcast::Sender<String>;
   pub fn create_broadcast_channel() -> BroadcastChannel {
       broadcast::channel(100).0
   }
   ```

2. **WebSocket Handler**
   - Accepts WebSocket connections
   - Subscribes clients to broadcast channel
   - Sends updates to all connected clients
   - Handles connection lifecycle (connect/disconnect)

3. **Broadcast Function**
   ```rust
   pub fn broadcast_change(channel: &BroadcastChannel, event_type: &str, data: &str) {
       let message = format!(r#"{{"type":"{}","data":{}}}"#, event_type, data);
       let _ = channel.send(message);
   }
   ```

#### Integration Points

**AppState** (`backend/rust-api/src/main.rs`):
- Added `broadcast_tx: BroadcastChannel` to application state
- Initialized on server startup
- Shared across all handlers

**Contact Creation** (`backend/rust-api/src/handlers/contacts.rs`):
- After creating contact, broadcasts `contact_created` event
- All connected clients receive update instantly

**Transaction Creation** (`backend/rust-api/src/handlers/transactions.rs`):
- After creating transaction, broadcasts `transaction_created` event
- All connected clients receive update instantly

### Frontend (Flutter)

#### Real-Time Service
- **File**: `mobile/lib/services/realtime_service.dart`
- **Technology**: `web_socket_channel` package

#### Key Features

1. **Connection Management**
   - Auto-connects on app start
   - Auto-reconnects if connection drops (3-second delay)
   - Platform-aware URL selection:
     - Web: `ws://localhost:8000/ws`
     - Android: `ws://10.0.2.2:8000/ws`
     - Desktop: `ws://localhost:8000/ws`

2. **Event Handling**
   - Listens for WebSocket messages
   - Parses JSON events
   - Notifies registered listeners
   - Handles different event types:
     - `contact_created` / `contact_updated`
     - `transaction_created` / `transaction_updated`

3. **Data Synchronization**
   - On receiving update, fetches latest data from API
   - Updates local Hive storage (offline cache)
   - Triggers UI refresh

4. **Offline Support**
   - Stores data in Hive (mobile/desktop only)
   - Falls back to Hive when API fails
   - Syncs when connection restored

#### Integration Points

**Main App** (`mobile/lib/main.dart`):
- Connects WebSocket on app start (both web and mobile)
- Syncs data when coming back online

**Contacts Screen** (`mobile/lib/screens/contacts_screen.dart`):
- Registers listener for real-time updates
- Reloads contacts when `contact_created`/`contact_updated` received
- Cleans up listener on dispose

**Transactions Screen** (`mobile/lib/screens/transactions_screen.dart`):
- Registers listener for real-time updates
- Reloads transactions when `transaction_created`/`transaction_updated` received
- Cleans up listener on dispose

## Data Flow

### Real-Time Update Flow

```
1. User creates contact/transaction in Client A
   ↓
2. Client A sends HTTP POST to backend
   ↓
3. Backend creates event in database
   ↓
4. Backend broadcasts change via WebSocket
   ↓
5. All connected clients (A, B, C...) receive update
   ↓
6. Each client fetches latest data from API
   ↓
7. Each client updates local state and Hive cache
   ↓
8. UI refreshes automatically
```

### Offline Flow

```
1. Client goes offline
   ↓
2. API calls fail
   ↓
3. Client loads from Hive cache
   ↓
4. User can still view/edit cached data
   ↓
5. Client comes back online
   ↓
6. WebSocket reconnects automatically
   ↓
7. Client syncs latest data from API
   ↓
8. Hive cache updated
   ↓
9. UI shows latest data
```

## Dependencies

### Backend
- `axum = { version = "0.7", features = ["ws"] }` - WebSocket support
- `futures-util = "0.3"` - Async utilities
- `tokio::sync::broadcast` - Broadcast channels

### Frontend
- `web_socket_channel: ^2.4.0` - WebSocket client
- `hive_flutter: ^1.1.0` - Offline storage (existing)

## Event Types

### Contact Events
- `contact_created` - New contact created
- `contact_updated` - Contact modified (future)

### Transaction Events
- `transaction_created` - New transaction created
- `transaction_updated` - Transaction modified (future)

## Message Format

```json
{
  "type": "contact_created",
  "data": {
    "id": "uuid",
    "name": "Contact Name",
    "balance": 0
  }
}
```

## Error Handling

### Backend
- WebSocket connection errors are logged
- Broadcast failures are silently ignored (non-critical)
- Client disconnections are handled gracefully

### Frontend
- Connection failures trigger auto-reconnect
- API fetch failures fall back to Hive cache
- Hive errors are logged but don't crash app
- WebSocket parse errors are logged and ignored

## Performance Considerations

1. **Broadcast Channel Size**: Limited to 100 messages (prevents memory issues)
2. **Reconnection Delay**: 3 seconds (prevents rapid reconnection loops)
3. **Hive Storage**: Only used on mobile/desktop (web uses state only)
4. **Selective Updates**: Only affected screens refresh (not entire app)

## Testing

### Manual Testing Steps

1. **Start Backend**
   ```bash
   ./START_SERVER.sh
   ```

2. **Open Multiple Clients**
   - Open http://localhost:8080 in multiple browser tabs
   - Or open web + desktop app simultaneously

3. **Test Real-Time Updates**
   - Create contact in Client A
   - Verify it appears instantly in Client B
   - Create transaction in Client B
   - Verify it appears instantly in Client A

4. **Test Offline Mode**
   - Disconnect network
   - Verify cached data still visible
   - Create/edit data (will be queued)
   - Reconnect network
   - Verify data syncs automatically

5. **Test Reconnection**
   - Stop backend server
   - Verify WebSocket reconnects when server restarts
   - Verify data syncs after reconnection

## Future Enhancements

1. **Optimistic Updates**: Update UI immediately, sync later
2. **Conflict Resolution**: Handle simultaneous edits
3. **Batch Updates**: Group multiple changes into single broadcast
4. **Presence**: Show which users are online
5. **Edit Events**: Broadcast when contacts/transactions are edited
6. **Delete Events**: Broadcast when contacts/transactions are deleted

## Files Modified

### Backend
- `backend/rust-api/Cargo.toml` - Added WebSocket dependencies
- `backend/rust-api/src/main.rs` - Added WebSocket route and broadcast channel
- `backend/rust-api/src/websocket.rs` - New WebSocket handler module
- `backend/rust-api/src/handlers/contacts.rs` - Added broadcast on create
- `backend/rust-api/src/handlers/transactions.rs` - Added broadcast on create

### Frontend
- `mobile/pubspec.yaml` - Added `web_socket_channel` dependency
- `mobile/lib/main.dart` - Added WebSocket connection on startup
- `mobile/lib/services/realtime_service.dart` - New real-time service
- `mobile/lib/screens/contacts_screen.dart` - Added real-time listener
- `mobile/lib/screens/transactions_screen.dart` - Added real-time listener

## Notes

- WebSocket connections are stateless (no authentication yet)
- Hive storage is optional and gracefully fails if unavailable
- Web platform doesn't use Hive (uses in-memory state only)
- All real-time updates trigger full data refresh (could be optimized)
