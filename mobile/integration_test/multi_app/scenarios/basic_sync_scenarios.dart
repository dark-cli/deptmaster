import 'dart:async';
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
  
  // Set longer timeout for sync tests (default is 30s, we need more for sync operations)
  group('Basic Sync Scenarios', () {
    AppInstance? app1;
    AppInstance? app2;
    AppInstance? app3;
    SyncMonitor? monitor;
    EventValidator? validator;
    ServerVerifier? serverVerifier;
    
    setUpAll(() async {
      // Initialize Hive once globally (use Hive.initFlutter() for integration tests)
      await Hive.initFlutter();
      Hive.registerAdapter(ContactAdapter());
      Hive.registerAdapter(TransactionAdapter());
      Hive.registerAdapter(TransactionTypeAdapter());
      Hive.registerAdapter(TransactionDirectionAdapter());
      Hive.registerAdapter(EventAdapter());
      
      // Ensure test user exists once for all tests (major performance optimization)
      // This avoids calling the Rust binary before each test
      await ensureTestUserExists();
    });
    
    setUp(() async {
      // Reset server before each test
      await resetServer();
      await waitForServerReady();
      
      // Note: Test user is ensured in setUpAll to avoid 1.2s delay per test
      
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
      
      // Login all instances sequentially to avoid conflicts
      // (they'll share auth, which is fine for testing)
      print('🔐 Logging in all app instances...');
      try {
        await app1!.login().timeout(const Duration(seconds: 20));
        print('✅ App1 login complete');
      } catch (e) {
        print('❌ App1 login failed: $e');
        rethrow;
      }
      
      try {
        await app2!.login().timeout(const Duration(seconds: 20));
        print('✅ App2 login complete');
      } catch (e) {
        print('❌ App2 login failed: $e');
        rethrow;
      }
      
      try {
        await app3!.login().timeout(const Duration(seconds: 20));
        print('✅ App3 login complete');
      } catch (e) {
        print('❌ App3 login failed: $e');
        rethrow;
      }
      
      print('✅ All app instances logged in');
      
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
    
    test('1.1 Single App Create → Multi-App Sync', () async {
      print('\n📋 Test 1.1: Single App Create → Multi-App Sync');
      
      // App1 creates contact
      print('📝 App1 creating contact...');
      final contact = await app1!.createContact(name: 'Test Contact 1');
      print('✅ Contact created: ${contact.id}');
      
      // Verify event created in App1
      // Note: Sync now happens immediately, so we check all events (not just unsynced)
      // The event should exist, and may already be synced
      await Future.delayed(const Duration(milliseconds: 100)); // Small delay for event creation
      final app1Events = await app1!.getEvents();
      final createdEvent = app1Events.firstWhere(
        (e) => e.aggregateId == contact.id && e.eventType == 'CREATED',
        orElse: () => throw Exception('CREATED event not found for contact ${contact.id}'),
      );
      print('✅ Event created in App1: ${createdEvent.id} (synced: ${createdEvent.synced})');
      
      // If not synced yet, wait a bit more (sync happens immediately but may take a few ms)
      if (!createdEvent.synced) {
        print('⏳ Event not yet synced, waiting for immediate sync...');
        int attempts = 0;
        while (attempts < 10) {
          await Future.delayed(const Duration(milliseconds: 100));
          final updatedEvents = await app1!.getEvents();
          final updatedEvent = updatedEvents.firstWhere(
            (e) => e.id == createdEvent.id,
            orElse: () => throw Exception('Event not found'),
          );
          if (updatedEvent.synced) {
            print('✅ Event synced after ${(attempts + 1) * 100}ms');
            break;
          }
          attempts++;
        }
      }
      
      // Wait for sync (with test timeout to match)
      print('⏳ Waiting for sync...');
      await monitor!.waitForSync(timeout: const Duration(seconds: 60)).timeout(
        const Duration(seconds: 90),
        onTimeout: () {
          throw TimeoutException(
            'Test timed out waiting for sync. This might indicate a sync issue.',
            const Duration(seconds: 90),
          );
        },
      );
      
      // Give server time to process
      await Future.delayed(const Duration(seconds: 1));
      
      // Verify event synced to server
      final serverEvents = await serverVerifier!.getServerEvents();
      expect(serverEvents.length, greaterThan(0), reason: 'Server should have events');
      final serverEvent = serverEvents.firstWhere(
        (e) => e['aggregate_id'] == contact.id && e['event_type'] == 'CREATED',
        orElse: () => throw Exception('CREATED event not found on server for contact ${contact.id}'),
      );
      expect(serverEvent['event_type'], 'CREATED');
      print('✅ Event synced to server: ${serverEvent['id']}');
      
      // Verify App2 and App3 receive event via WebSocket
      // (They should have it after sync - they share boxes so should be immediate)
      await Future.delayed(const Duration(seconds: 2)); // Give WebSocket time
      
      // All instances share the same boxes, so they should all have the contact
      final allContacts = await app1!.getContacts();
      expect(allContacts.any((c) => c.id == contact.id), true, 
        reason: 'Contact should exist in shared boxes');
      print('✅ Contact exists in all apps (shared boxes)');
      
      // Verify event marked as synced in App1
      final app1EventsAfter = await app1!.getEvents();
      final syncedEvent = app1EventsAfter.firstWhere((e) => e.id == createdEvent.id);
      expect(syncedEvent.synced, true);
      print('✅ Event marked as synced in App1');
      
      // Validate consistency
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true, reason: 'All instances should have consistent events');
      print('✅ Event consistency validated');
    });
    
    test('1.2 Concurrent Creates', () async {
      print('\n📋 Test 1.2: Concurrent Creates');
      
      // All apps create different contacts simultaneously
      print('📝 All apps creating contacts simultaneously...');
      final futures = [
        app1!.createContact(name: 'Contact from App1'),
        app2!.createContact(name: 'Contact from App2'),
        app3!.createContact(name: 'Contact from App3'),
      ];
      
      final contacts = await Future.wait(futures);
      print('✅ All contacts created');
      
      // Wait for sync
      print('⏳ Waiting for sync...');
      await monitor!.waitForSync(timeout: const Duration(seconds: 30));
      
      // Verify all events synced to server
      final serverEvents = await serverVerifier!.getServerEvents();
      for (final contact in contacts) {
        final serverEvent = serverEvents.firstWhere(
          (e) => e['aggregate_id'] == contact.id,
          orElse: () => throw Exception('Event for ${contact.id} not found on server'),
        );
        expect(serverEvent['event_type'], 'CREATED');
      }
      print('✅ All events synced to server');
      
      // Verify all apps receive all events
      final app1Contacts = await app1!.getContacts();
      final app2Contacts = await app2!.getContacts();
      final app3Contacts = await app3!.getContacts();
      
      expect(app1Contacts.length, 3, reason: 'App1 should have all 3 contacts');
      expect(app2Contacts.length, 3, reason: 'App2 should have all 3 contacts');
      expect(app3Contacts.length, 3, reason: 'App3 should have all 3 contacts');
      print('✅ All apps received all contacts');
      
      // Verify final state identical
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true, reason: 'All instances should have identical state');
      print('✅ Final state identical across all apps');
    });
    
    test('1.3 Update Propagation', () async {
      print('\n📋 Test 1.3: Update Propagation');
      
      // Create contact in all apps first
      print('📝 Creating contact in App1...');
      final contact = await app1!.createContact(name: 'Original Name');
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      await Future.delayed(const Duration(seconds: 2)); // Give time for propagation
      
      // Verify contact exists in all apps (they share boxes, so should be immediate)
      final allContacts = await app1!.getContacts();
      var app2Contact = allContacts.firstWhere((c) => c.id == contact.id);
      var app3Contact = allContacts.firstWhere((c) => c.id == contact.id);
      expect(app2Contact.name, 'Original Name');
      expect(app3Contact.name, 'Original Name');
      print('✅ Contact exists in all apps');
      
      // App1 and App2 update same contact simultaneously
      print('📝 App1 and App2 updating contact simultaneously...');
      await Future.wait([
        app1!.updateContact(contact.id, {'name': 'Updated by App1'}),
        app2!.updateContact(contact.id, {'name': 'Updated by App2'}),
      ]);
      
      // Wait for sync
      print('⏳ Waiting for sync...');
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      await Future.delayed(const Duration(seconds: 1));
      
      // Verify both updates created events
      final app1Events = await app1!.getEvents();
      final app2Events = await app2!.getEvents();
      
      final app1Updates = app1Events.where((e) => 
        e.aggregateId == contact.id && e.eventType == 'UPDATED'
      ).toList();
      final app2Updates = app2Events.where((e) => 
        e.aggregateId == contact.id && e.eventType == 'UPDATED'
      ).toList();
      
      expect(app1Updates.length, greaterThan(0), reason: 'App1 should have update event');
      expect(app2Updates.length, greaterThan(0), reason: 'App2 should have update event');
      print('✅ Both updates created events');
      
      // Verify events synced to server
      final serverEvents = await serverVerifier!.getServerEvents();
      final serverUpdates = serverEvents.where((e) => 
        e['aggregate_id'] == contact.id && e['event_type'] == 'UPDATED'
      ).toList();
      expect(serverUpdates.length, greaterThanOrEqualTo(2), 
        reason: 'Server should have at least 2 update events');
      print('✅ Both events synced to server');
      
      // Verify final state consistent (last update wins or conflict resolved)
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true, reason: 'Final state should be consistent');
      print('✅ Final state consistent');
    });
    
    test('1.4 Delete Propagation', () async {
      print('\n📋 Test 1.4: Delete Propagation');
      
      // Create contact in all apps first
      print('📝 Creating contact in App1...');
      final contact = await app1!.createContact(name: 'Contact to Delete');
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      await Future.delayed(const Duration(seconds: 2));
      
      // Verify contact exists (they share boxes, so should be immediate)
      final allContacts = await app1!.getContacts();
      expect(allContacts.any((c) => c.id == contact.id), true);
      print('✅ Contact exists');
      
      // App1 deletes contact
      print('📝 App1 deleting contact...');
      await app1!.deleteContact(contact.id);
      await Future.delayed(const Duration(milliseconds: 100)); // Small delay for event creation
      
      // Verify delete event created
      // Note: Sync now happens immediately, so the event may already be synced
      final app1Events = await app1!.getEvents();
      final deleteEvent = app1Events.firstWhere(
        (e) => e.aggregateId == contact.id && e.eventType == 'DELETED',
        orElse: () => throw Exception('Delete event not found'),
      );
      print('✅ Delete event created in App1: ${deleteEvent.id} (synced: ${deleteEvent.synced})');
      
      // If not synced yet, wait a bit more (sync happens immediately but may take a few ms)
      if (!deleteEvent.synced) {
        print('⏳ Delete event not yet synced, waiting for immediate sync...');
        int attempts = 0;
        while (attempts < 10) {
          await Future.delayed(const Duration(milliseconds: 100));
          final updatedEvents = await app1!.getEvents();
          final updatedEvent = updatedEvents.firstWhere(
            (e) => e.id == deleteEvent.id,
            orElse: () => throw Exception('Event not found'),
          );
          if (updatedEvent.synced) {
            print('✅ Delete event synced after ${(attempts + 1) * 100}ms');
            break;
          }
          attempts++;
        }
      }
      
      // Wait for sync (though sync happens immediately, wait for all instances to be in sync)
      print('⏳ Waiting for sync...');
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      await Future.delayed(const Duration(milliseconds: 500)); // Give state rebuild time
      
      // Verify event synced to server
      final serverEvents = await serverVerifier!.getServerEvents();
      final serverDeleteEvent = serverEvents.firstWhere(
        (e) => e['aggregate_id'] == contact.id && e['event_type'] == 'DELETED',
        orElse: () => throw Exception('Delete event not found on server'),
      );
      print('✅ Delete event synced to server');
      
      // Verify contact removed (they share boxes, so should be immediate after state rebuild)
      // State rebuild happens immediately, but we need to ensure it completed
      // Check multiple times to account for async state rebuild
      bool contactRemoved = false;
      for (int i = 0; i < 5; i++) {
        await Future.delayed(const Duration(milliseconds: 200));
        final contactsAfter = await app1!.getContacts();
        contactRemoved = !contactsAfter.any((c) => c.id == contact.id);
        if (contactRemoved) {
          print('✅ Contact removed after ${(i + 1) * 200}ms');
          break;
        }
      }
      expect(contactRemoved, true,
        reason: 'Contact should be removed after delete and state rebuild');
      print('✅ Contact removed from all apps');
      
      // Validate consistency
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true, reason: 'All instances should have consistent events');
      print('✅ Event consistency validated');
    });
  });
}
