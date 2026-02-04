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
import '../server_verifier.dart';
import '../sync_monitor.dart';
import '../event_generator.dart';
import '../../helpers/multi_app_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  group('Server-Side Scenarios', () {
    AppInstance? app1;
    ServerVerifier? serverVerifier;
    SyncMonitor? monitor;
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
      await app1!.initialize();
      await app1!.login();
      
      // Create server verifier and monitor
      serverVerifier = ServerVerifier(serverUrl: 'http://localhost:8000');
      await serverVerifier!.setAuthToken();
      monitor = SyncMonitor([app1!]);
      
      // Create event generator
      generator = EventGenerator({
        'app1': app1!,
      });
    });
    
    tearDown(() async {
      await app1?.disconnect();
      await app1?.clearData();
    });
    
    test('Server: Event Storage', () async {
      print('\n📋 Server Test: Event Storage');
      
      // Use event generator to create 12 events (1 contact + 11 transactions)
      final commands = [
        'app1: contact create "Test Contact" contact1',
        'app1: transaction create contact1 owed 1000 "T1" t1',
        'app1: transaction create contact1 lent 500 "T2" t2',
        'app1: transaction create contact1 owed 2000 "T3" t3',
        'app1: transaction create contact1 lent 800 "T4" t4',
        'app1: transaction create contact1 owed 1500 "T5" t5',
        'app1: transaction create contact1 lent 600 "T6" t6',
        'app1: transaction create contact1 owed 1200 "T7" t7',
        'app1: transaction create contact1 lent 900 "T8" t8',
        'app1: transaction update t1 amount 1100',
        'app1: transaction update t3 description "Updated T3"',
        'app1: transaction delete t5',
      ];
      
      print('📝 Creating ${commands.length} events...');
      await generator!.executeCommands(commands);
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Verify events stored in database via API
      final serverEvents = await serverVerifier!.getServerEvents();
      expect(serverEvents.length, greaterThanOrEqualTo(12));
      
      // Verify transaction events are majority
      final transactionEvents = serverEvents.where(
        (e) => e['aggregate_type'] == 'transaction'
      ).toList();
      expect(transactionEvents.length, greaterThan(8), reason: 'Transaction events should be majority');
      
      // Verify contact event exists
      final contactEvents = serverEvents.where(
        (e) => e['aggregate_type'] == 'contact'
      ).toList();
      expect(contactEvents.isNotEmpty, true);
      
      print('✅ All events stored correctly in database');
      
      // Verify event data integrity
      final contactEvent = contactEvents.first;
      final contactEventData = contactEvent['event_data'] as Map<String, dynamic>;
      expect(contactEventData['name'], 'Test Contact');
      
      // Verify transaction event data
      final transactionEvent = transactionEvents.firstWhere(
        (e) => e['event_type'] == 'CREATED',
        orElse: () => transactionEvents.first,
      );
      final transactionEventData = transactionEvent['event_data'] as Map<String, dynamic>;
      expect(transactionEventData['amount'], 1000);
      print('✅ Event data integrity verified');
    });
    
    test('Server: Event Retrieval', () async {
      print('\n📋 Server Test: Event Retrieval');
      
      // Use event generator to create 15 events (3 contacts + 12 transactions)
      final commands = [
        'app1: contact create "Contact 0" contact1',
        'app1: contact create "Contact 1" contact2',
        'app1: contact create "Contact 2" contact3',
        'app1: transaction create contact1 owed 1000 "T1" t1',
        'app1: transaction create contact1 lent 500 "T2" t2',
        'app1: transaction create contact2 owed 2000 "T3" t3',
        'app1: transaction create contact2 lent 800 "T4" t4',
        'app1: transaction create contact3 owed 1500 "T5" t5',
        'app1: transaction create contact3 lent 600 "T6" t6',
        'app1: transaction create contact1 owed 1200 "T7" t7',
        'app1: transaction create contact2 lent 900 "T8" t8',
        'app1: transaction create contact3 owed 1800 "T9" t9',
        'app1: transaction update t1 amount 1100',
        'app1: transaction update t3 description "Updated T3"',
        'app1: transaction delete t5',
      ];
      
      print('📝 Creating ${commands.length} events...');
      await generator!.executeCommands(commands);
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Test GET /api/sync/events without timestamp (all events)
      final allEvents = await serverVerifier!.getServerEvents();
      final contactEvents = allEvents.where((e) => e['aggregate_type'] == 'contact').toList();
      final transactionEvents = allEvents.where((e) => e['aggregate_type'] == 'transaction').toList();
      expect(contactEvents.length, 3, reason: 'Should retrieve all contact events');
      expect(transactionEvents.length, greaterThan(10), reason: 'Should retrieve all transaction events');
      print('✅ Retrieved all events: ${allEvents.length} (${contactEvents.length} contacts, ${transactionEvents.length} transactions)');
      
      // Test GET /api/sync/events with timestamp (incremental)
      final since = DateTime.now().subtract(const Duration(minutes: 1));
      final recentEvents = await serverVerifier!.getServerEvents(since: since);
      expect(recentEvents.length, greaterThanOrEqualTo(15), reason: 'Should retrieve recent events');
      print('✅ Retrieved recent events: ${recentEvents.length}');
    });
    
    test('Server: Event Acceptance', () async {
      print('\n📋 Server Test: Event Acceptance');
      
      // Use event generator to create 12 events (1 contact + 11 transactions)
      final commands = [
        'app1: contact create "Valid Contact" contact1',
        'app1: transaction create contact1 owed 1000 "T1" t1',
        'app1: transaction create contact1 lent 500 "T2" t2',
        'app1: transaction create contact1 owed 2000 "T3" t3',
        'app1: transaction create contact1 lent 800 "T4" t4',
        'app1: transaction create contact1 owed 1500 "T5" t5',
        'app1: transaction create contact1 lent 600 "T6" t6',
        'app1: transaction create contact1 owed 1200 "T7" t7',
        'app1: transaction create contact1 lent 900 "T8" t8',
        'app1: transaction update t1 amount 1100',
        'app1: transaction update t3 description "Updated T3"',
        'app1: transaction delete t5',
      ];
      
      print('📝 Creating ${commands.length} valid events...');
      await generator!.executeCommands(commands);
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Verify all events accepted
      final serverEvents = await serverVerifier!.getServerEvents();
      expect(serverEvents.length, greaterThanOrEqualTo(12));
      
      // Verify events have required fields
      for (final event in serverEvents) {
        expect(event['id'], isNotNull);
        expect(event['aggregate_id'], isNotNull);
        expect(event['aggregate_type'], isNotNull);
        expect(event['event_type'], isNotNull);
        expect(event['event_data'], isNotNull);
        expect(event['timestamp'], isNotNull);
      }
      print('✅ All events accepted and have all required fields');
    });
    
    test('Server: Hash Calculation', () async {
      print('\n📋 Server Test: Hash Calculation');
      
      // Get initial hash
      print('📥 Getting initial hash...');
      final hash1 = await serverVerifier!.getServerHash();
      expect(hash1, isNotEmpty);
      print('✅ Initial hash: $hash1');
      
      // Use event generator to create 10 events (2 contacts + 8 transactions)
      final commands1 = [
        'app1: contact create "Hash Test Contact" contact1',
        'app1: transaction create contact1 owed 1000 "T1" t1',
        'app1: transaction create contact1 lent 500 "T2" t2',
        'app1: transaction create contact1 owed 2000 "T3" t3',
        'app1: transaction create contact1 lent 800 "T4" t4',
      ];
      await generator!.executeCommands(commands1);
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Get new hash
      final hash2 = await serverVerifier!.getServerHash();
      expect(hash2, isNotEmpty);
      expect(hash2 != hash1, true, reason: 'Hash should change after events');
      
      // Create more events
      final commands2 = [
        'app1: contact create "Hash Test Contact 2" contact2',
        'app1: transaction create contact2 lent 500 "T5" t5',
        'app1: transaction create contact2 owed 1500 "T6" t6',
        'app1: transaction create contact2 lent 600 "T7" t7',
        'app1: transaction update t1 amount 1100',
      ];
      await generator!.executeCommands(commands2);
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Get final hash
      print('📥 Getting final hash...');
      final hash3 = await serverVerifier!.getServerHash();
      expect(hash3 != hash2, true, reason: 'Hash should change again');
      print('✅ Final hash: $hash3 (different from previous)');
    });
    
    test('Server: Projection Consistency', () async {
      print('\n📋 Server Test: Projection Consistency');
      
      // Use event generator to create 15 events (1 contact + 14 transactions) with updates
      final commands = [
        'app1: contact create "Projection Test" contact1',
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
        // Updates
        'app1: contact update contact1 name "Updated Projection Test"',
        'app1: transaction update t1 amount 2000',
        'app1: transaction update t3 description "Updated T3"',
        'app1: transaction delete t5',
      ];
      
      print('📝 Creating ${commands.length} events...');
      await generator!.executeCommands(commands);
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Verify events in events table
      final serverEvents = await serverVerifier!.getServerEvents();
      expect(serverEvents.length, greaterThanOrEqualTo(15));
      
      // Verify contact in projections
      final serverContacts = await serverVerifier!.getServerContacts();
      final serverContact = serverContacts.firstWhere(
        (c) => c['name'] == 'Updated Projection Test',
        orElse: () => throw Exception('Contact not found in projection'),
      );
      expect(serverContact['name'], 'Updated Projection Test');
      print('✅ Contact exists in projection with correct data');
      
      // Verify transactions in projections
      final serverTransactions = await serverVerifier!.getServerTransactions();
      // Note: Transaction t5 was deleted, so it won't be in the projection
      expect(serverTransactions.length, greaterThan(8));
      print('✅ Transactions exist in projection');
      
      // Verify updates in projections
      final updatedContact = serverContacts.firstWhere(
        (c) => c['name'] == 'Updated Projection Test',
        orElse: () => throw Exception('Updated contact not found'),
      );
      expect(updatedContact['name'], 'Updated Projection Test');
      print('✅ Projections updated correctly');
    });
    
    test('Server: Event Count and Statistics', () async {
      print('\n📋 Server Test: Event Count and Statistics');
      
      // Get initial count
      print('📥 Getting initial event count...');
      final initialCount = await serverVerifier!.getServerEventCount();
      print('✅ Initial count: $initialCount');
      
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
        'app1: transaction update t3 description "Updated T3"',
        'app1: transaction delete t5',
        'app1: transaction create contact1 owed 1300 "T13" t13',
        'app1: transaction create contact2 lent 500 "T14" t14',
      ];
      
      print('📝 Creating ${commands.length} events...');
      await generator!.executeCommands(commands);
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Get final count
      final finalCount = await serverVerifier!.getServerEventCount();
      expect(finalCount, greaterThanOrEqualTo(initialCount + 20), 
        reason: 'Event count should increase');
      print('✅ Final count: $finalCount (increased by ${finalCount - initialCount})');
      
      // Verify statistics
      final serverEvents = await serverVerifier!.getServerEvents();
      final contactEvents = serverEvents.where((e) => e['aggregate_type'] == 'contact').toList();
      final transactionEvents = serverEvents.where((e) => e['aggregate_type'] == 'transaction').toList();
      
      expect(contactEvents.length, 3);
      expect(transactionEvents.length, greaterThan(15));
      print('✅ Statistics verified: ${contactEvents.length} contacts, ${transactionEvents.length} transactions');
    });
  });
}