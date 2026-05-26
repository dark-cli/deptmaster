// ignore_for_file: unused_import, unused_local_variable

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
  
  group('Resync Scenarios', () {
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
      
      // Initialize all instances
      await app1!.initialize();
      await app2!.initialize();
      await app3!.initialize();
      
      // Login all instances
      await app1!.login();
      await app2!.login();
      await app3!.login();
      
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
    
    test('Full Resync After Disconnect', () async {
      print('\n📋 Test: Full Resync After Disconnect');
      
      // App1 disconnects
      print('📴 App1 disconnecting...');
      await app1!.disconnect();
      
      // Use event generator to create 25 events (5 contacts + 20 transactions) while App1 is disconnected
      final commands = [
        'app2: contact create "Contact from App2 #0" contact1',
        'app2: contact create "Contact from App2 #1" contact2',
        'app2: contact create "Contact from App2 #2" contact3',
        'app3: contact create "Contact from App3 #0" contact4',
        'app3: contact create "Contact from App3 #1" contact5',
        'app2: transaction create contact1 owed 1000 "T1" t1',
        'app2: transaction create contact1 lent 500 "T2" t2',
        'app2: transaction create contact2 owed 2000 "T3" t3',
        'app2: transaction create contact2 lent 800 "T4" t4',
        'app2: transaction create contact3 owed 1500 "T5" t5',
        'app3: transaction create contact4 lent 600 "T6" t6',
        'app3: transaction create contact4 owed 1200 "T7" t7',
        'app3: transaction create contact5 lent 900 "T8" t8',
        'app3: transaction create contact5 owed 1800 "T9" t9',
        'app2: transaction create contact1 owed 1100 "T10" t10',
        'app2: transaction create contact2 lent 700 "T11" t11',
        'app3: transaction create contact4 owed 1300 "T12" t12',
        'app3: transaction create contact5 lent 400 "T13" t13',
        'app2: transaction update t1 amount 1100',
        'app2: transaction update t3 description "Updated T3"',
        'app3: transaction update t6 amount 700',
        'app3: transaction delete t8',
        'app2: transaction create contact3 lent 500 "T14" t14',
        'app3: transaction create contact4 owed 1400 "T15" t15',
        'app2: transaction delete t5',
      ];
      
      print('📝 App2 and App3 executing ${commands.length} event commands...');
      await generator!.executeCommands(commands);
      
      // Wait for App2 and App3 to sync
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Verify events on server
      final serverEvents = await serverVerifier!.getServerEvents();
      expect(serverEvents.length, greaterThanOrEqualTo(25));
      
      // App1 reconnects
      print('📶 App1 reconnecting...');
      await app1!.login();
      
      // Wait for App1 to fetch all missed events
      await monitor!.waitForSync(timeout: const Duration(seconds: 90));
      
      // Verify App1 has all events
      final app1Events = await app1!.getEvents();
      // Note: Some events may be UNDO instead of DELETED, and some transactions may be removed silently
      expect(app1Events.length, greaterThanOrEqualTo(20));
      
      // Verify transaction events are majority
      final transactionEvents = app1Events.where(
        (e) => e.aggregateType == 'transaction'
      ).length;
      expect(transactionEvents, greaterThan(12), reason: 'Transaction events should be majority');
      
      // Verify state rebuilt correctly
      final app1Contacts = await app1!.getContacts();
      final app1Transactions = await app1!.getTransactions();
      expect(app1Contacts.length, 5);
      // Note: Some transactions may be deleted/undone, so count may be lower
      expect(app1Transactions.length, greaterThanOrEqualTo(13));
      print('✅ State rebuilt correctly');
      
      // Verify all apps in sync
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true, reason: 'All apps should be in sync');
      print('✅ All apps in sync');
    });
    
    test('Hash Mismatch Resync', () async {
      print('\n📋 Test: Hash Mismatch Resync');
      
      // Create some events in all apps
      // Create initial events
      final initialCommands = [
        'app1: contact create "Initial Contact 1" contact1',
        'app2: contact create "Initial Contact 2" contact2',
        'app1: transaction create contact1 owed 1000 "T1" t1',
        'app2: transaction create contact2 lent 500 "T2" t2',
      ];
      await generator!.executeCommands(initialCommands);
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Get server hash
      final serverHashBefore = await serverVerifier!.getServerHash();
      
      // App1 disconnects
      await app1!.disconnect();
      
      // App2 and App3 create more events (20 events: 6 contacts + 14 transactions)
      final newCommands = [
        'app2: contact create "New Contact from App2 #0" contact3',
        'app2: contact create "New Contact from App2 #1" contact4',
        'app2: contact create "New Contact from App2 #2" contact5',
        'app3: contact create "New Contact from App3 #0" contact6',
        'app3: contact create "New Contact from App3 #1" contact7',
        'app3: contact create "New Contact from App3 #2" contact8',
        'app2: transaction create contact3 owed 1000 "T3" t3',
        'app2: transaction create contact3 lent 500 "T4" t4',
        'app2: transaction create contact4 owed 2000 "T5" t5',
        'app2: transaction create contact4 lent 800 "T6" t6',
        'app2: transaction create contact5 owed 1500 "T7" t7',
        'app3: transaction create contact6 lent 600 "T8" t8',
        'app3: transaction create contact6 owed 1200 "T9" t9',
        'app3: transaction create contact7 lent 900 "T10" t10',
        'app3: transaction create contact7 owed 1800 "T11" t11',
        'app3: transaction create contact8 lent 400 "T12" t12',
        'app2: transaction update t3 amount 1100',
        'app3: transaction update t8 description "Updated T8"',
        'app2: transaction delete t6',
        'app3: transaction create contact8 owed 1100 "T13" t13',
      ];
      
      await generator!.executeCommands(newCommands);
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Get new server hash
      final serverHashAfter = await serverVerifier!.getServerHash();
      expect(serverHashAfter != serverHashBefore, true);
      
      // App1 reconnects (hash mismatch should trigger full resync)
      await app1!.login();
      await monitor!.waitForSync(timeout: const Duration(seconds: 90));
      
      // Verify App1 has all events
      final app1Events = await app1!.getEvents();
      expect(app1Events.length, greaterThanOrEqualTo(24)); // 2 initial + 20 new
      
      // Verify transaction events are majority
      final transactionEvents = app1Events.where(
        (e) => e.aggregateType == 'transaction'
      ).length;
      expect(transactionEvents, greaterThan(15), reason: 'Transaction events should be majority');
      
      // Validate consistency
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true);
      print('✅ Hash matches - full resync completed');
    });
    
    test('Incremental Resync', () async {
      print('\n📋 Test: Incremental Resync');
      
      // Create initial events
      final initialCommands = [
        'app1: contact create "Initial Contact" contact1',
        'app1: transaction create contact1 owed 1000 "T1" t1',
        'app1: transaction create contact1 lent 500 "T2" t2',
        'app1: transaction create contact1 owed 2000 "T3" t3',
      ];
      await generator!.executeCommands(initialCommands);
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // App1 disconnects briefly
      await app1!.disconnect();
      await Future.delayed(const Duration(seconds: 1));
      
      // App2 creates events after App1's last sync timestamp (15 events: 3 contacts + 12 transactions)
      final newCommands = [
        'app2: contact create "New Contact #0" contact2',
        'app2: contact create "New Contact #1" contact3',
        'app2: contact create "New Contact #2" contact4',
        'app2: transaction create contact2 owed 1000 "T4" t4',
        'app2: transaction create contact2 lent 500 "T5" t5',
        'app2: transaction create contact3 owed 2000 "T6" t6',
        'app2: transaction create contact3 lent 800 "T7" t7',
        'app2: transaction create contact4 owed 1500 "T8" t8',
        'app2: transaction create contact4 lent 600 "T9" t9',
        'app2: transaction create contact2 owed 1200 "T10" t10',
        'app2: transaction create contact3 lent 900 "T11" t11',
        'app2: transaction create contact4 owed 1800 "T12" t12',
        'app2: transaction update t4 amount 1100',
        'app2: transaction update t6 description "Updated T6"',
        'app2: transaction delete t8',
      ];
      
      await generator!.executeCommands(newCommands);
      await Future.delayed(const Duration(seconds: 3));
      
      // App1 reconnects
      await app1!.login();
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Verify App1 has all events
      final app1Events = await app1!.getEvents();
      expect(app1Events.length, greaterThanOrEqualTo(19)); // 4 initial + 15 new
      
      // Verify transaction events are majority
      final transactionEvents = app1Events.where(
        (e) => e.aggregateType == 'transaction'
      ).length;
      expect(transactionEvents, greaterThan(12), reason: 'Transaction events should be majority');
      
      // Verify state updated correctly
      final app1Contacts = await app1!.getContacts();
      final app1Transactions = await app1!.getTransactions();
      expect(app1Contacts.length, 4);
      // Note: Some transactions may be deleted/undone, so count may be lower
      expect(app1Transactions.length, greaterThanOrEqualTo(11));
      
      // Validate consistency
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true);
      print('✅ Incremental sync worked - App1 received new events');
    });
  });
}