---
tags:
  - sync
  - undo
  - offline-first
  - client-side
  - optimization
---

# UNDO Event Client-Side Optimization

## Overview

When a user undoes an event on the client (before it's synced to the server), instead of creating an UNDO event, **delete the original event locally**. This keeps the local state clean and avoids creating orphaned events.

## Problem

Without optimization:
1. User creates event locally (e.g., adds contact)
2. User immediately undoes it locally
3. Creates an UNDO event pointing to the original event
4. Both events sync to server
5. Result: Database has both event and UNDO, state is correct but cluttered

## Solution

Check if the event to be undone is already synced:

```
if event.synced == false:
    delete(event)          // Remove from local storage
    return success
else:
    create_undo_event()    // Create UNDO for synced events
```

## Benefits

1. **Cleaner local state** - Unsync'd events are removed instead of marked as undone
2. **Fewer events synced** - No orphaned UNDO events for temporary local changes
3. **Better UX** - "Undo" feels more like deletion for offline-only changes
4. **Less server storage** - Fewer events in the event log for temp operations

## Implementation

### Client-Side (Flutter/Dart)

```dart
Future<void> undoEvent(String eventId) async {
  final event = findEvent(eventId);
  
  if (event == null) return;
  
  // If event hasn't synced yet, just delete it locally
  if (event.synced == false) {
    deleteEvent(eventId);
    notifyListeners();
    return;
  }
  
  // If event is already synced, create an UNDO event
  final undoEvent = Event(
    id: Uuid().v4(),
    aggregateType: event.aggregateType,
    aggregateId: event.aggregateId,
    eventType: 'UNDO',
    eventData: {
      'undone_event_id': eventId,
    },
    timestamp: DateTime.now(),
    synced: false,
  );
  
  appendEvent(undoEvent);
  notifyListeners();
}
```

### Server-Side Validation

The server validates UNDO events using the `synced_at` timestamp:
- 5-second window = `current_time - undone_event.synced_at`
- This allows offline-created UNDO events (both event and UNDO created offline, synced together)
- Prevents abuse of UNDO for events that were synced long ago

## Edge Cases

1. **Event created and undone offline, then edited before sync**
   - If user edits after undo, the original event should not be deleted (keep UNDO for correct state)
   - Solution: Check edit timestamp, only delete if no edits after undo

2. **Multiple undos of the same event**
   - First undo deletes unsync'd event
   - Subsequent undos create UNDO events (for already-deleted events)
   - These will likely be conflicts on server

## See Also

- [[sync-architecture.md]] - Sync protocol overview
- [[sync-handler-deep-dive.md]] - Server-side UNDO validation
