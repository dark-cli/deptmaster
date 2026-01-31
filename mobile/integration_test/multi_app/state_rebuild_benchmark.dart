import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:debt_tracker_mobile/models/contact.dart';
import 'package:debt_tracker_mobile/models/transaction.dart';
import 'package:debt_tracker_mobile/models/event.dart';
import 'package:debt_tracker_mobile/services/event_store_service.dart';
import 'package:debt_tracker_mobile/services/local_database_service_v2.dart';
import 'package:debt_tracker_mobile/services/state_builder.dart';
import 'package:uuid/uuid.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  test('State Rebuild Benchmark - Time with Small Event Counts', () async {
    print('\n⏱️ State Rebuild Benchmark - Testing with Small Event Counts\n');
    
    // Setup
    await Hive.initFlutter();
    Hive.registerAdapter(ContactAdapter());
    Hive.registerAdapter(TransactionAdapter());
    Hive.registerAdapter(TransactionTypeAdapter());
    Hive.registerAdapter(TransactionDirectionAdapter());
    Hive.registerAdapter(EventAdapter());
    
    await EventStoreService.initialize();
    await LocalDatabaseServiceV2.initialize();
    
    // Clear everything
    final eventsBox = await Hive.openBox<Event>('events');
    final contactsBox = await Hive.openBox<Contact>('contacts');
    final transactionsBox = await Hive.openBox<Transaction>('transactions');
    await eventsBox.clear();
    await contactsBox.clear();
    await transactionsBox.clear();
    
    final timings = <String, Duration>{};
    Stopwatch stopwatch = Stopwatch();
    const uuid = Uuid();
    
    // Test 1: Rebuild with 1 event
    print('📊 Test 1: Rebuild with 1 event');
    final contact1 = Contact(
      id: uuid.v4(),
      name: 'Test Contact 1',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await LocalDatabaseServiceV2.createContact(contact1);
    
    stopwatch.start();
    final events1 = await EventStoreService.getAllEvents();
    final state1 = StateBuilder.buildState(events1);
    await contactsBox.clear();
    await transactionsBox.clear();
    for (final contact in state1.contacts) {
      await contactsBox.put(contact.id, contact);
    }
    for (final transaction in state1.transactions) {
      await transactionsBox.put(transaction.id, transaction);
    }
    stopwatch.stop();
    timings['1 event'] = stopwatch.elapsed;
    print('   ⏱️  ${stopwatch.elapsedMilliseconds}ms (${events1.length} events)');
    stopwatch.reset();
    
    // Test 2: Rebuild with 5 events
    print('📊 Test 2: Rebuild with 5 events');
    for (int i = 2; i <= 5; i++) {
      final contact = Contact(
        id: uuid.v4(),
        name: 'Test Contact $i',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await LocalDatabaseServiceV2.createContact(contact);
    }
    
    stopwatch.start();
    final events5 = await EventStoreService.getAllEvents();
    final state5 = StateBuilder.buildState(events5);
    await contactsBox.clear();
    await transactionsBox.clear();
    for (final contact in state5.contacts) {
      await contactsBox.put(contact.id, contact);
    }
    for (final transaction in state5.transactions) {
      await transactionsBox.put(transaction.id, transaction);
    }
    stopwatch.stop();
    timings['5 events'] = stopwatch.elapsed;
    print('   ⏱️  ${stopwatch.elapsedMilliseconds}ms (${events5.length} events)');
    stopwatch.reset();
    
    // Test 3: Rebuild with 10 events
    print('📊 Test 3: Rebuild with 10 events');
    for (int i = 6; i <= 10; i++) {
      final contact = Contact(
        id: uuid.v4(),
        name: 'Test Contact $i',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await LocalDatabaseServiceV2.createContact(contact);
    }
    
    stopwatch.start();
    final events10 = await EventStoreService.getAllEvents();
    final state10 = StateBuilder.buildState(events10);
    await contactsBox.clear();
    await transactionsBox.clear();
    for (final contact in state10.contacts) {
      await contactsBox.put(contact.id, contact);
    }
    for (final transaction in state10.transactions) {
      await transactionsBox.put(transaction.id, transaction);
    }
    stopwatch.stop();
    timings['10 events'] = stopwatch.elapsed;
    print('   ⏱️  ${stopwatch.elapsedMilliseconds}ms (${events10.length} events)');
    stopwatch.reset();
    
    // Test 4: Just StateBuilder.buildState (no Hive operations)
    print('📊 Test 4: Just StateBuilder.buildState (no Hive operations)');
    stopwatch.start();
    final stateOnly = StateBuilder.buildState(events10);
    stopwatch.stop();
    timings['StateBuilder only (10 events)'] = stopwatch.elapsed;
    print('   ⏱️  ${stopwatch.elapsedMilliseconds}ms');
    stopwatch.reset();
    
    // Test 5: Just Hive operations (clear + put)
    print('📊 Test 5: Just Hive operations (clear + put)');
    stopwatch.start();
    await contactsBox.clear();
    await transactionsBox.clear();
    for (final contact in state10.contacts) {
      await contactsBox.put(contact.id, contact);
    }
    for (final transaction in state10.transactions) {
      await transactionsBox.put(transaction.id, transaction);
    }
    stopwatch.stop();
    timings['Hive operations only (10 contacts)'] = stopwatch.elapsed;
    print('   ⏱️  ${stopwatch.elapsedMilliseconds}ms');
    stopwatch.reset();
    
    // Test 6: Get all events
    print('📊 Test 6: Get all events from EventStore');
    stopwatch.start();
    final allEvents = await EventStoreService.getAllEvents();
    stopwatch.stop();
    timings['Get all events (10 events)'] = stopwatch.elapsed;
    print('   ⏱️  ${stopwatch.elapsedMilliseconds}ms (${allEvents.length} events)');
    stopwatch.reset();
    
    // Test 7: Open Hive boxes
    print('📊 Test 7: Open Hive boxes');
    stopwatch.start();
    final contactsBox2 = await Hive.openBox<Contact>('contacts');
    final transactionsBox2 = await Hive.openBox<Transaction>('transactions');
    stopwatch.stop();
    timings['Open Hive boxes'] = stopwatch.elapsed;
    print('   ⏱️  ${stopwatch.elapsedMilliseconds}ms');
    stopwatch.reset();
    
    // Test 8: Hive putAll (batch operation)
    print('📊 Test 8: Hive putAll (batch operation)');
    await contactsBox.clear();
    await transactionsBox.clear();
    final contactMap = <String, Contact>{};
    for (final contact in state10.contacts) {
      contactMap[contact.id] = contact;
    }
    stopwatch.start();
    await contactsBox.putAll(contactMap);
    await transactionsBox.putAll(<String, Transaction>{});
    stopwatch.stop();
    timings['Hive putAll (10 contacts)'] = stopwatch.elapsed;
    print('   ⏱️  ${stopwatch.elapsedMilliseconds}ms');
    stopwatch.reset();
    
    // Print Summary
    print('\n📊 State Rebuild Benchmark Summary:\n');
    timings.forEach((step, duration) {
      print('   ${step.padRight(35)}: ${duration.inMilliseconds.toString().padLeft(6)}ms');
    });
    
    print('\n🔍 Analysis:');
    print('   If rebuild takes 1.5s with 1-10 events, the bottleneck is likely:');
    print('   - Opening Hive boxes (if not already open)');
    print('   - Multiple sequential Hive operations');
    print('   - Not the StateBuilder itself (should be < 10ms for 10 events)');
    print('\n   Recommendation: Use putAll() for batch operations instead of');
    print('   individual put() calls in a loop.');
  });
}
