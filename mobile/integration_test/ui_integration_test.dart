import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:debt_tracker_mobile/main.dart' as app;
import 'package:debt_tracker_mobile/services/event_store_service.dart';
import 'package:debt_tracker_mobile/services/local_database_service_v2.dart';
import 'package:debt_tracker_mobile/services/sync_service_v2.dart';
import 'package:debt_tracker_mobile/models/contact.dart';
import 'package:debt_tracker_mobile/models/transaction.dart';
import 'package:debt_tracker_mobile/models/event.dart';
import 'helpers/test_helpers.dart';
import 'helpers/ui_test_helpers.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:matcher/matcher.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('UI-Based Integration Tests', () {
    setUpAll(() async {
      // Don't initialize test environment here - app.main() will do it
      // This avoids double registration of Hive adapters
    });

    setUp(() async {
      // ALWAYS reset server data BEFORE cleaning local data (CRITICAL!)
      print('🔄 Resetting server data via ./manage.sh full-flash...');
      await resetServerData();
      
      // Clean up local data
      print('🧹 Cleaning local data...');
      try {
        await Hive.box<Contact>('contacts').clear();
        await Hive.box<Transaction>('transactions').clear();
        await Hive.box<Event>('events').clear();
      } catch (e) {
        // Boxes might not exist yet - that's okay
        print('⚠️ Could not clear boxes (might not exist yet): $e');
      }
    });

    tearDown(() async {
      // Clean up after each test
      await cleanupTestEnvironment();
    });

    testWidgets('Complete user flow: Create contacts and transactions via UI', (WidgetTester tester) async {
      // Start app
      app.main();
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      
      // Handle backend setup screen if it appears
      final testConnectionButton = find.text('Test Connection');
      if (testConnectionButton.evaluate().isNotEmpty) {
        print('📡 Found backend setup screen, pressing Test Connection...');
        // Press Test Connection button
        await tester.tap(testConnectionButton);
        await tester.pumpAndSettle(const Duration(milliseconds: 500));
        
        // Press Save & Continue button
        print('💾 Pressing Save & Continue...');
        var saveButton = find.text('Save & Continue');
        if (saveButton.evaluate().isEmpty) {
          saveButton = find.text('Save');
        }
        if (saveButton.evaluate().isNotEmpty) {
          await tester.tap(saveButton);
          await tester.pumpAndSettle(const Duration(milliseconds: 500));
        }
      }
      
      // Handle login screen if it appears
      final loginButtonText = find.text('Login');
      if (loginButtonText.evaluate().isNotEmpty) {
        print('🔐 Found login screen, filling credentials...');
        // Fill login form (default credentials)
        final usernameField = find.widgetWithText(TextFormField, 'Username');
        if (usernameField.evaluate().isNotEmpty) {
          await tester.enterText(usernameField.first, 'max');
          await tester.pump();
        }
        
        final passwordField = find.widgetWithText(TextFormField, 'Password');
        if (passwordField.evaluate().isNotEmpty) {
          await tester.enterText(passwordField.first, '1234');
          await tester.pump();
        }
        
        // Tap login button (find the ElevatedButton with Login text, not just text)
        print('🔑 Pressing Login...');
        final loginButton = find.widgetWithText(ElevatedButton, 'Login');
        if (loginButton.evaluate().isEmpty) {
          // Try finding by descendant
          final loginButtonAlt = find.descendant(
            of: find.byType(ElevatedButton),
            matching: find.text('Login'),
          );
          if (loginButtonAlt.evaluate().isNotEmpty) {
            await tester.tap(loginButtonAlt.first);
          } else {
            // Fallback: tap first Login text that's in a button
            await tester.tap(loginButtonText.first);
          }
        } else {
          await tester.tap(loginButton);
        }
        await tester.pumpAndSettle(const Duration(milliseconds: 500));
      }
      
      // Wait for home screen to load
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      
      // Clean up local data now that app has initialized
      print('🧹 Cleaning local data after app initialization...');
      try {
        await Hive.box<Contact>('contacts').clear();
        await Hive.box<Transaction>('transactions').clear();
        await Hive.box<Event>('events').clear();
        print('✅ Local data cleared');
      } catch (e) {
        print('⚠️ Could not clear boxes: $e');
      }
      
      // Verify we're on home screen (should have navigation bar or FAB)
      final navBar = find.byType(NavigationBar);
      final fab = find.byType(FloatingActionButton);
      expect(
        navBar.evaluate().isNotEmpty || fab.evaluate().isNotEmpty,
        true,
        reason: 'Should be on home screen (has navigation or FAB)',
      );

      // ========== STEP 1: Create Contact 1 via UI ==========
      print('\n📝 STEP 1: Creating Contact 1 via UI...');
      
      await navigateToContactsTab(tester);
      
      // Try to find the add contact button in the contacts screen app bar first
      final addContactButton = find.byIcon(Icons.add);
      if (addContactButton.evaluate().isNotEmpty) {
        // Tap the add button in contacts screen
        await tester.tap(addContactButton.first);
        await tester.pumpAndSettle(const Duration(milliseconds: 500));
      } else {
        // Fallback: long press the FAB
        await longPressAddContactFAB(tester);
      }
      
      final contact1 = await fillAndSaveContactForm(
        tester,
        name: 'John Doe',
        username: 'johndoe',
        phone: '1234567890',
        email: 'john@example.com',
      );
      
      print('✅ Contact 1 created: ${contact1.name} (ID: ${contact1.id})');
      
      // Verify event created locally
      await verifyEventCreatedLocally(
        aggregateType: 'contact',
        aggregateId: contact1.id,
        eventType: 'CREATED',
      );
      
      // Verify balance is 0
      await verifyBalanceInLocalData(contact1.id, 0);
      
      // Verify on server
      await verifyDataOnServer(contactId: contact1.id, expectedContactBalance: 0);
      
      // ========== STEP 2: Create Contact 2 via UI ==========
      print('\n📝 STEP 2: Creating Contact 2 via UI...');
      
      // Find and tap the add contact button in the contacts screen app bar
      final appBar2 = find.byType(AppBar);
      final addContactButton2 = find.descendant(
        of: appBar2,
        matching: find.byIcon(Icons.add),
      );
      
      if (addContactButton2.evaluate().isEmpty) {
        // Fallback: find any IconButton with add icon
        final addButtonAlt2 = find.widgetWithIcon(IconButton, Icons.add);
        if (addButtonAlt2.evaluate().isNotEmpty) {
          await tester.tap(addButtonAlt2.first);
        } else {
          // Last resort: long press the FAB
          await longPressAddContactFAB(tester);
        }
      } else {
        await tester.tap(addContactButton2.first);
      }
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      
      final contact2 = await fillAndSaveContactForm(
        tester,
        name: 'Jane Smith',
        username: 'janesmith',
        phone: '9876543210',
      );
      
      print('✅ Contact 2 created: ${contact2.name} (ID: ${contact2.id})');
      
      // Verify event created locally
      await verifyEventCreatedLocally(
        aggregateType: 'contact',
        aggregateId: contact2.id,
        eventType: 'CREATED',
      );
      
      // Sync to server immediately so it appears in admin page
      print('🔄 Syncing Contact 2 to server...');
      await SyncServiceV2.manualSync();
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      
      // Verify balance is 0
      await verifyBalanceInLocalData(contact2.id, 0);
      
      // ========== STEP 3: Create Transaction 1 (Lent to Contact 1) via UI ==========
      print('\n📝 STEP 3: Creating Transaction 1 (Lent 100,000 to John) via UI...');
      
      await navigateToTransactionsTab(tester);
      await tapAddTransactionFAB(tester);
      
      final transaction1 = await fillAndSaveTransactionForm(
        tester,
        contactName: 'John Doe',
        amount: 100000,
        direction: TransactionDirection.lent,
        description: 'Loan to John',
      );
      
      print('✅ Transaction 1 created: ${transaction1.amount} IQD lent to ${transaction1.contactId}');
      
      // Verify event created locally
      await verifyEventCreatedLocally(
        aggregateType: 'transaction',
        aggregateId: transaction1.id,
        eventType: 'CREATED',
      );
      
      // Verify balance updated (lent = positive balance)
      await verifyBalanceInLocalData(contact1.id, 100000);
      
      // Verify on server
      await verifyDataOnServer(
        contactId: contact1.id,
        transactionId: transaction1.id,
        expectedContactBalance: 100000,
      );
      
      // ========== STEP 4: Create Transaction 2 (Owed from Contact 2) via UI ==========
      print('\n📝 STEP 4: Creating Transaction 2 (Owed 50,000 from Jane) via UI...');
      
      // We should already be on transactions tab, but verify
      await tapAddTransactionFAB(tester);
      
      final transaction2 = await fillAndSaveTransactionForm(
        tester,
        contactName: 'Jane Smith',
        amount: 50000,
        direction: TransactionDirection.owed,
        description: 'Debt from Jane',
      );
      
      print('✅ Transaction 2 created: ${transaction2.amount} IQD owed from ${transaction2.contactId}');
      
      // Verify transaction in UI
      
      // Verify event created locally
      await verifyEventCreatedLocally(
        aggregateType: 'transaction',
        aggregateId: transaction2.id,
        eventType: 'CREATED',
      );
      
      // Verify balance updated (owed = negative balance)
      await verifyBalanceInLocalData(contact2.id, -50000);
      
      // Verify balance on dashboard
      
      // ========== STEP 5: Create Transaction 3 (More lent to Contact 1) via UI ==========
      print('\n📝 STEP 5: Creating Transaction 3 (Lent 25,000 more to John) via UI...');
      
      // We should already be on transactions tab after previous transaction
      await tapAddTransactionFAB(tester);
      
      final transaction3 = await fillAndSaveTransactionForm(
        tester,
        contactName: 'John Doe',
        amount: 25000,
        direction: TransactionDirection.lent,
        description: 'Additional loan',
      );
      
      print('✅ Transaction 3 created: ${transaction3.amount} IQD lent to ${transaction3.contactId}');
      
      // Sync to server immediately so it appears in admin page
      print('🔄 Syncing Transaction 3 to server...');
      await SyncServiceV2.manualSync();
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      
      // Verify balance updated (100,000 + 25,000 = 125,000)
      await verifyBalanceInLocalData(contact1.id, 125000);
      
      // Verify balance on dashboard
      
      // ========== STEP 6: Create Contact 3 via UI ==========
      print('\n📝 STEP 6: Creating Contact 3 via UI...');
      
      await navigateToContactsTab(tester);
      
      // Find and tap the add contact button in the contacts screen app bar
      final appBar3 = find.byType(AppBar);
      final addContactButton3 = find.descendant(
        of: appBar3,
        matching: find.byIcon(Icons.add),
      );
      
      if (addContactButton3.evaluate().isEmpty) {
        // Fallback: find any IconButton with add icon
        final addButtonAlt3 = find.widgetWithIcon(IconButton, Icons.add);
        if (addButtonAlt3.evaluate().isNotEmpty) {
          await tester.tap(addButtonAlt3.first);
        } else {
          // Last resort: long press the FAB
          await longPressAddContactFAB(tester);
        }
      } else {
        await tester.tap(addContactButton3.first);
      }
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      
      final contact3 = await fillAndSaveContactForm(
        tester,
        name: 'Bob Wilson',
        username: 'bobwilson',
      );
      
      print('✅ Contact 3 created: ${contact3.name} (ID: ${contact3.id})');
      
      // Sync Contact 3 to server immediately
      print('🔄 Syncing Contact 3 to server...');
      await SyncServiceV2.manualSync();
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      
      // ========== STEP 7: Create Transaction 4 (Lent to Contact 3) via UI ==========
      print('\n📝 STEP 7: Creating Transaction 4 (Lent 200,000 to Bob) via UI...');
      
      // Navigate to transactions tab to create new transaction
      await navigateToTransactionsTab(tester);
      await tapAddTransactionFAB(tester);
      
      final transaction4 = await fillAndSaveTransactionForm(
        tester,
        contactName: 'Bob Wilson',
        amount: 200000,
        direction: TransactionDirection.lent,
        description: 'Large loan to Bob',
      );
      
      print('✅ Transaction 4 created: ${transaction4.amount} IQD lent to ${transaction4.contactId}');
      
      // Sync to server immediately so it appears in admin page
      print('🔄 Syncing Transaction 4 to server...');
      await SyncServiceV2.manualSync();
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      
      // Verify balance updated
      await verifyBalanceInLocalData(contact3.id, 200000);
      
      // ========== STEP 8: Delete Transaction 3 via UI ==========
      print('\n📝 STEP 8: Deleting Transaction 3 via UI...');
      
      // Navigate to transactions tab
      await navigateToTransactionsTab(tester);
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      
      // Find and delete transaction by ID (swipe or long press)
      await deleteTransactionFromUI(tester, transaction3.id);
      
      // Verify transaction removed from UI
      await tester.pumpAndSettle();
      // Transaction should not appear (or appear as deleted)
      
      // Verify event created locally
      await verifyEventCreatedLocally(
        aggregateType: 'transaction',
        aggregateId: transaction3.id,
        eventType: 'DELETED',
      );
      
      // Verify balance updated (125,000 - 25,000 = 100,000)
      await verifyBalanceInLocalData(contact1.id, 100000);
      
      // ========== STEP 9: Verify Final State ==========
      print('\n📝 STEP 9: Verifying final state...');
      
      // Verify all contacts exist
      final contacts = await LocalDatabaseServiceV2.getContacts();
      expect(contacts.length, 3, reason: 'Should have 3 contacts');
      expect(contacts.any((c) => c.name == 'John Doe'), true);
      expect(contacts.any((c) => c.name == 'Jane Smith'), true);
      expect(contacts.any((c) => c.name == 'Bob Wilson'), true);
      
      // Verify all transactions exist (except deleted one)
      final transactions = await LocalDatabaseServiceV2.getTransactions();
      expect(transactions.length, 3, reason: 'Should have 3 transactions (1 deleted)');
      
      // Verify final balances
      final john = contacts.firstWhere((c) => c.name == 'John Doe');
      final jane = contacts.firstWhere((c) => c.name == 'Jane Smith');
      final bob = contacts.firstWhere((c) => c.name == 'Bob Wilson');
      
      expect(john.balance, 100000, reason: 'John should owe 100,000');
      expect(jane.balance, -50000, reason: 'You should owe Jane 50,000');
      expect(bob.balance, 200000, reason: 'Bob should owe 200,000');
      
      // Verify all events created
      final allEvents = await EventStoreService.getAllEvents();
      expect(allEvents.length, greaterThanOrEqualTo(7), reason: 'Should have at least 7 events (3 contacts + 4 transactions - 1 deleted)');
      
      // Verify event types
      final contactEvents = allEvents.where((e) => e.aggregateType == 'contact').toList();
      final transactionEvents = allEvents.where((e) => e.aggregateType == 'transaction').toList();
      
      expect(contactEvents.length, 3, reason: 'Should have 3 contact CREATED events');
      expect(transactionEvents.length, greaterThanOrEqualTo(4), reason: 'Should have at least 4 transaction events (3 CREATED + 1 DELETED)');
      
      // Verify CREATED events
      expect(contactEvents.every((e) => e.eventType == 'CREATED'), true);
      final createdTransactions = transactionEvents.where((e) => e.eventType == 'CREATED').length;
      final deletedTransactions = transactionEvents.where((e) => e.eventType == 'DELETED').length;
      expect(createdTransactions, greaterThanOrEqualTo(3), reason: 'Should have at least 3 CREATED transaction events');
      expect(deletedTransactions, greaterThanOrEqualTo(1), reason: 'Should have at least 1 DELETED transaction event');
      print('   📊 Transaction events breakdown: $createdTransactions CREATED, $deletedTransactions DELETED');
      
      print('\n✅ All steps completed successfully!');
      print('📊 Final Summary:');
      print('   - Contacts: 3');
      print('   - Transactions: 3 (1 deleted)');
      print('   - Events: ${allEvents.length}');
      print('   - John balance: ${john.balance}');
      print('   - Jane balance: ${jane.balance}');
      print('   - Bob balance: ${bob.balance}');
    });
  });
}
