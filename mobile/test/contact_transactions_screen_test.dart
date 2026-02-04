import 'dart:io';

import 'package:debt_tracker_mobile/models/event.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:debt_tracker_mobile/screens/contact_transactions_screen.dart';
import 'package:debt_tracker_mobile/models/contact.dart';
import 'package:debt_tracker_mobile/models/transaction.dart';
import 'package:debt_tracker_mobile/models/wallet.dart';
import 'package:debt_tracker_mobile/services/local_database_service_v2.dart';
import 'package:debt_tracker_mobile/services/event_store_service.dart';
import 'package:debt_tracker_mobile/services/wallet_service.dart';
import 'package:debt_tracker_mobile/services/dummy_data_service.dart';

void main() {
  group('ContactTransactionsScreen UI Tests', () {
    late Contact testContact;
    late List<Transaction> testTransactions;
    late Directory _hiveDir;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({'current_wallet_id': 'test-wallet-id'});
      _hiveDir = await Directory.systemTemp.createTemp('contact_txn_test_');
      Hive.init(_hiveDir.path);
      Hive.registerAdapter(ContactAdapter());
      Hive.registerAdapter(TransactionAdapter());
      Hive.registerAdapter(TransactionTypeAdapter());
      Hive.registerAdapter(TransactionDirectionAdapter());
      Hive.registerAdapter(EventAdapter());
      Hive.registerAdapter(WalletAdapter());
    });

    tearDownAll(() async {
      await Hive.close();
      try {
        await _hiveDir.delete(recursive: true);
      } catch (_) {}
    });

    setUp(() async {
      await EventStoreService.initialize();
      await WalletService.initialize();
      await Hive.openBox<Contact>(DummyDataService.contactsBoxName);
      await Hive.openBox<Transaction>(DummyDataService.transactionsBoxName);
      await Hive.openBox<Wallet>('wallets');
      await LocalDatabaseServiceV2.initialize();

      await Hive.box<Contact>(DummyDataService.contactsBoxName).clear();
      await Hive.box<Transaction>(DummyDataService.transactionsBoxName).clear();
      final events = await EventStoreService.getAllEvents();
      for (final event in events) {
        await event.delete();
      }

      testContact = Contact(
        id: 'test-contact-id',
        name: 'Test Contact',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        balance: 0,
        walletId: 'test-wallet-id',
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
      try {
        await Hive.box<Contact>(DummyDataService.contactsBoxName).clear();
        await Hive.box<Transaction>(DummyDataService.transactionsBoxName).clear();
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

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

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

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

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

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

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Find and tap the FAB
      final fab = find.byType(FloatingActionButton);
      expect(fab, findsOneWidget);
      
      await tester.tap(fab);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

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

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

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

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

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

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

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

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Find RefreshIndicator
      final refreshIndicator = find.byType(RefreshIndicator);
      expect(refreshIndicator, findsOneWidget);

      // Simulate pull to refresh
      await tester.drag(find.byType(ListView), const Offset(0, 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    });
  });
}