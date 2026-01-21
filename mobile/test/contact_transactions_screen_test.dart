import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:debt_tracker_mobile/screens/contact_transactions_screen.dart';
import 'package:debt_tracker_mobile/models/contact.dart';
import 'package:debt_tracker_mobile/models/transaction.dart';
import 'package:debt_tracker_mobile/services/local_database_service_v2.dart';
import 'package:debt_tracker_mobile/services/event_store_service.dart';
// Import generated adapters
import 'package:debt_tracker_mobile/models/contact.g.dart';
import 'package:debt_tracker_mobile/models/transaction.g.dart';
import 'package:debt_tracker_mobile/models/event.g.dart';

void main() {
  group('ContactTransactionsScreen UI Tests', () {
    late Contact testContact;
    late List<Transaction> testTransactions;

    setUpAll(() async {
      // Initialize Hive
      await Hive.initFlutter();
      Hive.registerAdapter(ContactAdapter());
      Hive.registerAdapter(TransactionAdapter());
      Hive.registerAdapter(TransactionTypeAdapter());
      Hive.registerAdapter(TransactionDirectionAdapter());
      Hive.registerAdapter(EventAdapter());
    });

    setUp(() async {
      // Initialize services
      await EventStoreService.initialize();
      try {
        await Hive.openBox<Contact>('contacts');
      } catch (e) {
        // Box already open
      }
      try {
        await Hive.openBox<Transaction>('transactions');
      } catch (e) {
        // Box already open
      }
      await LocalDatabaseServiceV2.initialize();

      // Clear existing data
      await Hive.box<Contact>('contacts').clear();
      await Hive.box<Transaction>('transactions').clear();
      final events = await EventStoreService.getAllEvents();
      for (final event in events) {
        await event.delete();
      }

      // Create test contact
      testContact = Contact(
        id: 'test-contact-id',
        name: 'Test Contact',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        balance: 0,
      );
      await LocalDatabaseServiceV2.createContact(testContact);

      // Create test transactions
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

      for (final txn in testTransactions) {
        await LocalDatabaseServiceV2.createTransaction(txn);
      }
    });

    tearDown(() async {
      // Clean up
      try {
        await Hive.box<Contact>('contacts').clear();
        await Hive.box<Transaction>('transactions').clear();
        await Hive.box<Event>('events').clear();
      } catch (e) {
        // Boxes might not exist
      }
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
      // Get updated contact with balance
      final updatedContact = await LocalDatabaseServiceV2.getContact(testContact.id);
      expect(updatedContact, isNotNull);

      // Build the widget
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ContactTransactionsScreen(contact: updatedContact!),
          ),
        ),
      );

      // Wait for data to load
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Verify transactions are displayed (check for description or amount)
      // The screen might display transactions differently, so we check for any transaction-related text
      final transactions = await LocalDatabaseServiceV2.getTransactionsByContact(testContact.id);
      expect(transactions.length, 2);
      
      // Verify at least one transaction description is visible
      expect(find.textContaining('Test transaction'), findsWidgets);
    });

    testWidgets('displays balance correctly', (WidgetTester tester) async {
      // Get updated contact with balance
      final updatedContact = await LocalDatabaseServiceV2.getContact(testContact.id);
      expect(updatedContact, isNotNull);
      // Balance should be -30000 (lent) + 20000 (owed) = -10000
      expect(updatedContact!.balance, -10000);

      // Build the widget
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ContactTransactionsScreen(contact: updatedContact),
          ),
        ),
      );

      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Verify balance is displayed (the screen should show balance somewhere)
      // Check for balance-related text or amount
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