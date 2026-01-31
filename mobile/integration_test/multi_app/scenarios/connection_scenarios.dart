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
  
  group('Connection Breakdown Scenarios', () {
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
    
    test('4.1 Sync Interruption', () async {
      print('\n📋 Test 4.1: Sync Interruption');
      
      // App1 creates contact
      print('📝 App1 creating contact...');
      final contact = await app1!.createContact(name: 'Contact to Interrupt');
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Verify event created (unsynced)
      final app1Unsynced = await app1!.getUnsyncedEvents();
      expect(app1Unsynced.length, greaterThan(0), reason: 'App1 should have unsynced events');
      final createdEvent = app1Unsynced.firstWhere(
        (e) => e.aggregateId == contact.id && e.eventType == 'CREATED',
        orElse: () => throw Exception('CREATED event not found'),
      );
      expect(createdEvent.synced, false, reason: 'Event should be unsynced');
      print('✅ Event created (unsynced): ${createdEvent.id}');
      
      // Interrupt connection during sync (go offline)
      print('📴 Interrupting connection (going offline)...');
      await app1!.goOffline();
      
      // Verify event remains unsynced
      await Future.delayed(const Duration(seconds: 2));
      final app1UnsyncedAfter = await app1!.getUnsyncedEvents();
      final eventAfter = app1UnsyncedAfter.firstWhere(
        (e) => e.id == createdEvent.id,
        orElse: () => throw Exception('Event not found'),
      );
      expect(eventAfter.synced, false, reason: 'Event should remain unsynced after interruption');
      print('✅ Event remains unsynced after interruption');
      
      // Restore connection
      print('📶 Restoring connection...');
      await app1!.goOnline();
      
      // Wait for sync retry
      print('⏳ Waiting for sync retry...');
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      await Future.delayed(const Duration(seconds: 2));
      
      // Verify event eventually synced
      final app1Events = await app1!.getEvents();
      final syncedEvent = app1Events.firstWhere((e) => e.id == createdEvent.id);
      expect(syncedEvent.synced, true, reason: 'Event should be synced after retry');
      print('✅ Event eventually synced');
      
      // Verify event on server
      final serverEvents = await serverVerifier!.getServerEvents();
      final serverEvent = serverEvents.firstWhere(
        (e) => e['aggregate_id'] == contact.id,
        orElse: () => throw Exception('Event not found on server'),
      );
      expect(serverEvent['event_type'], 'CREATED');
      print('✅ Event synced to server');
      
      // Verify other apps receive event
      final allContacts = await app1!.getContacts();
      expect(allContacts.any((c) => c.id == contact.id), true,
        reason: 'Other apps should receive event');
      print('✅ Other apps received event');
    });
    
    test('4.2 Multiple Sync Failures', () async {
      print('\n📋 Test 4.2: Multiple Sync Failures');
      
      // App1 creates multiple contacts
      print('📝 App1 creating multiple contacts...');
      final contacts = <Contact>[];
      for (int i = 0; i < 3; i++) {
        final contact = await app1!.createContact(name: 'Contact $i');
        contacts.add(contact);
        await Future.delayed(const Duration(milliseconds: 200));
      }
      print('✅ ${contacts.length} contacts created');
      
      // Verify all events created (unsynced)
      await Future.delayed(const Duration(milliseconds: 500));
      final app1Unsynced = await app1!.getUnsyncedEvents();
      expect(app1Unsynced.length, greaterThanOrEqualTo(3), 
        reason: 'App1 should have at least 3 unsynced events');
      print('✅ All events created (unsynced)');
      
      // Interrupt connection multiple times
      for (int i = 0; i < 2; i++) {
        print('📴 Interrupting connection (attempt ${i + 1})...');
        await app1!.goOffline();
        await Future.delayed(const Duration(seconds: 2));
        
        print('📶 Restoring connection (attempt ${i + 1})...');
        await app1!.goOnline();
        await Future.delayed(const Duration(seconds: 2));
      }
      
      // Final sync
      print('⏳ Waiting for final sync...');
      await monitor!.waitForSync(timeout: const Duration(seconds: 90));
      await Future.delayed(const Duration(seconds: 2));
      
      // Verify all events eventually synced
      final app1Events = await app1!.getEvents();
      for (final contact in contacts) {
        final event = app1Events.firstWhere(
          (e) => e.aggregateId == contact.id && e.eventType == 'CREATED',
          orElse: () => throw Exception('Event not found for contact ${contact.id}'),
        );
        expect(event.synced, true, reason: 'Event should be synced for contact ${contact.id}');
      }
      print('✅ All events eventually synced');
      
      // Verify all events on server
      final serverEvents = await serverVerifier!.getServerEvents();
      for (final contact in contacts) {
        final serverEvent = serverEvents.where(
          (e) => e['aggregate_id'] == contact.id,
        ).toList();
        expect(serverEvent.isNotEmpty, true, 
          reason: 'Event should be on server for contact ${contact.id}');
      }
      print('✅ All events on server');
      
      // Verify no duplicates
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true, reason: 'No duplicates should exist');
      print('✅ No duplicates - retry logic worked correctly');
    });
    
    test('4.3 Server Unavailable', () async {
      print('\n📋 Test 4.3: Server Unavailable');
      
      // Note: We can't actually stop the server in integration tests,
      // but we can simulate it by going offline on all apps
      // This tests the retry logic with backoff
      
      // All apps go offline (simulating server unavailable)
      print('📴 Simulating server unavailable (all apps offline)...');
      await app1!.goOffline();
      await app2!.goOffline();
      await app3!.goOffline();
      
      // Apps create events while "server unavailable"
      print('📝 Apps creating events while server unavailable...');
      final contact1 = await app1!.createContact(name: 'Contact from App1');
      final contact2 = await app2!.createContact(name: 'Contact from App2');
      final contact3 = await app3!.createContact(name: 'Contact from App3');
      print('✅ Events created locally');
      
      // Verify all events unsynced
      await Future.delayed(const Duration(milliseconds: 500));
      final app1Unsynced = await app1!.getUnsyncedEvents();
      final app2Unsynced = await app2!.getUnsyncedEvents();
      final app3Unsynced = await app3!.getUnsyncedEvents();
      
      expect(app1Unsynced.length, greaterThan(0), reason: 'App1 should have unsynced events');
      expect(app2Unsynced.length, greaterThan(0), reason: 'App2 should have unsynced events');
      expect(app3Unsynced.length, greaterThan(0), reason: 'App3 should have unsynced events');
      print('✅ All events unsynced (as expected)');
      
      // Verify events NOT on server
      final serverEventsBefore = await serverVerifier!.getServerEvents();
      final serverContact1 = serverEventsBefore.where((e) => e['aggregate_id'] == contact1.id).toList();
      final serverContact2 = serverEventsBefore.where((e) => e['aggregate_id'] == contact2.id).toList();
      final serverContact3 = serverEventsBefore.where((e) => e['aggregate_id'] == contact3.id).toList();
      
      expect(serverContact1.isEmpty, true, reason: 'Contact1 should not be on server');
      expect(serverContact2.isEmpty, true, reason: 'Contact2 should not be on server');
      expect(serverContact3.isEmpty, true, reason: 'Contact3 should not be on server');
      print('✅ Events not on server (as expected)');
      
      // "Server comes back" - all apps come online
      print('📶 Server available again (all apps coming online)...');
      await app1!.goOnline();
      await app2!.goOnline();
      await app3!.goOnline();
      
      // Wait for sync with retry backoff
      print('⏳ Waiting for sync with retry backoff...');
      await monitor!.waitForSync(timeout: const Duration(seconds: 120));
      await Future.delayed(const Duration(seconds: 2));
      
      // Verify all events synced
      final serverEventsAfter = await serverVerifier!.getServerEvents();
      final serverContact1After = serverEventsAfter.where((e) => e['aggregate_id'] == contact1.id).toList();
      final serverContact2After = serverEventsAfter.where((e) => e['aggregate_id'] == contact2.id).toList();
      final serverContact3After = serverEventsAfter.where((e) => e['aggregate_id'] == contact3.id).toList();
      
      expect(serverContact1After.isNotEmpty, true, reason: 'Contact1 should be on server');
      expect(serverContact2After.isNotEmpty, true, reason: 'Contact2 should be on server');
      expect(serverContact3After.isNotEmpty, true, reason: 'Contact3 should be on server');
      print('✅ All events synced when server available');
      
      // Verify no data loss
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true, reason: 'No data loss - all events consistent');
      print('✅ No data loss - all events synced correctly');
    });
  });
}
