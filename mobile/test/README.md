# Flutter Unit and Widget Tests

## Overview

This directory contains **unit tests** and **widget tests** for the Debt Tracker mobile app. These tests are complementary to the integration tests in `integration_test/`:

- **Unit Tests**: Fast, isolated component testing (no server needed)
- **Widget Tests**: UI component testing
- **Integration Tests**: Full system testing with real server and multi-app sync (see `integration_test/multi_app/README.md`)

## Test Structure

```
mobile/test/
├── unit/
│   ├── state_builder_test.dart          # StateBuilder function tests (12 tests)
│   ├── event_store_service_test.dart    # EventStoreService tests (8 tests)
│   ├── local_database_service_v2_test.dart # LocalDatabaseServiceV2 tests (9 tests)
│   ├── undo_event_test.dart            # Undo functionality tests (5 tests)
│   └── projection_snapshot_test.dart   # Projection snapshot tests (5 tests)
├── contacts_screen_test.dart            # Contacts screen widget tests (11 tests)
├── contact_transactions_screen_test.dart # Transaction screen widget tests (9 tests)
├── widget_test.dart                     # Basic app startup test (1 test)
└── README.md                            # This file
```

**Total**: 60 tests (39 unit tests + 21 widget tests)

## Running Tests

### How Tests Run

By default, `flutter test -d linux` (or just `flutter test`) runs **all test files in parallel** (multiple files can run concurrently). Tests within each file run **sequentially** (one after another).

### Run All Tests

```bash
cd mobile
flutter test -d linux
# or just
flutter test
```

This runs all 8 test files in parallel, executing all 60 tests.

### Run Tests One by One (Sequentially)

To run test files **one at a time** (not in parallel), use `--concurrency=1`:

```bash
cd mobile
flutter test -d linux --concurrency=1
```

This will run each test file sequentially, waiting for one to finish before starting the next.

### Run Only Unit Tests

```bash
cd mobile
flutter test -d linux test/unit/
```

Runs all 5 unit test files in parallel.

### Run Only Widget Tests

```bash
cd mobile
flutter test -d linux test/contacts_screen_test.dart test/contact_transactions_screen_test.dart test/widget_test.dart
```

### Run Specific Test File (One at a Time)

```bash
# Unit tests
flutter test -d linux test/unit/state_builder_test.dart
flutter test -d linux test/unit/event_store_service_test.dart
flutter test -d linux test/unit/local_database_service_v2_test.dart
flutter test -d linux test/unit/undo_event_test.dart
flutter test -d linux test/unit/projection_snapshot_test.dart

# Widget tests
flutter test -d linux test/contacts_screen_test.dart
flutter test -d linux test/contact_transactions_screen_test.dart
flutter test -d linux test/widget_test.dart
```

### Run Specific Test Case Within a File

To run a single test case (by name pattern):

```bash
# Run only tests matching a pattern
flutter test -d linux test/unit/state_builder_test.dart --name "Build state from empty"
flutter test -d linux test/contacts_screen_test.dart --name "Displays contacts list"
```

### Run with Verbose Output

```bash
flutter test -d linux --verbose
```

### Run with Coverage

```bash
flutter test -d linux --coverage
genhtml coverage/lcov.info -o coverage/html
```

Then open `coverage/html/index.html` in a browser.

## Test Content

### Unit Tests (`test/unit/`)

#### StateBuilder Tests (`state_builder_test.dart`) - 12 tests
Tests the pure function that builds application state from events.

- ✅ Build state from empty events
- ✅ Create contact from CREATED event
- ✅ Update contact from UPDATED event
- ✅ Delete contact from DELETED event
- ✅ Create transaction and calculate balance
- ✅ Handle multiple transactions
- ✅ Handle transaction deletion
- ✅ Apply events incrementally
- ✅ Handle events in chronological order
- ✅ Handle UNDO events
- ✅ Skip undone events in state building
- ✅ Handle complex event sequences

#### EventStoreService Tests (`event_store_service_test.dart`) - 8 tests
Tests the event store service that manages local event storage.

- ✅ Append event
- ✅ Get events for aggregate
- ✅ Get events by type
- ✅ Get unsynced events
- ✅ Mark event as synced
- ✅ Get latest version
- ✅ Get event count
- ✅ Get events after timestamp

#### LocalDatabaseServiceV2 Tests (`local_database_service_v2_test.dart`) - 9 tests
Tests the local database service that creates/updates/deletes contacts and transactions.

- ✅ Create contact (creates event and updates projections)
- ✅ Update contact (creates UPDATED event)
- ✅ Delete contact (creates DELETED event)
- ✅ Create transaction (updates balance)
- ✅ Update transaction (creates UPDATED event)
- ✅ Delete transaction (resets balance)
- ✅ Get transactions by contact
- ✅ Handle transaction undo
- ✅ Handle contact deletion with transactions

#### Undo Event Tests (`undo_event_test.dart`) - 5 tests
Tests the undo functionality for events.

- ✅ BuildState skips UNDO events themselves
- ✅ BuildState skips undone events
- ✅ Undo CREATED event removes aggregate
- ✅ Undo UPDATED event restores previous state
- ✅ Undo DELETED event restores aggregate

#### Projection Snapshot Tests (`projection_snapshot_test.dart`) - 5 tests
Tests the projection snapshot service for performance optimization.

- ✅ shouldCreateSnapshot returns true for multiples of 10
- ✅ saveSnapshot and getLatestSnapshot work correctly
- ✅ Snapshot contains correct state
- ✅ Snapshot can be used to rebuild state
- ✅ Multiple snapshots are managed correctly

### Widget Tests

#### Contacts Screen Tests (`contacts_screen_test.dart`) - 11 tests
Tests the contacts list screen UI.

- ✅ Displays "People" title in app bar
- ✅ Displays add contact button in app bar
- ✅ Displays contacts list
- ✅ Displays empty state when no contacts
- ✅ Handles contact tap navigation
- ✅ Handles pull-to-refresh
- ✅ Displays sync status icon
- ✅ Handles search functionality
- ✅ Handles filter functionality
- ✅ Displays contact count
- ✅ Handles contact deletion

#### Contact Transactions Screen Tests (`contact_transactions_screen_test.dart`) - 9 tests
Tests the transaction list screen UI for a specific contact.

- ✅ Displays contact name in app bar
- ✅ Displays transactions list
- ✅ Displays empty state when no transactions
- ✅ Displays transaction details correctly
- ✅ Handles transaction tap
- ✅ Handles add transaction button
- ✅ Displays balance correctly
- ✅ Handles pull-to-refresh
- ✅ Handles transaction deletion

#### Widget Test (`widget_test.dart`) - 1 test
Basic app startup test.

- ✅ App starts without crashing

## Prerequisites

### 1. Generate Hive Adapters

Before running tests, ensure Hive adapters are generated:

```bash
cd mobile
flutter pub run build_runner build --delete-conflicting-outputs
```

### 2. Test Data

Unit tests use local Hive boxes in `test/hive_test_data/` directory. These are automatically managed by the tests.

## Writing New Tests

### Unit Test Example

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:debt_tracker_mobile/services/my_service.dart';

void main() {
  group('MyService Unit Tests', () {
    setUp(() async {
      // Initialize test environment
    });

    tearDown(() async {
      // Clean up after test
    });

    test('my function works correctly', () {
      // Arrange
      final input = 'test';
      
      // Act
      final result = myFunction(input);
  
      // Assert
      expect(result, 'expected');
});
  });
}
```

### Widget Test Example

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:debt_tracker_mobile/screens/my_screen.dart';

void main() {
  group('MyScreen Widget Tests', () {
    testWidgets('displays content correctly', (WidgetTester tester) async {
      // Build widget
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: MyScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find widgets
      final content = find.text('Expected Content');
      
      // Verify
      expect(content, findsOneWidget);
    });
});
}
```

## Troubleshooting

### "Adapter not found" errors

Run `build_runner` to generate adapters:
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### Tests fail with Hive errors

Ensure Hive is properly initialized. Tests should handle this automatically, but if issues persist:
- Check that adapters are registered
- Clear test data: `rm -rf test/hive_test_data/*`
- Re-run tests

### Tests fail with "Box is already open" errors

Tests handle this automatically. If persistent:
- Restart test runner
- Close any running Flutter apps
- Clear test data: `rm -rf test/hive_test_data/*`

## Notes

- **Test Isolation**: Each test cleans up after itself to ensure isolation
- **Hive Initialization**: Unit tests use `Hive.init('test/hive_test_data')` instead of `Hive.initFlutter()` to avoid platform dependencies
- **No Server Required**: Unit and widget tests don't require a running server
- **Fast Execution**: Unit tests run very quickly (typically < 1 second per test)
- **Complementary to Integration Tests**: These tests focus on individual components, while integration tests test the full system

## Integration Tests

For full system testing with real server and multi-app sync scenarios, see:
- `integration_test/multi_app/README.md` - Comprehensive multi-app sync testing framework
