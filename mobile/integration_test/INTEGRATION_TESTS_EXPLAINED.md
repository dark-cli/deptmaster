# Integration Tests Explained

## Overview

The integration tests verify that the **entire event-sourcing architecture** works correctly end-to-end. They test the complete flow from user actions → events → state projections → synchronization.

## Architecture Being Tested

```
User Action (Create Contact/Transaction)
    ↓
LocalDatabaseServiceV2 (creates event)
    ↓
EventStoreService (stores event locally)
    ↓
StateBuilder (rebuilds projections from events)
    ↓
Hive Database (stores contacts/transactions)
    ↓
SyncServiceV2 (syncs events to server)
```

## What Each Test Does

### 1. **Create Contact and Verify Event Created Locally**
**What it tests:**
- When you create a contact, an event is automatically created
- The contact appears in the projections (readable data)
- The event is stored in the event store
- The event is initially unsynced (hasn't been sent to server yet)

**How it verifies:**
```dart
// 1. Create contact programmatically
final contact = await createTestContact(name: 'Integration Test Contact');

// 2. Check projections (readable data)
final contacts = await LocalDatabaseServiceV2.getContacts();
expect(contacts.any((c) => c.id == contact.id), true); // ✅ Contact exists

// 3. Check event store (source of truth)
await verifyEventCreated(
  aggregateType: 'contact',
  aggregateId: contact.id,
  eventType: 'CREATED',
  expectedData: {'name': 'Integration Test Contact'},
);

// 4. Verify event is unsynced
expect(events.first.synced, false); // ✅ Not synced yet
```

**Why this matters:** Ensures every action creates an event, and projections are rebuilt correctly.

---

### 2. **Create Transaction and Verify Balance Updates**
**What it tests:**
- Creating a transaction updates the contact's balance
- Balance calculation is correct (lent = positive, owed = negative)
- Transaction appears in projections
- Event is created for the transaction

**How it verifies:**
```dart
// 1. Create contact (balance starts at 0)
final contact = await createTestContact();
expect(contact.balance, 0); // ✅ Initial balance

// 2. Create transaction (lent 150,000)
final transaction = await createTestTransaction(
  contactId: contact.id,
  direction: TransactionDirection.lent,
  amount: 150000,
);

// 3. Check balance updated
contacts = await LocalDatabaseServiceV2.getContacts();
expect(contacts.firstWhere((c) => c.id == contact.id).balance, 150000);
// ✅ Balance = +150,000 (they owe you)

// 4. Verify transaction exists
final transactions = await LocalDatabaseServiceV2.getTransactions();
expect(transactions.any((t) => t.id == transaction.id), true);
```

**Why this matters:** Ensures balance calculations work correctly and state is rebuilt from events.

---

### 3. **Update Contact and Verify UPDATED Event**
**What it tests:**
- Updating a contact creates an UPDATED event (not a new contact)
- Projections reflect the update immediately
- Event contains the updated data

**How it verifies:**
```dart
// 1. Create contact
final contact = await createTestContact(name: 'Original Name');

// 2. Update contact
final updated = contact.copyWith(name: 'Updated Name');
await LocalDatabaseServiceV2.updateContact(updated);

// 3. Check projections updated
final contacts = await LocalDatabaseServiceV2.getContacts();
expect(contacts.firstWhere((c) => c.id == contact.id).name, 'Updated Name');
// ✅ Projection reflects update

// 4. Check UPDATED event created
final events = await EventStoreService.getEventsForAggregate('contact', contact.id);
expect(events.any((e) => e.eventType == 'UPDATED'), true);
// ✅ UPDATED event exists (not just CREATED)
```

**Why this matters:** Ensures updates create proper events and projections stay in sync.

---

### 4. **Delete Transaction and Verify Balance Resets**
**What it tests:**
- Deleting a transaction removes it from projections
- Balance is recalculated correctly (removes the transaction's effect)
- DELETED event is created

**How it verifies:**
```dart
// 1. Create contact and transaction
final contact = await createTestContact();
final transaction = await createTestTransaction(
  contactId: contact.id,
  direction: TransactionDirection.lent,
  amount: 200000,
);
expect(contact.balance, 200000); // ✅ Balance before deletion

// 2. Delete transaction
await LocalDatabaseServiceV2.deleteTransaction(transaction.id);

// 3. Check transaction removed
final transactions = await LocalDatabaseServiceV2.getTransactions();
expect(transactions.any((t) => t.id == transaction.id), false);
// ✅ Transaction gone

// 4. Check balance reset
contacts = await LocalDatabaseServiceV2.getContacts();
expect(contacts.firstWhere((c) => c.id == contact.id).balance, 0);
// ✅ Balance recalculated (200,000 - 200,000 = 0)

// 5. Check DELETED event
final events = await EventStoreService.getEventsForAggregate('transaction', transaction.id);
expect(events.any((e) => e.eventType == 'DELETED'), true);
```

**Why this matters:** Ensures deletions work correctly and state rebuilds properly.

---

### 5. **Sync Local Events to Server**
**What it tests:**
- Local events can be synced to the server
- Events are marked as "synced" after successful sync
- Sync works even if backend is configured

**How it verifies:**
```dart
// 1. Create local events (unsynced)
final contact = await createTestContact();
final transaction = await createTestTransaction(contactId: contact.id);

// 2. Verify events are unsynced
var unsyncedEvents = await EventStoreService.getUnsyncedEvents();
expect(unsyncedEvents.length, greaterThanOrEqualTo(2));
// ✅ Events exist but not synced

// 3. Trigger sync
await SyncServiceV2.sync();
await waitForSync(); // Wait for sync to complete

// 4. Verify events are now synced
unsyncedEvents = await EventStoreService.getUnsyncedEvents();
// ✅ Fewer unsynced events (or none)

// 5. Check specific events are synced
final contactCreatedEvent = contactEvents.firstWhere((e) => e.eventType == 'CREATED');
expect(contactCreatedEvent.synced, true);
// ✅ Event marked as synced
```

**Why this matters:** Ensures the sync mechanism works and events are properly synchronized.

---

### 6. **Compare Local and Server Events**
**What it tests:**
- After sync, local and server events match
- Event data is consistent between client and server
- No events are lost during sync

**How it verifies:**
```dart
// 1. Create and sync events
final contact = await createTestContact();
await SyncServiceV2.sync();
await waitForSync();

// 2. Compare local and server events
await compareLocalAndServerEvents();

// Inside compareLocalAndServerEvents():
final localEvents = await EventStoreService.getAllEvents();
final serverEvents = await ApiService.getSyncEvents();

// Filter to synced events
final syncedLocalEvents = localEvents.where((e) => e.synced).toList();

// 3. Verify counts match
expect(syncedLocalEvents.length, serverEvents.length);
// ✅ Same number of events

// 4. Verify each event matches
for (final localEvent in syncedLocalEvents) {
  final serverEvent = serverEvents.firstWhere((e) => e['id'] == localEvent.id);
  
  expect(serverEvent['aggregate_type'], localEvent.aggregateType);
  expect(serverEvent['aggregate_id'], localEvent.aggregateId);
  expect(serverEvent['event_type'], localEvent.eventType);
  // ✅ Event data matches
}
```

**Why this matters:** Ensures data consistency between client and server.

---

### 7. **Test Offline Creation and Online Sync**
**What it tests:**
- App works offline (creates events locally)
- Events are queued when offline
- When coming back online, events sync automatically
- No data loss during offline/online transitions

**How it verifies:**
```dart
// 1. Simulate offline (set invalid backend)
await BackendConfigService.setBackendConfig('127.0.0.1', 9999);

// 2. Create contact while "offline"
final contact = await createTestContact(name: 'Offline Contact');

// 3. Verify event is unsynced
final events = await EventStoreService.getEventsForAggregate('contact', contact.id);
expect(events.first.synced, false);
// ✅ Event created but not synced (offline)

// 4. Restore backend (simulate coming online)
await BackendConfigService.setBackendConfig(originalIp, originalPort);

// 5. Sync
await SyncServiceV2.sync();
await waitForSync();

// 6. Verify event is now synced
final updatedEvents = await EventStoreService.getEventsForAggregate('contact', contact.id);
expect(updatedEvents.firstWhere((e) => e.eventType == 'CREATED').synced, true);
// ✅ Event synced after coming online
```

**Why this matters:** Ensures the app works offline and syncs correctly when online.

---

### 8. **Create Multiple Contacts and Transactions**
**What it tests:**
- Multiple operations work correctly
- Balance calculations work for multiple contacts
- All events are created correctly
- Projections contain all data

**How it verifies:**
```dart
// 1. Create multiple contacts
final contact1 = await createTestContact(name: 'Contact 1');
final contact2 = await createTestContact(name: 'Contact 2');
final contact3 = await createTestContact(name: 'Contact 3');

// 2. Create transactions for each
final txn1 = await createTestTransaction(
  contactId: contact1.id,
  direction: TransactionDirection.lent,
  amount: 100000,
);
final txn2 = await createTestTransaction(
  contactId: contact2.id,
  direction: TransactionDirection.owed,
  amount: 50000,
);

// 3. Verify all contacts exist
final contacts = await LocalDatabaseServiceV2.getContacts();
expect(contacts.length, 3); // ✅ All contacts present

// 4. Verify all transactions exist
final transactions = await LocalDatabaseServiceV2.getTransactions();
expect(transactions.length, 3); // ✅ All transactions present

// 5. Verify balances are correct
expect(contacts.firstWhere((c) => c.id == contact1.id).balance, 100000);
// ✅ Contact 1: +100,000 (lent)
expect(contacts.firstWhere((c) => c.id == contact2.id).balance, -50000);
// ✅ Contact 2: -50,000 (owed)

// 6. Verify all events created
final allEvents = await EventStoreService.getAllEvents();
expect(allEvents.length, 6); // ✅ 3 contacts + 3 transactions = 6 events
```

**Why this matters:** Ensures the system handles multiple operations correctly and maintains consistency.

---

### 9. **Monitor Local Data During Operations**
**What it tests:**
- Event count increases as operations happen
- Event statistics are accurate
- We can track what's happening in real-time

**How it verifies:**
```dart
// 1. Get initial event count
final initialEvents = await EventStoreService.getAllEvents();
final initialCount = initialEvents.length;

// 2. Create contact
final contact = await createTestContact(name: 'Monitor Test Contact');

// 3. Verify event count increased
final afterContactEvents = await EventStoreService.getAllEvents();
expect(afterContactEvents.length, initialCount + 1);
// ✅ One more event (contact CREATED)

// 4. Create transaction
await createTestTransaction(contactId: contact.id, amount: 50000);

// 5. Verify event count increased again
final afterTransactionEvents = await EventStoreService.getAllEvents();
expect(afterTransactionEvents.length, initialCount + 2);
// ✅ Two more events (contact + transaction)

// 6. Get statistics
final stats = await getEventStats();
expect(stats['total'], initialCount + 2);
expect(stats['contacts'], 1);
expect(stats['transactions'], 1);
// ✅ Statistics accurate
```

**Why this matters:** Ensures we can monitor the system and track events correctly.

---

## How We Verify Correctness

### 1. **Event Verification**
- Check that events exist in the event store
- Verify event type (CREATED, UPDATED, DELETED)
- Verify event data matches what was sent
- Check event is marked as synced/unsynced

### 2. **Projection Verification**
- Check that projections (contacts/transactions) exist
- Verify data in projections matches what was created
- Verify balance calculations are correct
- Check that deletions remove items from projections

### 3. **State Consistency**
- Verify projections are rebuilt from events
- Check that balance calculations match transactions
- Ensure updates reflect in projections
- Verify deletions remove items correctly

### 4. **Sync Verification**
- Check events are marked as synced after sync
- Compare local and server events
- Verify event data matches between client and server
- Test offline/online scenarios

### 5. **Multi-Operation Verification**
- Test multiple operations in sequence
- Verify all operations create events
- Check projections contain all data
- Verify balances are calculated correctly for all contacts

---

## Key Testing Principles

1. **Event-First**: Every action must create an event
2. **Projections from Events**: Projections are rebuilt from events, not written directly
3. **Balance Calculation**: Balances are calculated from transactions, not stored directly
4. **Sync Consistency**: Local and server events must match after sync
5. **Offline Support**: App must work offline and sync when online

---

## What Makes These Integration Tests

Unlike unit tests that test individual functions, these tests:
- Test the **entire system** working together
- Use **real services** (not mocks)
- Test **real data flow** (events → projections → sync)
- Run on **real devices** (Android/iOS)
- Test **end-to-end scenarios** (create → update → delete → sync)

This ensures the event-sourcing architecture works correctly in real-world scenarios.
