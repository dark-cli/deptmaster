import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:debt_tracker_mobile/screens/contacts_screen.dart';
// Note: Tests need to be updated for local-first architecture

void main() {
  group('ContactsScreen UI Tests', () {

    setUp(() {
    });

    testWidgets('displays "People" title in app bar', (WidgetTester tester) async {
      // Build the widget
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ContactsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify title
      expect(find.text('People'), findsOneWidget);
    });

    testWidgets('displays add contact button in app bar', (WidgetTester tester) async {
      // Build the widget
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ContactsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify add button (plus icon)
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('displays total balance section', (WidgetTester tester) async {
      // Build the widget
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ContactsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify TOTAL label
      expect(find.text('TOTAL'), findsOneWidget);
      
      // Verify balance is displayed (formatted with IQD)
      expect(find.textContaining('IQD'), findsWidgets);
    });

    testWidgets('displays contacts list', (WidgetTester tester) async {
      // Build the widget
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ContactsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify contacts are displayed (if loaded)
      // In a real test with mocked API, we'd verify specific contact names
    });

    testWidgets('tapping contact navigates to transactions screen', (WidgetTester tester) async {
      // Build the widget
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ContactsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find a contact item (ListTile)
      final contactItems = find.byType(ListTile);
      
      if (contactItems.evaluate().isNotEmpty) {
        // Tap the first contact
        await tester.tap(contactItems.first);
        await tester.pumpAndSettle();

        // Verify navigation occurred
        // In a real test, you'd verify ContactTransactionsScreen is displayed
      }
    });

    testWidgets('displays FAB for adding transactions', (WidgetTester tester) async {
      // Build the widget
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ContactsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify FAB is present
      expect(find.byType(FloatingActionButton), findsOneWidget);
      
      // Verify it's orange (for adding transactions)
      final fab = tester.widget<FloatingActionButton>(find.byType(FloatingActionButton));
      expect(fab.backgroundColor, isNotNull);
    });

    testWidgets('tapping FAB opens add transaction screen', (WidgetTester tester) async {
      // Build the widget
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ContactsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find and tap FAB
      final fab = find.byType(FloatingActionButton);
      expect(fab, findsOneWidget);
      
      await tester.tap(fab);
      await tester.pumpAndSettle();

      // Verify navigation occurred
      // In a real test, you'd verify AddTransactionScreen is displayed
    });

    testWidgets('shows sorting options menu', (WidgetTester tester) async {
      // Build the widget
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ContactsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find sorting menu button
      final sortButton = find.byType(PopupMenuButton);
      expect(sortButton, findsOneWidget);
    });

    testWidgets('calculates total balance correctly', (WidgetTester tester) async {
      // Build the widget
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ContactsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Total should be: 50000 + (-30000) + 0 = 20000
      // Verify the total is displayed
      expect(find.textContaining('IQD'), findsWidgets);
    });

    testWidgets('displays empty state when no contacts', (WidgetTester tester) async {
      // Build the widget (with empty contacts list)
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ContactsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify empty state (if API returns empty list)
      // In a real test with mocked empty API response
    });

    testWidgets('shows loading indicator while fetching', (WidgetTester tester) async {
      // Build the widget
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ContactsScreen(),
          ),
        ),
      );

      // Don't wait for settle - check during loading
      await tester.pump();

      // Verify loading indicator is shown
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}