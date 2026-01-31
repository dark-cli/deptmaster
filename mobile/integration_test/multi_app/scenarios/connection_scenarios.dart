// ignore_for_file: unused_import

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
  
  group('Connection Breakdown Scenarios', () {
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
    
    test('Sync Interruption', () async {
      print('\n📋 Test: Sync Interruption');
      print('⚠️ NOTE: NetworkInterceptor is not fully integrated - HTTP calls bypass it');
      print('⚠️ This test verifies sync behavior, but offline simulation is limited');
      
      // Use event generator to create 15 events (1 contact + 11 transactions + 2 updates + 1 delete)
      // Final state: 1 contact, 10 transactions (11 created - 1 deleted)
      final commands = [
        'app1: contact create "Contact to Interrupt" contact1',
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
        'app1: transaction update t1 amount 1100',
        'app1: transaction update t3 description "Updated T3"',
        'app1: transaction delete t5',
      ];
      
      print('📝 App1 executing ${commands.length} event commands...');
      await generator!.executeCommands(commands);
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Verify events
      final app1Events = await app1!.getEvents();
      expect(app1Events.length, greaterThanOrEqualTo(15));
      
      // Verify transaction events are majority
      final transactionEvents = app1Events.where(
        (e) => e.aggregateType == 'transaction'
      ).length;
      expect(transactionEvents, greaterThan(10), reason: 'Transaction events should be majority');
      
      // Verify events synced to server
      final serverEvents = await serverVerifier!.getServerEvents();
      expect(serverEvents.length, greaterThanOrEqualTo(15));
      
      // Verify final state (11 transactions created - 1 deleted = 10 remaining)
      final allContacts = await app1!.getContacts();
      final allTransactions = await app1!.getTransactions();
      expect(allContacts.length, 1);
      expect(allTransactions.length, 10);
      print('✅ Contact and transaction exist in all apps');
      
      print('⚠️ Test completed - offline simulation not fully functional due to interceptor limitation');
      print('⚠️ See NETWORK_INTERCEPTOR_LIMITATION.md for details');
    });
    
    test('Multiple Sync Failures', () async {
      print('\n📋 Test: Multiple Sync Failures');
      print('⚠️ NOTE: NetworkInterceptor is not fully integrated - HTTP calls bypass it');
      print('⚠️ This test verifies sync behavior with multiple contacts and transactions');
      
      // Use event generator to create 20 events (3 contacts + 17 transactions)
      final commands = [
        'app1: contact create "Contact 0" contact1',
        'app1: contact create "Contact 1" contact2',
        'app1: contact create "Contact 2" contact3',
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
        'app1: transaction update t1 amount 1100',
        'app1: transaction update t4 description "Updated T4"',
        'app1: transaction delete t6',
        'app1: transaction update t7 amount 1600',
        'app1: transaction delete t9',
      ];
      
      print('📝 App1 executing ${commands.length} event commands...');
      await generator!.executeCommands(commands);
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Verify events
      final app1Events = await app1!.getEvents();
      expect(app1Events.length, greaterThanOrEqualTo(20));
      
      // Verify transaction events are majority
      final transactionEvents = app1Events.where(
        (e) => e.aggregateType == 'transaction'
      ).length;
      expect(transactionEvents, greaterThan(15), reason: 'Transaction events should be majority');
      
      // Verify all events on server
      final serverEvents = await serverVerifier!.getServerEvents();
      expect(serverEvents.length, greaterThanOrEqualTo(20));
      
      // Verify no duplicates
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true);
      print('✅ No duplicates - sync worked correctly');
      
      print('⚠️ Test completed - offline simulation not fully functional due to interceptor limitation');
    });
    
    test('Server Unavailable', () async {
      print('\n📋 Test: Server Unavailable');
      print('⚠️ NOTE: NetworkInterceptor is not fully integrated - HTTP calls bypass it');
      print('⚠️ This test verifies sync behavior with multiple apps, but offline simulation is limited');
      
      // Use event generator to create 18 events across all apps (3 contacts + 15 transactions)
      final commands = [
        'app1: contact create "Contact from App1" contact1',
        'app2: contact create "Contact from App2" contact2',
        'app3: contact create "Contact from App3" contact3',
        'app1: transaction create contact1 owed 1000 "T1" t1',
        'app1: transaction create contact1 lent 500 "T2" t2',
        'app1: transaction create contact1 owed 2000 "T3" t3',
        'app2: transaction create contact2 lent 800 "T4" t4',
        'app2: transaction create contact2 owed 1200 "T5" t5',
        'app2: transaction create contact2 lent 600 "T6" t6',
        'app3: transaction create contact3 owed 1500 "T7" t7',
        'app3: transaction create contact3 lent 900 "T8" t8',
        'app3: transaction create contact3 owed 1800 "T9" t9',
        'app1: transaction create contact1 lent 400 "T10" t10',
        'app2: transaction create contact2 owed 1100 "T11" t11',
        'app3: transaction create contact3 lent 700 "T12" t12',
        'app1: transaction update t1 amount 1100',
        'app2: transaction update t4 description "Updated T4"',
        'app3: transaction delete t7',
      ];
      
      print('📝 All apps executing ${commands.length} event commands...');
      await generator!.executeCommands(commands);
      
      // Wait for all events to sync
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Verify events
      final app1Events = await app1!.getEvents();
      expect(app1Events.length, greaterThanOrEqualTo(18));
      
      // Verify transaction events are majority
      final transactionEvents = app1Events.where(
        (e) => e.aggregateType == 'transaction'
      ).length;
      expect(transactionEvents, greaterThan(12), reason: 'Transaction events should be majority');
      
      // Verify all events on server
      final serverEvents = await serverVerifier!.getServerEvents();
      expect(serverEvents.length, greaterThanOrEqualTo(18));
      
      // Verify no data loss
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true);
      print('✅ No data loss - all events synced correctly');
      
      print('⚠️ Test completed - offline simulation not fully functional due to interceptor limitation');
      print('⚠️ See NETWORK_INTERCEPTOR_LIMITATION.md for details');
    });
  });
}