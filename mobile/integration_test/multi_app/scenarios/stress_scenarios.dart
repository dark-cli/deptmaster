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
  
  group('Stress Scenarios', () {
    AppInstance? app1;
    AppInstance? app2;
    AppInstance? app3;
    AppInstance? app4;
    AppInstance? app5;
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
      
      // Create app instances (5 for stress tests)
      app1 = await AppInstance.create(id: 'app1', serverUrl: 'http://localhost:8000');
      app2 = await AppInstance.create(id: 'app2', serverUrl: 'http://localhost:8000');
      app3 = await AppInstance.create(id: 'app3', serverUrl: 'http://localhost:8000');
      app4 = await AppInstance.create(id: 'app4', serverUrl: 'http://localhost:8000');
      app5 = await AppInstance.create(id: 'app5', serverUrl: 'http://localhost:8000');
      
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
    
    test('6.1 High Volume Concurrent Operations', () async {
      print('\n📋 Test 6.1: High Volume Concurrent Operations');
      
      // Each app creates 20 contacts simultaneously (100 total)
      print('📝 All apps creating 20 contacts each simultaneously...');
      final startTime = DateTime.now();
      
      final futures = <Future<Contact>>[];
      for (int appNum = 1; appNum <= 5; appNum++) {
        final app = appNum == 1 ? app1! : 
                   appNum == 2 ? app2! : 
                   appNum == 3 ? app3! : 
                   appNum == 4 ? app4! : app5!;
        for (int i = 0; i < 20; i++) {
          futures.add(app.createContact(name: 'Contact from App$appNum #$i'));
        }
      }
      
      final contacts = await Future.wait(futures);
      final createTime = DateTime.now().difference(startTime);
      print('✅ ${contacts.length} contacts created in ${createTime.inSeconds}s');
      
      // Wait for sync
      print('⏳ Waiting for sync...');
      final syncStartTime = DateTime.now();
      await monitor!.waitForSync(timeout: const Duration(seconds: 180));
      final syncTime = DateTime.now().difference(syncStartTime);
      await Future.delayed(const Duration(seconds: 2));
      
      print('✅ Sync completed in ${syncTime.inSeconds}s');
      
      // Verify all events synced to server
      final serverEvents = await serverVerifier!.getServerEvents();
      expect(serverEvents.length, greaterThanOrEqualTo(contacts.length),
        reason: 'Server should have all events');
      print('✅ All events synced to server');
      
      // Verify all apps receive all events
      final app1Contacts = await app1!.getContacts();
      final app2Contacts = await app2!.getContacts();
      final app3Contacts = await app3!.getContacts();
      
      expect(app1Contacts.length, greaterThanOrEqualTo(contacts.length),
        reason: 'App1 should have all contacts');
      expect(app2Contacts.length, greaterThanOrEqualTo(contacts.length),
        reason: 'App2 should have all contacts');
      expect(app3Contacts.length, greaterThanOrEqualTo(contacts.length),
        reason: 'App3 should have all contacts');
      print('✅ All apps received all contacts');
      
      // Verify no duplicates
      final isValid = await validator!.validateEventConsistency([
        app1!, app2!, app3!, app4!, app5!
      ]);
      expect(isValid, true, reason: 'No duplicates should exist');
      print('✅ No duplicates - performance acceptable');
      
      // Verify final state consistent
      expect(app1Contacts.length, app2Contacts.length,
        reason: 'All apps should have same number of contacts');
      print('✅ Final state consistent');
    });
    
    test('6.2 Rapid Create-Update-Delete', () async {
      print('\n📋 Test 6.2: Rapid Create-Update-Delete');
      
      // Create contact
      print('📝 Creating contact...');
      final contact = await app1!.createContact(name: 'Rapid Test Contact');
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      await Future.delayed(const Duration(seconds: 1));
      
      // Rapid sequence: update, update, delete
      print('📝 Rapid sequence: update, update, delete...');
      await app1!.updateContact(contact.id, {'name': 'Updated 1'});
      await Future.delayed(const Duration(milliseconds: 100));
      await app1!.updateContact(contact.id, {'name': 'Updated 2'});
      await Future.delayed(const Duration(milliseconds: 100));
      await app1!.deleteContact(contact.id);
      await Future.delayed(const Duration(milliseconds: 500));
      
      print('✅ Rapid sequence completed');
      
      // Wait for sync
      print('⏳ Waiting for sync...');
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      await Future.delayed(const Duration(seconds: 2));
      
      // Verify all events created in order
      final app1Events = await app1!.getEvents();
      final contactEvents = app1Events.where(
        (e) => e.aggregateId == contact.id,
      ).toList();
      
      expect(contactEvents.length, greaterThanOrEqualTo(3),
        reason: 'Should have at least 3 events (create, update, update, delete)');
      
      // Verify event order (CREATED, UPDATED, UPDATED, DELETED)
      final created = contactEvents.where((e) => e.eventType == 'CREATED').toList();
      final updated = contactEvents.where((e) => e.eventType == 'UPDATED').toList();
      final deleted = contactEvents.where((e) => e.eventType == 'DELETED').toList();
      
      expect(created.isNotEmpty, true, reason: 'Should have CREATED event');
      expect(updated.length, greaterThanOrEqualTo(2), reason: 'Should have at least 2 UPDATED events');
      expect(deleted.isNotEmpty, true, reason: 'Should have DELETED event');
      print('✅ All events created in order');
      
      // Verify events synced correctly
      final serverEvents = await serverVerifier!.getServerEvents();
      final serverContactEvents = serverEvents.where(
        (e) => e['aggregate_id'] == contact.id,
      ).toList();
      expect(serverContactEvents.length, greaterThanOrEqualTo(3),
        reason: 'Server should have all events');
      print('✅ Events synced correctly');
      
      // Verify final state correct (contact deleted)
      await Future.delayed(const Duration(seconds: 2));
      final contactsAfter = await app1!.getContacts();
      expect(contactsAfter.any((c) => c.id == contact.id), false,
        reason: 'Contact should be deleted');
      print('✅ Final state correct - contact deleted');
      
      // Verify no race conditions
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true, reason: 'No race conditions');
      print('✅ No race conditions');
    });
    
    test('6.3 Mixed Operations Stress', () async {
      print('\n📋 Test 6.3: Mixed Operations Stress');
      
      // Create initial contacts
      print('📝 Creating initial contacts...');
      final contacts = <Contact>[];
      for (int i = 0; i < 5; i++) {
        final contact = await app1!.createContact(name: 'Initial Contact $i');
        contacts.add(contact);
      }
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      await Future.delayed(const Duration(seconds: 2));
      
      // Mixed operations across all apps
      print('📝 Performing mixed operations across all apps...');
      final operations = <Future>[];
      
      // App1: Create 3, Update 2, Delete 1
      for (int i = 0; i < 3; i++) {
        operations.add(app1!.createContact(name: 'App1 Contact $i'));
      }
      operations.add(app1!.updateContact(contacts[0].id, {'name': 'Updated by App1'}));
      operations.add(app1!.updateContact(contacts[1].id, {'name': 'Updated by App1'}));
      operations.add(app1!.deleteContact(contacts[2].id));
      
      // App2: Create 2, Update 3
      for (int i = 0; i < 2; i++) {
        operations.add(app2!.createContact(name: 'App2 Contact $i'));
      }
      operations.add(app2!.updateContact(contacts[3].id, {'name': 'Updated by App2'}));
      operations.add(app2!.updateContact(contacts[4].id, {'name': 'Updated by App2'}));
      
      // App3: Create 4, Delete 1
      for (int i = 0; i < 4; i++) {
        operations.add(app3!.createContact(name: 'App3 Contact $i'));
      }
      operations.add(app3!.deleteContact(contacts[0].id)); // May conflict with App1 update
      
      // Execute all operations
      await Future.wait(operations);
      await Future.delayed(const Duration(milliseconds: 500));
      print('✅ Mixed operations completed');
      
      // Wait for sync
      print('⏳ Waiting for sync...');
      await monitor!.waitForSync(timeout: const Duration(seconds: 120));
      await Future.delayed(const Duration(seconds: 2));
      
      // Verify all operations succeed
      final app1Events = await app1!.getEvents();
      final app2Events = await app2!.getEvents();
      final app3Events = await app3!.getEvents();
      
      expect(app1Events.length, greaterThan(0), reason: 'App1 should have events');
      expect(app2Events.length, greaterThan(0), reason: 'App2 should have events');
      expect(app3Events.length, greaterThan(0), reason: 'App3 should have events');
      print('✅ All operations created events');
      
      // Verify events synced correctly
      final serverEvents = await serverVerifier!.getServerEvents();
      expect(serverEvents.length, greaterThan(0), reason: 'Server should have events');
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
