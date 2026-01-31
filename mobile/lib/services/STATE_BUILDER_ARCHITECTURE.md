# State Builder Architecture

## How State Building Works

### Overview

The state builder uses **fast RAM data structures** to build the current state, then saves it all at once to Hive boxes using batch operations. It does **NOT** edit the database event by event.

### Process Flow

```
1. Get all events from Hive
   ↓
2. Build state in RAM using Maps (fast!)
   ↓
3. Clear Hive boxes (one operation)
   ↓
4. Save entire state to Hive (batch operation)
```

### Step-by-Step Breakdown

#### Step 1: Get All Events
```dart
final events = await EventStoreService.getAllEvents();
```
- Reads all events from Hive `events` box
- Returns a list of Event objects

#### Step 2: Build State in RAM (Fast!)
```dart
final state = StateBuilder.buildState(events);
```

**Inside `StateBuilder.buildState()`:**

1. **Sort events by timestamp** (in RAM)
   ```dart
   final sortedEvents = List<Event>.from(events)
     ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
   ```

2. **Create in-memory Maps** (fast RAM data structures)
   ```dart
   final contacts = <String, Contact>{};      // Map in RAM
   final transactions = <String, Transaction>{}; // Map in RAM
   ```

3. **Process all events in RAM** (no database writes)
   ```dart
   for (final event in sortedEvents) {
     if (event.aggregateType == 'contact') {
       _applyContactEvent(contacts, event, transactions); // Modifies RAM Map
     } else if (event.aggregateType == 'transaction') {
       _applyTransactionEvent(transactions, event, contacts); // Modifies RAM Map
     }
   }
   ```

4. **Calculate balances** (in RAM)
   ```dart
   _calculateBalances(contacts, transactions.values.toList());
   ```

5. **Return AppState object** (still in RAM)
   ```dart
   return AppState(
     contacts: contacts.values.toList(),      // Convert Map to List
     transactions: transactions.values.toList(), // Convert Map to List
     lastBuiltAt: DateTime.now(),
   );
   ```

**Key Point**: All of this happens in RAM using Dart Maps. No database operations!

#### Step 3: Clear Hive Boxes
```dart
await _contactsBox!.clear();      // One operation
await _transactionsBox!.clear();   // One operation
```
- Two clear operations (very fast)

#### Step 4: Save Entire State (Batch Operation)
```dart
// Batch write contacts
final contactMap = <String, Contact>{};
for (final contact in state.contacts) {
  contactMap[contact.id] = contact;
}
await _contactsBox!.putAll(contactMap);  // ONE batch operation

// Batch write transactions
final transactionMap = <String, Transaction>{};
for (final transaction in state.transactions) {
  transactionMap[transaction.id] = transaction;
}
await _transactionsBox!.putAll(transactionMap);  // ONE batch operation
```

**Key Point**: Uses `putAll()` for batch writes, not individual `put()` calls!

### Performance Characteristics

#### Why This is Fast:

1. **RAM Operations are Fast**
   - Maps are O(1) for lookups and inserts
   - All event processing happens in memory
   - No I/O during state building

2. **Minimal Database Operations**
   - Only 4 database operations total:
     - 1x `getAllEvents()` (read all events)
     - 2x `clear()` (clear contacts and transactions boxes)
     - 2x `putAll()` (batch write contacts and transactions)
   - No event-by-event database writes

3. **Batch Writes**
   - `putAll()` writes all contacts in one operation
   - `putAll()` writes all transactions in one operation
   - Much faster than individual `put()` calls

#### Performance Metrics (from benchmarks):

- **State rebuild with 1-10 events**: 0-3ms
- **StateBuilder.buildState()**: 0ms (instant)
- **Hive operations**: 0-2ms (very fast)

### Comparison: Event-by-Event vs Batch

#### ❌ Event-by-Event (Slow):
```dart
// BAD: Would be slow
for (final event in events) {
  if (event.eventType == 'CREATED') {
    await contactsBox.put(event.aggregateId, contact); // Database write per event
  }
}
// For 100 events = 100 database writes = SLOW!
```

#### ✅ Current Approach (Fast):
```dart
// GOOD: Fast batch operation
final contactMap = <String, Contact>{};
// Build map in RAM (fast)
for (final event in events) {
  if (event.eventType == 'CREATED') {
    contactMap[event.aggregateId] = contact; // RAM operation
  }
}
await contactsBox.putAll(contactMap); // ONE database write = FAST!
// For 100 events = 1 database write = FAST!
```

### Code Locations

- **State Building Logic**: `mobile/lib/services/state_builder.dart`
  - `buildState()` - Pure function, builds state in RAM
  - `_applyContactEvent()` - Modifies RAM Map
  - `_applyTransactionEvent()` - Modifies RAM Map
  - `_calculateBalances()` - Calculates in RAM

- **State Rebuilding**: `mobile/lib/services/sync_service_v2.dart`
  - `_rebuildState()` - Orchestrates the rebuild process
  - Gets events → Builds state in RAM → Clears boxes → Batch writes

### Summary

**Answer**: The builder uses **fast RAM data structures (Maps)** to build the current state, then saves it all at once using batch operations (`putAll()`).

**Benefits**:
- ✅ Fast (0-3ms for 1-10 events)
- ✅ Efficient (minimal database operations)
- ✅ Clean (batch writes instead of event-by-event)
- ✅ Consistent (always rebuilds from scratch, no partial states)
