// ignore_for_file: unused_local_variable

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:debt_tracker_mobile/models/contact.dart';
import 'package:debt_tracker_mobile/models/transaction.dart';
import 'package:debt_tracker_mobile/models/event.dart';
import 'app_instance.dart';
import '../helpers/multi_app_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  test(
    'Performance Test - Time Each Step',
    () async {
    print('\n⏱️ Performance Test - Timing Each Step\n');
    
    final timings = <String, Duration>{};
    Stopwatch stopwatch = Stopwatch();
    Map<String, String>? creds;
    
    // Step 1: Server Ready Check
    stopwatch.start();
    print('📊 Step 1: Server Ready Check...');
    await waitForServerReady();
    stopwatch.stop();
    timings['Server Ready'] = stopwatch.elapsed;
    print('   ⏱️  ${stopwatch.elapsedMilliseconds}ms');
    stopwatch.reset();
    
    // Step 2: Create unique test user and wallet
    stopwatch.start();
    print('📊 Step 2: Create unique test user and wallet...');
    await ensureTestUserExists();
    creds = await createUniqueTestUserAndWallet();
    stopwatch.stop();
    timings['Create Test User & Wallet'] = stopwatch.elapsed;
    print('   ⏱️  ${stopwatch.elapsedMilliseconds}ms');
    stopwatch.reset();
    
    // Step 3: Hive Initialization
    stopwatch.start();
    print('📊 Step 3: Hive Initialization...');
    await Hive.initFlutter();
    Hive.registerAdapter(ContactAdapter());
    Hive.registerAdapter(TransactionAdapter());
    Hive.registerAdapter(TransactionTypeAdapter());
    Hive.registerAdapter(TransactionDirectionAdapter());
    Hive.registerAdapter(EventAdapter());
    stopwatch.stop();
    timings['Hive Init'] = stopwatch.elapsed;
    print('   ⏱️  ${stopwatch.elapsedMilliseconds}ms');
    stopwatch.reset();
    
    // Step 4: Clear Hive Boxes
    stopwatch.start();
    print('📊 Step 4: Clear Hive Boxes...');
    try {
      await Hive.box<Contact>('contacts').clear();
      await Hive.box<Transaction>('transactions').clear();
      await Hive.box<Event>('events').clear();
    } catch (e) {
      // Boxes might not exist
    }
    stopwatch.stop();
    timings['Clear Boxes'] = stopwatch.elapsed;
    print('   ⏱️  ${stopwatch.elapsedMilliseconds}ms');
    stopwatch.reset();
    
    // Step 5: Create App Instance
    stopwatch.start();
    print('📊 Step 5: Create App Instance...');
    final app = await AppInstance.create(
      id: 'perf_test',
      serverUrl: 'http://localhost:8000',
      username: creds!['email']!,
      password: creds['password']!,
      walletId: creds['walletId'],
    );
    stopwatch.stop();
    timings['Create Instance'] = stopwatch.elapsed;
    print('   ⏱️  ${stopwatch.elapsedMilliseconds}ms');
    stopwatch.reset();
    
    // Step 6: Initialize App Instance
    stopwatch.start();
    print('📊 Step 6: Initialize App Instance...');
    await app.initialize();
    stopwatch.stop();
    timings['Initialize Instance'] = stopwatch.elapsed;
    print('   ⏱️  ${stopwatch.elapsedMilliseconds}ms');
    stopwatch.reset();
    
    // Step 7: Login
    stopwatch.start();
    print('📊 Step 7: Login...');
    await app.login();
    stopwatch.stop();
    timings['Login'] = stopwatch.elapsed;
    print('   ⏱️  ${stopwatch.elapsedMilliseconds}ms');
    stopwatch.reset();
    
    // Step 8: Create Contact
    stopwatch.start();
    print('📊 Step 8: Create Contact...');
    final contact = await app.createContact(name: 'Test Contact');
    stopwatch.stop();
    timings['Create Contact'] = stopwatch.elapsed;
    print('   ⏱️  ${stopwatch.elapsedMilliseconds}ms');
    stopwatch.reset();
    
    // Step 9: Get Unsynced Events
    stopwatch.start();
    print('📊 Step 9: Get Unsynced Events...');
    final unsynced = await app.getUnsyncedEvents();
    stopwatch.stop();
    timings['Get Unsynced'] = stopwatch.elapsed;
    print('   ⏱️  ${stopwatch.elapsedMilliseconds}ms (found ${unsynced.length})');
    stopwatch.reset();
    
    // Step 10: Sync (wait for sync to complete)
    stopwatch.start();
    print('📊 Step 10: Wait for Sync...');
    // Manually trigger sync and wait
    // Note: The sync loop polls every 1 second, so we need to wait for it
    int iterations = 0;
    final syncStartTime = DateTime.now();
    while (iterations < 30) {
      final unsyncedCheck = await app.getUnsyncedEvents();
      if (unsyncedCheck.isEmpty) {
        final actualSyncTime = DateTime.now().difference(syncStartTime);
        print('   ⏱️  Sync detected complete after ${actualSyncTime.inMilliseconds}ms');
        print('   ⏱️  (Note: Actual sync operation is ~216ms, but loop polls every 1s)');
        break;
      }
      await Future.delayed(const Duration(milliseconds: 500));
      iterations++;
    }
    stopwatch.stop();
    timings['Sync (wait for loop)'] = stopwatch.elapsed;
    print('   ⏱️  ${stopwatch.elapsedMilliseconds}ms (includes loop polling delay)');
    stopwatch.reset();
    
    // Step 11: Get Contacts
    stopwatch.start();
    print('📊 Step 11: Get Contacts...');
    final contacts = await app.getContacts();
    stopwatch.stop();
    timings['Get Contacts'] = stopwatch.elapsed;
    print('   ⏱️  ${stopwatch.elapsedMilliseconds}ms (found ${contacts.length})');
    stopwatch.reset();
    
    // Cleanup
    await app.disconnect();
    await app.clearData();
    
    // Print Summary
    print('\n📊 Performance Summary:\n');
    final total = timings.values.fold<Duration>(
      Duration.zero,
      (sum, duration) => sum + duration,
    );
    
    timings.forEach((step, duration) {
      final percentage = (duration.inMilliseconds / total.inMilliseconds * 100).toStringAsFixed(1);
      print('   ${step.padRight(25)}: ${duration.inMilliseconds.toString().padLeft(6)}ms (${percentage}%)');
    });
    
    print('\n   ${"TOTAL".padRight(25)}: ${total.inMilliseconds.toString().padLeft(6)}ms');
    print('\n🔍 Bottleneck Analysis:');
    
    // Find top 3 slowest steps
    final sorted = timings.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    for (int i = 0; i < sorted.length && i < 3; i++) {
      final entry = sorted[i];
      final percentage = (entry.value.inMilliseconds / total.inMilliseconds * 100).toStringAsFixed(1);
      print('   ${i + 1}. ${entry.key}: ${entry.value.inMilliseconds}ms (${percentage}%)');
    }
  },
    tags: ['standalone'],
  );
}