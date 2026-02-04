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
      
      // Ensure admin user exists (used by createUniqueTestUserAndWallet to create users via API)
      await ensureTestUserExists();
    });
    
    setUp(() async {
      await waitForServerReady();
      
      // Each test gets its own user and wallet for isolation
      final creds = await createUniqueTestUserAndWallet();
      
      // Clear local Hive boxes (these are namespaced per user/wallet, but clear defaults for safety)
      try {
        await Hive.box<Contact>('contacts').clear();
        await Hive.box<Transaction>('transactions').clear();
        await Hive.box<Event>('events').clear();
      } catch (e) {
        // Boxes might not exist yet
      }
      
      // Create app instances with this test's unique user and wallet
      app1 = await AppInstance.create(
        id: 'app1',
        serverUrl: 'http://localhost:8000',
        username: creds['email']!,
        password: creds['password']!,
        walletId: creds['walletId'],
      );
      app2 = await AppInstance.create(
        id: 'app2',
        serverUrl: 'http://localhost:8000',
        username: creds['email']!,
        password: creds['password']!,
        walletId: creds['walletId'],
      );
      app3 = await AppInstance.create(
        id: 'app3',
        serverUrl: 'http://localhost:8000',
        username: creds['email']!,
        password: creds['password']!,
        walletId: creds['walletId'],
      );
      
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
    
    test('Single App Create → Multi-App Sync (Contact & Transaction)', () async {
      print('\n📋 Test: Single App Create → Multi-App Sync (Contact & Transaction)');
      
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
      // Note: When transaction delete happens within 5 seconds, an UNDO event is created instead of removing the event
      final app1Events = await app1!.getEvents();
      expect(app1Events.length, greaterThanOrEqualTo(12), 
          reason: 'Should have at least 12 events (UNDO events are created instead of removing events)');
      
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
    
    test('Concurrent Creates (Contacts & Transactions)', () async {
      print('\n📋 Test: Concurrent Creates (Contacts & Transactions)');
      
      // Use event generator to create 15 events (3 contacts + 12 transactions)
      final commands = [
        'app1: contact create "Contact from App1" contact1',
        'app2: contact create "Contact from App2" contact2',
        'app3: contact create "Contact from App3" contact3',
        'app1: transaction create contact1 owed 1000 "T1" t1',
        'app1: transaction create contact1 lent 500 "T2" t2',
        'app2: transaction create contact2 lent 800 "T3" t3',
        'app2: transaction create contact2 owed 1200 "T4" t4',
        'app3: transaction create contact3 owed 2000 "T5" t5',
        'app3: transaction create contact3 lent 600 "T6" t6',
        'app1: transaction create contact1 owed 1500 "T7" t7',
        'app2: transaction create contact2 lent 900 "T8" t8',
        'app3: transaction create contact3 owed 1800 "T9" t9',
        'app1: transaction update t1 amount 1100',
        'app2: transaction update t3 description "Updated T3"',
        'app3: transaction delete t5',
      ];
      
      print('📝 Executing ${commands.length} event commands...');
      await generator!.executeCommands(commands);
      
      // Wait for sync
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Verify events
      // Note: When transaction delete happens within 5 seconds, an UNDO event is created instead of removing the event
      final app1Events = await app1!.getEvents();
      expect(app1Events.length, greaterThanOrEqualTo(15), 
          reason: 'Should have at least 15 events (UNDO events are created instead of removing events)');
      
      // Verify transaction events are majority
      final transactionEvents = app1Events.where(
        (e) => e.aggregateType == 'transaction'
      ).length;
      expect(transactionEvents, greaterThan(3 * 2), reason: 'Transaction events should be majority');
      
      // Verify all apps receive all events
      final app1Contacts = await app1!.getContacts();
      final app1Transactions = await app1!.getTransactions();
      expect(app1Contacts.length, 3);
      expect(app1Transactions.length, greaterThan(5));
      
      // Validate consistency
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true);
      print('✅ Event consistency validated');
    });
    
    test('Update Propagation (Contact & Transaction)', () async {
      print('\n📋 Test: Update Propagation (Contact & Transaction)');
      
      // Use event generator to create 18 events (1 contact + 10 transactions + 7 updates)
      final commands = [
        'app1: contact create "Original Name" contact1',
        'app1: transaction create contact1 owed 1000 "T1" t1',
        'app1: transaction create contact1 lent 500 "T2" t2',
        'app1: transaction create contact1 owed 2000 "T3" t3',
        'app1: transaction create contact1 lent 800 "T4" t4',
        'app1: transaction create contact1 owed 1500 "T5" t5',
        'app2: transaction create contact1 lent 600 "T6" t6',
        'app2: transaction create contact1 owed 1200 "T7" t7',
        'app3: transaction create contact1 lent 900 "T8" t8',
        'app3: transaction create contact1 owed 1800 "T9" t9',
        'app3: transaction create contact1 lent 400 "T10" t10',
        // Multiple updates from different apps
        'app1: contact update contact1 name "Updated by App1"',
        'app2: contact update contact1 name "Updated by App2"',
        'app1: transaction update t1 amount 2000',
        'app2: transaction update t1 amount 3000',
        'app1: transaction update t3 amount 2200',
        'app2: transaction update t5 description "Updated T5"',
        'app3: transaction update t7 amount 1300',
      ];
      
      print('📝 Executing ${commands.length} event commands...');
      await generator!.executeCommands(commands);
      
      // Wait for sync
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Verify events
      final allEvents = await app1!.getEvents();
      expect(allEvents.length, greaterThanOrEqualTo(18));
      
      // Verify we have UPDATE events
      final updateEvents = allEvents.where((e) => e.eventType == 'UPDATED').length;
      expect(updateEvents, greaterThanOrEqualTo(7), reason: 'Should have at least 7 update events');
      
      // Verify transaction events are majority
      final transactionEvents = allEvents.where(
        (e) => e.aggregateType == 'transaction'
      ).length;
      expect(transactionEvents, greaterThan(10), reason: 'Transaction events should be majority');
      
      // Verify events synced to server
      final serverEvents = await serverVerifier!.getServerEvents();
      expect(serverEvents.length, greaterThanOrEqualTo(18));
      
      // Verify final state consistent
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true);
      print('✅ Final state consistent');
    });
    
    test('Delete Propagation (Contact & Transaction)', () async {
      print('\n📋 Test: Delete Propagation (Contact & Transaction)');
      
      // Use event generator to create 16 events (1 contact + 12 transactions + 3 deletes)
      final commands = [
        'app1: contact create "Contact to Delete" contact1',
        'app1: transaction create contact1 owed 1000 "T1" t1',
        'app1: transaction create contact1 lent 500 "T2" t2',
        'app1: transaction create contact1 owed 2000 "T3" t3',
        'app1: transaction create contact1 lent 800 "T4" t4',
        'app1: transaction create contact1 owed 1500 "T5" t5',
        'app2: transaction create contact1 lent 600 "T6" t6',
        'app2: transaction create contact1 owed 1200 "T7" t7',
        'app3: transaction create contact1 lent 900 "T8" t8',
        'app3: transaction create contact1 owed 1800 "T9" t9',
        'app3: transaction create contact1 lent 400 "T10" t10',
        'app1: transaction create contact1 owed 1100 "T11" t11',
        'app2: transaction create contact1 lent 700 "T12" t12',
        // Deletes from different apps
        'app2: transaction delete t1',
        'app3: transaction delete t5',
        'app3: contact delete contact1',
      ];
      
      print('📝 Executing ${commands.length} event commands...');
      await generator!.executeCommands(commands);
      
      // Wait for sync
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Verify events
      // Note: When transaction delete happens within 5 seconds, an UNDO event is created instead of removing the event
      final allEvents = await app1!.getEvents();
      expect(allEvents.length, greaterThanOrEqualTo(16), 
          reason: 'Should have at least 16 events (UNDO events are created instead of removing events)');
      
      // Verify we have DELETE events (or transactions were undone if within 5 seconds)
      final deleteEvents = allEvents.where((e) => e.eventType == 'DELETED').length;
      // Note: If deletes happen within 5 seconds, they might undo instead of creating DELETE events
      print('📊 Delete events: $deleteEvents');
      
      // Verify transaction events are majority
      final transactionEvents = allEvents.where(
        (e) => e.aggregateType == 'transaction'
      ).length;
      expect(transactionEvents, greaterThan(10), reason: 'Transaction events should be majority');
      
      // Verify final state - contact should be deleted
      final contactsAfter = await app1!.getContacts();
      final contactRemoved = !contactsAfter.any((c) => c.name == 'Contact to Delete');
      expect(contactRemoved, true, reason: 'Contact should be removed');
      
      // Validate consistency
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true);
      print('✅ Event consistency validated');
    });
  });
}