import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:debt_tracker_mobile/models/contact.dart';
import 'package:debt_tracker_mobile/models/transaction.dart';
import 'package:debt_tracker_mobile/models/event.dart';
import 'package:debt_tracker_mobile/services/auth_service.dart';
import 'package:debt_tracker_mobile/services/api_service.dart';
import 'package:debt_tracker_mobile/services/backend_config_service.dart';
import 'package:debt_tracker_mobile/services/event_store_service.dart';
import 'package:debt_tracker_mobile/services/local_database_service_v2.dart';
import 'package:debt_tracker_mobile/services/sync_service_v2.dart';
import '../helpers/multi_app_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  test('Flutter HTTP Benchmark - Compare with Server', () async {
    print('\n⏱️ Flutter HTTP Benchmark - Comparing with Server\n');
    
    final timings = <String, Duration>{};
    Stopwatch stopwatch = Stopwatch();
    
    // Setup
    await Hive.initFlutter();
    Hive.registerAdapter(ContactAdapter());
    Hive.registerAdapter(TransactionAdapter());
    Hive.registerAdapter(TransactionTypeAdapter());
    Hive.registerAdapter(TransactionDirectionAdapter());
    Hive.registerAdapter(EventAdapter());
    
    await resetServer();
    await waitForServerReady();
    await ensureTestUserExists();
    
    final uri = Uri.parse('http://localhost:8000');
    await BackendConfigService.setBackendConfig(uri.host, uri.port);
    await BackendConfigService.setUseHttps(false);
    
    await EventStoreService.initialize();
    await LocalDatabaseServiceV2.initialize();
    await SyncServiceV2.initialize();
    
    // Test 1: Login
    stopwatch.start();
    print('📊 Test 1: Login (POST /api/auth/login)');
    final loginResult = await AuthService.login('max', '12345678');
    stopwatch.stop();
    timings['Login'] = stopwatch.elapsed;
    print('   ⏱️  ${stopwatch.elapsedMilliseconds}ms');
    expect(loginResult['success'], true);
    stopwatch.reset();
    
    // Test 2: Get Sync Hash
    stopwatch.start();
    print('📊 Test 2: Get Sync Hash (GET /api/sync/hash)');
    final hashResult = await ApiService.getSyncHash();
    stopwatch.stop();
    timings['Get Sync Hash'] = stopwatch.elapsed;
    print('   ⏱️  ${stopwatch.elapsedMilliseconds}ms');
    expect(hashResult['hash'], isNotNull);
    stopwatch.reset();
    
    // Test 3: Get Sync Events (empty)
    stopwatch.start();
    print('📊 Test 3: Get Sync Events - Empty (GET /api/sync/events)');
    final events = await ApiService.getSyncEvents();
    stopwatch.stop();
    timings['Get Sync Events (empty)'] = stopwatch.elapsed;
    print('   ⏱️  ${stopwatch.elapsedMilliseconds}ms (found ${events.length})');
    stopwatch.reset();
    
    // Test 4: Create Contact (local)
    stopwatch.start();
    print('📊 Test 4: Create Contact (local)');
    final contact = Contact(
      id: '550e8400-e29b-41d4-a716-446655440000',
      name: 'Benchmark Contact',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await LocalDatabaseServiceV2.createContact(contact);
    stopwatch.stop();
    timings['Create Contact (local)'] = stopwatch.elapsed;
    print('   ⏱️  ${stopwatch.elapsedMilliseconds}ms');
    stopwatch.reset();
    
    // Test 5: Get Unsynced Events
    stopwatch.start();
    print('📊 Test 5: Get Unsynced Events (local)');
    final unsynced = await EventStoreService.getUnsyncedEvents();
    stopwatch.stop();
    timings['Get Unsynced Events'] = stopwatch.elapsed;
    print('   ⏱️  ${stopwatch.elapsedMilliseconds}ms (found ${unsynced.length})');
    stopwatch.reset();
    
    // Test 6: Post Sync Events (single event)
    stopwatch.start();
    print('📊 Test 6: Post Sync Events - Single Event (POST /api/sync/events)');
    final eventsToSend = unsynced.map((e) {
      String timestamp = e.timestamp.toUtc().toIso8601String();
      if (!timestamp.endsWith('Z')) {
        timestamp = '${timestamp}Z';
      }
      return {
        'id': e.id,
        'aggregate_type': e.aggregateType,
        'aggregate_id': e.aggregateId,
        'event_type': e.eventType,
        'event_data': e.eventData,
        'timestamp': timestamp,
        'version': e.version,
      };
    }).toList();
    final postResult = await ApiService.postSyncEvents(eventsToSend);
    stopwatch.stop();
    timings['Post Sync Events (1 event)'] = stopwatch.elapsed;
    print('   ⏱️  ${stopwatch.elapsedMilliseconds}ms');
    expect(postResult['accepted'], isNotNull);
    stopwatch.reset();
    
    // Test 7: Full Sync Operation (syncLocalToServer)
    stopwatch.start();
    print('📊 Test 7: Full Sync Operation (syncLocalToServer)');
    final syncResult = await SyncServiceV2.syncLocalToServer();
    stopwatch.stop();
    timings['Full Sync Operation'] = stopwatch.elapsed;
    print('   ⏱️  ${stopwatch.elapsedMilliseconds}ms');
    expect(syncResult, SyncResult.done);
    stopwatch.reset();
    
    // Test 8: Get Sync Events (with data)
    stopwatch.start();
    print('📊 Test 8: Get Sync Events - With Data (GET /api/sync/events)');
    final eventsWithData = await ApiService.getSyncEvents();
    stopwatch.stop();
    timings['Get Sync Events (with data)'] = stopwatch.elapsed;
    print('   ⏱️  ${stopwatch.elapsedMilliseconds}ms (found ${eventsWithData.length})');
    stopwatch.reset();
    
    // Test 9: Sequential Requests (warmup)
    print('📊 Test 9: Sequential Requests (10x Get Sync Hash - warmup test)');
    int totalTime = 0;
    for (int i = 1; i <= 10; i++) {
      stopwatch.start();
      await ApiService.getSyncHash();
      stopwatch.stop();
      final time = stopwatch.elapsedMilliseconds;
      totalTime += time;
      if (i == 1) {
        print('   Request 1: ${time}ms (cold start)');
      } else if (i == 10) {
        print('   Request 10: ${time}ms');
      }
      stopwatch.reset();
    }
    final avgTime = totalTime ~/ 10;
    timings['Sequential Requests (avg)'] = Duration(milliseconds: avgTime);
    print('   Average: ${avgTime}ms');
    
    // Print Summary
    print('\n📊 Flutter HTTP Benchmark Summary:\n');
    final total = timings.values.fold<Duration>(
      Duration.zero,
      (sum, duration) => sum + duration,
    );
    
    timings.forEach((step, duration) {
      final percentage = (duration.inMilliseconds / total.inMilliseconds * 100).toStringAsFixed(1);
      print('   ${step.padRight(30)}: ${duration.inMilliseconds.toString().padLeft(6)}ms (${percentage}%)');
    });
    
    print('\n   ${"TOTAL".padRight(30)}: ${total.inMilliseconds.toString().padLeft(6)}ms');
    print('\n🔍 Comparison with Server (curl):');
    print('   Server Login: ~630ms');
    print('   Flutter Login: ${timings['Login']!.inMilliseconds}ms');
    print('');
    print('   Server Get Hash: ~8ms');
    print('   Flutter Get Hash: ${timings['Get Sync Hash']!.inMilliseconds}ms');
    print('');
    print('   Server Post Events (1): ~24ms');
    print('   Flutter Post Events (1): ${timings['Post Sync Events (1 event)']!.inMilliseconds}ms');
    print('');
    print('   Server Sequential (avg): ~8ms');
    print('   Flutter Sequential (avg): ${timings['Sequential Requests (avg)']!.inMilliseconds}ms');
    print('');
    print('   Full Sync Operation: ${timings['Full Sync Operation']!.inMilliseconds}ms');
    print('   (Includes: get hash, post events, state rebuild)');
  });
}
