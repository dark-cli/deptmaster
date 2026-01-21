# Flutter Test Suite

This directory contains comprehensive unit and integration tests for the Debt Tracker mobile app.

## Test Structure

```
mobile/
├── test/
│   ├── unit/
│   │   ├── state_builder_test.dart          # StateBuilder function tests
│   │   ├── event_store_service_test.dart    # EventStoreService tests
│   │   └── local_database_service_v2_test.dart # LocalDatabaseServiceV2 tests
│   └── widget/
│       └── ... (existing widget tests)
└── integration_test/
    ├── app_test.dart                        # Full app flow integration tests
    └── helpers/
        └── test_helpers.dart                # Test utility functions
```

## Running Tests

### Unit Tests (run on desktop)
```bash
cd mobile
flutter test test/unit/
```

### Integration Tests (can run on device/emulator)
```bash
cd mobile
flutter test integration_test/app_test.dart
```

### Run All Tests
```bash
cd mobile
flutter test
```

### Run Tests on Specific Device
```bash
flutter test integration_test/app_test.dart -d <device-id>
```

## Test Coverage

### Unit Tests

#### StateBuilder Tests
- ✅ Build state from empty events
- ✅ Create contact from CREATED event
- ✅ Update contact from UPDATED event
- ✅ Delete contact from DELETED event
- ✅ Create transaction and calculate balance
- ✅ Handle multiple transactions
- ✅ Handle transaction deletion
- ✅ Apply events incrementally
- ✅ Handle events in chronological order

#### EventStoreService Tests
- ✅ Append event
- ✅ Get events for aggregate
- ✅ Get events by type
- ✅ Get unsynced events
- ✅ Mark event as synced
- ✅ Get latest version
- ✅ Get event count
- ✅ Get events after timestamp

#### LocalDatabaseServiceV2 Tests
- ✅ Create contact (creates event and updates projections)
- ✅ Update contact (creates UPDATED event)
- ✅ Delete contact (creates DELETED event)
- ✅ Create transaction (updates balance)
- ✅ Delete transaction (resets balance)
- ✅ Get transactions by contact

### Integration Tests

#### Full App Flow Tests
- ✅ Create contact and verify event created locally
- ✅ Create transaction and verify balance updates
- ✅ Update contact and verify UPDATED event
- ✅ Delete transaction and verify balance resets
- ✅ Sync local events to server
- ✅ Compare local and server events after sync
- ✅ Test offline creation and online sync
- ✅ Create multiple contacts and transactions
- ✅ Monitor local data during operations

## Test Helpers

The `test_helpers.dart` file provides utility functions:

- `initializeTestEnvironment()` - Set up test environment
- `cleanupTestEnvironment()` - Clean up after tests
- `createTestContact()` - Create a test contact
- `createTestTransaction()` - Create a test transaction
- `verifyEventCreated()` - Verify event was created locally
- `verifyEventSyncedToServer()` - Verify event synced to server
- `compareLocalAndServerEvents()` - Compare local and server events
- `waitForSync()` - Wait for sync to complete
- `getEventStats()` - Get event count statistics

## Notes

1. **Hive Adapters**: Tests automatically register Hive adapters. Ensure `build_runner` has been run to generate adapter files.

2. **Backend Configuration**: Some integration tests require backend to be configured. They will skip if backend is not configured.

3. **Test Isolation**: Each test cleans up after itself to ensure isolation.

4. **Offline Testing**: Tests can simulate offline mode by changing backend configuration.

## Writing New Tests

### Unit Test Example
```dart
test('my function works correctly', () {
  // Arrange
  final input = 'test';
  
  // Act
  final result = myFunction(input);
  
  // Assert
  expect(result, 'expected');
});
```

### Integration Test Example
```dart
testWidgets('user can create contact', (WidgetTester tester) async {
  // Start app
  app.main();
  await tester.pumpAndSettle();
  
  // Perform actions
  final contact = await createTestContact(name: 'Test');
  
  // Verify
  final contacts = await LocalDatabaseServiceV2.getContacts();
  expect(contacts.any((c) => c.id == contact.id), true);
});
```
