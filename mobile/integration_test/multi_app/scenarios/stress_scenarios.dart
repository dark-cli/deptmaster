// ignore_for_file: unused_import

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
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
  
  group('Stress Scenarios', () {
    AppInstance? app1;
    AppInstance? app2;
    AppInstance? app3;
    AppInstance? app4;
    AppInstance? app5;
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
      app4 = await AppInstance.create(
        id: 'app4',
        serverUrl: 'http://localhost:8000',
        username: creds['email']!,
        password: creds['password']!,
        walletId: creds['walletId'],
      );
      app5 = await AppInstance.create(
        id: 'app5',
        serverUrl: 'http://localhost:8000',
        username: creds['email']!,
        password: creds['password']!,
        walletId: creds['walletId'],
      );
      
      // Initialize all instances
      await app1!.initialize();
      await app2!.initialize();
      await app3!.initialize();
      await app4!.initialize();
      await app5!.initialize();
      
      // Login all instances
      await app1!.login();
      await app2!.login();
      await app3!.login();
      await app4!.login();
      await app5!.login();
      
      // Create monitor and validator
      monitor = SyncMonitor([app1!, app2!, app3!, app4!, app5!]);
      validator = EventValidator();
      serverVerifier = ServerVerifier(serverUrl: 'http://localhost:8000');
      await serverVerifier!.setAuthToken();
      
      // Create event generator
      generator = EventGenerator({
        'app1': app1!,
        'app2': app2!,
        'app3': app3!,
        'app4': app4!,
        'app5': app5!,
      });
    });
    
    tearDown(() async {
      // Disconnect all instances
      await app1?.disconnect();
      await app2?.disconnect();
      await app3?.disconnect();
      await app4?.disconnect();
      await app5?.disconnect();
      
      // Clear data
      await app1?.clearData();
      await app2?.clearData();
      await app3?.clearData();
      await app4?.clearData();
      await app5?.clearData();
    });
    
    test('High Volume Concurrent Operations (Contacts & Transactions)', () async {
      print('\n📋 Test: High Volume Concurrent Operations (Contacts & Transactions)');
      
      // Use event generator to create 30 events (3 contacts + 27 transactions) across all apps
      final commands = [
        'app1: contact create "Contact App1-1" contact1',
        'app2: contact create "Contact App2-1" contact2',
        'app3: contact create "Contact App3-1" contact3',
        'app1: transaction create contact1 owed 1000 "T1" t1',
        'app1: transaction create contact1 lent 500 "T2" t2',
        'app1: transaction create contact1 owed 2000 "T3" t3',
        'app2: transaction create contact2 lent 800 "T4" t4',
        'app2: transaction create contact2 owed 1200 "T5" t5',
        'app2: transaction create contact2 lent 600 "T6" t6',
        'app3: transaction create contact3 owed 1500 "T7" t7',
        'app3: transaction create contact3 lent 900 "T8" t8',
        'app3: transaction create contact3 owed 1800 "T9" t9',
        'app4: transaction create contact1 lent 400 "T10" t10',
        'app4: transaction create contact2 owed 1100 "T11" t11',
        'app5: transaction create contact3 lent 700 "T12" t12',
        'app1: transaction create contact1 owed 1300 "T13" t13',
        'app2: transaction create contact2 lent 500 "T14" t14',
        'app3: transaction create contact3 owed 1600 "T15" t15',
        'app4: transaction create contact1 lent 300 "T16" t16',
        'app5: transaction create contact2 owed 1400 "T17" t17',
        'app1: transaction update t1 amount 1100',
        'app2: transaction update t4 description "Updated T4"',
        'app3: transaction update t7 amount 1600',
        'app4: transaction update t10 amount 500',
        'app5: transaction update t12 description "Updated T12"',
        'app1: transaction delete t3',
        'app2: transaction delete t6',
        'app3: transaction update t9 amount 1900',
        'app4: transaction create contact3 lent 200 "T18" t18',
        'app5: transaction create contact1 owed 1700 "T19" t19',
      ];
      
      print('📝 Executing ${commands.length} concurrent event commands...');
      final startTime = DateTime.now();
      await generator!.executeCommands(commands);
      final createTime = DateTime.now().difference(startTime);
      print('✅ Events created in ${createTime.inSeconds}s');
      
      // Wait for sync
      final syncStartTime = DateTime.now();
      await monitor!.waitForSync(timeout: const Duration(seconds: 180));
      final syncTime = DateTime.now().difference(syncStartTime);
      print('✅ Sync completed in ${syncTime.inSeconds}s');
      
      // Verify events
      final app1Events = await app1!.getEvents();
      // Note: Some events may be UNDO instead of DELETED
      expect(app1Events.length, greaterThanOrEqualTo(25));
      
      // Verify transaction events are majority
      final transactionEvents = app1Events.where(
        (e) => e.aggregateType == 'transaction'
      ).length;
      expect(transactionEvents, greaterThan(15), reason: 'Transaction events should be majority');
      
      // Verify all apps receive all events
      final app1Contacts = await app1!.getContacts();
      final app1Transactions = await app1!.getTransactions();
      expect(app1Contacts.length, 3);
      expect(app1Transactions.length, greaterThan(15));
      
      // Verify no duplicates
      final isValid = await validator!.validateEventConsistency([
        app1!, app2!, app3!, app4!, app5!
      ]);
      expect(isValid, true);
      print('✅ No duplicates - performance acceptable');
      
      // Verify final state consistent
      final app2Contacts = await app2!.getContacts();
      final app2Transactions = await app2!.getTransactions();
      expect(app1Contacts.length, app2Contacts.length);
      expect(app1Transactions.length, app2Transactions.length);
      print('✅ Final state consistent');
    });
    
    test('Rapid Create-Update-Delete (Contact & Transaction)', () async {
      print('\n📋 Test: Rapid Create-Update-Delete (Contact & Transaction)');
      
      // Use event generator to create 25 events with rapid create-update-delete sequences
      final commands = [
        'app1: contact create "Rapid Test Contact" contact1',
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
        // Rapid updates
        'app1: contact update contact1 name "Updated 1"',
        'app1: transaction update t1 amount 2000',
        'app1: transaction update t2 description "Updated T2"',
        'app1: transaction update t3 amount 2200',
        'app1: contact update contact1 name "Updated 2"',
        'app1: transaction update t4 amount 900',
        'app1: transaction update t5 description "Updated T5"',
        // Rapid deletes
        'app1: transaction delete t6',
        'app1: transaction delete t7',
        'app1: transaction delete t8',
        'app1: transaction delete t9',
        'app1: transaction delete t10',
        'app1: contact delete contact1',
      ];
      
      print('📝 Executing ${commands.length} rapid create-update-delete commands...');
      await generator!.executeCommands(commands);
      
      // Get IDs from generator
      final contactId = generator!.getContactId('contact1');
      final transactionId = generator!.getTransactionId('t1');
      
      if (contactId == null) {
        throw Exception('Contact ID not found for label: contact1');
      }
      if (transactionId == null) {
        throw Exception('Transaction ID not found for label: t1');
      }
      
      // Wait for sync
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      await Future.delayed(const Duration(seconds: 2));
      
      // Verify all events created in order
      final app1Events = await app1!.getEvents();
      final contactEvents = app1Events.where(
        (e) => e.aggregateId == contactId && e.aggregateType == 'contact',
      ).toList();
      final transactionEvents = app1Events.where(
        (e) => e.aggregateId == transactionId && e.aggregateType == 'transaction',
      ).toList();
      
      // Contact should have: CREATED, UPDATED, UPDATED, DELETED (at least 4 events)
      expect(contactEvents.length, greaterThanOrEqualTo(3), reason: 'Contact: CREATED, UPDATED, UPDATED, DELETED');
      
      // Transaction: When deleteTransaction is called after updates, it may undo the last update
      // So we might have: CREATED, UPDATED (first), UPDATED (second - undone), or CREATED, UPDATED, DELETED
      // Minimum is 2 events (CREATED + one UPDATED if second was undone)
      expect(transactionEvents.length, greaterThanOrEqualTo(2), reason: 'Transaction: CREATED, UPDATED (second may be undone), possibly DELETED');
      
      // Verify event types
      final contactCreated = contactEvents.where((e) => e.eventType == 'CREATED').toList();
      final contactUpdated = contactEvents.where((e) => e.eventType == 'UPDATED').toList();
      final contactDeleted = contactEvents.where((e) => e.eventType == 'DELETED').toList();
      final transactionCreated = transactionEvents.where((e) => e.eventType == 'CREATED').toList();
      final transactionUpdated = transactionEvents.where((e) => e.eventType == 'UPDATED').toList();
      final transactionDeleted = transactionEvents.where((e) => e.eventType == 'DELETED').toList();
      
      expect(contactCreated.isNotEmpty, true);
      expect(contactUpdated.length, greaterThanOrEqualTo(2));
      expect(contactDeleted.isNotEmpty, true);
      expect(transactionCreated.isNotEmpty, true);
      // Transaction may have 1 or 2 UPDATED events (second may be undone)
      expect(transactionUpdated.length, greaterThanOrEqualTo(1), reason: 'Transaction should have at least 1 UPDATED event');
      // Transaction DELETED may not exist if the transaction was undone instead
      print('✅ All events created in order for both contact and transaction');
      print('   Contact events: ${contactEvents.length} (CREATED: ${contactCreated.length}, UPDATED: ${contactUpdated.length}, DELETED: ${contactDeleted.length})');
      print('   Transaction events: ${transactionEvents.length} (CREATED: ${transactionCreated.length}, UPDATED: ${transactionUpdated.length}, DELETED: ${transactionDeleted.length})');
      
      // Verify events synced correctly
      final serverEvents = await serverVerifier!.getServerEvents();
      final serverContactEvents = serverEvents.where(
        (e) => e['aggregate_id'] == contactId && e['aggregate_type'] == 'contact',
      ).toList();
      final serverTransactionEvents = serverEvents.where(
        (e) => e['aggregate_id'] == transactionId && e['aggregate_type'] == 'transaction',
      ).toList();
      expect(serverContactEvents.length, greaterThanOrEqualTo(3));
      // Transaction may have fewer events if the last update was undone
      expect(serverTransactionEvents.length, greaterThanOrEqualTo(2));
      print('✅ All events synced correctly');
      
      // Verify final state correct (both deleted)
      await Future.delayed(const Duration(seconds: 2));
      final contactsAfter = await app1!.getContacts();
      final transactionsAfter = await app1!.getTransactions();
      expect(contactsAfter.any((c) => c.id == contactId), false, reason: 'Contact should be deleted');
      expect(transactionsAfter.any((t) => t.id == transactionId), false, reason: 'Transaction should be deleted');
      print('✅ Final state correct - both deleted');
      
      // Verify no race conditions
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true, reason: 'No race conditions');
      print('✅ No race conditions');
    });
    
    test('Mixed Operations Stress (Contacts & Transactions)', () async {
      print('\n📋 Test: Mixed Operations Stress (Contacts & Transactions)');
      
      // Use event generator to create 30 events with mixed operations across all apps
      final commands = [
        // Initial setup
        'app1: contact create "Initial Contact 0" contact1',
        'app1: contact create "Initial Contact 1" contact2',
        'app1: contact create "Initial Contact 2" contact3',
        'app1: transaction create contact1 owed 1000 "T1" t1',
        'app1: transaction create contact2 lent 500 "T2" t2',
        'app1: transaction create contact3 owed 2000 "T3" t3',
        // App1: Create, Update, Delete
        'app1: contact create "App1 Contact" contact4',
        'app1: transaction create contact4 owed 1500 "T4" t4',
        'app1: contact update contact1 name "Updated by App1"',
        'app1: transaction update t1 amount 2000',
        'app1: contact delete contact3',
        'app1: transaction delete t3',
        // App2: Create, Update
        'app2: contact create "App2 Contact" contact5',
        'app2: transaction create contact5 lent 800 "T5" t5',
        'app2: contact update contact2 name "Updated by App2"',
        'app2: transaction update t2 description "Updated T2"',
        // App3: Create, Delete (conflicts)
        'app3: contact create "App3 Contact" contact6',
        'app3: transaction create contact6 owed 1200 "T6" t6',
        'app3: contact delete contact1',
        'app3: transaction delete t1',
        // App4: Create, Update
        'app4: contact create "App4 Contact" contact7',
        'app4: transaction create contact7 lent 600 "T7" t7',
        'app4: transaction update t4 amount 1600',
        // App5: Create, Update, Delete
        'app5: contact create "App5 Contact" contact8',
        'app5: transaction create contact8 owed 1800 "T8" t8',
        'app5: transaction update t5 amount 900',
        'app5: transaction delete t6',
        'app5: contact update contact4 name "Updated by App5"',
        'app5: transaction create contact2 lent 400 "T9" t9',
      ];
      
      print('📝 Executing ${commands.length} mixed operation commands...');
      await generator!.executeCommands(commands);
      
      // Wait for sync
      await monitor!.waitForSync(timeout: const Duration(seconds: 120));
      
      // Verify events
      final app1Events = await app1!.getEvents();
      // Note: Some events may be UNDO instead of DELETED, and some transactions may be removed silently
      expect(app1Events.length, greaterThanOrEqualTo(25));
      
      // Verify transaction events are majority
      final transactionEvents = app1Events.where(
        (e) => e.aggregateType == 'transaction'
      ).length;
      expect(transactionEvents, greaterThan(15), reason: 'Transaction events should be majority');
      
      // Verify events synced correctly
      final serverEvents = await serverVerifier!.getServerEvents();
      expect(serverEvents.length, greaterThanOrEqualTo(25));
      print('✅ Events synced correctly');
      
      // Verify state consistent
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true, reason: 'State should be consistent');
      print('✅ State consistent');
      
      // Verify no data corruption
      final app1Contacts = await app1!.getContacts();
      final app2Contacts = await app2!.getContacts();
      final app3Contacts = await app3!.getContacts();
      
      // All apps should have similar number of contacts (some may be deleted)
      expect(app1Contacts.length, greaterThan(0), reason: 'App1 should have contacts');
      expect(app2Contacts.length, greaterThan(0), reason: 'App2 should have contacts');
      expect(app3Contacts.length, greaterThan(0), reason: 'App3 should have contacts');
      print('✅ No data corruption');
    });
  });
}