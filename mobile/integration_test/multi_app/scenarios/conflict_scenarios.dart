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
  
  group('Conflict Scenarios', () {
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
    
    test('3.1 Simultaneous Updates (Contact & Transaction)', () async {
      print('\n📋 Test 3.1: Simultaneous Updates (Contact & Transaction)');
      
      // Create contact and transaction
      print('📝 Creating contact and transaction in App1...');
      final contact = await app1!.createContact(name: 'Original Name');
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      final transaction = await app1!.createTransaction(
        contactId: contact.id,
        direction: TransactionDirection.owed,
        amount: 1000,
      );
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Verify both exist in all apps
      final allContacts = await app1!.getContacts();
      final allTransactions = await app1!.getTransactions();
      expect(allContacts.any((c) => c.id == contact.id), true);
      expect(allTransactions.any((t) => t.id == transaction.id), true);
      print('✅ Contact and transaction exist in all apps');
      
      // App1 and App2 update both simultaneously
      print('📝 App1 and App2 updating contact and transaction simultaneously...');
      await Future.wait([
        app1!.updateContact(contact.id, {'name': 'Updated by App1'}),
        app2!.updateContact(contact.id, {'name': 'Updated by App2'}),
        app1!.updateTransaction(transaction.id, {'amount': 2000}),
        app2!.updateTransaction(transaction.id, {'amount': 3000}),
      ]);
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Verify all updates created events
      final allEvents = await app1!.getEvents();
      final contactUpdates = allEvents.where((e) => 
        e.aggregateId == contact.id && e.eventType == 'UPDATED' && e.aggregateType == 'contact'
      ).toList();
      final transactionUpdates = allEvents.where((e) => 
        e.aggregateId == transaction.id && e.eventType == 'UPDATED' && e.aggregateType == 'transaction'
      ).toList();
      
      expect(contactUpdates.length, greaterThanOrEqualTo(2), reason: 'Should have at least 2 contact updates');
      expect(transactionUpdates.length, greaterThanOrEqualTo(2), reason: 'Should have at least 2 transaction updates');
      print('✅ All updates created events');
      
      // Wait for sync
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      await Future.delayed(const Duration(seconds: 2));
      
      // Verify all events synced to server
      final serverEvents = await serverVerifier!.getServerEvents();
      final serverContactUpdates = serverEvents.where((e) => 
        e['aggregate_id'] == contact.id && e['event_type'] == 'UPDATED' && e['aggregate_type'] == 'contact'
      ).toList();
      final serverTransactionUpdates = serverEvents.where((e) => 
        e['aggregate_id'] == transaction.id && e['event_type'] == 'UPDATED' && e['aggregate_type'] == 'transaction'
      ).toList();
      
      expect(serverContactUpdates.length, greaterThanOrEqualTo(2));
      expect(serverTransactionUpdates.length, greaterThanOrEqualTo(2));
      print('✅ All events synced to server');
      
      // Verify final state consistent
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true);
      print('✅ Final state consistent');
      
      // Verify both exist with updated values
      final contactsAfter = await app1!.getContacts();
      final transactionsAfter = await app1!.getTransactions();
      final finalContact = contactsAfter.firstWhere((c) => c.id == contact.id);
      final finalTransaction = transactionsAfter.firstWhere((t) => t.id == transaction.id);
      expect(finalContact.name, isNotEmpty);
      expect(finalTransaction.amount, greaterThan(0));
      print('✅ Conflicts resolved - both updated');
    });
    
    test('3.2 Update-Delete Conflict (Contact & Transaction)', () async {
      print('\n📋 Test 3.2: Update-Delete Conflict (Contact & Transaction)');
      
      // Create contact and transaction
      print('📝 Creating contact and transaction in App1...');
      final contact = await app1!.createContact(name: 'Contact to Conflict');
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      final transaction = await app1!.createTransaction(
        contactId: contact.id,
        direction: TransactionDirection.owed,
        amount: 1000,
      );
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Verify both exist
      final allContacts = await app1!.getContacts();
      final allTransactions = await app1!.getTransactions();
      expect(allContacts.any((c) => c.id == contact.id), true);
      expect(allTransactions.any((t) => t.id == transaction.id), true);
      print('✅ Contact and transaction exist');
      
      // App1 updates contact, App2 deletes contact
      // App1 updates transaction, App2 deletes transaction
      print('📝 App1 updating, App2 deleting both...');
      await Future.wait([
        app1!.updateContact(contact.id, {'name': 'Updated Name'}),
        app2!.deleteContact(contact.id),
        app1!.updateTransaction(transaction.id, {'amount': 2000}),
        app2!.deleteTransaction(transaction.id),
      ]);
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Verify all events created
      final allEvents = await app1!.getEvents();
      final contactUpdate = allEvents.where((e) => 
        e.aggregateId == contact.id && e.eventType == 'UPDATED' && e.aggregateType == 'contact'
      ).toList();
      final contactDelete = allEvents.where((e) => 
        e.aggregateId == contact.id && e.eventType == 'DELETED' && e.aggregateType == 'contact'
      ).toList();
      final transactionUpdate = allEvents.where((e) => 
        e.aggregateId == transaction.id && e.eventType == 'UPDATED' && e.aggregateType == 'transaction'
      ).toList();
      final transactionDelete = allEvents.where((e) => 
        e.aggregateId == transaction.id && e.eventType == 'DELETED' && e.aggregateType == 'transaction'
      ).toList();
      
      expect(contactUpdate.isNotEmpty, true);
      expect(contactDelete.isNotEmpty, true);
      expect(transactionUpdate.isNotEmpty, true);
      expect(transactionDelete.isNotEmpty, true);
      print('✅ All events created');
      
      // Wait for sync
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      await Future.delayed(const Duration(seconds: 2));
      
      // Verify all events synced to server
      final serverEvents = await serverVerifier!.getServerEvents();
      final serverContactUpdate = serverEvents.where((e) => 
        e['aggregate_id'] == contact.id && e['event_type'] == 'UPDATED' && e['aggregate_type'] == 'contact'
      ).toList();
      final serverContactDelete = serverEvents.where((e) => 
        e['aggregate_id'] == contact.id && e['event_type'] == 'DELETED' && e['aggregate_type'] == 'contact'
      ).toList();
      final serverTransactionUpdate = serverEvents.where((e) => 
        e['aggregate_id'] == transaction.id && e['event_type'] == 'UPDATED' && e['aggregate_type'] == 'transaction'
      ).toList();
      final serverTransactionDelete = serverEvents.where((e) => 
        e['aggregate_id'] == transaction.id && e['event_type'] == 'DELETED' && e['aggregate_type'] == 'transaction'
      ).toList();
      
      expect(serverContactUpdate.isNotEmpty, true);
      expect(serverContactDelete.isNotEmpty, true);
      expect(serverTransactionUpdate.isNotEmpty, true);
      expect(serverTransactionDelete.isNotEmpty, true);
      print('✅ All events synced to server');
      
      // Verify conflicts resolved (delete should win)
      await Future.delayed(const Duration(seconds: 2));
      final contactsAfter = await app1!.getContacts();
      final transactionsAfter = await app1!.getTransactions();
      expect(contactsAfter.any((c) => c.id == contact.id), false, reason: 'Contact should be deleted');
      expect(transactionsAfter.any((t) => t.id == transaction.id), false, reason: 'Transaction should be deleted');
      print('✅ Conflicts resolved - both deleted (delete wins)');
      
      // Validate consistency
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true);
      print('✅ Final state consistent');
    });
    
    test('3.3 Offline Update Conflict (Contact & Transaction)', () async {
      print('\n📋 Test 3.3: Offline Update Conflict (Contact & Transaction)');
      
      // Create contact and transaction
      print('📝 Creating contact and transaction in App1...');
      final contact = await app1!.createContact(name: 'Original Name');
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      final transaction = await app1!.createTransaction(
        contactId: contact.id,
        direction: TransactionDirection.owed,
        amount: 1000,
      );
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Verify both exist
      final allContacts = await app1!.getContacts();
      final allTransactions = await app1!.getTransactions();
      expect(allContacts.any((c) => c.id == contact.id), true);
      expect(allTransactions.any((t) => t.id == transaction.id), true);
      print('✅ Contact and transaction exist');
      
      // App1 goes offline
      print('📴 App1 going offline...');
      await app1!.goOffline();
      
      // App1 updates both offline, App2 updates both online
      print('📝 App1 updating both offline, App2 updating both online...');
      await Future.wait([
        app1!.updateContact(contact.id, {'name': 'Updated Offline by App1'}),
        app2!.updateContact(contact.id, {'name': 'Updated Online by App2'}),
        app1!.updateTransaction(transaction.id, {'amount': 2000}),
        app2!.updateTransaction(transaction.id, {'amount': 3000}),
      ]);
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Verify all updates created events
      final allEvents = await app1!.getEvents();
      final contactUpdates = allEvents.where((e) => 
        e.aggregateId == contact.id && e.eventType == 'UPDATED' && e.aggregateType == 'contact'
      ).toList();
      final transactionUpdates = allEvents.where((e) => 
        e.aggregateId == transaction.id && e.eventType == 'UPDATED' && e.aggregateType == 'transaction'
      ).toList();
      
      expect(contactUpdates.length, greaterThanOrEqualTo(2), reason: 'Should have at least 2 contact updates');
      expect(transactionUpdates.length, greaterThanOrEqualTo(2), reason: 'Should have at least 2 transaction updates');
      print('✅ All updates created events');
      
      // App2's updates should sync first (it's online)
      await Future.delayed(const Duration(seconds: 5));
      
      // Verify App2's events synced to server
      final serverEventsBefore = await serverVerifier!.getServerEvents();
      final serverContactUpdateBefore = serverEventsBefore.where((e) => 
        e['aggregate_id'] == contact.id && e['event_type'] == 'UPDATED' && e['aggregate_type'] == 'contact'
      ).toList();
      final serverTransactionUpdateBefore = serverEventsBefore.where((e) => 
        e['aggregate_id'] == transaction.id && e['event_type'] == 'UPDATED' && e['aggregate_type'] == 'transaction'
      ).toList();
      expect(serverContactUpdateBefore.isNotEmpty, true);
      expect(serverTransactionUpdateBefore.isNotEmpty, true);
      print('✅ App2 updates synced to server');
      
      // App1 comes online
      print('📶 App1 coming online...');
      await app1!.goOnline();
      
      // Wait for sync
      try {
        await monitor!.waitForSync(timeout: const Duration(seconds: 30)).timeout(
          const Duration(seconds: 35),
        );
      } catch (e) {
        final allSynced = await monitor!.allInstancesSynced();
        if (!allSynced) rethrow;
      }
      await Future.delayed(const Duration(seconds: 1));
      
      // Verify all updates synced to server
      final serverEventsAfter = await serverVerifier!.getServerEvents();
      final serverContactUpdatesAfter = serverEventsAfter.where((e) => 
        e['aggregate_id'] == contact.id && e['event_type'] == 'UPDATED' && e['aggregate_type'] == 'contact'
      ).toList();
      final serverTransactionUpdatesAfter = serverEventsAfter.where((e) => 
        e['aggregate_id'] == transaction.id && e['event_type'] == 'UPDATED' && e['aggregate_type'] == 'transaction'
      ).toList();
      
      expect(serverContactUpdatesAfter.length, greaterThanOrEqualTo(2));
      expect(serverTransactionUpdatesAfter.length, greaterThanOrEqualTo(2));
      print('✅ All updates synced to server');
      
      // Verify conflict resolved
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true, reason: 'Final state should be consistent');
      print('✅ Conflict resolved - final state consistent');
      
      // Verify contact exists with some name
      final contactsAfter = await app1!.getContacts();
      final finalContact = contactsAfter.firstWhere((c) => c.id == contact.id);
      expect(finalContact.name, isNotEmpty, reason: 'Contact should have a name');
      print('✅ Contact has name: ${finalContact.name}');
    });
  });
}
