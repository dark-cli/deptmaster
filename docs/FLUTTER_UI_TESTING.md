# Flutter UI Testing Guide

## Yes, Flutter Has Excellent UI Testing Support!

Flutter provides comprehensive UI/widget testing capabilities through the `flutter_test` package. You can test:

- ✅ **Button taps and interactions**
- ✅ **Form inputs and validation**
- ✅ **Navigation between screens**
- ✅ **Widget visibility and state**
- ✅ **Text rendering and formatting**
- ✅ **Real-time updates**
- ✅ **User gestures (tap, drag, scroll)**
- ✅ **Dialog and popup interactions**

## Types of Flutter Tests

### 1. Widget Tests (UI Tests)
Test individual widgets and their interactions:

```dart
testWidgets('button tap works', (WidgetTester tester) async {
  // Build widget
  await tester.pumpWidget(MyButton());
  
  // Find button
  final button = find.byType(ElevatedButton);
  
  // Tap button
  await tester.tap(button);
  await tester.pump();
  
  // Verify result
  expect(find.text('Clicked!'), findsOneWidget);
});
```

### 2. Integration Tests
Test complete user flows across multiple screens:

```dart
testWidgets('complete user flow', (WidgetTester tester) async {
  // Start app
  await tester.pumpWidget(MyApp());
  
  // Navigate through screens
  await tester.tap(find.text('Next'));
  await tester.pumpAndSettle();
  
  // Verify final state
  expect(find.text('Success'), findsOneWidget);
});
```

## Common Testing Patterns

### Finding Widgets

```dart
// By type
find.byType(ElevatedButton)
find.byType(TextField)

// By text
find.text('Hello')
find.textContaining('Hello')

// By icon
find.byIcon(Icons.add)

// By key
find.byKey(Key('my-button'))

// By widget
find.byWidget(myWidget)
```

### User Interactions

```dart
// Tap
await tester.tap(find.byType(Button));

// Enter text
await tester.enterText(find.byType(TextField), 'Hello');

// Drag
await tester.drag(find.byType(ListView), Offset(0, -300));

// Long press
await tester.longPress(find.byType(ListTile));

// Scroll
await tester.scrollUntilVisible(find.text('Item 100'), 500);
```

### Verifying State

```dart
// Check if widget exists
expect(find.text('Hello'), findsOneWidget);
expect(find.text('Hello'), findsNothing);
expect(find.text('Hello'), findsWidgets); // One or more

// Check widget properties
final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
expect(button.onPressed, isNotNull);

// Check widget tree
expect(tester.widgetList(find.byType(Text)), hasLength(3));
```

## Example: Testing Transaction Screen

```dart
testWidgets('transaction screen interactions', (WidgetTester tester) async {
  // 1. Build the screen
  await tester.pumpWidget(
    MaterialApp(
      home: ContactTransactionsScreen(contact: testContact),
    ),
  );
  
  // 2. Wait for data to load
  await tester.pumpAndSettle();
  
  // 3. Verify UI elements
  expect(find.text('Test Contact'), findsOneWidget); // App bar title
  expect(find.byType(FloatingActionButton), findsOneWidget); // FAB
  expect(find.text('BALANCE'), findsOneWidget); // Balance label
  
  // 4. Test button tap
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
  
  // 5. Verify navigation
  expect(find.text('Add Transaction'), findsOneWidget);
  
  // 6. Test popup menu
  await tester.tap(find.byType(PopupMenuButton).first);
  await tester.pumpAndSettle();
  
  // 7. Verify menu items
  expect(find.text('Edit'), findsOneWidget);
  expect(find.text('Delete'), findsOneWidget);
});
```

## Running Tests

```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/contact_transactions_screen_test.dart

# Run with coverage
flutter test --coverage

# Run in watch mode (auto-rerun on changes)
flutter test --watch
```

## Best Practices

1. **Use `pumpAndSettle()`** to wait for all animations and async operations
2. **Mock external dependencies** (API, WebSocket) for reliable tests
3. **Test user flows**, not implementation details
4. **Keep tests isolated** - each test should be independent
5. **Use descriptive test names** that explain what is being tested
6. **Test edge cases** - empty states, error states, loading states

## Mocking for Tests

Use `mockito` to mock services:

```dart
@GenerateMocks([ApiService])
import 'test.mocks.dart';

testWidgets('loads data from API', (tester) async {
  final mockApi = MockApiService();
  when(mockApi.getContacts()).thenAnswer((_) async => testContacts);
  
  // Use mock in widget
  await tester.pumpWidget(MyWidget(api: mockApi));
});
```

## Real-World Example

See `mobile/test/contact_transactions_screen_test.dart` for a complete example testing:
- UI rendering
- Button interactions
- Navigation
- Real-time updates
- Empty states
- Form validation

## Resources

- [Flutter Testing Documentation](https://docs.flutter.dev/testing)
- [Widget Testing Cookbook](https://docs.flutter.dev/cookbook/testing/widget)
- [Integration Testing Guide](https://docs.flutter.dev/testing/integration-tests)
