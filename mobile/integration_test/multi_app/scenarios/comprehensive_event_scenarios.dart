// ignore_for_file: unused_local_variable

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
  
  group('Comprehensive Event Type Scenarios', () {
    AppInstance? app1;
    AppInstance? app2;
    AppInstance? app3;
    SyncMonitor? monitor;
    EventValidator? validator;
    ServerVerifier? serverVerifier;
    EventGenerator? generator;
    
    setUpAll(() async {
      await Hive.initFlutter();
      Hive.registerAdapter(ContactAdapter());
      Hive.registerAdapter(TransactionAdapter());
      Hive.registerAdapter(TransactionTypeAdapter());
      Hive.registerAdapter(TransactionDirectionAdapter());
      Hive.registerAdapter(EventAdapter());
      
      await ensureTestUserExists();
    });
    
    setUp(() async {
      await waitForServerReady();
      final creds = await createUniqueTestUserAndWallet();
      
      try {
        await Hive.box<Contact>('contacts').clear();
        await Hive.box<Transaction>('transactions').clear();
        await Hive.box<Event>('events').clear();
      } catch (e) {
        // Boxes might not exist yet
      }
      
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
      
      await Future.wait([
        app1!.initialize(),
        app2!.initialize(),
        app3!.initialize(),
      ]);
      
      await app1!.login().timeout(const Duration(seconds: 20));
      await app2!.login().timeout(const Duration(seconds: 20));
      await app3!.login().timeout(const Duration(seconds: 20));
      
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
      await app1?.disconnect();
      await app2?.disconnect();
      await app3?.disconnect();
      
      await app1?.clearData();
      await app2?.clearData();
      await app3?.clearData();
    });
    
    test('Contact Event Types: CREATED, UPDATED, DELETED', () async {
      print('\n📋 Test: Contact Event Types - CREATED, UPDATED, DELETED');
      
      // Use event generator to create 15 events (3 contacts + 12 transactions) with all event types
      final commands = [
        'app1: contact create "Test Contact 1" contact1',
        'app1: contact create "Test Contact 2" contact2',
        'app1: contact create "Test Contact 3" contact3',
        'app1: transaction create contact1 owed 1000 "T1" t1',
        'app1: transaction create contact1 lent 500 "T2" t2',
        'app1: transaction create contact2 owed 2000 "T3" t3',
        'app1: transaction create contact2 lent 800 "T4" t4',
        'app1: transaction create contact3 owed 1500 "T5" t5',
        'app1: transaction create contact3 lent 600 "T6" t6',
        // Updates (UPDATED events)
        'app2: contact update contact1 name "Updated Name 1"',
        'app2: contact update contact2 name "Updated Name 2"',
        'app1: transaction update t1 amount 1100',
        'app1: transaction update t3 description "Updated T3"',
        // Deletes (DELETED events)
        'app3: contact delete contact3',
        'app1: transaction delete t5',
      ];
      
      print('📝 Executing ${commands.length} event commands...');
      await generator!.executeCommands(commands);
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Verify all event types exist
      final app1Events = await app1!.getEvents();
      final createdEvents = app1Events.where((e) => e.eventType == 'CREATED').toList();
      final updatedEvents = app1Events.where((e) => e.eventType == 'UPDATED').toList();
      final deletedEvents = app1Events.where((e) => e.eventType == 'DELETED').toList();
      final undoEvents = app1Events.where((e) => e.eventType == 'UNDO').toList();
      
      expect(createdEvents.length, greaterThanOrEqualTo(9), reason: 'Should have CREATED events');
      expect(updatedEvents.length, greaterThanOrEqualTo(4), reason: 'Should have UPDATED events');
      // Note: Transaction deletes within 5 seconds create UNDO events, not DELETED events
      // Also, deleting a contact removes its transactions silently (no DELETED events for them)
      expect(deletedEvents.length + undoEvents.length, greaterThanOrEqualTo(1), reason: 'Should have at least 1 DELETED or UNDO event');
      
      // Verify contact event types
      final contactCreated = app1Events.where((e) => e.aggregateType == 'contact' && e.eventType == 'CREATED').toList();
      final contactUpdated = app1Events.where((e) => e.aggregateType == 'contact' && e.eventType == 'UPDATED').toList();
      final contactDeleted = app1Events.where((e) => e.aggregateType == 'contact' && e.eventType == 'DELETED').toList();
      
      expect(contactCreated.length, 3, reason: 'Should have 3 contact CREATED events');
      expect(contactUpdated.length, 2, reason: 'Should have 2 contact UPDATED events');
      expect(contactDeleted.length, 1, reason: 'Should have 1 contact DELETED event');
      
      print('✅ All contact event types verified: CREATED, UPDATED, DELETED');
      
      // Verify all events on server
      final serverEvents = await serverVerifier!.getServerEvents();
      expect(serverEvents.length, greaterThanOrEqualTo(15));
      
      final serverContactEvents = serverEvents.where((e) => e['aggregate_type'] == 'contact').toList();
      final serverEventTypes = serverContactEvents.map((e) => e['event_type'] as String).toSet();
      expect(serverEventTypes.contains('CREATED'), true);
      expect(serverEventTypes.contains('UPDATED'), true);
      expect(serverEventTypes.contains('DELETED'), true);
      print('✅ All contact event types verified on server');
      
      // Verify consistency
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true);
      print('✅ Event consistency validated');
    });
    
    test('Transaction Event Types: CREATED, UPDATED, DELETED', () async {
      print('\n📋 Test: Transaction Event Types - CREATED, UPDATED, DELETED');
      
      // Use event generator to create 18 events (1 contact + 17 transactions) with all transaction event types
      final commands = [
        'app1: contact create "Contact for Transaction" contact1',
        'app1: transaction create contact1 owed 1000 "T1" t1',
        'app1: transaction create contact1 lent 500 "T2" t2',
        'app1: transaction create contact1 owed 2000 "T3" t3',
        'app1: transaction create contact1 lent 800 "T4" t4',
        'app1: transaction create contact1 owed 1500 "T5" t5',
        'app1: transaction create contact1 lent 600 "T6" t6',
        'app1: transaction create contact1 owed 1200 "T7" t7',
        'app1: transaction create contact1 lent 900 "T8" t8',
        'app1: transaction create contact1 owed 1800 "T9" t9',
        'app1: transaction create contact1 lent 400 "T10" t10',
        // Updates (UPDATED events)
        'app2: transaction update t1 amount 2000',
        'app2: transaction update t2 description "Updated T2"',
        'app2: transaction update t3 amount 2200',
        'app2: transaction update t4 description "Updated T4"',
        // Deletes (DELETED events)
        'app3: transaction delete t5',
        'app3: transaction delete t6',
        'app3: transaction delete t7',
      ];
      
      print('📝 Executing ${commands.length} event commands...');
      await generator!.executeCommands(commands);
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Verify all transaction event types exist
      final app1Events = await app1!.getEvents();
      final transactionCreated = app1Events.where((e) => e.aggregateType == 'transaction' && e.eventType == 'CREATED').toList();
      final transactionUpdated = app1Events.where((e) => e.aggregateType == 'transaction' && e.eventType == 'UPDATED').toList();
      final transactionDeleted = app1Events.where((e) => e.aggregateType == 'transaction' && e.eventType == 'DELETED').toList();
      final transactionUndo = app1Events.where((e) => e.aggregateType == 'transaction' && e.eventType == 'UNDO').toList();
      
      expect(transactionCreated.length, greaterThanOrEqualTo(10), reason: 'Should have multiple transaction CREATED events');
      expect(transactionUpdated.length, greaterThanOrEqualTo(4), reason: 'Should have multiple transaction UPDATED events');
      // Note: Transaction deletes within 5 seconds create UNDO events, not DELETED events
      expect(transactionDeleted.length + transactionUndo.length, greaterThanOrEqualTo(3), reason: 'Should have multiple transaction DELETED or UNDO events');
      
      print('✅ All transaction event types verified: CREATED, UPDATED, DELETED');
      
      // Verify all events on server
      final serverEvents = await serverVerifier!.getServerEvents();
      final serverTransactionEvents = serverEvents.where((e) => e['aggregate_type'] == 'transaction').toList();
      final serverEventTypes = serverTransactionEvents.map((e) => e['event_type'] as String).toSet();
      expect(serverEventTypes.contains('CREATED'), true);
      expect(serverEventTypes.contains('UPDATED'), true);
      // Note: Transaction deletes within 5 seconds create UNDO events, not DELETED events
      expect(serverEventTypes.contains('DELETED') || serverEventTypes.contains('UNDO'), true);
      print('✅ All transaction event types verified on server');
      
      // Verify consistency
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true);
      print('✅ Event consistency validated');
    });
    
    test('Mixed Operations: Contacts and Transactions', () async {
      print('\n📋 Test: Mixed Operations - Contacts and Transactions');
      
      // Use event generator to create 20 events (2 contacts + 18 transactions) with mixed operations
      final commands = [
        'app1: contact create "Contact 1" contact1',
        'app1: contact create "Contact 2" contact2',
        'app2: transaction create contact1 owed 1000 "T1" t1',
        'app2: transaction create contact1 lent 500 "T2" t2',
        'app2: transaction create contact1 owed 2000 "T3" t3',
        'app2: transaction create contact2 lent 800 "T4" t4',
        'app2: transaction create contact2 owed 1200 "T5" t5',
        'app3: transaction create contact1 lent 600 "T6" t6',
        'app3: transaction create contact1 owed 1500 "T7" t7',
        'app3: transaction create contact2 lent 900 "T8" t8',
        'app3: transaction create contact2 owed 1800 "T9" t9',
        'app1: transaction create contact1 lent 400 "T10" t10',
        'app1: transaction create contact2 owed 1100 "T11" t11',
        // Updates
        'app3: contact update contact1 name "Updated Contact 1"',
        'app3: transaction update t1 amount 1500',
        'app1: transaction update t3 description "Updated T3"',
        'app2: transaction update t5 amount 1300',
        // Deletes
        'app1: transaction delete t6',
        'app2: transaction delete t8',
        'app3: transaction create contact1 owed 1300 "T12" t12',
      ];
      
      print('📝 Executing ${commands.length} mixed operation commands...');
      await generator!.executeCommands(commands);
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Verify all event types exist
      final allEvents = await app1!.getEvents();
      final contactEvents = allEvents.where((e) => e.aggregateType == 'contact').toList();
      final transactionEvents = allEvents.where((e) => e.aggregateType == 'transaction').toList();
      
      expect(contactEvents.length, greaterThan(2), reason: 'Should have contact events');
      expect(transactionEvents.length, greaterThan(15), reason: 'Should have transaction events');
      
      final contactEventTypes = contactEvents.map((e) => e.eventType).toSet();
      final transactionEventTypes = transactionEvents.map((e) => e.eventType).toSet();
      
      expect(contactEventTypes.contains('CREATED'), true);
      expect(contactEventTypes.contains('UPDATED'), true);
      expect(transactionEventTypes.contains('CREATED'), true);
      expect(transactionEventTypes.contains('UPDATED'), true);
      // Note: Transaction deletes within 5 seconds create UNDO events, not DELETED events
      expect(transactionEventTypes.contains('DELETED') || transactionEventTypes.contains('UNDO'), true);
      
      print('✅ Mixed operations verified: ${contactEvents.length} contact events, ${transactionEvents.length} transaction events');
      
      // Verify on server
      final serverEvents = await serverVerifier!.getServerEvents();
      expect(serverEvents.length, greaterThanOrEqualTo(20));
      print('✅ Mixed operations verified on server');
      
      // Verify consistency
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true);
      print('✅ Event consistency validated');
    });
    
    test('Concurrent Mixed Operations', () async {
      print('\n📋 Test: Concurrent Mixed Operations');
      
      // Use event generator to create 25 concurrent events (3 contacts + 22 transactions) across all apps
      final commands = [
        'app1: contact create "Contact from App1" contact1',
        'app2: contact create "Contact from App2" contact2',
        'app3: contact create "Contact from App3" contact3',
        'app1: transaction create contact1 owed 1000 "T1" t1',
        'app1: transaction create contact2 lent 500 "T2" t2',
        'app2: transaction create contact2 owed 2000 "T3" t3',
        'app2: transaction create contact3 lent 750 "T4" t4',
        'app3: transaction create contact3 owed 3000 "T5" t5',
        'app3: transaction create contact1 lent 1000 "T6" t6',
        'app1: transaction create contact1 owed 1500 "T7" t7',
        'app1: transaction create contact2 lent 600 "T8" t8',
        'app2: transaction create contact2 owed 2500 "T9" t9',
        'app2: transaction create contact3 lent 850 "T10" t10',
        'app3: transaction create contact3 owed 3500 "T11" t11',
        'app3: transaction create contact1 lent 1100 "T12" t12',
        'app1: transaction create contact1 owed 1200 "T13" t13',
        'app1: transaction create contact2 lent 700 "T14" t14',
        'app2: transaction create contact2 owed 1800 "T15" t15',
        'app2: transaction create contact3 lent 550 "T16" t16',
        'app3: transaction create contact3 owed 2200 "T17" t17',
        'app3: transaction create contact1 lent 900 "T18" t18',
        'app1: transaction update t1 amount 1100',
        'app2: transaction update t3 description "Updated T3"',
        'app3: transaction delete t5',
        'app1: transaction delete t7',
      ];
      
      print('📝 Executing ${commands.length} concurrent event commands...');
      await generator!.executeCommands(commands);
      await monitor!.waitForSync(timeout: const Duration(seconds: 90));
      
      // Verify all events synced
      final allEvents = await app1!.getEvents();
      final contactEvents = allEvents.where((e) => e.aggregateType == 'contact').toList();
      final transactionEvents = allEvents.where((e) => e.aggregateType == 'transaction').toList();
      
      expect(contactEvents.length, 3, reason: 'Should have 3 contact CREATED events');
      expect(transactionEvents.length, greaterThan(20), reason: 'Should have many transaction events');
      
      // Verify transaction events are majority
      expect(transactionEvents.length, greaterThan(contactEvents.length * 5), 
        reason: 'Transaction events should be majority');
      
      print('✅ All ${contactEvents.length + transactionEvents.length} events synced');
      
      // Verify on server
      final serverEvents = await serverVerifier!.getServerEvents();
      expect(serverEvents.length, greaterThanOrEqualTo(25));
      print('✅ All events verified on server');
      
      // Verify consistency
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true);
      print('✅ Event consistency validated');
    });
    
    test('Full Lifecycle: Create, Update, Delete for Both Types', () async {
      print('\n📋 Test: Full Lifecycle - Create, Update, Delete for Both Types');
      
      // Use event generator to create 20 events (2 contacts + 18 transactions) with full lifecycle
      final commands = [
        'app1: contact create "Lifecycle Contact" contact1',
        'app1: contact create "Lifecycle Contact 2" contact2',
        'app1: transaction create contact1 owed 1000 "T1" t1',
        'app1: transaction create contact1 lent 500 "T2" t2',
        'app1: transaction create contact1 owed 2000 "T3" t3',
        'app1: transaction create contact2 lent 800 "T4" t4',
        'app1: transaction create contact2 owed 1200 "T5" t5',
        'app1: transaction create contact1 lent 600 "T6" t6',
        'app1: transaction create contact1 owed 1500 "T7" t7',
        'app1: transaction create contact2 lent 900 "T8" t8',
        'app1: transaction create contact2 owed 1800 "T9" t9',
        'app1: transaction create contact1 lent 400 "T10" t10',
        // Updates (UPDATED events)
        'app2: contact update contact1 name "Updated Lifecycle Contact"',
        'app2: transaction update t1 amount 2000',
        'app2: transaction update t3 description "Updated T3"',
        'app2: transaction update t5 amount 1300',
        // Deletes (DELETED events)
        'app3: transaction delete t6',
        'app3: transaction delete t7',
        'app3: contact delete contact1',
        'app3: transaction delete t1',
      ];
      
      print('📝 Executing ${commands.length} full lifecycle commands...');
      await generator!.executeCommands(commands);
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Verify all event types for both aggregates
      final allEvents = await app1!.getEvents();
      final contactCreated = allEvents.where((e) => e.aggregateType == 'contact' && e.eventType == 'CREATED').toList();
      final contactUpdated = allEvents.where((e) => e.aggregateType == 'contact' && e.eventType == 'UPDATED').toList();
      final contactDeleted = allEvents.where((e) => e.aggregateType == 'contact' && e.eventType == 'DELETED').toList();
      final transactionCreated = allEvents.where((e) => e.aggregateType == 'transaction' && e.eventType == 'CREATED').toList();
      final transactionUpdated = allEvents.where((e) => e.aggregateType == 'transaction' && e.eventType == 'UPDATED').toList();
      final transactionDeleted = allEvents.where((e) => e.aggregateType == 'transaction' && e.eventType == 'DELETED').toList();
      final transactionUndo = allEvents.where((e) => e.aggregateType == 'transaction' && e.eventType == 'UNDO').toList();
      
      expect(contactCreated.length, 2, reason: 'Should have 2 contact CREATED events');
      expect(contactUpdated.length, 1, reason: 'Should have 1 contact UPDATED event');
      expect(contactDeleted.length, 1, reason: 'Should have 1 contact DELETED event');
      // Note: Transaction deletes within 5 seconds create UNDO events, not DELETED events
      // Also, deleting contact1 removes its transactions silently (no DELETED events for them)
      expect(transactionCreated.length, greaterThanOrEqualTo(10), reason: 'Should have many transaction CREATED events');
      expect(transactionUpdated.length, greaterThan(2), reason: 'Should have transaction UPDATED events');
      // Transactions deleted within 5 seconds create UNDO events, not DELETED events
      expect(transactionDeleted.length + transactionUndo.length, greaterThan(2), reason: 'Should have transaction DELETED or UNDO events');
      
      print('✅ Full lifecycle verified for both contact and transaction');
      
      // Verify on server
      final serverEvents = await serverVerifier!.getServerEvents();
      expect(serverEvents.length, greaterThanOrEqualTo(20));
      
      final serverContactEvents = serverEvents.where((e) => e['aggregate_type'] == 'contact').toList();
      final serverTransactionEvents = serverEvents.where((e) => e['aggregate_type'] == 'transaction').toList();
      final serverContactEventTypes = serverContactEvents.map((e) => e['event_type'] as String).toSet();
      final serverTransactionEventTypes = serverTransactionEvents.map((e) => e['event_type'] as String).toSet();
      
      expect(serverContactEventTypes.contains('CREATED'), true);
      expect(serverContactEventTypes.contains('UPDATED'), true);
      expect(serverContactEventTypes.contains('DELETED'), true);
      expect(serverTransactionEventTypes.contains('CREATED'), true);
      expect(serverTransactionEventTypes.contains('UPDATED'), true);
      // Note: Transaction deletes within 5 seconds create UNDO events, not DELETED events
      expect(serverTransactionEventTypes.contains('DELETED') || serverTransactionEventTypes.contains('UNDO'), true);
      print('✅ Full lifecycle verified on server');
      
      // Verify consistency
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true);
      print('✅ Event consistency validated');
    });
  });
}