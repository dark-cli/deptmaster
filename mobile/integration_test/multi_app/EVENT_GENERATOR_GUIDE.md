# Event Generator Guide

The Event Generator is a helper tool that allows you to create complex test scenarios with many events (10-30+) using a simple text format, minimizing the amount of code needed in test files.

## Usage

### Basic Example

```dart
final generator = EventGenerator({
  'app1': app1!,
  'app2': app2!,
  'app3': app3!,
});

final commands = [
  'app1: contact create "Alice" alice',
  'app1: transaction create alice owed 1000 "Lunch" t1',
  'app2: transaction update t1 amount 1200',
  'app2: contact update alice name "Alice Smith"',
  'app1: transaction delete t1',
];

await generator.executeCommands(commands);
```

## Command Format

### Contact Commands

**Create Contact:**
```
app: contact create "Contact Name" [label]
```
- `label` is optional, defaults to lowercase name without spaces
- Example: `app1: contact create "Alice" alice`

**Update Contact:**
```
app: contact update label field "value"
```
- Fields: `name`, `phone`, `email`
- Example: `app2: contact update alice name "Alice Smith"`

**Delete Contact:**
```
app: contact delete label
```
- Example: `app1: contact delete alice`

### Transaction Commands

**Create Transaction:**
```
app: transaction create contactLabel direction amount ["description"] [label]
```
- `direction`: `owed` or `lent`
- `description` is optional (use quotes if contains spaces)
- `label` is optional, auto-generated if not provided
- Example: `app1: transaction create alice owed 1000 "Lunch" t1`

**Update Transaction:**
```
app: transaction update transLabel field value
```
- Fields: `amount`, `description`
- Example: `app2: transaction update t1 amount 1200`

**Delete Transaction:**
```
app: transaction delete transLabel
```
- Example: `app1: transaction delete t1`

### Undo Commands

**Undo Contact Action:**
```
app: undo contact label
```
- Must be within 5 seconds of the action
- Example: `app1: undo contact alice`

**Undo Transaction Action:**
```
app: undo transaction label
```
- Must be within 5 seconds of the action
- Example: `app2: undo transaction t1`

## Best Practices

### 1. Use 10-30 Events Per Test

Tests should have enough events to thoroughly test the system:
- **10-15 events**: Basic scenarios
- **15-25 events**: Complex scenarios
- **25-30+ events**: Stress/edge case scenarios

### 2. Majority Should Be Transactions

Most events should be transactions (at least 2x contacts):
```dart
// Good: 3 contacts, 12 transactions = 15 events
final commands = [
  'app1: contact create "Alice" alice',
  'app1: contact create "Bob" bob',
  'app1: contact create "Charlie" charlie',
  'app1: transaction create alice owed 1000 "T1" t1',
  'app1: transaction create alice lent 500 "T2" t2',
  // ... 10 more transactions
];
```

### 3. Include Edits, Deletes, and Undos

Every test should include:
- **Updates**: At least 20-30% of creates should have updates
- **Deletes**: At least 10-15% of creates should be deleted
- **Undos**: Include undo operations (within 5-second window)

### 4. Test Offline Scenarios

Test multiple apps offline making changes:
```dart
// App1 and App2 go offline
await app1!.goOffline();
await app2!.goOffline();

// Both make changes
final offlineCommands = [
  'app1: contact create "Dave" dave',
  'app1: transaction create dave owed 1000 "T1" t1',
  'app2: contact create "Eve" eve',
  'app2: transaction create eve lent 500 "T2" t2',
];

await generator.executeCommands(offlineCommands);

// Come back online and sync
await app1!.goOnline();
await app2!.goOnline();
await monitor!.waitForSync();
```

### 5. Verify State Builder

Always verify the final state after events:
```dart
// Verify event counts
final events = await app1!.getEvents();
expect(events.length, greaterThanOrEqualTo(20));

// Verify transaction events are majority
final transactionEvents = events.where(
  (e) => e.aggregateType == 'transaction'
).length;
expect(transactionEvents, greaterThan(contactEvents * 2));

// Verify we have UPDATE and DELETE events
final updateEvents = events.where((e) => e.eventType == 'UPDATED').length;
final deleteEvents = events.where((e) => e.eventType == 'DELETED').length;
expect(updateEvents, greaterThan(0));
expect(deleteEvents, greaterThan(0));

// Verify final state
final contacts = await app1!.getContacts();
final transactions = await app1!.getTransactions();
expect(contacts.length, expectedContactCount);
expect(transactions.length, expectedTransactionCount);
```

## Example: Complex Test with 25 Events

```dart
test('Complex Scenario with 25 Events', () async {
  final commands = [
    // Create 3 contacts (3 events)
    'app1: contact create "Alice" alice',
    'app1: contact create "Bob" bob',
    'app1: contact create "Charlie" charlie',
    
    // Create 10 transactions (10 events)
    'app2: transaction create alice owed 1000 "T1" t1',
    'app2: transaction create alice lent 500 "T2" t2',
    'app2: transaction create alice owed 2000 "T3" t3',
    'app3: transaction create bob lent 1500 "T4" t4',
    'app3: transaction create bob owed 800 "T5" t5',
    'app3: transaction create charlie owed 3000 "T6" t6',
    'app3: transaction create charlie lent 1000 "T7" t7',
    'app1: transaction create bob owed 500 "T8" t8',
    'app1: transaction create alice lent 200 "T9" t9',
    'app2: transaction create charlie owed 1500 "T10" t10',
    
    // Update 5 transactions (5 events)
    'app1: transaction update t1 amount 1200',
    'app1: transaction update t2 description "Coffee and snacks"',
    'app2: transaction update t4 amount 1600',
    'app2: transaction update t6 amount 3200',
    'app3: transaction update t8 description "Taxi ride"',
    
    // Update 2 contacts (2 events)
    'app2: contact update alice name "Alice Smith"',
    'app3: contact update bob phone "123-456-7890"',
    
    // Delete 3 transactions (3 events)
    'app1: transaction delete t3',
    'app3: transaction delete t5',
    'app2: transaction delete t7',
    
    // Delete 1 contact (1 event)
    'app1: contact delete charlie',
    
    // Create 1 more transaction (1 event)
    'app2: transaction create alice lent 300 "T11" t11',
  ];
  
  await generator.executeCommands(commands);
  await monitor!.waitForSync();
  
  // Verify: 3+10+5+2+3+1+1 = 25 events
  final events = await app1!.getEvents();
  expect(events.length, greaterThanOrEqualTo(25));
});
```

## Notes

- **Labels**: Use descriptive labels (e.g., `alice`, `t1`, `t2`) to reference entities later
- **Timing**: Undo operations must be within 5 seconds of the action
- **Comments**: Use `#` for comments in command lists
- **Sync**: Always wait for sync after executing commands: `await monitor!.waitForSync()`
