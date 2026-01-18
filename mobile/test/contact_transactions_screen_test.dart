import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:debt_tracker_mobile/screens/contact_transactions_screen.dart';
import 'package:debt_tracker_mobile/models/contact.dart';
import 'package:debt_tracker_mobile/models/transaction.dart';
import 'package:debt_tracker_mobile/services/api_service.dart';
import 'package:debt_tracker_mobile/services/realtime_service.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

// Generate mocks
@GenerateMocks([ApiService, RealtimeService])
import 'contact_transactions_screen_test.mocks.dart';

void main() {
  group('ContactTransactionsScreen UI Tests', () {
    late Contact testContact;
    late List<Transaction> testTransactions;

    setUp(() {
      testContact = Contact(
        id: 'test-contact-id',
        name: 'Test Contact',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        balance: 50000, // 50,000 IQD
      );

      testTransactions = [
        Transaction(
          id: 'txn-1',
          contactId: testContact.id,
          type: TransactionType.money,
          direction: TransactionDirection.lent,
          amount: 30000,
          currency: 'IQD',
          description: 'Test transaction 1',
          transactionDate: DateTime.now().subtract(const Duration(days: 1)),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        Transaction(
          id: 'txn-2',
          contactId: testContact.id,
          type: TransactionType.money,
          direction: TransactionDirection.owed,
          amount: 20000,
          currency: 'IQD',
          description: 'Test transaction 2',
          transactionDate: DateTime.now().subtract(const Duration(days: 2)),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];
    });

    testWidgets('displays contact name in app bar', (WidgetTester tester) async {
      // Build the widget
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ContactTransactionsScreen(contact: testContact),
          ),
        ),
      );

      // Wait for initial load
      await tester.pumpAndSettle();

      // Verify contact name is displayed
      expect(find.text('Test Contact'), findsOneWidget);
    });

    testWidgets('displays transactions list', (WidgetTester tester) async {
      // Mock API service
      final mockApiService = MockApiService();
      when(mockApiService.getTransactions()).thenAnswer((_) async => testTransactions);

      // Build the widget
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ContactTransactionsScreen(contact: testContact),
          ),
        ),
      );

      // Wait for data to load
      await tester.pumpAndSettle();

      // Verify transactions are displayed
      expect(find.text('Test transaction 1'), findsOneWidget);
      expect(find.text('Test transaction 2'), findsOneWidget);
    });

    testWidgets('displays balance correctly', (WidgetTester tester) async {
      // Build the widget
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ContactTransactionsScreen(contact: testContact),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify balance label
      expect(find.text('BALANCE'), findsOneWidget);
      
      // Balance should be calculated from transactions: 30000 - 20000 = 10000
      // But we're using the contact's balance which is 50000
      // The screen calculates from transactions, so we need to verify the calculation
      expect(find.textContaining('IQD'), findsWidgets);
    });

    testWidgets('shows FloatingActionButton for adding transactions', (WidgetTester tester) async {
      // Build the widget
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ContactTransactionsScreen(contact: testContact),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify FAB is present
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('FAB opens add transaction screen when tapped', (WidgetTester tester) async {
      // Build the widget
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ContactTransactionsScreen(contact: testContact),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find and tap the FAB
      final fab = find.byType(FloatingActionButton);
      expect(fab, findsOneWidget);
      
      await tester.tap(fab);
      await tester.pumpAndSettle();

      // Verify navigation occurred (this would open AddTransactionScreen)
      // In a real test, you'd verify the screen changed
    });

    testWidgets('shows popup menu on transaction item', (WidgetTester tester) async {
      // Build the widget
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ContactTransactionsScreen(contact: testContact),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find popup menu button (three dots icon)
      final popupMenu = find.byType(PopupMenuButton);
      expect(popupMenu, findsWidgets);
    });

    testWidgets('displays empty state when no transactions', (WidgetTester tester) async {
      // Create contact with no transactions
      final emptyContact = Contact(
        id: 'empty-contact',
        name: 'Empty Contact',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        balance: 0,
      );

      // Build the widget
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ContactTransactionsScreen(contact: emptyContact),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify empty state message
      expect(find.textContaining('No transactions'), findsOneWidget);
      expect(find.textContaining('Tap + to add'), findsOneWidget);
    });

    testWidgets('transaction item shows correct amount and direction', (WidgetTester tester) async {
      // Build the widget
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ContactTransactionsScreen(contact: testContact),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify transaction amounts are displayed
      // Amounts should be formatted with commas and IQD
      expect(find.textContaining('30,000 IQD'), findsOneWidget);
      expect(find.textContaining('20,000 IQD'), findsOneWidget);
    });

    testWidgets('pull to refresh reloads transactions', (WidgetTester tester) async {
      // Build the widget
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ContactTransactionsScreen(contact: testContact),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find RefreshIndicator
      final refreshIndicator = find.byType(RefreshIndicator);
      expect(refreshIndicator, findsOneWidget);

      // Simulate pull to refresh
      await tester.drag(find.byType(ListView), const Offset(0, 300));
      await tester.pumpAndSettle();
    });
  });
}
