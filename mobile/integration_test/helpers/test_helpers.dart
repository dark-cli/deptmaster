import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:debt_tracker_mobile/services/event_store_service.dart';
import 'package:debt_tracker_mobile/services/local_database_service_v2.dart';
import 'package:debt_tracker_mobile/services/sync_service_v2.dart';
import 'package:debt_tracker_mobile/services/api_service.dart';
import 'package:debt_tracker_mobile/models/contact.dart' show Contact, ContactAdapter;
import 'package:debt_tracker_mobile/models/transaction.dart' show Transaction, TransactionAdapter, TransactionType, TransactionTypeAdapter, TransactionDirection, TransactionDirectionAdapter;
import 'package:debt_tracker_mobile/models/event.dart' show Event, EventAdapter;

/// Helper functions for integration tests

/// Initialize test environment
Future<void> initializeTestEnvironment() async {
  await Hive.initFlutter();
  // Register adapters (importing models automatically imports generated adapters)
  Hive.registerAdapter(ContactAdapter());
  Hive.registerAdapter(TransactionAdapter());
  Hive.registerAdapter(TransactionTypeAdapter());
  Hive.registerAdapter(TransactionDirectionAdapter());
  Hive.registerAdapter(EventAdapter());
  
  // Open Hive boxes
  try {
    await Hive.openBox<Contact>('contacts');
  } catch (e) {
    // Box already open
  }
  try {
    await Hive.openBox<Transaction>('transactions');
  } catch (e) {
    // Box already open
  }
  
  await EventStoreService.initialize();
  await LocalDatabaseServiceV2.initialize();
}

/// Clean up test environment
Future<void> cleanupTestEnvironment() async {
  try {
    await Hive.box<Contact>('contacts').clear();
    await Hive.box<Transaction>('transactions').clear();
    await Hive.box<Event>('events').clear();
  } catch (e) {
    // Boxes might not exist
  }
}

/// Create a test contact
Future<Contact> createTestContact({
  String? name,
  String? username,
  String? phone,
  String? email,
}) async {
  final contact = Contact(
    id: 'test-contact-${DateTime.now().millisecondsSinceEpoch}',
    name: name ?? 'Test Contact',
    username: username,
    phone: phone,
    email: email,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
  
  return await LocalDatabaseServiceV2.createContact(
    contact,
    comment: 'Test contact creation',
  );
}

/// Create a test transaction
Future<Transaction> createTestTransaction({
  required String contactId,
  TransactionDirection? direction,
  int? amount,
  String? description,
}) async {
  final transaction = Transaction(
    id: 'test-transaction-${DateTime.now().millisecondsSinceEpoch}',
    contactId: contactId,
    type: TransactionType.money,
    direction: direction ?? TransactionDirection.lent,
    amount: amount ?? 100000,
    currency: 'IQD',
    description: description,
    transactionDate: DateTime.now(),
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
  
  return await LocalDatabaseServiceV2.createTransaction(transaction);
}

/// Verify event was created locally
Future<void> verifyEventCreated({
  required String aggregateType,
  required String aggregateId,
  required String eventType,
  Map<String, dynamic>? expectedData,
}) async {
  final events = await EventStoreService.getEventsForAggregate(
    aggregateType,
    aggregateId,
  );
  
  expect(events.isNotEmpty, true, reason: 'Event should be created');
  
  final event = events.firstWhere(
    (e) => e.eventType == eventType,
    orElse: () => throw Exception('Event type $eventType not found'),
  );
  
  if (expectedData != null) {
    for (final entry in expectedData.entries) {
      expect(event.eventData[entry.key], entry.value,
          reason: 'Event data ${entry.key} should match');
    }
  }
}

/// Verify event is synced to server
Future<void> verifyEventSyncedToServer({
  required String eventId,
}) async {
  // Get server events
  final serverEvents = await ApiService.getSyncEvents();
  
  final serverEvent = serverEvents.firstWhere(
    (e) => e['id'] == eventId,
    orElse: () => throw Exception('Event $eventId not found on server'),
  );
  
  expect(serverEvent, isNotNull, reason: 'Event should exist on server');
  
  // Verify local event is marked as synced
  final localEvents = await EventStoreService.getAllEvents();
  final localEvent = localEvents.firstWhere(
    (e) => e.id == eventId,
    orElse: () => throw Exception('Event $eventId not found locally'),
  );
  
  expect(localEvent.synced, true, reason: 'Event should be marked as synced');
}

/// Compare local and server events
Future<void> compareLocalAndServerEvents() async {
  final localEvents = await EventStoreService.getAllEvents();
  final serverEvents = await ApiService.getSyncEvents();
  
  // Filter to synced events only
  final syncedLocalEvents = localEvents.where((e) => e.synced).toList();
  
  expect(syncedLocalEvents.length, serverEvents.length,
      reason: 'Local and server should have same number of synced events');
  
  // Verify each synced local event exists on server
  for (final localEvent in syncedLocalEvents) {
    final serverEvent = serverEvents.firstWhere(
      (e) => e['id'] == localEvent.id,
      orElse: () => throw Exception('Local event ${localEvent.id} not found on server'),
    );
    
    // Compare key fields
    expect(serverEvent['aggregate_type'], localEvent.aggregateType);
    expect(serverEvent['aggregate_id'], localEvent.aggregateId);
    expect(serverEvent['event_type'], localEvent.eventType);
  }
}

/// Wait for sync to complete
Future<void> waitForSync({Duration timeout = const Duration(seconds: 30)}) async {
  final startTime = DateTime.now();
  
  while (DateTime.now().difference(startTime) < timeout) {
    final unsyncedEvents = await EventStoreService.getUnsyncedEvents();
    if (unsyncedEvents.isEmpty) {
      return; // All events synced
    }
    await Future.delayed(const Duration(milliseconds: 500));
  }
  
  throw TimeoutException('Sync did not complete within timeout');
}

/// Get event count statistics
Future<Map<String, int>> getEventStats() async {
  final allEvents = await EventStoreService.getAllEvents();
  final unsyncedEvents = await EventStoreService.getUnsyncedEvents();
  
  return {
    'total': allEvents.length,
    'synced': allEvents.where((e) => e.synced).length,
    'unsynced': unsyncedEvents.length,
    'contacts': allEvents.where((e) => e.aggregateType == 'contact').length,
    'transactions': allEvents.where((e) => e.aggregateType == 'transaction').length,
  };
}
