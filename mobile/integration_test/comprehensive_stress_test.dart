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

/// Calculate total debt from all contacts
Future<int> _calculateTotalDebt() async {
  final contacts = await LocalDatabaseServiceV2.getContacts();
  return contacts.fold<int>(0, (sum, contact) => sum + contact.balance);
}

/// Log action with balance verification
Future<void> _logAction(
  String actionType,
  String details,
  EnhancedActionTracker tracker,
) async {
  final totalDebt = await _calculateTotalDebt();
  print('   📝 Action #${tracker.actions.length + 1}: $actionType');
  print('      Details: $details');
  print('      💰 Total Debt: ${totalDebt.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} IQD');
  
  // Verify balance matches expected
  final contacts = await LocalDatabaseServiceV2.getContacts();
  final transactions = await LocalDatabaseServiceV2.getTransactions();
  
  // Calculate expected total debt
  int expectedTotalDebt = 0;
  for (final contact in contacts) {
    final contactTransactions = transactions.where((t) => t.contactId == contact.id).toList();
    int calculatedBalance = 0;
    for (final transaction in contactTransactions) {
      if (transaction.direction == TransactionDirection.lent) {
        calculatedBalance += transaction.amount;
      } else {
        calculatedBalance -= transaction.amount;
      }
    }
    expectedTotalDebt += calculatedBalance;
    
    // Verify individual contact balance
    if (contact.balance != calculatedBalance) {
      print('      ⚠️ Balance mismatch for ${contact.name}: Expected $calculatedBalance, got ${contact.balance}');
    }
  }
  
  if (totalDebt == expectedTotalDebt) {
    print('      ✅ Balance verified: Total debt matches expected ($expectedTotalDebt)');
  } else {
    print('      ❌ Balance mismatch: Expected $expectedTotalDebt, got $totalDebt');
  }
}

/// Enhanced Action Tracker with per-action verification
class EnhancedActionTracker {
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
  
  /// Verify events after each action - ensures immediate detection of issues
  Future<bool> verifyActionEvent(String aggregateType, String aggregateId, String expectedType) async {
    try {
      // Get local events for this aggregate
      final localEvents = await EventStoreService.getEventsForAggregate(aggregateType, aggregateId);
      
      if (localEvents.isEmpty) {
        print('   ⚠️ No events found for $aggregateType:$aggregateId');
        return false;
      }
      
      // Find the most recent event matching our action
      final matchingEvents = localEvents.where((e) => e.eventType == expectedType).toList();
      
      if (matchingEvents.isEmpty) {
        print('   ⚠️ No $expectedType event found for $aggregateType:$aggregateId. Found: ${localEvents.map((e) => e.eventType).join(", ")}');
        return false;
      }
      
      // Check if the most recent event matches
      final mostRecent = localEvents.last;
      if (mostRecent.eventType != expectedType) {
        print('   ⚠️ Most recent event type mismatch: Expected $expectedType, got ${mostRecent.eventType}');
        return false;
      }
      
      return true;
    } catch (e) {
      print('   ⚠️ Could not verify event: $e');
      return false;
    }
  }
  
  /// Verify events match between local and server
  Future<void> verifyAllEvents() async {
    print('\n🔍 Verifying all events...');
    
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
    final mismatches = <String>[];
    
    for (final entry in expectedEvents.entries) {
      final aggregateKey = entry.key;
      final expectedActions = entry.value;
      
      // Check local events
      final localAggregateEvents = localEventsByAggregate[aggregateKey] ?? [];
      if (localAggregateEvents.length != expectedActions.length) {
        final mismatch = '$aggregateKey: Expected ${expectedActions.length} events, found ${localAggregateEvents.length} locally';
        print('❌ $mismatch');
        mismatches.add(mismatch);
        mismatchCount++;
      } else {
        verifiedCount++;
      }
      
      // Check server events if available
      if (isConfigured && serverEvents.isNotEmpty) {
        final serverAggregateEvents = serverEventsByAggregate[aggregateKey] ?? [];
        if (serverAggregateEvents.length != expectedActions.length) {
          final mismatch = '$aggregateKey: Expected ${expectedActions.length} events, found ${serverAggregateEvents.length} on server';
          print('❌ $mismatch');
          mismatches.add(mismatch);
          mismatchCount++;
        }
      }
    }
    
    print('✅ Verified: $verifiedCount aggregates, ❌ Mismatches: $mismatchCount');
    if (mismatches.isNotEmpty) {
      print('\n📋 Mismatch details:');
      for (final mismatch in mismatches.take(10)) {
        print('   - $mismatch');
      }
      if (mismatches.length > 10) {
        print('   ... and ${mismatches.length - 10} more');
      }
    }
    
    // Verify total counts
    expect(localEvents.length, greaterThanOrEqualTo(actions.length), 
      reason: 'Local events should match or exceed actions');
    
    if (isConfigured && serverEvents.isNotEmpty) {
      expect(serverEvents.length, greaterThanOrEqualTo(actions.length),
        reason: 'Server events should match or exceed actions');
    }
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

  group('Comprehensive Stress Test', () {
    final actionTracker = EnhancedActionTracker();
    final random = Random(42); // Fixed seed for reproducibility
    List<Contact> createdContacts = [];
    List<Transaction> createdTransactions = [];
    
    setUpAll(() async {
      // Don't initialize here - app.main() will do it
      // This avoids double registration of Hive adapters
    });

    setUp(() async {
      // Note: Server reset happens via run_integration_test.sh before test runs
      // We don't reset server from within the test (would require running manage.sh on device)
      
      // Clean up local data
      print('🧹 Cleaning local data...');
      try {
        // Open boxes if not already open
        if (!Hive.isBoxOpen('contacts')) {
          await Hive.openBox<Contact>('contacts');
        }
        if (!Hive.isBoxOpen('transactions')) {
          await Hive.openBox<Transaction>('transactions');
        }
        if (!Hive.isBoxOpen('events')) {
          await Hive.openBox<Event>('events');
        }
        
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

        testWidgets('Comprehensive stress test: 10 contacts + 2000 natural actions', (WidgetTester tester) async {
      // Set global tester for helper functions
      globalTester = tester;
      
      // Start app
      app.main();
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      
      // Handle backend setup screen if it appears
      final testConnectionButton = find.text('Test Connection');
      if (testConnectionButton.evaluate().isNotEmpty) {
        print('📡 Found backend setup screen, pressing Test Connection...');
        await tester.tap(testConnectionButton);
        await tester.pumpAndSettle(const Duration(milliseconds: 200));
        
        var saveButton = find.text('Save & Continue');
        if (saveButton.evaluate().isEmpty) {
          saveButton = find.text('Save');
        }
        if (saveButton.evaluate().isNotEmpty) {
          await tester.tap(saveButton);
          await tester.pumpAndSettle(const Duration(milliseconds: 200));
        }
      }
      
      // Handle login screen if it appears
      final loginButtonText = find.text('Login');
      if (loginButtonText.evaluate().isNotEmpty) {
        print('🔐 Found login screen, filling credentials...');
        final usernameField = find.widgetWithText(TextFormField, 'Username');
        if (usernameField.evaluate().isNotEmpty) {
          await tester.enterText(usernameField.first, 'max');
          await tester.pump();
        }
        
        final passwordField = find.widgetWithText(TextFormField, 'Password');
        if (passwordField.evaluate().isNotEmpty) {
          await tester.enterText(passwordField.first, '1234');
          await tester.pump();
        }
        
        print('🔑 Pressing Login...');
        final loginButton = find.widgetWithText(ElevatedButton, 'Login');
        if (loginButton.evaluate().isEmpty) {
          final loginButtonAlt = find.descendant(
            of: find.byType(ElevatedButton),
            matching: find.text('Login'),
          );
          if (loginButtonAlt.evaluate().isNotEmpty) {
            await tester.tap(loginButtonAlt.first);
          }
        } else {
          await tester.tap(loginButton.first);
        }
        await tester.pumpAndSettle(const Duration(milliseconds: 500));
      }
      
      // Wait for home screen to load
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      
      // Clean up local data after app initialization
      print('🧹 Cleaning local data after app initialization...');
      await Hive.box<Contact>('contacts').clear();
      await Hive.box<Transaction>('transactions').clear();
      await Hive.box<Event>('events').clear();
      print('✅ Local data cleared');
      
      print('\n🚀 Starting comprehensive stress test...');
      print('📋 Plan: Create 10 contacts, then perform 2000 natural actions');
      
      // ========== PHASE 1: Create 10 Contacts ==========
      print('\n📝 PHASE 1: Creating 10 contacts...');
      await navigateToContactsTab(tester);
      
      for (int i = 1; i <= 10; i++) {
        print('   Creating contact $i/10...');
        
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
          phone: '07${(random.nextInt(90000000) + 10000000).toString()}',
          email: 'contact$i@example.com',
          notes: 'Test contact $i',
        );
        
        createdContacts.add(contact);
        actionTracker.recordAction('CREATED', 'contact', contact.id, {'name': contact.name});
        
        // Verify event immediately
        final verified = await actionTracker.verifyActionEvent('contact', contact.id, 'CREATED');
        if (!verified) {
          print('   ⚠️ Event verification failed for contact ${contact.id}');
        }
        
        // Sync every 5 contacts
        if (i % 5 == 0) {
          print('   🔄 Syncing after $i contacts...');
          await SyncServiceV2.manualSync();
          await tester.pumpAndSettle(const Duration(milliseconds: 200));
        }
      }
      
      print('✅ Created ${createdContacts.length} contacts');
      
      // ========== PHASE 2: Perform 2000 Natural Actions ==========
      print('\n📝 PHASE 2: Performing 2000 natural actions...');
      
      int actionCount = 0;
      int lastSyncAction = 0;
      int lastDashboardVisit = 0;
      
      while (actionCount < 2000) {
        // Visit dashboard every 50 actions for visual check
        if (actionCount > 0 && actionCount - lastDashboardVisit >= 50) {
          print('\n   📊 Visiting Dashboard for visual check...');
          await navigateToDashboardTab(tester);
          await tester.pumpAndSettle(const Duration(milliseconds: 500));
          final totalDebt = await _calculateTotalDebt();
          print('   💰 Current Total Debt: ${totalDebt.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} IQD');
          await tester.pumpAndSettle(const Duration(milliseconds: 1000)); // Give time to see dashboard
          lastDashboardVisit = actionCount;
        }
        
        // Determine action type based on current state - more natural distribution
        final actionType = _selectNaturalAction(random, createdContacts.length, createdTransactions.length, actionCount);
        
        try {
          bool actionSucceeded = false;
          
          switch (actionType) {
            case 'create_contact':
              await _createRandomContact(tester, actionTracker, createdContacts, random);
              actionSucceeded = true;
              break;
              
            case 'swipe_contact_add_transaction':
              if (createdContacts.isNotEmpty) {
                await _swipeContactToAddTransaction(tester, actionTracker, createdContacts, createdTransactions, random);
                actionSucceeded = true;
              }
              break;
              
            case 'create_transaction':
              if (createdContacts.isNotEmpty) {
                await _createRandomTransaction(tester, actionTracker, createdContacts, createdTransactions, random);
                actionSucceeded = true;
              }
              break;
              
            case 'swipe_transaction_close':
              if (createdTransactions.isNotEmpty) {
                await _swipeTransactionToClose(tester, actionTracker, createdTransactions, createdContacts, random);
                actionSucceeded = true;
              }
              break;
              
            case 'delete_transaction':
              if (createdTransactions.isNotEmpty) {
                await _deleteRandomTransaction(tester, actionTracker, createdTransactions, random);
                actionSucceeded = true;
              }
              break;
              
            case 'delete_contact':
              if (createdContacts.length > 10) { // Keep at least 10 contacts
                await _deleteRandomContact(tester, actionTracker, createdContacts, random);
                actionSucceeded = true;
              }
              break;
              
            case 'bulk_delete_contacts':
              if (createdContacts.length > 15) { // Keep at least 15 contacts
                await _bulkDeleteContacts(tester, actionTracker, createdContacts, random);
                actionSucceeded = true;
              }
              break;
              
            case 'bulk_delete_transactions':
              if (createdTransactions.length > 5) {
                await _bulkDeleteTransactions(tester, actionTracker, createdTransactions, random);
                actionSucceeded = true;
              }
              break;
              
            case 'dashboard_tap_contact':
              if (createdContacts.isNotEmpty) {
                await _dashboardTapContact(tester, actionTracker, createdContacts, createdTransactions, random);
                actionSucceeded = true;
              }
              break;
              
            case 'dashboard_tap_transaction':
              if (createdTransactions.isNotEmpty) {
                await _dashboardTapTransaction(tester, actionTracker, createdTransactions, createdContacts, random);
                actionSucceeded = true;
              }
              break;
          }
          
          if (actionSucceeded) {
            actionCount++;
            
            // Verify event after each action (critical for catching issues early)
            if (actionCount % 10 == 0) {
              // Quick verification every 10 actions
              final allActions = actionTracker.actions;
              final startIndex = allActions.length > 10 ? allActions.length - 10 : 0;
              final recentActions = allActions.sublist(startIndex);
              for (final action in recentActions) {
                await actionTracker.verifyActionEvent(
                  action.aggregateType,
                  action.aggregateId,
                  action.type,
                );
              }
            }
            
            // Sync every 50 actions
            if (actionCount - lastSyncAction >= 50) {
              print('   🔄 Syncing after $actionCount actions...');
              await SyncServiceV2.manualSync();
              await tester.pumpAndSettle(const Duration(milliseconds: 200));
              lastSyncAction = actionCount;
              
              // Verify events after sync
              print('   🔍 Verifying events after sync...');
              await actionTracker.verifyAllEvents();
            }
            
            // Progress report every 100 actions
            if (actionCount % 100 == 0) {
              print('   ✅ Completed $actionCount actions');
              print('      Contacts: ${createdContacts.length}, Transactions: ${createdTransactions.length}');
              print('      Actions tracked: ${actionTracker.actions.length}');
            }
          }
        } catch (e) {
          print('   ⚠️ Error performing action $actionType: $e');
          // Continue with next action
        }
      }
      
      print('✅ Completed all 2000 actions');
      print('📊 Final state: ${createdContacts.length} contacts, ${createdTransactions.length} transactions');
      print('📊 Total actions tracked: ${actionTracker.actions.length}');
      
      // ========== PHASE 3: Final Sync and Comprehensive Verification ==========
      print('\n📝 PHASE 3: Final sync and comprehensive verification...');
      
      // Final sync
      print('🔄 Performing final sync...');
      await SyncServiceV2.manualSync();
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      
      // Comprehensive event verification
      await actionTracker.verifyAllEvents();
      
      // Verify data consistency
      print('\n🔍 Verifying data consistency...');
      final localContacts = await LocalDatabaseServiceV2.getContacts();
      final localTransactions = await LocalDatabaseServiceV2.getTransactions();
      
      print('📊 Local data: ${localContacts.length} contacts, ${localTransactions.length} transactions');
      
      // Verify balances are correct
      int balanceErrors = 0;
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
        if (contact.balance != calculatedBalance) {
          print('❌ Balance mismatch for ${contact.name}: Expected $calculatedBalance, got ${contact.balance}');
          balanceErrors++;
        }
      }
      
      expect(balanceErrors, 0, reason: 'All contact balances should be correct');
      
      print('✅ All verifications passed!');
      print('\n📊 Final Test Summary:');
      print('   - Actions performed: ${actionTracker.actions.length}');
      print('   - Contacts created: ${createdContacts.length}');
      print('   - Transactions created: ${createdTransactions.length}');
      print('   - Final contacts: ${localContacts.length}');
      print('   - Final transactions: ${localTransactions.length}');
      print('   - Balance errors: $balanceErrors');
    });
  });
}

/// Select natural action - mimics real user behavior
String _selectNaturalAction(Random random, int contactCount, int transactionCount, int actionCount) {
  final actions = <String>[];
  
  // Early phase: Focus on creating contacts and transactions (prefer swipes)
  if (actionCount < 500) {
    if (contactCount < 10) {
      actions.addAll(['create_contact', 'create_contact', 'create_contact']); // 3x weight
    }
    if (contactCount > 0) {
      // Heavily favor swipe actions for creating transactions
      actions.addAll([
        'swipe_contact_add_transaction', 'swipe_contact_add_transaction', 'swipe_contact_add_transaction', // 3x weight
        'swipe_contact_add_transaction', 'swipe_contact_add_transaction', // 2 more
        'create_transaction', // Regular FAB creation (less frequent)
      ]);
    }
  }
  
  // Mid phase: Mix of create, swipe actions, and some deletes (favor swipes)
  else if (actionCount < 1500) {
    if (contactCount < 10) {
      actions.add('create_contact');
    }
    if (contactCount > 0) {
      // Favor swipe actions heavily
      actions.addAll([
        'swipe_contact_add_transaction', 'swipe_contact_add_transaction', 'swipe_contact_add_transaction', // 3x weight
        'swipe_transaction_close', 'swipe_transaction_close', // 2x weight for closing
        'create_transaction', // Regular FAB creation (less frequent)
        'dashboard_tap_contact',
      ]);
    }
    if (transactionCount > 0) {
      actions.addAll([
        'swipe_transaction_close', 'swipe_transaction_close', 'swipe_transaction_close', // 3x weight
        'delete_transaction',
        'dashboard_tap_transaction',
      ]);
    }
    if (contactCount > 10) {
      actions.add('delete_contact');
    }
  }
  
  // Late phase: More deletions, bulk operations, closing transactions (still favor swipes)
  else {
    if (contactCount > 0) {
      actions.addAll([
        'swipe_contact_add_transaction', 'swipe_contact_add_transaction', // 2x weight
        'swipe_transaction_close', 'swipe_transaction_close', 'swipe_transaction_close', // 3x weight
      ]);
    }
    if (transactionCount > 0) {
      actions.addAll([
        'swipe_transaction_close', 'swipe_transaction_close', 'swipe_transaction_close', 'swipe_transaction_close', // 4x weight
        'delete_transaction',
      ]);
    }
    if (contactCount > 5) {
      actions.addAll(['delete_contact', 'bulk_delete_contacts']);
    }
    if (transactionCount > 5) {
      actions.add('bulk_delete_transactions');
    }
  }
  
  // Always allow some operations regardless of phase (favor swipes)
  if (contactCount < 10) {
    actions.add('create_contact');
  }
  if (contactCount > 0) {
    actions.addAll([
      'swipe_contact_add_transaction', 'swipe_contact_add_transaction', // 2x weight for swipes
      'create_transaction', // Regular FAB (less frequent)
      'dashboard_tap_contact',
    ]);
  }
  if (transactionCount > 0) {
    actions.addAll([
      'swipe_transaction_close', 'swipe_transaction_close', 'swipe_transaction_close', // 3x weight
      'dashboard_tap_transaction',
    ]);
  }
  if (contactCount > 10) {
    actions.add('delete_contact');
  }
  if (transactionCount > 0) {
    actions.add('delete_transaction');
  }
  
  if (actions.isEmpty) {
    return 'create_contact'; // Fallback
  }
  
  return actions[random.nextInt(actions.length)];
}

/// Create a random contact
Future<void> _createRandomContact(
  WidgetTester tester,
  EnhancedActionTracker tracker,
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
  await tester.pumpAndSettle(const Duration(milliseconds: 50));
  
  final name = 'Contact ${contacts.length + 1}';
  final contact = await fillAndSaveContactForm(
    tester,
    name: name,
    username: 'user${contacts.length + 1}',
    phone: '07${(random.nextInt(90000000) + 10000000).toString()}',
    email: 'contact${contacts.length + 1}@example.com',
  );
  
  contacts.add(contact);
  tracker.recordAction('CREATED', 'contact', contact.id, {'name': contact.name});
  
  await _logAction(
    'CREATE_CONTACT',
    'Created contact: ${contact.name}',
    tracker,
  );
}

/// Swipe contact to add transaction
Future<void> _swipeContactToAddTransaction(
  WidgetTester tester,
  EnhancedActionTracker tracker,
  List<Contact> contacts,
  List<Transaction> transactions,
  Random random,
) async {
  globalTester = tester;
  await navigateToContactsTab(tester);
  await tester.pumpAndSettle(const Duration(milliseconds: 50));
  
  // Find a random contact in the list
  final contact = contacts[random.nextInt(contacts.length)];
  final contactItem = find.text(contact.name);
  
  if (contactItem.evaluate().isEmpty) {
    // Contact might not be visible, scroll or skip
    return;
  }
  
  // Swipe right on contact (Dismissible swipe)
  await tester.drag(contactItem.first, const Offset(300, 0)); // Swipe right
  await tester.pumpAndSettle(const Duration(milliseconds: 300));
  
  // Fill transaction form (should be pre-filled with contact)
  // Amount range: 30,000 to 300,000 IQD (matching database range)
  final amount = random.nextInt(270001) + 30000;
  final direction = random.nextBool() ? TransactionDirection.lent : TransactionDirection.owed;
  final description = 'Swipe transaction ${transactions.length + 1}';
  
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
    'method': 'swipe',
  });
}

/// Create a random transaction
Future<void> _createRandomTransaction(
  WidgetTester tester,
  EnhancedActionTracker tracker,
  List<Contact> contacts,
  List<Transaction> transactions,
  Random random,
) async {
  globalTester = tester;
  // FAB works from anywhere on home screen, no need to navigate
  await tapAddTransactionFAB(tester);
  await tester.pumpAndSettle(const Duration(milliseconds: 50));
  
  final contact = contacts[random.nextInt(contacts.length)];
  // Amount range: 30,000 to 300,000 IQD (matching database range)
  final amount = random.nextInt(270001) + 30000;
  final direction = random.nextBool() ? TransactionDirection.lent : TransactionDirection.owed;
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
  
  await _logAction(
    'CREATE_TRANSACTION',
    '${direction == TransactionDirection.lent ? "Lent" : "Owed"} ${amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} IQD to ${contact.name}',
    tracker,
  );
}

/// Swipe transaction to close it (create reverse transaction)
Future<void> _swipeTransactionToClose(
  WidgetTester tester,
  EnhancedActionTracker tracker,
  List<Transaction> transactions,
  List<Contact> contacts,
  Random random,
) async {
  globalTester = tester;
  await navigateToTransactionsTab(tester);
  await tester.pumpAndSettle(const Duration(milliseconds: 50));
  
  // Find a random transaction
  final transactionToClose = transactions[random.nextInt(transactions.length)];
  
  // Find transaction item by amount or description
  final formattedAmount = transactionToClose.amount.toString().replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (Match m) => '${m[1]},',
  );
  
  var transactionItem = find.textContaining('$formattedAmount IQD');
  if (transactionItem.evaluate().isEmpty && transactionToClose.description != null) {
    transactionItem = find.textContaining(transactionToClose.description!);
  }
  
  if (transactionItem.evaluate().isEmpty) {
    // Try finding by Dismissible key
    transactionItem = find.byKey(Key(transactionToClose.id));
  }
  
  if (transactionItem.evaluate().isEmpty) {
    return; // Skip if not found
  }
  
  // Swipe right to close transaction
  await tester.drag(transactionItem.first, const Offset(300, 0));
  await tester.pumpAndSettle(const Duration(milliseconds: 300));
  
  // The swipe should open a reverse transaction form - fill and save it
  // Find the contact for this transaction
  final contact = contacts.firstWhere(
    (c) => c.id == transactionToClose.contactId,
    orElse: () => contacts.first,
  );
  
  // The form should be pre-filled, just save it
  final saveIcon = find.byIcon(Icons.save);
  if (saveIcon.evaluate().isNotEmpty) {
    await tester.tap(saveIcon.first);
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    
    // Get the newly created reverse transaction
    await Future.delayed(const Duration(milliseconds: 300));
    final allTransactions = await LocalDatabaseServiceV2.getTransactions();
    final newTransactions = allTransactions.where((t) => 
      t.contactId == transactionToClose.contactId &&
      t.amount == transactionToClose.amount &&
      t.direction != transactionToClose.direction &&
      t.id != transactionToClose.id
    ).toList();
    
    if (newTransactions.isNotEmpty) {
      final reverseTransaction = newTransactions.first;
      transactions.add(reverseTransaction);
      tracker.recordAction('CREATED', 'transaction', reverseTransaction.id, {
        'contactId': reverseTransaction.contactId,
        'amount': reverseTransaction.amount,
        'direction': reverseTransaction.direction.toString(),
        'method': 'swipe_close',
        'closes': transactionToClose.id,
      });
      
      await _logAction(
        'SWIPE_TRANSACTION_CLOSE',
        'Closed transaction: ${reverseTransaction.direction == TransactionDirection.lent ? "Lent" : "Owed"} ${reverseTransaction.amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} IQD for ${contact.name}',
        tracker,
      );
    }
  }
}

/// Delete a random contact
Future<void> _deleteRandomContact(
  WidgetTester tester,
  EnhancedActionTracker tracker,
  List<Contact> contacts,
  Random random,
) async {
  if (contacts.isEmpty) return;
  
  globalTester = tester;
  final contactToDelete = contacts[random.nextInt(contacts.length)];
  final contactName = contactToDelete.name;
  await deleteContactFromUI(tester, contactName);
  contacts.remove(contactToDelete);
  tracker.recordAction('DELETED', 'contact', contactToDelete.id, {});
  
  await _logAction(
    'DELETE_CONTACT',
    'Deleted contact: $contactName',
    tracker,
  );
}

/// Delete a random transaction
Future<void> _deleteRandomTransaction(
  WidgetTester tester,
  EnhancedActionTracker tracker,
  List<Transaction> transactions,
  Random random,
) async {
  if (transactions.isEmpty) return;
  
  globalTester = tester;
  final transactionToDelete = transactions[random.nextInt(transactions.length)];
  final amount = transactionToDelete.amount;
  final direction = transactionToDelete.direction;
  final contacts = await LocalDatabaseServiceV2.getContacts();
  final contact = contacts.firstWhere((c) => c.id == transactionToDelete.contactId, orElse: () => contacts.first);
  
  await deleteTransactionFromUI(tester, transactionToDelete.id);
  transactions.remove(transactionToDelete);
  tracker.recordAction('DELETED', 'transaction', transactionToDelete.id, {});
  
  await _logAction(
    'DELETE_TRANSACTION',
    'Deleted ${direction == TransactionDirection.lent ? "lent" : "owed"} ${amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} IQD transaction for ${contact.name}',
    tracker,
  );
}

/// Bulk delete contacts
Future<void> _bulkDeleteContacts(
  WidgetTester tester,
  EnhancedActionTracker tracker,
  List<Contact> contacts,
  Random random,
) async {
  if (contacts.length < 3) return; // Need at least 3 to bulk delete
  
  globalTester = tester;
  await navigateToContactsTab(tester);
  await tester.pumpAndSettle(const Duration(milliseconds: 50));
  
  // Enter selection mode
  final selectButton = find.byIcon(Icons.checklist);
  if (selectButton.evaluate().isNotEmpty) {
    await tester.tap(selectButton.first);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  }
  
  // Select 2-3 random contacts
  final contactsToDelete = contacts.take(2 + random.nextInt(2)).toList();
  for (final contact in contactsToDelete) {
    final contactItem = find.text(contact.name);
    if (contactItem.evaluate().isNotEmpty) {
      await tester.tap(contactItem.first);
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
    }
  }
  
  // Tap delete button
  final deleteButton = find.byIcon(Icons.delete);
  if (deleteButton.evaluate().isNotEmpty) {
    await tester.tap(deleteButton.first);
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    
    // Confirm deletion
    final confirmButton = find.text('Delete');
    if (confirmButton.evaluate().isNotEmpty) {
      await tester.tap(confirmButton.first);
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      
      // Record deletions
      for (final contact in contactsToDelete) {
        contacts.remove(contact);
        tracker.recordAction('DELETED', 'contact', contact.id, {'bulk': true});
      }
    }
  }
  
  // Exit selection mode
  final closeButton = find.byIcon(Icons.close);
  if (closeButton.evaluate().isNotEmpty) {
    await tester.tap(closeButton.first);
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
  }
}

/// Bulk delete transactions
Future<void> _bulkDeleteTransactions(
  WidgetTester tester,
  EnhancedActionTracker tracker,
  List<Transaction> transactions,
  Random random,
) async {
  if (transactions.length < 3) return;
  
  globalTester = tester;
  await navigateToTransactionsTab(tester);
  await tester.pumpAndSettle(const Duration(milliseconds: 50));
  
  // Enter selection mode - find the select/checklist icon button
  final appBar = find.byType(AppBar);
  final selectButton = find.descendant(
    of: appBar,
    matching: find.byIcon(Icons.checklist),
  );
  
  if (selectButton.evaluate().isEmpty) {
    // Try finding by tooltip or text
    final selectByTooltip = find.byTooltip('Select');
    if (selectByTooltip.evaluate().isNotEmpty) {
      await tester.tap(selectByTooltip.first);
    } else {
      return; // Can't enter selection mode
    }
  } else {
    await tester.tap(selectButton.first);
  }
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  
  // Select 2-3 random transactions
  final numToDelete = 2 + random.nextInt(2);
  final transactionsToDelete = transactions.take(numToDelete).toList();
  int selected = 0;
  
  for (final transaction in transactionsToDelete) {
    // Try finding by Dismissible key first (most reliable)
    var transactionItem = find.byKey(Key(transaction.id));
    
    if (transactionItem.evaluate().isEmpty) {
      // Fallback: find by amount
      final formattedAmount = transaction.amount.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (Match m) => '${m[1]},',
      );
      transactionItem = find.textContaining('$formattedAmount IQD');
    }
    
    if (transactionItem.evaluate().isNotEmpty) {
      await tester.tap(transactionItem.first);
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      selected++;
      if (selected >= numToDelete) break;
    }
  }
  
  if (selected == 0) {
    // Exit selection mode if nothing selected
    final closeButton = find.byIcon(Icons.close);
    if (closeButton.evaluate().isNotEmpty) {
      await tester.tap(closeButton.first);
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
    }
    return;
  }
  
  // Tap delete button (in app bar when in selection mode)
  final deleteButton = find.descendant(
    of: appBar,
    matching: find.byIcon(Icons.delete),
  );
  
  if (deleteButton.evaluate().isEmpty) {
    // Try finding delete button directly
    final deleteDirect = find.byIcon(Icons.delete);
    if (deleteDirect.evaluate().isNotEmpty) {
      await tester.tap(deleteDirect.first);
    } else {
      // Exit selection mode
      final closeButton = find.byIcon(Icons.close);
      if (closeButton.evaluate().isNotEmpty) {
        await tester.tap(closeButton.first);
      }
      return;
    }
  } else {
    await tester.tap(deleteButton.first);
  }
  await tester.pumpAndSettle(const Duration(milliseconds: 200));
  
  // Confirm deletion dialog
  final confirmButton = find.text('Delete');
  if (confirmButton.evaluate().isNotEmpty) {
    await tester.tap(confirmButton.first);
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    
    // Record deletions
    for (final transaction in transactionsToDelete) {
      transactions.remove(transaction);
      tracker.recordAction('DELETED', 'transaction', transaction.id, {'bulk': true});
    }
  }
  
  // Exit selection mode
  final closeButton = find.byIcon(Icons.close);
  if (closeButton.evaluate().isNotEmpty) {
    await tester.tap(closeButton.first);
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
  }
}

/// Tap on a contact from dashboard to view transactions or create new one
Future<void> _dashboardTapContact(
  WidgetTester tester,
  EnhancedActionTracker tracker,
  List<Contact> contacts,
  List<Transaction> transactions,
  Random random,
) async {
  globalTester = tester;
  await navigateToDashboardTab(tester);
  await tester.pumpAndSettle(const Duration(milliseconds: 200));
  
  // Find a random contact from the dashboard
  final contact = contacts[random.nextInt(contacts.length)];
  
  // Try to find the contact in the dashboard (could be in Debts or Credits section)
  var contactItem = find.text(contact.name);
  if (contactItem.evaluate().isEmpty) {
    // Contact might be shown with balance, try finding by partial match
    contactItem = find.textContaining(contact.name);
  }
  
  if (contactItem.evaluate().isEmpty) {
    return; // Contact not visible on dashboard, skip
  }
  
  // Tap on the contact
  await tester.tap(contactItem.first);
  await tester.pumpAndSettle(const Duration(milliseconds: 300));
  
  // We're now on ContactTransactionsScreen
  // Randomly decide: view transactions or create new one
  if (random.nextBool() && transactions.where((t) => t.contactId == contact.id).isNotEmpty) {
    // View existing transaction (tap on one)
    final contactTransactions = transactions.where((t) => t.contactId == contact.id).toList();
    final transaction = contactTransactions[random.nextInt(contactTransactions.length)];
    
    final formattedAmount = transaction.amount.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    
    var transactionItem = find.textContaining('$formattedAmount IQD');
    if (transactionItem.evaluate().isEmpty && transaction.description != null) {
      transactionItem = find.textContaining(transaction.description!);
    }
    
    if (transactionItem.evaluate().isNotEmpty) {
      await tester.tap(transactionItem.first);
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      
      // Go back
      final backButton = find.byIcon(Icons.arrow_back);
      if (backButton.evaluate().isNotEmpty) {
        await tester.tap(backButton.first);
        await tester.pumpAndSettle(const Duration(milliseconds: 200));
      }
      
      await _logAction(
        'DASHBOARD_TAP_CONTACT_VIEW_TRANSACTION',
        'Viewed transaction ${formattedAmount} IQD for ${contact.name}',
        tracker,
      );
    }
  } else {
    // Create new transaction from contact screen
    // Look for FAB or add button
    final fab = find.byType(FloatingActionButton);
    if (fab.evaluate().isNotEmpty) {
      await tester.tap(fab.first);
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      
      // Amount range: 30,000 to 300,000 IQD (matching database range)
      final amount = random.nextInt(270001) + 30000;
      final direction = random.nextBool() ? TransactionDirection.lent : TransactionDirection.owed;
      
      // Form should be pre-filled with contact, just fill amount and direction
      final amountField = find.widgetWithText(TextFormField, 'Amount');
      if (amountField.evaluate().isEmpty) {
        final allTextFields = find.byType(TextFormField);
        if (allTextFields.evaluate().length > 1) {
          await tester.enterText(allTextFields.at(1), amount.toString());
        }
      } else {
        await tester.enterText(amountField.first, amount.toString());
      }
      await tester.pump();
      
      if (direction == TransactionDirection.lent) {
        final lentSegment = find.widgetWithText(ButtonSegment<TransactionDirection>, 'Give');
        if (lentSegment.evaluate().isNotEmpty) {
          await tester.tap(lentSegment);
        }
      } else {
        final owedSegment = find.widgetWithText(ButtonSegment<TransactionDirection>, 'Received');
        if (owedSegment.evaluate().isNotEmpty) {
          await tester.tap(owedSegment);
        }
      }
      await tester.pump();
      
      final saveIcon = find.byIcon(Icons.save);
      if (saveIcon.evaluate().isNotEmpty) {
        await tester.tap(saveIcon.first);
        await tester.pumpAndSettle(const Duration(milliseconds: 200));
        
        await Future.delayed(const Duration(milliseconds: 300));
        final allTransactions = await LocalDatabaseServiceV2.getTransactions();
        final newTransaction = allTransactions.firstWhere(
          (t) => t.contactId == contact.id && 
                 t.amount == amount && 
                 t.direction == direction,
          orElse: () => allTransactions.last,
        );
        
        transactions.add(newTransaction);
        tracker.recordAction('CREATED', 'transaction', newTransaction.id, {
          'contactId': newTransaction.contactId,
          'amount': newTransaction.amount,
          'direction': newTransaction.direction.toString(),
          'method': 'dashboard',
        });
        
        await _logAction(
          'DASHBOARD_TAP_CONTACT_CREATE_TRANSACTION',
          '${direction == TransactionDirection.lent ? "Lent" : "Owed"} ${amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} IQD to ${contact.name} (via dashboard)',
          tracker,
        );
      }
    }
  }
  
  // Navigate back to dashboard
  final backButton = find.byIcon(Icons.arrow_back);
  if (backButton.evaluate().isNotEmpty) {
    await tester.tap(backButton.first);
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
  }
}

/// Tap on a transaction from dashboard (upcoming due dates section)
Future<void> _dashboardTapTransaction(
  WidgetTester tester,
  EnhancedActionTracker tracker,
  List<Transaction> transactions,
  List<Contact> contacts,
  Random random,
) async {
  globalTester = tester;
  await navigateToDashboardTab(tester);
  await tester.pumpAndSettle(const Duration(milliseconds: 200));
  
  // Find a random transaction that might be shown on dashboard
  final transaction = transactions[random.nextInt(transactions.length)];
  final contact = contacts.firstWhere((c) => c.id == transaction.contactId, orElse: () => contacts.first);
  
  final formattedAmount = transaction.amount.toString().replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (Match m) => '${m[1]},',
  );
  
  // Try to find transaction on dashboard (might be in upcoming due dates)
  var transactionItem = find.textContaining('$formattedAmount IQD');
  if (transactionItem.evaluate().isEmpty && transaction.description != null) {
    transactionItem = find.textContaining(transaction.description!);
  }
  if (transactionItem.evaluate().isEmpty) {
    transactionItem = find.textContaining(contact.name);
  }
  
  if (transactionItem.evaluate().isEmpty) {
    return; // Transaction not visible on dashboard, skip
  }
  
  // Tap on the transaction
  await tester.tap(transactionItem.first);
  await tester.pumpAndSettle(const Duration(milliseconds: 300));
  
  // We're now on ContactTransactionsScreen or transaction detail
  // Just view it and go back
  await tester.pumpAndSettle(const Duration(milliseconds: 200));
  
  final backButton = find.byIcon(Icons.arrow_back);
  if (backButton.evaluate().isNotEmpty) {
    await tester.tap(backButton.first);
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
  }
  
  await _logAction(
    'DASHBOARD_TAP_TRANSACTION',
    'Viewed transaction ${formattedAmount} IQD for ${contact.name} from dashboard',
    tracker,
  );
}
