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
      await resetServer();
      await waitForServerReady();
      
      try {
        await Hive.box<Contact>('contacts').clear();
        await Hive.box<Transaction>('transactions').clear();
        await Hive.box<Event>('events').clear();
      } catch (e) {
        // Boxes might not exist yet
      }
      
      app1 = await AppInstance.create(id: 'app1', serverUrl: 'http://localhost:8000');
      app2 = await AppInstance.create(id: 'app2', serverUrl: 'http://localhost:8000');
      app3 = await AppInstance.create(id: 'app3', serverUrl: 'http://localhost:8000');
      
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
    });
    
    tearDown(() async {
      await app1?.disconnect();
      await app2?.disconnect();
      await app3?.disconnect();
      
      await app1?.clearData();
      await app2?.clearData();
      await app3?.clearData();
    });
    
    test('5.1 Contact Event Types: CREATED, UPDATED, DELETED', () async {
      print('\n📋 Test 5.1: Contact Event Types - CREATED, UPDATED, DELETED');
      
      // App1 creates contact (CREATED)
      print('📝 App1 creating contact...');
      final contact = await app1!.createContact(name: 'Test Contact');
      await Future.delayed(const Duration(milliseconds: 200));
      
      // Verify CREATED event
      final app1Events = await app1!.getEvents();
      final createdEvent = app1Events.firstWhere(
        (e) => e.aggregateId == contact.id && e.eventType == 'CREATED',
      );
      expect(createdEvent.aggregateType, 'contact');
      expect(createdEvent.eventType, 'CREATED');
      print('✅ CREATED event verified');
      
      // Wait for sync
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // App2 updates contact (UPDATED)
      print('📝 App2 updating contact...');
      await app2!.updateContact(contact.id, {'name': 'Updated Name'});
      await Future.delayed(const Duration(milliseconds: 200));
      
      // Verify UPDATED event
      final app2Events = await app2!.getEvents();
      final updatedEvent = app2Events.firstWhere(
        (e) => e.aggregateId == contact.id && e.eventType == 'UPDATED',
      );
      expect(updatedEvent.aggregateType, 'contact');
      expect(updatedEvent.eventType, 'UPDATED');
      print('✅ UPDATED event verified');
      
      // Wait for sync
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // App3 deletes contact (DELETED)
      print('📝 App3 deleting contact...');
      await app3!.deleteContact(contact.id);
      await Future.delayed(const Duration(milliseconds: 200));
      
      // Verify DELETED event
      final app3Events = await app3!.getEvents();
      final deletedEvent = app3Events.firstWhere(
        (e) => e.aggregateId == contact.id && e.eventType == 'DELETED',
      );
      expect(deletedEvent.aggregateType, 'contact');
      expect(deletedEvent.eventType, 'DELETED');
      print('✅ DELETED event verified');
      
      // Wait for sync
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Verify all events on server
      final serverEvents = await serverVerifier!.getServerEvents();
      final contactEvents = serverEvents.where((e) => e['aggregate_id'] == contact.id).toList();
      expect(contactEvents.length, 3, reason: 'Should have CREATED, UPDATED, DELETED events');
      
      final eventTypes = contactEvents.map((e) => e['event_type'] as String).toList();
      expect(eventTypes.contains('CREATED'), true);
      expect(eventTypes.contains('UPDATED'), true);
      expect(eventTypes.contains('DELETED'), true);
      print('✅ All contact event types verified on server');
      
      // Verify consistency
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true);
      print('✅ Event consistency validated');
    });
    
    test('5.2 Transaction Event Types: CREATED, UPDATED, DELETED', () async {
      print('\n📋 Test 5.2: Transaction Event Types - CREATED, UPDATED, DELETED');
      
      // Create contact first (needed for transaction)
      print('📝 Creating contact...');
      final contact = await app1!.createContact(name: 'Contact for Transaction');
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // App1 creates transaction (CREATED)
      print('📝 App1 creating transaction...');
      final transaction = await app1!.createTransaction(
        contactId: contact.id,
        direction: TransactionDirection.owed,
        amount: 1000,
        description: 'Test transaction',
      );
      await Future.delayed(const Duration(milliseconds: 200));
      
      // Verify CREATED event
      final app1Events = await app1!.getEvents();
      final createdEvent = app1Events.firstWhere(
        (e) => e.aggregateId == transaction.id && e.eventType == 'CREATED',
      );
      expect(createdEvent.aggregateType, 'transaction');
      expect(createdEvent.eventType, 'CREATED');
      print('✅ CREATED event verified');
      
      // Wait for sync
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // App2 updates transaction (UPDATED)
      print('📝 App2 updating transaction...');
      await app2!.updateTransaction(transaction.id, {'amount': 2000});
      await Future.delayed(const Duration(milliseconds: 200));
      
      // Verify UPDATED event
      final app2Events = await app2!.getEvents();
      final updatedEvent = app2Events.firstWhere(
        (e) => e.aggregateId == transaction.id && e.eventType == 'UPDATED',
      );
      expect(updatedEvent.aggregateType, 'transaction');
      expect(updatedEvent.eventType, 'UPDATED');
      print('✅ UPDATED event verified');
      
      // Wait for sync
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // App3 deletes transaction (DELETED)
      print('📝 App3 deleting transaction...');
      await app3!.deleteTransaction(transaction.id);
      await Future.delayed(const Duration(milliseconds: 200));
      
      // Verify DELETED event
      final app3Events = await app3!.getEvents();
      final deletedEvent = app3Events.firstWhere(
        (e) => e.aggregateId == transaction.id && e.eventType == 'DELETED',
      );
      expect(deletedEvent.aggregateType, 'transaction');
      expect(deletedEvent.eventType, 'DELETED');
      print('✅ DELETED event verified');
      
      // Wait for sync
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Verify all events on server
      final serverEvents = await serverVerifier!.getServerEvents();
      final transactionEvents = serverEvents.where((e) => e['aggregate_id'] == transaction.id).toList();
      expect(transactionEvents.length, 3, reason: 'Should have CREATED, UPDATED, DELETED events');
      
      final eventTypes = transactionEvents.map((e) => e['event_type'] as String).toList();
      expect(eventTypes.contains('CREATED'), true);
      expect(eventTypes.contains('UPDATED'), true);
      expect(eventTypes.contains('DELETED'), true);
      print('✅ All transaction event types verified on server');
      
      // Verify consistency
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true);
      print('✅ Event consistency validated');
    });
    
    test('5.3 Mixed Operations: Contacts and Transactions', () async {
      print('\n📋 Test 5.3: Mixed Operations - Contacts and Transactions');
      
      // App1 creates contact
      print('📝 App1 creating contact...');
      final contact1 = await app1!.createContact(name: 'Contact 1');
      final contact2 = await app1!.createContact(name: 'Contact 2');
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // App2 creates transactions for contact1
      print('📝 App2 creating transactions...');
      final transaction1 = await app2!.createTransaction(
        contactId: contact1.id,
        direction: TransactionDirection.owed,
        amount: 1000,
      );
      final transaction2 = await app2!.createTransaction(
        contactId: contact1.id,
        direction: TransactionDirection.lent,
        amount: 500,
      );
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // App3 updates contact and transaction
      print('📝 App3 updating contact and transaction...');
      await app3!.updateContact(contact1.id, {'name': 'Updated Contact 1'});
      await app3!.updateTransaction(transaction1.id, {'amount': 1500});
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Verify all event types exist
      final allEvents = await app1!.getEvents();
      final contactEvents = allEvents.where((e) => e.aggregateType == 'contact').toList();
      final transactionEvents = allEvents.where((e) => e.aggregateType == 'transaction').toList();
      
      expect(contactEvents.length, greaterThan(0), reason: 'Should have contact events');
      expect(transactionEvents.length, greaterThan(0), reason: 'Should have transaction events');
      
      final contactEventTypes = contactEvents.map((e) => e.eventType).toSet();
      final transactionEventTypes = transactionEvents.map((e) => e.eventType).toSet();
      
      expect(contactEventTypes.contains('CREATED'), true);
      expect(contactEventTypes.contains('UPDATED'), true);
      expect(transactionEventTypes.contains('CREATED'), true);
      expect(transactionEventTypes.contains('UPDATED'), true);
      
      print('✅ Mixed operations verified: ${contactEvents.length} contact events, ${transactionEvents.length} transaction events');
      
      // Verify on server
      final serverEvents = await serverVerifier!.getServerEvents();
      final serverContactEvents = serverEvents.where((e) => e['aggregate_type'] == 'contact').toList();
      final serverTransactionEvents = serverEvents.where((e) => e['aggregate_type'] == 'transaction').toList();
      
      expect(serverContactEvents.length, greaterThan(0));
      expect(serverTransactionEvents.length, greaterThan(0));
      print('✅ Mixed operations verified on server');
      
      // Verify consistency
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true);
      print('✅ Event consistency validated');
    });
    
    test('5.4 Concurrent Mixed Operations', () async {
      print('\n📋 Test 5.4: Concurrent Mixed Operations');
      
      // All apps create contacts and transactions simultaneously
      print('📝 All apps creating contacts and transactions simultaneously...');
      
      // Create contacts first (needed for transactions)
      final contact1 = await app1!.createContact(name: 'Contact from App1');
      final contact2 = await app2!.createContact(name: 'Contact from App2');
      final contact3 = await app3!.createContact(name: 'Contact from App3');
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // All apps create transactions simultaneously
      final futures = [
        app1!.createTransaction(contactId: contact1.id, direction: TransactionDirection.owed, amount: 1000),
        app1!.createTransaction(contactId: contact2.id, direction: TransactionDirection.lent, amount: 500),
        app2!.createTransaction(contactId: contact2.id, direction: TransactionDirection.owed, amount: 2000),
        app2!.createTransaction(contactId: contact3.id, direction: TransactionDirection.lent, amount: 750),
        app3!.createTransaction(contactId: contact3.id, direction: TransactionDirection.owed, amount: 3000),
        app3!.createTransaction(contactId: contact1.id, direction: TransactionDirection.lent, amount: 1000),
      ];
      
      final transactions = await Future.wait(futures);
      print('✅ All ${transactions.length} transactions created');
      
      // Wait for sync
      await monitor!.waitForSync(timeout: const Duration(seconds: 90));
      
      // Verify all events synced
      final allEvents = await app1!.getEvents();
      final contactEvents = allEvents.where((e) => e.aggregateType == 'contact').toList();
      final transactionEvents = allEvents.where((e) => e.aggregateType == 'transaction').toList();
      
      expect(contactEvents.length, 3, reason: 'Should have 3 contact CREATED events');
      expect(transactionEvents.length, 6, reason: 'Should have 6 transaction CREATED events');
      
      // Verify all events synced
      for (final event in [...contactEvents, ...transactionEvents]) {
        expect(event.synced, true, reason: 'Event ${event.id} should be synced');
      }
      
      print('✅ All ${contactEvents.length + transactionEvents.length} events synced');
      
      // Verify on server
      final serverEvents = await serverVerifier!.getServerEvents();
      final serverContactEvents = serverEvents.where((e) => e['aggregate_type'] == 'contact').toList();
      final serverTransactionEvents = serverEvents.where((e) => e['aggregate_type'] == 'transaction').toList();
      
      expect(serverContactEvents.length, 3);
      expect(serverTransactionEvents.length, 6);
      print('✅ All events verified on server');
      
      // Verify consistency
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true);
      print('✅ Event consistency validated');
    });
    
    test('5.5 Full Lifecycle: Create, Update, Delete for Both Types', () async {
      print('\n📋 Test 5.5: Full Lifecycle - Create, Update, Delete for Both Types');
      
      // Create contact and transaction
      print('📝 Creating contact and transaction...');
      final contact = await app1!.createContact(name: 'Lifecycle Contact');
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      final transaction = await app1!.createTransaction(
        contactId: contact.id,
        direction: TransactionDirection.owed,
        amount: 1000,
      );
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Update both
      print('📝 Updating contact and transaction...');
      await app2!.updateContact(contact.id, {'name': 'Updated Lifecycle Contact'});
      await app2!.updateTransaction(transaction.id, {'amount': 2000});
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Delete both
      print('📝 Deleting transaction and contact...');
      await app3!.deleteTransaction(transaction.id);
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      await app3!.deleteContact(contact.id);
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Verify all event types for both aggregates
      final allEvents = await app1!.getEvents();
      final contactEvents = allEvents.where((e) => e.aggregateId == contact.id).toList();
      final transactionEvents = allEvents.where((e) => e.aggregateId == transaction.id).toList();
      
      expect(contactEvents.length, 3, reason: 'Contact should have CREATED, UPDATED, DELETED');
      expect(transactionEvents.length, 3, reason: 'Transaction should have CREATED, UPDATED, DELETED');
      
      final contactEventTypes = contactEvents.map((e) => e.eventType).toSet();
      final transactionEventTypes = transactionEvents.map((e) => e.eventType).toSet();
      
      expect(contactEventTypes.contains('CREATED'), true);
      expect(contactEventTypes.contains('UPDATED'), true);
      expect(contactEventTypes.contains('DELETED'), true);
      expect(transactionEventTypes.contains('CREATED'), true);
      expect(transactionEventTypes.contains('UPDATED'), true);
      expect(transactionEventTypes.contains('DELETED'), true);
      
      print('✅ Full lifecycle verified for both contact and transaction');
      
      // Verify on server
      final serverEvents = await serverVerifier!.getServerEvents();
      final serverContactEvents = serverEvents.where((e) => e['aggregate_id'] == contact.id).toList();
      final serverTransactionEvents = serverEvents.where((e) => e['aggregate_id'] == transaction.id).toList();
      
      expect(serverContactEvents.length, 3);
      expect(serverTransactionEvents.length, 3);
      print('✅ Full lifecycle verified on server');
      
      // Verify consistency
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true);
      print('✅ Event consistency validated');
    });
  });
}