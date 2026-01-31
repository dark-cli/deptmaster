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
    
    test('5.1 Full Resync After Disconnect', () async {
      print('\n📋 Test 5.1: Full Resync After Disconnect');
      
      // App1 disconnects
      print('📴 App1 disconnecting...');
      await app1!.disconnect();
      
      // App2 and App3 create many events (contacts and transactions)
      print('📝 App2 and App3 creating events...');
      final contacts = <Contact>[];
      final transactions = <Transaction>[];
      for (int i = 0; i < 5; i++) {
        final contact2 = await app2!.createContact(name: 'Contact from App2 #$i');
        final contact3 = await app3!.createContact(name: 'Contact from App3 #$i');
        contacts.add(contact2);
        contacts.add(contact3);
        
        final transaction2 = await app2!.createTransaction(
          contactId: contact2.id,
          direction: TransactionDirection.owed,
          amount: 1000 + i * 100,
        );
        final transaction3 = await app3!.createTransaction(
          contactId: contact3.id,
          direction: TransactionDirection.lent,
          amount: 500 + i * 50,
        );
        transactions.add(transaction2);
        transactions.add(transaction3);
        await Future.delayed(const Duration(milliseconds: 300));
      }
      print('✅ ${contacts.length} contacts and ${transactions.length} transactions created');
      
      // Wait for App2 and App3 to sync
      print('⏳ Waiting for App2 and App3 to sync...');
      await Future.delayed(const Duration(seconds: 5));
      
      // Verify events on server
      final serverEvents = await serverVerifier!.getServerEvents();
      final contactEvents = serverEvents.where((e) => e['aggregate_type'] == 'contact').toList();
      final transactionEvents = serverEvents.where((e) => e['aggregate_type'] == 'transaction').toList();
      expect(contactEvents.length, greaterThanOrEqualTo(contacts.length),
        reason: 'Server should have all contact events');
      expect(transactionEvents.length, greaterThanOrEqualTo(transactions.length),
        reason: 'Server should have all transaction events');
      print('✅ Events synced to server');
      
      // App1 reconnects
      print('📶 App1 reconnecting...');
      await app1!.login();
      
      // Wait for App1 to fetch all missed events
      print('⏳ Waiting for App1 to resync...');
      await monitor!.waitForSync(timeout: const Duration(seconds: 90));
      await Future.delayed(const Duration(seconds: 2));
      
      // Verify App1 has all events
      final app1Events = await app1!.getEvents();
      for (final contact in contacts) {
        final event = app1Events.where(
          (e) => e.aggregateId == contact.id && e.eventType == 'CREATED' && e.aggregateType == 'contact',
        ).toList();
        expect(event.isNotEmpty, true, 
          reason: 'App1 should have event for contact ${contact.id}');
      }
      for (final transaction in transactions) {
        final event = app1Events.where(
          (e) => e.aggregateId == transaction.id && e.eventType == 'CREATED' && e.aggregateType == 'transaction',
        ).toList();
        expect(event.isNotEmpty, true, 
          reason: 'App1 should have event for transaction ${transaction.id}');
      }
      print('✅ App1 fetched all missed events');
      
      // Verify state rebuilt correctly
      final app1Contacts = await app1!.getContacts();
      final app1Transactions = await app1!.getTransactions();
      expect(app1Contacts.length, greaterThanOrEqualTo(contacts.length),
        reason: 'App1 should have all contacts');
      expect(app1Transactions.length, greaterThanOrEqualTo(transactions.length),
        reason: 'App1 should have all transactions');
      print('✅ State rebuilt correctly');
      
      // Verify all apps in sync
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true, reason: 'All apps should be in sync');
      print('✅ All apps in sync');
    });
    
    test('5.2 Hash Mismatch Resync', () async {
      print('\n📋 Test 5.2: Hash Mismatch Resync');
      
      // Create some events in all apps
      print('📝 Creating initial events...');
      final contact1 = await app1!.createContact(name: 'Initial Contact 1');
      final contact2 = await app2!.createContact(name: 'Initial Contact 2');
      
      final transaction1 = await app1!.createTransaction(
        contactId: contact1.id,
        direction: TransactionDirection.owed,
        amount: 1000,
      );
      final transaction2 = await app2!.createTransaction(
        contactId: contact2.id,
        direction: TransactionDirection.lent,
        amount: 500,
      );
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      await Future.delayed(const Duration(seconds: 2));
      
      // Get server hash
      final serverHashBefore = await serverVerifier!.getServerHash();
      print('✅ Server hash: $serverHashBefore');
      
      // App1 disconnects
      print('📴 App1 disconnecting...');
      await app1!.disconnect();
      
      // App2 and App3 create more events (contacts and transactions)
      print('📝 App2 and App3 creating more events...');
      final newContacts = <Contact>[];
      for (int i = 0; i < 3; i++) {
        final contact2 = await app2!.createContact(name: 'New Contact from App2 #$i');
        final contact3 = await app3!.createContact(name: 'New Contact from App3 #$i');
        newContacts.add(contact2);
        newContacts.add(contact3);
        
        await app2!.createTransaction(
          contactId: contact2.id,
          direction: TransactionDirection.owed,
          amount: 1000 + i * 100,
        );
        await app3!.createTransaction(
          contactId: contact3.id,
          direction: TransactionDirection.lent,
          amount: 500 + i * 50,
        );
        await Future.delayed(const Duration(milliseconds: 300));
      }
      
      // Wait for sync
      await Future.delayed(const Duration(seconds: 5));
      
      // Get new server hash
      final serverHashAfter = await serverVerifier!.getServerHash();
      expect(serverHashAfter != serverHashBefore, true, 
        reason: 'Server hash should have changed');
      print('✅ Server hash changed: $serverHashAfter');
      
      // App1 reconnects (hash mismatch should trigger full resync)
      print('📶 App1 reconnecting (hash mismatch expected)...');
      await app1!.login();
      
      // Wait for resync
      print('⏳ Waiting for hash mismatch resync...');
      await monitor!.waitForSync(timeout: const Duration(seconds: 90));
      await Future.delayed(const Duration(seconds: 2));
      
      // Verify App1 has all events
      final app1Events = await app1!.getEvents();
      expect(app1Events.length, greaterThan(0), reason: 'App1 should have events');
      print('✅ App1 has all events after resync');
      
      // Verify hash matches
      final app1Contacts = await app1!.getContacts();
      expect(app1Contacts.length, greaterThan(2), 
        reason: 'App1 should have all contacts');
      print('✅ Hash matches - full resync completed');
      
      // Validate consistency
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true, reason: 'All instances should have consistent events');
      print('✅ Event consistency validated');
    });
    
    test('5.3 Incremental Resync', () async {
      print('\n📋 Test 5.3: Incremental Resync');
      
      // Create initial events
      print('📝 Creating initial events...');
      final contact1 = await app1!.createContact(name: 'Initial Contact');
      final transaction1 = await app1!.createTransaction(
        contactId: contact1.id,
        direction: TransactionDirection.owed,
        amount: 1000,
      );
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      await Future.delayed(const Duration(seconds: 2));
      
      // Verify all apps have initial events
      final allContacts = await app1!.getContacts();
      final allTransactions = await app1!.getTransactions();
      expect(allContacts.any((c) => c.id == contact1.id), true);
      expect(allTransactions.any((t) => t.id == transaction1.id), true);
      print('✅ Initial events synced');
      
      // App1 disconnects briefly
      print('📴 App1 disconnecting briefly...');
      await app1!.disconnect();
      await Future.delayed(const Duration(seconds: 1));
      
      // App2 creates events after App1's last sync timestamp (contacts and transactions)
      print('📝 App2 creating events after App1 disconnect...');
      final newContacts = <Contact>[];
      final newTransactions = <Transaction>[];
      for (int i = 0; i < 3; i++) {
        final contact = await app2!.createContact(name: 'New Contact #$i');
        newContacts.add(contact);
        
        final transaction = await app2!.createTransaction(
          contactId: contact.id,
          direction: TransactionDirection.owed,
          amount: 1000 + i * 100,
        );
        newTransactions.add(transaction);
        await Future.delayed(const Duration(milliseconds: 300));
      }
      
      // Wait for App2 to sync
      await Future.delayed(const Duration(seconds: 3));
      
      // App1 reconnects
      print('📶 App1 reconnecting...');
      await app1!.login();
      
      // Wait for incremental sync
      print('⏳ Waiting for incremental resync...');
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      await Future.delayed(const Duration(seconds: 2));
      
      // Verify App1 received only new events (incremental)
      final app1Events = await app1!.getEvents();
      final app1NewContactEvents = app1Events.where(
        (e) => newContacts.any((c) => c.id == e.aggregateId && e.eventType == 'CREATED' && e.aggregateType == 'contact'),
      ).toList();
      final app1NewTransactionEvents = app1Events.where(
        (e) => newTransactions.any((t) => t.id == e.aggregateId && e.eventType == 'CREATED' && e.aggregateType == 'transaction'),
      ).toList();
      expect(app1NewContactEvents.length, newContacts.length,
        reason: 'App1 should have all new contact events');
      expect(app1NewTransactionEvents.length, newTransactions.length,
        reason: 'App1 should have all new transaction events');
      print('✅ Incremental sync worked - App1 received new events');
      
      // Verify state updated correctly
      final app1Contacts = await app1!.getContacts();
      final app1Transactions = await app1!.getTransactions();
      for (final contact in newContacts) {
        expect(app1Contacts.any((c) => c.id == contact.id), true,
          reason: 'App1 should have contact ${contact.id}');
      }
      for (final transaction in newTransactions) {
        expect(app1Transactions.any((t) => t.id == transaction.id), true,
          reason: 'App1 should have transaction ${transaction.id}');
      }
      print('✅ State updated correctly');
      
      // Validate consistency
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true, reason: 'All instances should have consistent events');
      print('✅ Event consistency validated');
    });
  });
}