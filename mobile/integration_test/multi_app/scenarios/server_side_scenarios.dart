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
import '../../helpers/multi_app_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  group('Server-Side Scenarios', () {
    AppInstance? app1;
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
      
      // Create app instance
      app1 = await AppInstance.create(id: 'app1', serverUrl: 'http://localhost:8000');
      await app1!.initialize();
      await app1!.login();
      
      // Create server verifier
      serverVerifier = ServerVerifier(serverUrl: 'http://localhost:8000');
      await serverVerifier!.setAuthToken();
    });
    
    tearDown(() async {
      await app1?.disconnect();
      await app1?.clearData();
    });
    
    test('Server 1: Event Storage', () async {
      print('\n📋 Server Test 1: Event Storage');
      
      // Create contact
      print('📝 Creating contact...');
      final contact = await app1!.createContact(name: 'Test Contact');
      await Future.delayed(const Duration(seconds: 3)); // Wait for sync
      
      // Verify event stored in database via API
      final serverEvents = await serverVerifier!.getServerEvents();
      final serverEvent = serverEvents.firstWhere(
        (e) => e['aggregate_id'] == contact.id && e['event_type'] == 'CREATED',
        orElse: () => throw Exception('Event not found on server'),
      );
      
      expect(serverEvent['event_type'], 'CREATED');
      expect(serverEvent['aggregate_id'], contact.id);
      expect(serverEvent['aggregate_type'], 'Contact');
      expect(serverEvent['event_data'], isNotNull);
      print('✅ Event stored correctly in database');
      
      // Verify event data integrity
      final eventData = serverEvent['event_data'] as Map<String, dynamic>;
      expect(eventData['name'], 'Test Contact');
      print('✅ Event data integrity verified');
    });
    
    test('Server 2: Event Retrieval', () async {
      print('\n📋 Server Test 2: Event Retrieval');
      
      // Create multiple contacts
      print('📝 Creating multiple contacts...');
      final contacts = <Contact>[];
      for (int i = 0; i < 5; i++) {
        final contact = await app1!.createContact(name: 'Contact $i');
        contacts.add(contact);
        await Future.delayed(const Duration(milliseconds: 300));
      }
      await Future.delayed(const Duration(seconds: 3)); // Wait for sync
      
      // Test GET /api/sync/events without timestamp (all events)
      print('📥 Testing GET /api/sync/events (all events)...');
      final allEvents = await serverVerifier!.getServerEvents();
      expect(allEvents.length, greaterThanOrEqualTo(contacts.length),
        reason: 'Should retrieve all events');
      print('✅ Retrieved all events: ${allEvents.length}');
      
      // Test GET /api/sync/events with timestamp (incremental)
      print('📥 Testing GET /api/sync/events (with timestamp)...');
      final since = DateTime.now().subtract(const Duration(minutes: 1));
      final recentEvents = await serverVerifier!.getServerEvents(since: since);
      expect(recentEvents.length, greaterThanOrEqualTo(contacts.length),
        reason: 'Should retrieve recent events');
      print('✅ Retrieved recent events: ${recentEvents.length}');
      
      // Verify all contacts are in the events
      for (final contact in contacts) {
        final event = allEvents.where(
          (e) => e['aggregate_id'] == contact.id,
        ).toList();
        expect(event.isNotEmpty, true, reason: 'Event for contact ${contact.id} should exist');
      }
      print('✅ All contacts found in events');
    });
    
    test('Server 3: Event Acceptance', () async {
      print('\n📋 Server Test 3: Event Acceptance');
      
      // Create contact (valid event)
      print('📝 Creating contact (valid event)...');
      final contact = await app1!.createContact(name: 'Valid Contact');
      await Future.delayed(const Duration(seconds: 3));
      
      // Verify event accepted
      final serverEvents = await serverVerifier!.getServerEvents();
      final serverEvent = serverEvents.firstWhere(
        (e) => e['aggregate_id'] == contact.id,
        orElse: () => throw Exception('Event not found'),
      );
      expect(serverEvent['event_type'], 'CREATED');
      print('✅ Valid event accepted');
      
      // Verify event has required fields
      expect(serverEvent['id'], isNotNull);
      expect(serverEvent['aggregate_id'], isNotNull);
      expect(serverEvent['aggregate_type'], isNotNull);
      expect(serverEvent['event_type'], isNotNull);
      expect(serverEvent['event_data'], isNotNull);
      expect(serverEvent['timestamp'], isNotNull);
      print('✅ Event has all required fields');
    });
    
    test('Server 4: Hash Calculation', () async {
      print('\n📋 Server Test 4: Hash Calculation');
      
      // Get initial hash
      print('📥 Getting initial hash...');
      final hash1 = await serverVerifier!.getServerHash();
      expect(hash1, isNotEmpty);
      print('✅ Initial hash: $hash1');
      
      // Create contact
      print('📝 Creating contact...');
      final contact = await app1!.createContact(name: 'Hash Test Contact');
      await Future.delayed(const Duration(seconds: 3));
      
      // Get new hash
      print('📥 Getting new hash...');
      final hash2 = await serverVerifier!.getServerHash();
      expect(hash2, isNotEmpty);
      expect(hash2 != hash1, true, reason: 'Hash should change after event');
      print('✅ New hash: $hash2 (different from initial)');
      
      // Create another contact
      print('📝 Creating another contact...');
      await app1!.createContact(name: 'Hash Test Contact 2');
      await Future.delayed(const Duration(seconds: 3));
      
      // Get final hash
      print('📥 Getting final hash...');
      final hash3 = await serverVerifier!.getServerHash();
      expect(hash3 != hash2, true, reason: 'Hash should change again');
      print('✅ Final hash: $hash3 (different from previous)');
    });
    
    test('Server 5: Projection Consistency', () async {
      print('\n📋 Server Test 5: Projection Consistency');
      
      // Create contact
      print('📝 Creating contact...');
      final contact = await app1!.createContact(
        name: 'Projection Test',
        email: 'test@example.com',
        phone: '1234567890',
      );
      await Future.delayed(const Duration(seconds: 3));
      
      // Verify event in events table
      final serverEvents = await serverVerifier!.getServerEvents();
      final serverEvent = serverEvents.firstWhere(
        (e) => e['aggregate_id'] == contact.id,
        orElse: () => throw Exception('Event not found'),
      );
      expect(serverEvent['event_type'], 'CREATED');
      print('✅ Event exists in events table');
      
      // Verify contact in projections (via API)
      final serverContact = await serverVerifier!.getServerContact(contact.id);
      expect(serverContact, isNotNull, reason: 'Contact should exist in projection');
      expect(serverContact!['name'], 'Projection Test');
      expect(serverContact['email'], 'test@example.com');
      expect(serverContact['phone'], '1234567890');
      print('✅ Contact exists in projection with correct data');
      
      // Update contact
      print('📝 Updating contact...');
      await app1!.updateContact(contact.id, {'name': 'Updated Projection Test'});
      await Future.delayed(const Duration(seconds: 3));
      
      // Verify update in projection
      final updatedContact = await serverVerifier!.getServerContact(contact.id);
      expect(updatedContact!['name'], 'Updated Projection Test');
      print('✅ Projection updated correctly');
    });
    
    test('Server 6: Event Count and Statistics', () async {
      print('\n📋 Server Test 6: Event Count and Statistics');
      
      // Get initial count
      print('📥 Getting initial event count...');
      final initialCount = await serverVerifier!.getServerEventCount();
      print('✅ Initial count: $initialCount');
      
      // Create multiple contacts
      print('📝 Creating multiple contacts...');
      final count = 10;
      for (int i = 0; i < count; i++) {
        await app1!.createContact(name: 'Contact $i');
        await Future.delayed(const Duration(milliseconds: 200));
      }
      await Future.delayed(const Duration(seconds: 5)); // Wait for sync
      
      // Get final count
      print('📥 Getting final event count...');
      final finalCount = await serverVerifier!.getServerEventCount();
      expect(finalCount, greaterThanOrEqualTo(initialCount + count),
        reason: 'Event count should have increased');
      print('✅ Final count: $finalCount (increased by at least $count)');
      
      // Verify all events are retrievable
      final allEvents = await serverVerifier!.getServerEvents();
      expect(allEvents.length, finalCount, reason: 'All events should be retrievable');
      print('✅ All events are retrievable');
    });
  });
}
