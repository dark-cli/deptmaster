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
import '../../helpers/multi_app_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  group('Server-Side Scenarios', () {
    AppInstance? app1;
    ServerVerifier? serverVerifier;
    SyncMonitor? monitor;
    
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
      
      // Create app instance
      app1 = await AppInstance.create(id: 'app1', serverUrl: 'http://localhost:8000');
      await app1!.initialize();
      await app1!.login();
      
      // Create server verifier and monitor
      serverVerifier = ServerVerifier(serverUrl: 'http://localhost:8000');
      await serverVerifier!.setAuthToken();
      monitor = SyncMonitor([app1!]);
    });
    
    tearDown(() async {
      await app1?.disconnect();
      await app1?.clearData();
    });
    
    test('Server 1: Event Storage', () async {
      print('\n📋 Server Test 1: Event Storage');
      
      // Create contact and transaction
      print('📝 Creating contact and transaction...');
      final contact = await app1!.createContact(name: 'Test Contact');
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      final transaction = await app1!.createTransaction(
        contactId: contact.id,
        direction: TransactionDirection.owed,
        amount: 1000,
      );
      await Future.delayed(const Duration(seconds: 3)); // Wait for sync
      
      // Verify both events stored in database via API
      final serverEvents = await serverVerifier!.getServerEvents();
      final serverContactEvent = serverEvents.firstWhere(
        (e) => e['aggregate_id'] == contact.id && e['event_type'] == 'CREATED' && e['aggregate_type'] == 'contact',
        orElse: () => throw Exception('Contact event not found on server'),
      );
      final serverTransactionEvent = serverEvents.firstWhere(
        (e) => e['aggregate_id'] == transaction.id && e['event_type'] == 'CREATED' && e['aggregate_type'] == 'transaction',
        orElse: () => throw Exception('Transaction event not found on server'),
      );
      
      expect(serverContactEvent['event_type'], 'CREATED');
      expect(serverContactEvent['aggregate_id'], contact.id);
      expect(serverContactEvent['aggregate_type'], 'contact');
      expect(serverTransactionEvent['event_type'], 'CREATED');
      expect(serverTransactionEvent['aggregate_id'], transaction.id);
      expect(serverTransactionEvent['aggregate_type'], 'transaction');
      print('✅ Both events stored correctly in database');
      
      // Verify event data integrity
      final contactEventData = serverContactEvent['event_data'] as Map<String, dynamic>;
      final transactionEventData = serverTransactionEvent['event_data'] as Map<String, dynamic>;
      expect(contactEventData['name'], 'Test Contact');
      expect(transactionEventData['amount'], 1000);
      print('✅ Event data integrity verified');
    });
    
    test('Server 2: Event Retrieval', () async {
      print('\n📋 Server Test 2: Event Retrieval');
      
      // Create multiple contacts and transactions
      print('📝 Creating multiple contacts and transactions...');
      final contacts = <Contact>[];
      final transactions = <Transaction>[];
      for (int i = 0; i < 5; i++) {
        final contact = await app1!.createContact(name: 'Contact $i');
        contacts.add(contact);
        
        final transaction = await app1!.createTransaction(
          contactId: contact.id,
          direction: TransactionDirection.owed,
          amount: 1000 + i * 100,
        );
        transactions.add(transaction);
        await Future.delayed(const Duration(milliseconds: 300));
      }
      await Future.delayed(const Duration(seconds: 3)); // Wait for sync
      
      // Test GET /api/sync/events without timestamp (all events)
      print('📥 Testing GET /api/sync/events (all events)...');
      final allEvents = await serverVerifier!.getServerEvents();
      final contactEvents = allEvents.where((e) => e['aggregate_type'] == 'contact').toList();
      final transactionEvents = allEvents.where((e) => e['aggregate_type'] == 'transaction').toList();
      expect(contactEvents.length, greaterThanOrEqualTo(contacts.length),
        reason: 'Should retrieve all contact events');
      expect(transactionEvents.length, greaterThanOrEqualTo(transactions.length),
        reason: 'Should retrieve all transaction events');
      print('✅ Retrieved all events: ${allEvents.length} (${contactEvents.length} contacts, ${transactionEvents.length} transactions)');
      
      // Test GET /api/sync/events with timestamp (incremental)
      print('📥 Testing GET /api/sync/events (with timestamp)...');
      final since = DateTime.now().subtract(const Duration(minutes: 1));
      final recentEvents = await serverVerifier!.getServerEvents(since: since);
      final recentContactEvents = recentEvents.where((e) => e['aggregate_type'] == 'contact').toList();
      final recentTransactionEvents = recentEvents.where((e) => e['aggregate_type'] == 'transaction').toList();
      expect(recentContactEvents.length, greaterThanOrEqualTo(contacts.length),
        reason: 'Should retrieve recent contact events');
      expect(recentTransactionEvents.length, greaterThanOrEqualTo(transactions.length),
        reason: 'Should retrieve recent transaction events');
      print('✅ Retrieved recent events: ${recentEvents.length}');
      
      // Verify all contacts and transactions are in the events
      for (final contact in contacts) {
        final event = allEvents.where(
          (e) => e['aggregate_id'] == contact.id && e['aggregate_type'] == 'contact',
        ).toList();
        expect(event.isNotEmpty, true, reason: 'Event for contact ${contact.id} should exist');
      }
      for (final transaction in transactions) {
        final event = allEvents.where(
          (e) => e['aggregate_id'] == transaction.id && e['aggregate_type'] == 'transaction',
        ).toList();
        expect(event.isNotEmpty, true, reason: 'Event for transaction ${transaction.id} should exist');
      }
      print('✅ All contacts and transactions found in events');
    });
    
    test('Server 3: Event Acceptance', () async {
      print('\n📋 Server Test 3: Event Acceptance');
      
      // Create contact and transaction (valid events)
      print('📝 Creating contact and transaction (valid events)...');
      final contact = await app1!.createContact(name: 'Valid Contact');
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      final transaction = await app1!.createTransaction(
        contactId: contact.id,
        direction: TransactionDirection.owed,
        amount: 1000,
      );
      await Future.delayed(const Duration(seconds: 3));
      
      // Verify both events accepted
      final serverEvents = await serverVerifier!.getServerEvents();
      final serverContactEvent = serverEvents.firstWhere(
        (e) => e['aggregate_id'] == contact.id && e['aggregate_type'] == 'contact',
        orElse: () => throw Exception('Contact event not found'),
      );
      final serverTransactionEvent = serverEvents.firstWhere(
        (e) => e['aggregate_id'] == transaction.id && e['aggregate_type'] == 'transaction',
        orElse: () => throw Exception('Transaction event not found'),
      );
      expect(serverContactEvent['event_type'], 'CREATED');
      expect(serverTransactionEvent['event_type'], 'CREATED');
      print('✅ Both valid events accepted');
      
      // Verify both events have required fields
      for (final event in [serverContactEvent, serverTransactionEvent]) {
        expect(event['id'], isNotNull);
        expect(event['aggregate_id'], isNotNull);
        expect(event['aggregate_type'], isNotNull);
        expect(event['event_type'], isNotNull);
        expect(event['event_data'], isNotNull);
        expect(event['timestamp'], isNotNull);
      }
      print('✅ Both events have all required fields');
    });
    
    test('Server 4: Hash Calculation', () async {
      print('\n📋 Server Test 4: Hash Calculation');
      
      // Get initial hash
      print('📥 Getting initial hash...');
      final hash1 = await serverVerifier!.getServerHash();
      expect(hash1, isNotEmpty);
      print('✅ Initial hash: $hash1');
      
      // Create contact and transaction
      print('📝 Creating contact and transaction...');
      final contact = await app1!.createContact(name: 'Hash Test Contact');
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      final transaction = await app1!.createTransaction(
        contactId: contact.id,
        direction: TransactionDirection.owed,
        amount: 1000,
      );
      await Future.delayed(const Duration(seconds: 3));
      
      // Get new hash
      print('📥 Getting new hash...');
      final hash2 = await serverVerifier!.getServerHash();
      expect(hash2, isNotEmpty);
      expect(hash2 != hash1, true, reason: 'Hash should change after events');
      print('✅ New hash: $hash2 (different from initial)');
      
      // Create another contact and transaction
      print('📝 Creating another contact and transaction...');
      final contact2 = await app1!.createContact(name: 'Hash Test Contact 2');
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      await app1!.createTransaction(
        contactId: contact2.id,
        direction: TransactionDirection.lent,
        amount: 500,
      );
      await Future.delayed(const Duration(seconds: 3));
      
      // Get final hash
      print('📥 Getting final hash...');
      final hash3 = await serverVerifier!.getServerHash();
      expect(hash3 != hash2, true, reason: 'Hash should change again');
      print('✅ Final hash: $hash3 (different from previous)');
    });
    
    test('Server 5: Projection Consistency', () async {
      print('\n📋 Server Test 5: Projection Consistency');
      
      // Create contact and transaction
      print('📝 Creating contact and transaction...');
      final contact = await app1!.createContact(
        name: 'Projection Test',
        email: 'test@example.com',
        phone: '1234567890',
      );
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      final transaction = await app1!.createTransaction(
        contactId: contact.id,
        direction: TransactionDirection.owed,
        amount: 1000,
      );
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      await Future.delayed(const Duration(seconds: 2));
      
      // Verify events in events table
      final serverEvents = await serverVerifier!.getServerEvents();
      final serverContactEvent = serverEvents.firstWhere(
        (e) => e['aggregate_id'] == contact.id && e['aggregate_type'] == 'contact',
        orElse: () => throw Exception('Contact event not found'),
      );
      final serverTransactionEvent = serverEvents.firstWhere(
        (e) => e['aggregate_id'] == transaction.id && e['aggregate_type'] == 'transaction',
        orElse: () => throw Exception('Transaction event not found'),
      );
      expect(serverContactEvent['event_type'], 'CREATED');
      expect(serverTransactionEvent['event_type'], 'CREATED');
      print('✅ Both events exist in events table');
      
      // Verify contact in projections (via API - get all contacts and find by ID)
      final serverContacts = await serverVerifier!.getServerContacts();
      final serverContact = serverContacts.firstWhere(
        (c) => c['id'] == contact.id,
        orElse: () => throw Exception('Contact not found in projection'),
      );
      expect(serverContact['name'], 'Projection Test');
      expect(serverContact['email'], 'test@example.com');
      expect(serverContact['phone'], '1234567890');
      print('✅ Contact exists in projection with correct data');
      
      // Verify transaction in projections (via API - get all transactions and find by ID)
      final serverTransactions = await serverVerifier!.getServerTransactions();
      final serverTransaction = serverTransactions.firstWhere(
        (t) => t['id'] == transaction.id,
        orElse: () => throw Exception('Transaction not found in projection'),
      );
      expect(serverTransaction['amount'], 1000);
      print('✅ Transaction exists in projection with correct data');
      
      // Update contact and transaction
      print('📝 Updating contact and transaction...');
      await app1!.updateContact(contact.id, {'name': 'Updated Projection Test'});
      await app1!.updateTransaction(transaction.id, {'amount': 2000});
      await Future.delayed(const Duration(seconds: 3));
      
      // Verify updates in projections
      final updatedServerContacts = await serverVerifier!.getServerContacts();
      final updatedServerTransactions = await serverVerifier!.getServerTransactions();
      final updatedContact = updatedServerContacts.firstWhere(
        (c) => c['id'] == contact.id,
        orElse: () => throw Exception('Updated contact not found'),
      );
      final updatedTransaction = updatedServerTransactions.firstWhere(
        (t) => t['id'] == transaction.id,
        orElse: () => throw Exception('Updated transaction not found'),
      );
      expect(updatedContact['name'], 'Updated Projection Test');
      expect(updatedTransaction['amount'], 2000);
      print('✅ Projections updated correctly');
    });
    
    test('Server 6: Event Count and Statistics', () async {
      print('\n📋 Server Test 6: Event Count and Statistics');
      
      // Get initial count
      print('📥 Getting initial event count...');
      final initialCount = await serverVerifier!.getServerEventCount();
      print('✅ Initial count: $initialCount');
      
      // Create multiple contacts and transactions
      print('📝 Creating multiple contacts and transactions...');
      final count = 10;
      final contacts = <Contact>[];
      for (int i = 0; i < count; i++) {
        final contact = await app1!.createContact(name: 'Contact $i');
        contacts.add(contact);
        await Future.delayed(const Duration(milliseconds: 200));
        
        await app1!.createTransaction(
          contactId: contact.id,
          direction: TransactionDirection.owed,
          amount: 1000 + i * 100,
        );
        await Future.delayed(const Duration(milliseconds: 200));
      }
      await Future.delayed(const Duration(seconds: 5)); // Wait for sync
      
      // Get final count
      print('📥 Getting final event count...');
      final finalCount = await serverVerifier!.getServerEventCount();
      // Should have at least count contacts + count transactions = 2*count events
      expect(finalCount, greaterThanOrEqualTo(initialCount + count * 2),
        reason: 'Event count should have increased by at least ${count * 2} (contacts + transactions)');
      print('✅ Final count: $finalCount (increased by at least ${count * 2})');
      
      // Verify all events are retrievable
      final allEvents = await serverVerifier!.getServerEvents();
      final contactEvents = allEvents.where((e) => e['aggregate_type'] == 'contact').toList();
      final transactionEvents = allEvents.where((e) => e['aggregate_type'] == 'transaction').toList();
      expect(contactEvents.length, greaterThanOrEqualTo(count),
        reason: 'Should have at least $count contact events');
      expect(transactionEvents.length, greaterThanOrEqualTo(count),
        reason: 'Should have at least $count transaction events');
      print('✅ All events are retrievable');
    });
  });
}