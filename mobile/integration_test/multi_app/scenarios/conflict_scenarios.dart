// ignore_for_file: unused_import

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:debt_tracker_mobile/models/contact.dart';
import 'package:debt_tracker_mobile/models/transaction.dart';
import 'package:debt_tracker_mobile/models/event.dart';
import '../app_instance.dart';
import '../sync_monitor.dart';
import '../event_validator.dart';
import '../server_verifier.dart';
import '../event_generator.dart';
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
    EventGenerator? generator;
    
    setUpAll(() async {
      await Hive.initFlutter();
      Hive.registerAdapter(ContactAdapter());
      Hive.registerAdapter(TransactionAdapter());
      Hive.registerAdapter(TransactionTypeAdapter());
      Hive.registerAdapter(TransactionDirectionAdapter());
      Hive.registerAdapter(EventAdapter());
      await ensureTestUserExists();
    });
    
    setUp(() async {
      await waitForServerReady();
      final creds = await createUniqueTestUserAndWallet();
      
      try {
        await Hive.box<Contact>('contacts').clear();
        await Hive.box<Transaction>('transactions').clear();
        await Hive.box<Event>('events').clear();
      } catch (e) {
        // Boxes might not exist yet
      }
      
      app1 = await AppInstance.create(
        id: 'app1',
        serverUrl: 'http://localhost:8000',
        username: creds['email']!,
        password: creds['password']!,
        walletId: creds['walletId'],
      );
      app2 = await AppInstance.create(
        id: 'app2',
        serverUrl: 'http://localhost:8000',
        username: creds['email']!,
        password: creds['password']!,
        walletId: creds['walletId'],
      );
      app3 = await AppInstance.create(
        id: 'app3',
        serverUrl: 'http://localhost:8000',
        username: creds['email']!,
        password: creds['password']!,
        walletId: creds['walletId'],
      );
      
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
      
      // Create event generator
      generator = EventGenerator({
        'app1': app1!,
        'app2': app2!,
        'app3': app3!,
      });
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
    
    test('Simultaneous Updates (Contact & Transaction)', () async {
      print('\n📋 Test: Simultaneous Updates (Contact & Transaction)');
      
      // Use event generator to create 18 events (1 contact + 10 transactions + 7 simultaneous updates)
      final commands = [
        'app1: contact create "Original Name" contact1',
        'app1: transaction create contact1 owed 1000 "T1" t1',
        'app1: transaction create contact1 lent 500 "T2" t2',
        'app1: transaction create contact1 owed 2000 "T3" t3',
        'app1: transaction create contact1 lent 800 "T4" t4',
        'app1: transaction create contact1 owed 1500 "T5" t5',
        'app2: transaction create contact1 lent 600 "T6" t6',
        'app2: transaction create contact1 owed 1200 "T7" t7',
        'app3: transaction create contact1 lent 900 "T8" t8',
        'app3: transaction create contact1 owed 1800 "T9" t9',
        'app3: transaction create contact1 lent 400 "T10" t10',
        // Simultaneous updates from different apps
        'app1: contact update contact1 name "Updated by App1"',
        'app2: contact update contact1 name "Updated by App2"',
        'app1: transaction update t1 amount 2000',
        'app2: transaction update t1 amount 3000',
        'app1: transaction update t3 amount 2200',
        'app2: transaction update t5 description "Updated by App2"',
        'app3: transaction update t7 amount 1300',
      ];
      
      print('📝 Executing ${commands.length} event commands...');
      await generator!.executeCommands(commands);
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Verify events
      final allEvents = await app1!.getEvents();
      expect(allEvents.length, greaterThanOrEqualTo(18));
      
      // Verify we have UPDATE events
      final updateEvents = allEvents.where((e) => e.eventType == 'UPDATED').length;
      expect(updateEvents, greaterThanOrEqualTo(7), reason: 'Should have multiple update events');
      
      // Verify transaction events are majority
      final transactionEvents = allEvents.where(
        (e) => e.aggregateType == 'transaction'
      ).length;
      expect(transactionEvents, greaterThan(10), reason: 'Transaction events should be majority');
      
      // Verify all events synced to server
      final serverEvents = await serverVerifier!.getServerEvents();
      expect(serverEvents.length, greaterThanOrEqualTo(18));
      
      // Verify final state consistent
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true);
      print('✅ Final state consistent');
      
      // Verify final state
      final contactsAfter = await app1!.getContacts();
      final transactionsAfter = await app1!.getTransactions();
      expect(contactsAfter.length, 1);
      expect(transactionsAfter.length, greaterThan(8));
      // Verify at least one transaction has a valid amount
      expect(transactionsAfter.any((t) => t.amount > 0), true);
      print('✅ Conflicts resolved - both updated');
    });
    
    test('Update-Delete Conflict (Contact & Transaction)', () async {
      print('\n📋 Test: Update-Delete Conflict (Contact & Transaction)');
      
      // Use event generator to create 20 events (2 contacts + 15 transactions + 3 conflicts)
      final commands = [
        'app1: contact create "Contact to Conflict" contact1',
        'app1: contact create "Contact 2" contact2',
        'app1: transaction create contact1 owed 1000 "T1" t1',
        'app1: transaction create contact1 lent 500 "T2" t2',
        'app1: transaction create contact1 owed 2000 "T3" t3',
        'app1: transaction create contact2 lent 800 "T4" t4',
        'app1: transaction create contact2 owed 1200 "T5" t5',
        'app2: transaction create contact1 lent 600 "T6" t6',
        'app2: transaction create contact1 owed 1500 "T7" t7',
        'app2: transaction create contact2 lent 900 "T8" t8',
        'app3: transaction create contact1 owed 1800 "T9" t9',
        'app3: transaction create contact2 lent 400 "T10" t10',
        'app3: transaction create contact1 owed 1100 "T11" t11',
        'app1: transaction create contact2 lent 700 "T12" t12',
        'app2: transaction create contact1 owed 1300 "T13" t13',
        'app3: transaction create contact2 lent 500 "T14" t14',
        // Conflicts: App1 updates, App2 deletes
        // Note: Use t4 (from contact2) for transaction conflict since deleting contact1
        // will delete all its transactions (t1, t2, t3, t6, t7, t9, t11, t13)
        'app1: contact update contact1 name "Updated Name"',
        'app2: contact delete contact1',
        'app1: transaction update t4 amount 2000',
        'app2: transaction delete t4',
      ];
      
      print('📝 Executing ${commands.length} event commands...');
      await generator!.executeCommands(commands);
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      await Future.delayed(const Duration(seconds: 2));
      
      // Verify events
      final allEvents = await app1!.getEvents();
      expect(allEvents.length, greaterThanOrEqualTo(20));
      
      // Verify transaction events are majority
      final transactionEvents = allEvents.where(
        (e) => e.aggregateType == 'transaction'
      ).length;
      expect(transactionEvents, greaterThan(15), reason: 'Transaction events should be majority');
      
      // Verify conflicts resolved (delete should win)
      final contactsAfter = await app1!.getContacts();
      final contact1Removed = !contactsAfter.any((c) => c.name == 'Contact to Conflict' || c.name == 'Updated Name');
      expect(contact1Removed, true, reason: 'Contact should be deleted');
      
      // Validate consistency
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true);
      print('✅ Final state consistent');
    });
    
    test('Offline Update Conflict (Contact & Transaction)', () async {
      print('\n📋 Test: Offline Update Conflict (Contact & Transaction)');
      
      // Create contact and transactions first
      final setupCommands = [
        'app1: contact create "Original Name" contact1',
        'app1: transaction create contact1 owed 1000 "T1" t1',
        'app1: transaction create contact1 lent 500 "T2" t2',
        'app1: transaction create contact1 owed 2000 "T3" t3',
        'app1: transaction create contact1 lent 800 "T4" t4',
        'app1: transaction create contact1 owed 1500 "T5" t5',
        'app2: transaction create contact1 lent 600 "T6" t6',
        'app2: transaction create contact1 owed 1200 "T7" t7',
      ];
      await generator!.executeCommands(setupCommands);
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // App1 goes offline, App2 stays online
      print('📴 App1 going offline, App2 staying online...');
      await app1!.goOffline();
      
      // App1 updates while offline, App2 updates while online (conflict scenario)
      final conflictCommands = [
        'app1: contact update contact1 name "Updated Offline by App1"',
        'app1: transaction update t1 amount 2000',
        'app1: transaction update t3 amount 2200',
        'app2: contact update contact1 name "Updated Online by App2"',
        'app2: transaction update t1 amount 3000',
        'app2: transaction update t5 description "Updated by App2"',
        'app1: transaction create contact1 lent 900 "T8" t8',
        'app2: transaction create contact1 owed 1800 "T9" t9',
      ];
      
      print('📝 Executing ${conflictCommands.length} conflict commands...');
      await generator!.executeCommands(conflictCommands);
      
      // App2's updates should sync first (it's online)
      await Future.delayed(const Duration(seconds: 5));
      
      // App1 comes online
      print('📶 App1 coming online...');
      await app1!.goOnline();
      await monitor!.waitForSync(timeout: const Duration(seconds: 60));
      
      // Verify events
      final allEvents = await app1!.getEvents();
      expect(allEvents.length, greaterThanOrEqualTo(16)); // 8 setup + 8 conflict
      
      // Verify we have multiple UPDATE events
      final updateEvents = allEvents.where((e) => e.eventType == 'UPDATED').length;
      expect(updateEvents, greaterThanOrEqualTo(5), reason: 'Should have multiple update events');
      
      // Verify conflict resolved
      final isValid = await validator!.validateEventConsistency([app1!, app2!, app3!]);
      expect(isValid, true);
      print('✅ Conflict resolved - final state consistent');
      
      // Verify contact exists
      final contactsAfter = await app1!.getContacts();
      expect(contactsAfter.length, 1);
      expect(contactsAfter.first.name, isNotEmpty);
      print('✅ Contact has name: ${contactsAfter.first.name}');
    });
  });
}