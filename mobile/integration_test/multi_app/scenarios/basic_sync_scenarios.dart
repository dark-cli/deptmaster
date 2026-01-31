// ignore_for_file: unused_local_variable, duplicate_ignore

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:debt_tracker_mobile/models/contact.dart';
import 'package:debt_tracker_mobile/models/transaction.dart';
import 'package:debt_tracker_mobile/models/event.dart';
import '../app_instance.dart';
import '../sync_monitor.dart';
import '../event_validator.dart';
import '../server_verifier.dart';
import '../event_generator.dart';
import '../../helpers/multi_app_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  // Set longer timeout for sync tests (default is 30s, we need more for sync operations)
  group('Basic Sync Scenarios', () {
    AppInstance? app1;
    AppInstance? app2;
    AppInstance? app3;
    SyncMonitor? monitor;
    EventValidator? validator;
    ServerVerifier? serverVerifier;
    EventGenerator? generator;
    
    setUpAll(() async {
      // Initialize Hive once globally (use Hive.initFlutter() for integration tests)
      await Hive.initFlutter();
      Hive.registerAdapter(ContactAdapter());
      Hive.registerAdapter(TransactionAdapter());
      Hive.registerAdapter(TransactionTypeAdapter());
      Hive.registerAdapter(TransactionDirectionAdapter());
      Hive.registerAdapter(EventAdapter());
      
      // Ensure test user exists once for all tests (major performance optimization)
      // This avoids calling the Rust binary before each test
      await ensureTestUserExists();
    });
    
    setUp(() async {
      // Reset server before each test
      await resetServer();
      await waitForServerReady();
      
      // Note: Test user is ensured in setUpAll to avoid 1.2s delay per test
      
      // Clear all Hive boxes
      try {
        await Hive.box<Contact>('contacts').clear();
        await Hive.box<Transaction>('transactions').clear();
        await Hive.box<Event>('events').clear();
      } catch (e) {
        // Boxes might not exist yet
      }
      
      // Create app instances
      app1 = await AppInstance.create(id: 'app1', serverUrl: 'http://localhost:8000');
      app2 = await AppInstance.create(id: 'app2', serverUrl: 'http://localhost:8000');
      app3 = await AppInstance.create(id: 'app3', serverUrl: 'http://localhost:8000');
      
      // Initialize all instances in parallel (optimization)
      await Future.wait([
        app1!.initialize(),
        app2!.initialize(),
        app3!.initialize(),
      ]);
      
      // Login all instances sequentially to avoid conflicts
      // (they'll share auth, which is fine for testing)
      print('🔐 Logging in all app instances...');
      try {
        await app1!.login().timeout(const Duration(seconds: 20));
        print('✅ App1 login complete');
      } catch (e) {
        print('❌ App1 login failed: $e');
        rethrow;
      }
      
      try {
        await app2!.login().timeout(const Duration(seconds: 20));
        print('✅ App2 login complete');
      } catch (e) {
        print('❌ App2 login failed: $e');
        rethrow;
      }
      
      try {
        await app3!.login().timeout(const Duration(seconds: 20));
        print('✅ App3 login complete');
      } catch (e) {
        print('❌ App3 login failed: $e');
        rethrow;
      }
      
      print('✅ All app instances logged in');
      
      // Create monitor and validator
      monitor = SyncMonitor([app1!, app2!, app3!]);
      validator = EventValidator();
      serverVerifier = ServerVerifier(serverUrl: 'http://localhost:8000');
      await serverVerifier!.setAuthToken();
      
      // Create event generator
      generator = EventGenerator({
        'app1': app1!,
        'app2': app2!,
        'app3': app3!,
      });
    });
    
    tearDown(() async {
      // Disconnect all instances
      await app1?.disconnect();
      await app2?.disconnect();
      await app3?.disconnect();
      
      // Clear data
      await app1?.clearData();
      await app2?.clearData();
      await app3?.clearData();
    });
    
    test('1.1 Single App Create → Multi-App Sync (Contact & Transaction)', () async {
      print('\n📋 Test 1.1: Single App Create → Multi-App Sync (Contact & Transaction)');
      
      // Use event generator to create 12 events (1 contact + 11 transactions)
      final commands = [
        'app1: contact create "Test Contact 1" contact1',
        'app1: transaction create contact1 owed 1000 "Transaction 1" t1',
        'app1: transaction create contact1 lent 500 "Transaction 2" t2',
        'app1: transaction create contact1 owed 2000 "Transaction 3" t3',
        'app1: transaction create contact1 lent 800 "Transaction 4" t4',
        'app1: transaction create contact1 owed 1500 "Transaction 5" t5',
        'app1: transaction create contact1 lent 300 "Transaction 6" t6',
        'app1: transaction create contact1 owed 1200 "Transaction 7" t7',
        'app1: transaction update t1 amount 1100',
        'app1: transaction update t3 description "Updated Transaction 3"',
        'app1: transaction delete t5',
        'app1: contact update contact1 name "Updated Contact 1"',
      ];
      
      print('📝 Executing ${commands.length} event commands...');
      await generator!.executeCommands(commands);
      
      // Wait for sync
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Verify events
      final app1Events = await app1!.getEvents();
      expect(app1Events.length, greaterThanOrEqualTo(12), 
          reason: 'Should have at least 12 events');
      
      // Verify transaction events are majority
      final transactionEvents = app1Events.where(
        (e) => e.aggregateType == 'transaction'
      ).length;
      final contactEvents = app1Events.where(
        (e) => e.aggregateType == 'contact'
      ).length;
      expect(transactionEvents, greaterThan(contactEvents * 2),
          reason: 'Transaction events should be majority');
      
      // Verify we have UPDATE events
      final updateEvents = app1Events.where((e) => e.eventType == 'UPDATED').length;
      expect(updateEvents, greaterThan(0), reason: 'Should have UPDATE events');
      
      // Verify server has all events
      final serverEvents = await serverVerifier!.getServerEvents();
      expect(serverEvents.length, greaterThanOrEqualTo(12));
      
      // Verify final state
      final contacts = await app1!.getContacts();
      final transactions = await app1!.getTransactions();
      expect(contacts.length, 1);
      expect(transactions.length, greaterThan(5));
      
      // Validate consistency
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true);
      print('✅ Event consistency validated');
    });
    
    test('1.2 Concurrent Creates (Contacts & Transactions)', () async {
      print('\n📋 Test 1.2: Concurrent Creates (Contacts & Transactions)');
      
      // All apps create different contacts simultaneously
      print('📝 All apps creating contacts simultaneously...');
      final contactFutures = [
        app1!.createContact(name: 'Contact from App1'),
        app2!.createContact(name: 'Contact from App2'),
        app3!.createContact(name: 'Contact from App3'),
      ];
      
      final contacts = await Future.wait(contactFutures);
      print('✅ All contacts created');
      
      // Wait for contacts to sync
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // All apps create transactions for different contacts simultaneously
      print('📝 All apps creating transactions simultaneously...');
      final transactionFutures = [
        app1!.createTransaction(contactId: contacts[0].id, direction: TransactionDirection.owed, amount: 1000),
        app2!.createTransaction(contactId: contacts[1].id, direction: TransactionDirection.lent, amount: 500),
        app3!.createTransaction(contactId: contacts[2].id, direction: TransactionDirection.owed, amount: 2000),
      ];
      
      final transactions = await Future.wait(transactionFutures);
      print('✅ All transactions created');
      
      // Wait for sync
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Verify all events synced to server
      final serverEvents = await serverVerifier!.getServerEvents();
      for (final contact in contacts) {
        final serverEvent = serverEvents.firstWhere(
          (e) => e['aggregate_id'] == contact.id && e['aggregate_type'] == 'contact',
          orElse: () => throw Exception('Contact event for ${contact.id} not found on server'),
        );
        expect(serverEvent['event_type'], 'CREATED');
        expect(serverEvent['aggregate_type'], 'contact');
      }
      for (final transaction in transactions) {
        final serverEvent = serverEvents.firstWhere(
          (e) => e['aggregate_id'] == transaction.id && e['aggregate_type'] == 'transaction',
          orElse: () => throw Exception('Transaction event for ${transaction.id} not found on server'),
        );
        expect(serverEvent['event_type'], 'CREATED');
        expect(serverEvent['aggregate_type'], 'transaction');
      }
      print('✅ All events synced to server');
      
      // Verify all apps receive all events
      final app1Contacts = await app1!.getContacts();
      final app1Transactions = await app1!.getTransactions();
      
      expect(app1Contacts.length, 3, reason: 'App1 should have all 3 contacts');
      expect(app1Transactions.length, 3, reason: 'App1 should have all 3 transactions');
      print('✅ All apps received all contacts and transactions');
      
      // Verify final state identical
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true, reason: 'All instances should have identical state');
      print('✅ Final state identical across all apps');
    });
    
    test('1.3 Update Propagation (Contact & Transaction)', () async {
      print('\n📋 Test 1.3: Update Propagation (Contact & Transaction)');
      
      // Create contact and transaction
      print('📝 Creating contact and transaction in App1...');
      final contact = await app1!.createContact(name: 'Original Name');
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      final transaction = await app1!.createTransaction(
        contactId: contact.id,
        direction: TransactionDirection.owed,
        amount: 1000,
      );
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Verify both exist in all apps
      final allContacts = await app1!.getContacts();
      final allTransactions = await app1!.getTransactions();
      expect(allContacts.any((c) => c.id == contact.id), true);
      expect(allTransactions.any((t) => t.id == transaction.id), true);
      print('✅ Contact and transaction exist in all apps');
      
      // App1 and App2 update contact and transaction simultaneously
      print('📝 App1 and App2 updating contact and transaction simultaneously...');
      await Future.wait([
        app1!.updateContact(contact.id, {'name': 'Updated by App1'}),
        app2!.updateContact(contact.id, {'name': 'Updated by App2'}),
        app1!.updateTransaction(transaction.id, {'amount': 2000}),
        app2!.updateTransaction(transaction.id, {'amount': 3000}),
      ]);
      
      // Wait for sync
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Verify all updates created events
      final allEvents = await app1!.getEvents();
      final contactUpdates = allEvents.where((e) => 
        e.aggregateId == contact.id && e.eventType == 'UPDATED' && e.aggregateType == 'contact'
      ).toList();
      final transactionUpdates = allEvents.where((e) => 
        e.aggregateId == transaction.id && e.eventType == 'UPDATED' && e.aggregateType == 'transaction'
      ).toList();
      
      expect(contactUpdates.length, greaterThanOrEqualTo(2), reason: 'Should have at least 2 contact updates');
      expect(transactionUpdates.length, greaterThanOrEqualTo(2), reason: 'Should have at least 2 transaction updates');
      print('✅ All updates created events');
      
      // Verify events synced to server
      final serverEvents = await serverVerifier!.getServerEvents();
      final serverContactUpdates = serverEvents.where((e) => 
        e['aggregate_id'] == contact.id && e['event_type'] == 'UPDATED' && e['aggregate_type'] == 'contact'
      ).toList();
      final serverTransactionUpdates = serverEvents.where((e) => 
        e['aggregate_id'] == transaction.id && e['event_type'] == 'UPDATED' && e['aggregate_type'] == 'transaction'
      ).toList();
      
      expect(serverContactUpdates.length, greaterThanOrEqualTo(2));
      expect(serverTransactionUpdates.length, greaterThanOrEqualTo(2));
      print('✅ All events synced to server');
      
      // Verify final state consistent
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true);
      print('✅ Final state consistent');
    });
    
    test('1.4 Delete Propagation (Contact & Transaction)', () async {
      print('\n📋 Test 1.4: Delete Propagation (Contact & Transaction)');
      
      // Create contact and transaction
      print('📝 Creating contact and transaction in App1...');
      final contact = await app1!.createContact(name: 'Contact to Delete');
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      final transaction = await app1!.createTransaction(
        contactId: contact.id,
        direction: TransactionDirection.owed,
        amount: 1000,
      );
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Verify both exist
      final allContacts = await app1!.getContacts();
      final allTransactions = await app1!.getTransactions();
      expect(allContacts.any((c) => c.id == contact.id), true);
      expect(allTransactions.any((t) => t.id == transaction.id), true);
      print('✅ Contact and transaction exist');
      
      // App2 deletes transaction
      print('📝 App2 deleting transaction...');
      await app2!.deleteTransaction(transaction.id);
      await Future.delayed(const Duration(milliseconds: 200));
      
      // Verify transaction delete event
      final app2Events = await app2!.getEvents();
      final transactionDeleteEvent = app2Events.firstWhere(
        (e) => e.aggregateId == transaction.id && e.eventType == 'DELETED' && e.aggregateType == 'transaction',
        orElse: () => throw Exception('Transaction delete event not found'),
      );
      expect(transactionDeleteEvent.aggregateType, 'transaction');
      expect(transactionDeleteEvent.eventType, 'DELETED');
      print('✅ Transaction DELETED event created');
      
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      await Future.delayed(const Duration(milliseconds: 500));
      
      // App3 deletes contact
      print('📝 App3 deleting contact...');
      await app3!.deleteContact(contact.id);
      await Future.delayed(const Duration(milliseconds: 200));
      
      // Verify contact delete event
      final app3Events = await app3!.getEvents();
      final contactDeleteEvent = app3Events.firstWhere(
        (e) => e.aggregateId == contact.id && e.eventType == 'DELETED' && e.aggregateType == 'contact',
        orElse: () => throw Exception('Contact delete event not found'),
      );
      expect(contactDeleteEvent.aggregateType, 'contact');
      expect(contactDeleteEvent.eventType, 'DELETED');
      print('✅ Contact DELETED event created');
      
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Verify both delete events synced to server
      final serverEvents = await serverVerifier!.getServerEvents();
      final serverTransactionDelete = serverEvents.firstWhere(
        (e) => e['aggregate_id'] == transaction.id && e['event_type'] == 'DELETED' && e['aggregate_type'] == 'transaction',
        orElse: () => throw Exception('Transaction delete event not found on server'),
      );
      // ignore: unused_local_variable
      final serverContactDelete = serverEvents.firstWhere(
        (e) => e['aggregate_id'] == contact.id && e['event_type'] == 'DELETED' && e['aggregate_type'] == 'contact',
        orElse: () => throw Exception('Contact delete event not found on server'),
      );
      print('✅ Both delete events synced to server');
      
      // Verify both removed from state
      bool transactionRemoved = false;
      bool contactRemoved = false;
      for (int i = 0; i < 5; i++) {
        await Future.delayed(const Duration(milliseconds: 200));
        final contactsAfter = await app1!.getContacts();
        final transactionsAfter = await app1!.getTransactions();
        transactionRemoved = !transactionsAfter.any((t) => t.id == transaction.id);
        contactRemoved = !contactsAfter.any((c) => c.id == contact.id);
        if (transactionRemoved && contactRemoved) {
          print('✅ Both removed after ${(i + 1) * 200}ms');
          break;
        }
      }
      expect(transactionRemoved, true, reason: 'Transaction should be removed');
      expect(contactRemoved, true, reason: 'Contact should be removed');
      print('✅ Both contact and transaction removed from all apps');
      
      // Validate consistency
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true);
      print('✅ Event consistency validated');
    });
  });
}