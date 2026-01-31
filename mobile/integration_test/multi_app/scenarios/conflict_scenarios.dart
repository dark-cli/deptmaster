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
    
    test('3.1 Simultaneous Updates', () async {
      print('\n📋 Test 3.1: Simultaneous Updates');
      
      // Create contact in all apps first
      print('📝 Creating contact in App1...');
      final contact = await app1!.createContact(name: 'Original Name');
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      await Future.delayed(const Duration(seconds: 2));
      
      // Verify contact exists in all apps
      final allContacts = await app1!.getContacts();
      expect(allContacts.any((c) => c.id == contact.id), true);
      print('✅ Contact exists in all apps');
      
      // App1 and App2 update same contact simultaneously
      print('📝 App1 and App2 updating contact simultaneously...');
      await Future.wait([
        app1!.updateContact(contact.id, {'name': 'Updated by App1'}),
        app2!.updateContact(contact.id, {'name': 'Updated by App2'}),
      ]);
      await Future.delayed(const Duration(milliseconds: 500));
      
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
      
      // Wait for sync
      print('⏳ Waiting for sync...');
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      await Future.delayed(const Duration(seconds: 2));
      
      // Verify both events synced to server
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
      
      // Verify contact exists with some name (conflict resolution applied)
      final contactsAfter = await app1!.getContacts();
      final finalContact = contactsAfter.firstWhere((c) => c.id == contact.id);
      expect(finalContact.name, isNotEmpty, reason: 'Contact should have a name');
      print('✅ Conflict resolved - contact has name: ${finalContact.name}');
    });
    
    test('3.2 Update-Delete Conflict', () async {
      print('\n📋 Test 3.2: Update-Delete Conflict');
      
      // Create contact in all apps first
      print('📝 Creating contact in App1...');
      final contact = await app1!.createContact(name: 'Contact to Conflict');
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      await Future.delayed(const Duration(seconds: 2));
      
      // Verify contact exists
      final allContacts = await app1!.getContacts();
      expect(allContacts.any((c) => c.id == contact.id), true);
      print('✅ Contact exists');
      
      // App1 updates contact, App2 deletes same contact simultaneously
      print('📝 App1 updating contact, App2 deleting same contact...');
      await Future.wait([
        app1!.updateContact(contact.id, {'name': 'Updated Name'}),
        app2!.deleteContact(contact.id),
      ]);
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Verify both events created
      final app1Events = await app1!.getEvents();
      final app2Events = await app2!.getEvents();
      
      final app1Update = app1Events.where((e) => 
        e.aggregateId == contact.id && e.eventType == 'UPDATED'
      ).toList();
      final app2Delete = app2Events.where((e) => 
        e.aggregateId == contact.id && e.eventType == 'DELETED'
      ).toList();
      
      expect(app1Update.isNotEmpty, true, reason: 'App1 should have update event');
      expect(app2Delete.isNotEmpty, true, reason: 'App2 should have delete event');
      print('✅ Both events created');
      
      // Wait for sync
      print('⏳ Waiting for sync...');
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      await Future.delayed(const Duration(seconds: 2));
      
      // Verify both events synced to server
      final serverEvents = await serverVerifier!.getServerEvents();
      final serverUpdate = serverEvents.where((e) => 
        e['aggregate_id'] == contact.id && e['event_type'] == 'UPDATED'
      ).toList();
      final serverDelete = serverEvents.where((e) => 
        e['aggregate_id'] == contact.id && e['event_type'] == 'DELETED'
      ).toList();
      
      expect(serverUpdate.isNotEmpty, true, reason: 'Update event should be on server');
      expect(serverDelete.isNotEmpty, true, reason: 'Delete event should be on server');
      print('✅ Both events synced to server');
      
      // Verify conflict resolved (delete should win)
      await Future.delayed(const Duration(seconds: 2)); // Give state rebuild time
      final contactsAfter = await app1!.getContacts();
      expect(contactsAfter.any((c) => c.id == contact.id), false,
        reason: 'Contact should be deleted (delete wins)');
      print('✅ Conflict resolved - contact deleted (delete wins)');
      
      // Validate consistency
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true, reason: 'Final state should be consistent');
      print('✅ Final state consistent');
    });
    
    test('3.3 Offline Update Conflict', () async {
      print('\n📋 Test 3.3: Offline Update Conflict');
      
      // Create contact in all apps first
      print('📝 Creating contact in App1...');
      final contact = await app1!.createContact(name: 'Original Name');
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      await Future.delayed(const Duration(seconds: 2));
      
      // Verify contact exists
      final allContacts = await app1!.getContacts();
      expect(allContacts.any((c) => c.id == contact.id), true);
      print('✅ Contact exists');
      
      // App1 goes offline
      print('📴 App1 going offline...');
      await app1!.goOffline();
      
      // App1 updates contact offline, App2 updates same contact online
      print('📝 App1 updating contact offline, App2 updating same contact online...');
      await Future.wait([
        app1!.updateContact(contact.id, {'name': 'Updated Offline by App1'}),
        app2!.updateContact(contact.id, {'name': 'Updated Online by App2'}),
      ]);
      await Future.delayed(const Duration(milliseconds: 500));
      
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
      
      // App2's update should sync first (it's online)
      print('⏳ Waiting for App2 to sync...');
      await Future.delayed(const Duration(seconds: 5));
      
      // Verify App2's event synced to server
      final serverEventsBefore = await serverVerifier!.getServerEvents();
      final serverUpdateBefore = serverEventsBefore.where((e) => 
        e['aggregate_id'] == contact.id && e['event_type'] == 'UPDATED'
      ).toList();
      expect(serverUpdateBefore.isNotEmpty, true, reason: 'App2 update should be on server');
      print('✅ App2 update synced to server');
      
      // App1 comes online
      print('📶 App1 coming online...');
      await app1!.goOnline();
      
      // Wait for sync (with timeout wrapper to prevent test framework timeout)
      print('⏳ Waiting for sync...');
      try {
        await monitor!.waitForSync(timeout: const Duration(seconds: 30)).timeout(
          const Duration(seconds: 35),
        );
      } catch (e) {
        print('⚠️ Sync wait timed out, checking if actually synced: $e');
        final allSynced = await monitor!.allInstancesSynced();
        if (!allSynced) {
          rethrow;
        }
        print('✅ All instances are actually synced');
      }
      await Future.delayed(const Duration(seconds: 1));
      
      // Verify both updates synced to server
      final serverEventsAfter = await serverVerifier!.getServerEvents();
      final serverUpdatesAfter = serverEventsAfter.where((e) => 
        e['aggregate_id'] == contact.id && e['event_type'] == 'UPDATED'
      ).toList();
      expect(serverUpdatesAfter.length, greaterThanOrEqualTo(2), 
        reason: 'Server should have both update events');
      print('✅ Both updates synced to server');
      
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
