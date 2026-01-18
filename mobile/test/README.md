# Flutter Tests

## Running Tests

```bash
cd mobile
flutter test
```

## Test Files

- `realtime_service_test.dart` - Tests for WebSocket real-time service
- `contact_transactions_screen_test.dart` - Widget tests for transaction list screen
- `contacts_screen_test.dart` - Widget tests for contacts list screen

## Writing Tests

### Widget Tests

Test UI components and user interactions:

```dart
testWidgets('displays transactions', (WidgetTester tester) async {
  // Build widget
  await tester.pumpWidget(MyWidget());
  
  // Find widgets
  final transactionList = find.byType(ListView);
  
  // Verify
  expect(transactionList, findsOneWidget);
});
```

### Unit Tests

Test business logic:

```dart
test('calculates balance correctly', () {
  final transactions = [
    Transaction(direction: TransactionDirection.lent, amount: 100),
    Transaction(direction: TransactionDirection.owed, amount: 50),
  ];
  
  final balance = calculateBalance(transactions);
  
  expect(balance, equals(50));
});
```

## Mocking

For testing with API calls, use mocks:

```dart
// Use mockito or similar
final mockApiService = MockApiService();
when(mockApiService.getTransactions()).thenAnswer((_) async => testTransactions);
```

## Note

The current test files contain TODO placeholders. They need:
- Mock implementations for API service
- Mock WebSocket connections
- Test data fixtures
- Actual test implementations
