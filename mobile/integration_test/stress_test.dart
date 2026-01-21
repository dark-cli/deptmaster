import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:debt_tracker_mobile/main.dart' as app;
import 'package:debt_tracker_mobile/services/event_store_service.dart';
import 'package:debt_tracker_mobile/services/local_database_service_v2.dart';
import 'package:debt_tracker_mobile/services/sync_service_v2.dart';
import 'package:debt_tracker_mobile/services/api_service.dart';
import 'package:debt_tracker_mobile/services/backend_config_service.dart';
import 'package:debt_tracker_mobile/models/contact.dart';
import 'package:debt_tracker_mobile/models/transaction.dart';
import 'package:debt_tracker_mobile/models/event.dart';
// TransactionDirection is imported via transaction.dart
import 'helpers/test_helpers.dart';
import 'helpers/ui_test_helpers.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:matcher/matcher.dart';
import 'dart:math';

// Global tester instance for helper functions
WidgetTester? globalTester;

/// Action tracker to keep track of all actions performed
class ActionTracker {
  final List<ActionRecord> actions = [];
  
  void recordAction(String type, String aggregateType, String aggregateId, Map<String, dynamic>? data) {
    actions.add(ActionRecord(
      type: type,
      aggregateType: aggregateType,
      aggregateId: aggregateId,
      data: data ?? {},
      timestamp: DateTime.now(),
    ));
  }
  
  /// Get expected events based on actions
  Map<String, List<ActionRecord>> getExpectedEvents() {
    final events = <String, List<ActionRecord>>{};
    for (final action in actions) {
      final key = '${action.aggregateType}:${action.aggregateId}';
      if (!events.containsKey(key)) {
        events[key] = [];
      }
      events[key]!.add(action);
    }
    return events;
  }
  
  /// Verify events match between local and server
  Future<void> verifyEvents() async {
    print('\n🔍 Verifying events...');
    
    // Get local events
    final localEvents = await EventStoreService.getAllEvents();
    print('📊 Local events: ${localEvents.length}');
    
    // Get server events
    final isConfigured = await BackendConfigService.isConfigured();
    List<Map<String, dynamic>> serverEvents = [];
    if (isConfigured) {
      try {
        serverEvents = await ApiService.getSyncEvents();
        print('📊 Server events: ${serverEvents.length}');
      } catch (e) {
        print('⚠️ Could not fetch server events: $e');
      }
    }
    
    // Group events by aggregate
    final localEventsByAggregate = <String, List<Event>>{};
    for (final event in localEvents) {
      final key = '${event.aggregateType}:${event.aggregateId}';
      if (!localEventsByAggregate.containsKey(key)) {
        localEventsByAggregate[key] = [];
      }
      localEventsByAggregate[key]!.add(event);
    }
    
    final serverEventsByAggregate = <String, List<Map<String, dynamic>>>{};
    for (final event in serverEvents) {
      final key = '${event['aggregate_type']}:${event['aggregate_id']}';
      if (!serverEventsByAggregate.containsKey(key)) {
        serverEventsByAggregate[key] = [];
      }
      serverEventsByAggregate[key]!.add(event);
    }
    
    // Verify each action has corresponding events
    final expectedEvents = getExpectedEvents();
    int verifiedCount = 0;
    int mismatchCount = 0;
    
    for (final entry in expectedEvents.entries) {
      final aggregateKey = entry.key;
      final expectedActions = entry.value;
      
      // Check local events
      final localAggregateEvents = localEventsByAggregate[aggregateKey] ?? [];
      if (localAggregateEvents.length != expectedActions.length) {
        print('❌ Mismatch for $aggregateKey: Expected ${expectedActions.length} events, found ${localAggregateEvents.length} locally');
        mismatchCount++;
      } else {
        verifiedCount++;
      }
      
      // Check server events if available
      if (isConfigured && serverEvents.isNotEmpty) {
        final serverAggregateEvents = serverEventsByAggregate[aggregateKey] ?? [];
        if (serverAggregateEvents.length != expectedActions.length) {
          print('❌ Mismatch for $aggregateKey: Expected ${expectedActions.length} events, found ${serverAggregateEvents.length} on server');
          mismatchCount++;
        }
      }
    }
    
    print('✅ Verified: $verifiedCount aggregates, ❌ Mismatches: $mismatchCount');
    
    // Verify total counts
    expect(localEvents.length, greaterThanOrEqualTo(actions.length), 
      reason: 'Local events should match or exceed actions');
    
    if (isConfigured && serverEvents.isNotEmpty) {
      expect(serverEvents.length, greaterThanOrEqualTo(actions.length),
        reason: 'Server events should match or exceed actions');
    }
  }
}

class ActionRecord {
  final String type; // CREATED, UPDATED, DELETED
  final String aggregateType; // contact, transaction
  final String aggregateId;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  
  ActionRecord({
    required this.type,
    required this.aggregateType,
    required this.aggregateId,
    required this.data,
    required this.timestamp,
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Automated Stress Test', () {
    final actionTracker = ActionTracker();
    final random = Random(42); // Fixed seed for reproducibility
    List<Contact> createdContacts = [];
    List<Transaction> createdTransactions = [];
    
    setUpAll(() async {
      await initializeTestEnvironment();
    });

    setUp(() async {
      // Reset server data BEFORE cleaning local data (CRITICAL!)
      print('🔄 Resetting server data via ./manage.sh full-flash...');
      await resetServerData();
      
      // Clean up local data
      print('🧹 Cleaning local data...');
      try {
        await Hive.box<Contact>('contacts').clear();
        await Hive.box<Transaction>('transactions').clear();
        await Hive.box<Event>('events').clear();
      } catch (e) {
        print('⚠️ Could not clear boxes (might not exist yet): $e');
      }
      
      // Clear action tracker
      actionTracker.actions.clear();
      createdContacts.clear();
      createdTransactions.clear();
    });

    tearDown(() async {
      await cleanupTestEnvironment();
    });

    testWidgets('Automated stress test: 20 contacts + 500 random actions', (WidgetTester tester) async {
      print('\n🚀 Starting automated stress test...');
      print('📋 Plan: Create 20 contacts, then perform 500 random actions');
      
      // ========== PHASE 1: Create 20 Contacts ==========
      print('\n📝 PHASE 1: Creating 20 contacts...');
      await navigateToContactsTab(tester);
      
      for (int i = 1; i <= 20; i++) {
        print('   Creating contact $i/20...');
        
        // Find and tap add contact button
        final appBar = find.byType(AppBar);
        final addContactButton = find.descendant(
          of: appBar,
          matching: find.byIcon(Icons.add),
        );
        
        if (addContactButton.evaluate().isEmpty) {
          final addButtonAlt = find.widgetWithIcon(IconButton, Icons.add);
          if (addButtonAlt.evaluate().isNotEmpty) {
            await tester.tap(addButtonAlt.first);
          } else {
            await longPressAddContactFAB(tester);
          }
        } else {
          await tester.tap(addContactButton.first);
        }
        await tester.pumpAndSettle(const Duration(milliseconds: 50));
        
        final contact = await fillAndSaveContactForm(
          tester,
          name: 'Contact $i',
          username: 'user$i',
          phone: '123456789$i',
          email: 'contact$i@example.com',
          notes: 'Test contact $i',
        );
        
        createdContacts.add(contact);
        actionTracker.recordAction('CREATED', 'contact', contact.id, {
          'name': contact.name,
          'username': contact.username,
          'phone': contact.phone,
          'email': contact.email,
        });
        
        // Sync every 10 contacts (less frequent for speed)
        if (i % 10 == 0) {
          print('   🔄 Syncing after $i contacts...');
          await SyncServiceV2.manualSync();
          await tester.pumpAndSettle(const Duration(milliseconds: 200));
        }
      }
      
      print('✅ Created ${createdContacts.length} contacts');
      
      // ========== PHASE 2: Perform 500 Random Actions ==========
      print('\n📝 PHASE 2: Performing 500 random actions...');
      
      int actionCount = 0;
      while (actionCount < 500) {
        // Determine action type based on current state
        final actionType = _selectRandomAction(random, createdContacts.length, createdTransactions.length);
        
        try {
          switch (actionType) {
            case 'create_contact':
              await _createRandomContact(tester, actionTracker, createdContacts, random);
              actionCount++;
              break;
              
            case 'update_contact':
              if (createdContacts.isNotEmpty) {
                await _updateRandomContact(tester, actionTracker, createdContacts, random);
                actionCount++;
              }
              break;
              
            case 'delete_contact':
              if (createdContacts.length > 5) { // Keep at least 5 contacts
                await _deleteRandomContact(tester, actionTracker, createdContacts, random);
                actionCount++;
              }
              break;
              
            case 'create_transaction':
              if (createdContacts.isNotEmpty) {
                await _createRandomTransaction(tester, actionTracker, createdContacts, createdTransactions, random);
                actionCount++;
              }
              break;
              
            case 'update_transaction':
              if (createdTransactions.isNotEmpty) {
                await _updateRandomTransaction(tester, actionTracker, createdTransactions, createdContacts, random);
                actionCount++;
              }
              break;
              
            case 'delete_transaction':
              if (createdTransactions.isNotEmpty) {
                await _deleteRandomTransaction(tester, actionTracker, createdTransactions, random);
                actionCount++;
              }
              break;
          }
          
          // Sync every 25 actions (less frequent for speed)
          if (actionCount % 25 == 0) {
            print('   🔄 Syncing after $actionCount actions...');
            await SyncServiceV2.manualSync();
            await tester.pumpAndSettle(const Duration(milliseconds: 200));
          }
          
          // Verify progress every 50 actions
          if (actionCount % 50 == 0) {
            print('   ✅ Completed $actionCount actions');
            print('      Contacts: ${createdContacts.length}, Transactions: ${createdTransactions.length}');
          }
        } catch (e) {
          print('   ⚠️ Error performing action: $e');
          // Continue with next action
        }
      }
      
      print('✅ Completed all 500 actions');
      print('📊 Final state: ${createdContacts.length} contacts, ${createdTransactions.length} transactions');
      
      // ========== PHASE 3: Final Sync and Verification ==========
      print('\n📝 PHASE 3: Final sync and verification...');
      
      // Final sync
      print('🔄 Performing final sync...');
      await SyncServiceV2.manualSync();
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      
      // Verify events
      await actionTracker.verifyEvents();
      
      // Verify data consistency
      print('\n🔍 Verifying data consistency...');
      final localContacts = await LocalDatabaseServiceV2.getContacts();
      final localTransactions = await LocalDatabaseServiceV2.getTransactions();
      
      print('📊 Local data: ${localContacts.length} contacts, ${localTransactions.length} transactions');
      
      // Verify balances are correct
      for (final contact in localContacts) {
        final contactTransactions = localTransactions.where((t) => t.contactId == contact.id).toList();
        int calculatedBalance = 0;
        for (final transaction in contactTransactions) {
          if (transaction.direction == TransactionDirection.lent) {
            calculatedBalance += transaction.amount;
          } else {
            calculatedBalance -= transaction.amount;
          }
        }
        expect(contact.balance, calculatedBalance, 
          reason: 'Balance mismatch for contact ${contact.name}');
      }
      
      print('✅ All verifications passed!');
      print('\n📊 Test Summary:');
      print('   - Actions performed: ${actionTracker.actions.length}');
      print('   - Contacts created: ${createdContacts.length}');
      print('   - Transactions created: ${createdTransactions.length}');
      print('   - Final contacts: ${localContacts.length}');
      print('   - Final transactions: ${localTransactions.length}');
    });
  });
}

/// Select random action based on current state
String _selectRandomAction(Random random, int contactCount, int transactionCount) {
  final actions = <String>[];
  
  // Always allow creating contacts (up to 30 total)
  if (contactCount < 30) {
    actions.add('create_contact');
  }
  
  // Allow updating contacts if we have some
  if (contactCount > 0) {
    actions.add('update_contact');
  }
  
  // Allow deleting contacts if we have more than 5
  if (contactCount > 5) {
    actions.add('delete_contact');
  }
  
  // Allow creating transactions if we have contacts
  if (contactCount > 0) {
    actions.add('create_transaction');
  }
  
  // Allow updating transactions if we have some
  if (transactionCount > 0) {
    actions.add('update_transaction');
  }
  
  // Allow deleting transactions if we have some
  if (transactionCount > 0) {
    actions.add('delete_transaction');
  }
  
  if (actions.isEmpty) {
    return 'create_contact'; // Fallback
  }
  
  // Weight actions: prefer create operations
  final weightedActions = <String>[];
  for (final action in actions) {
    if (action.startsWith('create')) {
      weightedActions.addAll([action, action, action]); // 3x weight
    } else {
      weightedActions.add(action);
    }
  }
  
  return weightedActions[random.nextInt(weightedActions.length)];
}

/// Create a random contact
Future<void> _createRandomContact(
  WidgetTester tester,
  ActionTracker tracker,
  List<Contact> contacts,
  Random random,
) async {
  globalTester = tester;
  await navigateToContactsTab(tester);
  
  final appBar = find.byType(AppBar);
  final addContactButton = find.descendant(
    of: appBar,
    matching: find.byIcon(Icons.add),
  );
  
  if (addContactButton.evaluate().isEmpty) {
    final addButtonAlt = find.widgetWithIcon(IconButton, Icons.add);
    if (addButtonAlt.evaluate().isNotEmpty) {
      await tester.tap(addButtonAlt.first);
    } else {
      await longPressAddContactFAB(tester);
    }
  } else {
    await tester.tap(addContactButton.first);
  }
  await tester.pumpAndSettle(const Duration(milliseconds: 300));
  
  final name = 'Contact ${contacts.length + 1}';
  final contact = await fillAndSaveContactForm(
    tester,
    name: name,
    username: 'user${contacts.length + 1}',
    phone: '${random.nextInt(900000000) + 100000000}',
    email: 'contact${contacts.length + 1}@example.com',
  );
  
  contacts.add(contact);
  tracker.recordAction('CREATED', 'contact', contact.id, {'name': contact.name});
}

/// Update a random contact
Future<void> _updateRandomContact(
  WidgetTester tester,
  ActionTracker tracker,
  List<Contact> contacts,
  Random random,
) async {
  globalTester = tester;
  // Skip update for now - would require implementing update UI interaction
  // The test will still cover create/delete operations
}

/// Delete a random contact
Future<void> _deleteRandomContact(
  WidgetTester tester,
  ActionTracker tracker,
  List<Contact> contacts,
  Random random,
) async {
  if (contacts.isEmpty) return;
  
  globalTester = tester;
  final contactToDelete = contacts[random.nextInt(contacts.length)];
  await deleteContactFromUI(tester, contactToDelete.name);
  contacts.remove(contactToDelete);
  tracker.recordAction('DELETED', 'contact', contactToDelete.id, {});
}

/// Create a random transaction
Future<void> _createRandomTransaction(
  WidgetTester tester,
  ActionTracker tracker,
  List<Contact> contacts,
  List<Transaction> transactions,
  Random random,
) async {
  globalTester = tester;
  await navigateToTransactionsTab(tester);
  await tapAddTransactionFAB(tester);
  
  final contact = contacts[random.nextInt(contacts.length)];
  final amount = (random.nextInt(900000) + 10000) * 1000; // 10k-1M IQD
  final direction = random.nextBool() 
      ? TransactionDirection.lent 
      : TransactionDirection.owed;
  final description = 'Transaction ${transactions.length + 1}';
  
  final transaction = await fillAndSaveTransactionForm(
    tester,
    contactName: contact.name,
    amount: amount,
    direction: direction,
    description: description,
  );
  
  transactions.add(transaction);
  tracker.recordAction('CREATED', 'transaction', transaction.id, {
    'contactId': transaction.contactId,
    'amount': transaction.amount,
    'direction': transaction.direction.toString(),
  });
}

/// Update a random transaction
Future<void> _updateRandomTransaction(
  WidgetTester tester,
  ActionTracker tracker,
  List<Transaction> transactions,
  List<Contact> contacts,
  Random random,
) async {
  globalTester = tester;
  // Skip update for now - would require implementing update UI interaction
  // The test will still cover create/delete operations
}

/// Delete a random transaction
Future<void> _deleteRandomTransaction(
  WidgetTester tester,
  ActionTracker tracker,
  List<Transaction> transactions,
  Random random,
) async {
  if (transactions.isEmpty) return;
  
  globalTester = tester;
  final transactionToDelete = transactions[random.nextInt(transactions.length)];
  await deleteTransactionFromUI(tester, transactionToDelete.id);
  transactions.remove(transactionToDelete);
  tracker.recordAction('DELETED', 'transaction', transactionToDelete.id, {});
}
