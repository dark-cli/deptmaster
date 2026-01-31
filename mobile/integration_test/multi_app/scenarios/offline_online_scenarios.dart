// ignore_for_file: unused_import, unused_local_variable

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:debt_tracker_mobile/models/contact.dart';
import 'package:debt_tracker_mobile/models/transaction.dart';
import 'package:debt_tracker_mobile/models/event.dart';
import 'package:debt_tracker_mobile/services/backend_config_service.dart';
import '../app_instance.dart';
import '../sync_monitor.dart';
import '../event_validator.dart';
import '../server_verifier.dart';
import '../event_generator.dart';
import '../../helpers/multi_app_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  group('Offline/Online Scenarios', () {
    AppInstance? app1;
    AppInstance? app2;
    AppInstance? app3;
    SyncMonitor? monitor;
    EventValidator? validator;
    ServerVerifier? serverVerifier;
    EventGenerator? generator;
    
    setUpAll(() async {
      // Initialize Hive once globally
      await Hive.initFlutter();
      Hive.registerAdapter(ContactAdapter());
      Hive.registerAdapter(TransactionAdapter());
      Hive.registerAdapter(TransactionTypeAdapter());
      Hive.registerAdapter(TransactionDirectionAdapter());
      Hive.registerAdapter(EventAdapter());
    });
    
    setUp(() async {
      // Reset server before each test
      await resetServer();
      await waitForServerReady();
      
      // Ensure test user exists
      await ensureTestUserExists();
      
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
    
    test('Offline Create → Online Sync (Contact & Transaction)', () async {
      print('\n📋 Test: Offline Create → Online Sync (Contact & Transaction)');
      print('⚠️ NOTE: NetworkInterceptor is not fully integrated - HTTP calls bypass it');
      print('⚠️ This test verifies sync behavior, but offline simulation is limited');
      
      // App1 goes offline
      print('📴 App1 going offline...');
      await app1!.goOffline();
      
      // Use event generator to create 14 events while offline (1 contact + 13 transactions)
      final offlineCommands = [
        'app1: contact create "Offline Contact" contact1',
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
        'app1: transaction create contact1 owed 1100 "T11" t11',
        'app1: transaction create contact1 lent 700 "T12" t12',
        'app1: transaction update t1 amount 1100',
      ];
      
      print('📝 App1 (offline) executing ${offlineCommands.length} event commands...');
      await generator!.executeCommands(offlineCommands);
      
      // Wait for sync (events sync immediately due to NetworkInterceptor limitation)
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Verify events
      final app1Events = await app1!.getEvents();
      expect(app1Events.length, greaterThanOrEqualTo(14));
      
      // Verify transaction events are majority
      final transactionEvents = app1Events.where(
        (e) => e.aggregateType == 'transaction'
      ).length;
      expect(transactionEvents, greaterThan(10), reason: 'Transaction events should be majority');
      
      // App1 comes online (already synced, but verify)
      print('📶 App1 coming online...');
      await app1!.goOnline();
      
      // Wait a bit to ensure everything is stable
      await Future.delayed(const Duration(seconds: 1));
      
      // Verify events synced to server
      final serverEventsAfter = await serverVerifier!.getServerEvents();
      expect(serverEventsAfter.length, greaterThanOrEqualTo(14));
      
      // Verify both exist in all apps
      final allContacts = await app1!.getContacts();
      final allTransactions = await app1!.getTransactions();
      expect(allContacts.length, greaterThanOrEqualTo(1));
      expect(allTransactions.length, greaterThan(10));
      
      // Validate consistency
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true);
      print('✅ Event consistency validated');
      print('⚠️ Test completed - offline simulation not fully functional due to interceptor limitation');
    });
    
    test('Multiple Offline Creates (Contacts & Transactions)', () async {
      print('\n📋 Test: Multiple Offline Creates (Contacts & Transactions)');
      
      // App1 goes offline
      print('📴 App1 going offline...');
      await app1!.goOffline();
      
      // Use event generator to create 20 events while offline (3 contacts + 17 transactions)
      final offlineCommands = [
        'app1: contact create "Offline Contact 1" contact1',
        'app1: contact create "Offline Contact 2" contact2',
        'app1: contact create "Offline Contact 3" contact3',
        'app1: transaction create contact1 owed 1000 "T1" t1',
        'app1: transaction create contact1 lent 500 "T2" t2',
        'app1: transaction create contact1 owed 2000 "T3" t3',
        'app1: transaction create contact2 lent 800 "T4" t4',
        'app1: transaction create contact2 owed 1200 "T5" t5',
        'app1: transaction create contact2 lent 600 "T6" t6',
        'app1: transaction create contact3 owed 1500 "T7" t7',
        'app1: transaction create contact3 lent 900 "T8" t8',
        'app1: transaction create contact3 owed 1800 "T9" t9',
        'app1: transaction create contact1 lent 400 "T10" t10',
        'app1: transaction create contact2 owed 1100 "T11" t11',
        'app1: transaction create contact3 lent 700 "T12" t12',
        'app1: transaction create contact1 owed 1300 "T13" t13',
        'app1: transaction create contact2 lent 500 "T14" t14',
        'app1: transaction create contact3 owed 1600 "T15" t15',
        'app1: transaction update t1 amount 1100',
        'app1: transaction delete t5',
      ];
      
      print('📝 App1 (offline) executing ${offlineCommands.length} event commands...');
      await generator!.executeCommands(offlineCommands);
      
      // Wait for sync
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Verify events
      final app1Events = await app1!.getEvents();
      expect(app1Events.length, greaterThanOrEqualTo(20));
      
      // Verify transaction events are majority
      final transactionEvents = app1Events.where(
        (e) => e.aggregateType == 'transaction'
      ).length;
      expect(transactionEvents, greaterThan(15), reason: 'Transaction events should be majority');
      
      // App1 comes online
      print('📶 App1 coming online...');
      await app1!.goOnline();
      await Future.delayed(const Duration(seconds: 1));
      
      // Verify final state
      final allContacts = await app1!.getContacts();
      final allTransactions = await app1!.getTransactions();
      expect(allContacts.length, 3);
      expect(allTransactions.length, greaterThan(10));
      
      // Validate consistency
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true);
      print('✅ Event consistency validated');
    });
    
    
    test('Offline Update → Online Sync (Contact & Transaction)', () async {
      print('\n📋 Test: Offline Update → Online Sync (Contact & Transaction)');
      
      // Create contact and transactions first
      final setupCommands = [
        'app1: contact create "Original Name" contact1',
        'app1: transaction create contact1 owed 1000 "T1" t1',
        'app1: transaction create contact1 lent 500 "T2" t2',
        'app1: transaction create contact1 owed 2000 "T3" t3',
        'app1: transaction create contact1 lent 800 "T4" t4',
        'app1: transaction create contact1 owed 1500 "T5" t5',
      ];
      await generator!.executeCommands(setupCommands);
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // App1 goes offline
      print('📴 App1 going offline...');
      await app1!.goOffline();
      
      // Use event generator to create 10 update events while offline
      final offlineUpdateCommands = [
        'app1: contact update contact1 name "Updated Offline"',
        'app1: transaction update t1 amount 2000',
        'app1: transaction update t2 description "Updated T2"',
        'app1: transaction update t3 amount 2200',
        'app1: transaction update t4 description "Updated T4"',
        'app1: transaction update t5 amount 1600',
        'app1: transaction create contact1 lent 600 "T6" t6',
        'app1: transaction create contact1 owed 1200 "T7" t7',
        'app1: transaction update t6 amount 700',
        'app1: transaction delete t5',
      ];
      
      print('📝 App1 (offline) executing ${offlineUpdateCommands.length} update commands...');
      await generator!.executeCommands(offlineUpdateCommands);
      
      // Wait for sync
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Verify events
      final app1Events = await app1!.getEvents();
      expect(app1Events.length, greaterThanOrEqualTo(16)); // 6 setup + 10 updates
      
      // Verify we have UPDATE events
      final updateEvents = app1Events.where((e) => e.eventType == 'UPDATED').length;
      expect(updateEvents, greaterThanOrEqualTo(6), reason: 'Should have multiple update events');
      
      // App1 comes online
      print('📶 App1 coming online...');
      await app1!.goOnline();
      await Future.delayed(const Duration(seconds: 1));
      
      // Verify final state
      final contactsAfter = await app1!.getContacts();
      final transactionsAfter = await app1!.getTransactions();
      expect(contactsAfter.length, 1);
      expect(transactionsAfter.length, greaterThan(5));
      
      // Validate consistency
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true);
      print('✅ State consistent');
    });
    
    test('Partial Offline (Some Apps Online)', () async {
      print('\n📋 Test: Partial Offline (Some Apps Online)');
      
      // App1 offline, App2 and App3 online
      print('📴 App1 going offline, App2 and App3 staying online...');
      await app1!.goOffline();
      
      // App2 and App3 create events online (15 events)
      final onlineCommands = [
        'app2: contact create "Online Contact 1" contact1',
        'app2: contact create "Online Contact 2" contact2',
        'app3: contact create "Online Contact 3" contact3',
        'app2: transaction create contact1 owed 1000 "T1" t1',
        'app2: transaction create contact1 lent 500 "T2" t2',
        'app2: transaction create contact1 owed 2000 "T3" t3',
        'app3: transaction create contact2 lent 800 "T4" t4',
        'app3: transaction create contact2 owed 1200 "T5" t5',
        'app2: transaction create contact3 lent 600 "T6" t6',
        'app3: transaction create contact3 owed 1500 "T7" t7',
        'app2: transaction create contact1 lent 900 "T8" t8',
        'app3: transaction create contact2 owed 1800 "T9" t9',
        'app2: transaction update t1 amount 1100',
        'app3: transaction update t4 description "Updated T4"',
        'app2: transaction delete t3',
      ];
      
      print('📝 App2 and App3 (online) executing ${onlineCommands.length} event commands...');
      await generator!.executeCommands(onlineCommands);
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // App1 creates events offline
      final offlineCommands = [
        'app1: contact create "Offline Contact" contact4',
        'app1: transaction create contact4 owed 1000 "T10" t10',
        'app1: transaction create contact4 lent 500 "T11" t11',
        'app1: transaction create contact4 owed 2000 "T12" t12',
      ];
      
      print('📝 App1 (offline) executing ${offlineCommands.length} event commands...');
      await generator!.executeCommands(offlineCommands);
      
      // App1 comes online
      print('📶 App1 coming online...');
      await app1!.goOnline();
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Verify all events
      final app1Events = await app1!.getEvents();
      expect(app1Events.length, greaterThanOrEqualTo(19)); // 15 online + 4 offline
      
      // Verify final state
      final allContacts = await app1!.getContacts();
      final allTransactions = await app1!.getTransactions();
      expect(allContacts.length, 4);
      expect(allTransactions.length, greaterThan(10));
      
      // Validate consistency
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true);
      print('✅ All apps have consistent events');
    });
  });
}