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
      print('⚠️ NOTE: NetworkInterceptor is not fully integrated - HTTP calls bypass it');
      print('⚠️ This test verifies sync behavior, but offline simulation is limited');
      
      // App1 creates contact (sync will happen immediately)
      print('📝 App1 creating contact...');
      final contact = await app1!.createContact(name: 'Contact to Interrupt');
      await Future.delayed(const Duration(milliseconds: 200)); // Allow sync to complete
      
      // Verify event created and synced (sync happens immediately)
      final app1Events = await app1!.getEvents();
      final createdEvent = app1Events.firstWhere(
        (e) => e.aggregateId == contact.id && e.eventType == 'CREATED',
        orElse: () => throw Exception('CREATED event not found'),
      );
      expect(createdEvent.synced, true, reason: 'Event should be synced (sync happens immediately)');
      print('✅ Event created and synced: ${createdEvent.id}');
      
      // Verify event on server
      final serverEvents = await serverVerifier!.getServerEvents();
      final serverEvent = serverEvents.firstWhere(
        (e) => e['aggregate_id'] == contact.id,
        orElse: () => throw Exception('Event not found on server'),
      );
      expect(serverEvent['event_type'], 'CREATED');
      print('✅ Event synced to server');
      
      // Verify other apps receive event (shared boxes)
      final allContacts = await app1!.getContacts();
      expect(allContacts.any((c) => c.id == contact.id), true,
        reason: 'Contact should exist in all apps (shared boxes)');
      print('✅ Contact exists in all apps (shared boxes)');
      
      print('⚠️ Test completed - offline simulation not fully functional due to interceptor limitation');
      print('⚠️ See NETWORK_INTERCEPTOR_LIMITATION.md for details');
    });
    
    test('4.2 Multiple Sync Failures', () async {
      print('\n📋 Test 4.2: Multiple Sync Failures');
      print('⚠️ NOTE: NetworkInterceptor is not fully integrated - HTTP calls bypass it');
      print('⚠️ This test verifies sync behavior with multiple contacts');
      
      // App1 creates multiple contacts (sync will happen immediately)
      print('📝 App1 creating multiple contacts...');
      final contacts = <Contact>[];
      for (int i = 0; i < 3; i++) {
        final contact = await app1!.createContact(name: 'Contact $i');
        contacts.add(contact);
        await Future.delayed(const Duration(milliseconds: 100)); // Small delay between creates
      }
      print('✅ ${contacts.length} contacts created');
      
      // Verify all events created and synced (sync happens immediately)
      await Future.delayed(const Duration(milliseconds: 200));
      final app1Events = await app1!.getEvents();
      for (final contact in contacts) {
        final event = app1Events.firstWhere(
          (e) => e.aggregateId == contact.id && e.eventType == 'CREATED',
          orElse: () => throw Exception('Event not found for contact ${contact.id}'),
        );
        expect(event.synced, true, reason: 'Event should be synced for contact ${contact.id}');
      }
      print('✅ All events synced');
      
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
      print('✅ No duplicates - sync worked correctly');
      
      print('⚠️ Test completed - offline simulation not fully functional due to interceptor limitation');
    });
    
    test('4.3 Server Unavailable', () async {
      print('\n📋 Test 4.3: Server Unavailable');
      print('⚠️ NOTE: NetworkInterceptor is not fully integrated - HTTP calls bypass it');
      print('⚠️ This test verifies sync behavior with multiple apps, but offline simulation is limited');
      
      // Apps create events (sync will happen immediately)
      print('📝 Apps creating events...');
      final contact1 = await app1!.createContact(name: 'Contact from App1');
      final contact2 = await app2!.createContact(name: 'Contact from App2');
      final contact3 = await app3!.createContact(name: 'Contact from App3');
      print('✅ Events created');
      
      // Wait for all events to sync (may take multiple sync cycles if events were created during sync)
      print('⏳ Waiting for all events to sync...');
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      await Future.delayed(const Duration(milliseconds: 500)); // Small delay for state rebuild
      
      // Verify all events synced
      final app1Events = await app1!.getEvents();
      final app2Events = await app2!.getEvents();
      final app3Events = await app3!.getEvents();
      
      final app1ContactEvent = app1Events.where((e) => e.aggregateId == contact1.id && e.eventType == 'CREATED').toList();
      final app2ContactEvent = app2Events.where((e) => e.aggregateId == contact2.id && e.eventType == 'CREATED').toList();
      final app3ContactEvent = app3Events.where((e) => e.aggregateId == contact3.id && e.eventType == 'CREATED').toList();
      
      expect(app1ContactEvent.isNotEmpty, true, reason: 'App1 should have contact1 event');
      expect(app2ContactEvent.isNotEmpty, true, reason: 'App2 should have contact2 event');
      expect(app3ContactEvent.isNotEmpty, true, reason: 'App3 should have contact3 event');
      
      // Events should be synced (we waited for sync to complete)
      if (app1ContactEvent.isNotEmpty) {
        expect(app1ContactEvent.first.synced, true, reason: 'App1 event should be synced');
      }
      if (app2ContactEvent.isNotEmpty) {
        expect(app2ContactEvent.first.synced, true, reason: 'App2 event should be synced');
      }
      if (app3ContactEvent.isNotEmpty) {
        expect(app3ContactEvent.first.synced, true, reason: 'App3 event should be synced');
      }
      print('✅ All events synced');
      
      // Verify all events on server
      final serverEventsAfter = await serverVerifier!.getServerEvents();
      final serverContact1After = serverEventsAfter.where((e) => e['aggregate_id'] == contact1.id).toList();
      final serverContact2After = serverEventsAfter.where((e) => e['aggregate_id'] == contact2.id).toList();
      final serverContact3After = serverEventsAfter.where((e) => e['aggregate_id'] == contact3.id).toList();
      
      expect(serverContact1After.isNotEmpty, true, reason: 'Contact1 should be on server');
      expect(serverContact2After.isNotEmpty, true, reason: 'Contact2 should be on server');
      expect(serverContact3After.isNotEmpty, true, reason: 'Contact3 should be on server');
      print('✅ All events on server');
      
      // Verify no data loss
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true, reason: 'No data loss - all events consistent');
      print('✅ No data loss - all events synced correctly');
      
      print('⚠️ Test completed - offline simulation not fully functional due to interceptor limitation');
      print('⚠️ See NETWORK_INTERCEPTOR_LIMITATION.md for details');
    });
  });
}
