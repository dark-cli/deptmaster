// ignore_for_file: unused_import, unused_local_variable

import 'dart:developer' as developer;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive_flutter/hive_flutter.dart';
import '../models/contact.dart';
import '../models/transaction.dart';
import '../models/event.dart';
import 'event_store_service.dart';
import 'state_builder.dart';
import 'sync_service_v2.dart';
import 'api_service.dart';
import 'projection_snapshot_service.dart';
import 'wallet_service.dart';
import 'dummy_data_service.dart';
import 'auth_service.dart';
import 'package:uuid/uuid.dart';

/// Simplified Local Database Service - KISS approach
/// All writes create events, state is rebuilt from events using StateBuilder
class LocalDatabaseServiceV2 {
  static const uuid = Uuid();

  // ========== READ OPERATIONS ==========
  // Read directly from Hive boxes (projections)

  static Future<List<Contact>> getContacts() async {
    if (kIsWeb) return [];
    
    try {
      final walletId = WalletService.getCurrentWalletId();
      if (walletId == null) {
        print('⚠️ No current wallet set, returning empty contacts list');
        return [];
      }
      
      final userId = await AuthService.getUserId();
      final boxName = DummyDataService.getContactsBoxName(userId: userId, walletId: walletId);
      await Hive.openBox<Contact>(boxName);
      final contactsBox = Hive.box<Contact>(boxName);
      return contactsBox.values
          .where((c) => c.walletId == walletId || c.walletId == null) // Include null for migration
          .toList();
    } catch (e) {
      print('Error reading contacts: $e');
      return [];
    }
  }

  static Future<Contact?> getContact(String id) async {
    if (kIsWeb) return null;
    
    try {
      final walletId = WalletService.getCurrentWalletId();
      if (walletId == null) return null;
      
      final userId = await AuthService.getUserId();
      final boxName = DummyDataService.getContactsBoxName(userId: userId, walletId: walletId);
      await Hive.openBox<Contact>(boxName);
      final contactsBox = Hive.box<Contact>(boxName);
      final contact = contactsBox.get(id);
      
      // Verify contact belongs to current wallet (or is legacy data)
      if (contact != null && contact.walletId != null && contact.walletId != walletId) {
        return null; // Contact belongs to different wallet
      }
      
      return contact;
    } catch (e) {
      print('Error reading contact: $e');
      return null;
    }
  }

  static Future<List<Transaction>> getTransactions() async {
    if (kIsWeb) return [];
    
    try {
      final walletId = WalletService.getCurrentWalletId();
      if (walletId == null) {
        print('⚠️ No current wallet set, returning empty transactions list');
        return [];
      }
      
      final userId = await AuthService.getUserId();
      final boxName = DummyDataService.getTransactionsBoxName(userId: userId, walletId: walletId);
      await Hive.openBox<Transaction>(boxName);
      final transactionsBox = Hive.box<Transaction>(boxName);
      return transactionsBox.values
          .where((t) => t.walletId == walletId || t.walletId == null) // Include null for migration
          .toList();
    } catch (e) {
      print('Error reading transactions: $e');
      return [];
    }
  }

  static Future<Transaction?> getTransaction(String id) async {
    if (kIsWeb) return null;
    
    try {
      final walletId = WalletService.getCurrentWalletId();
      if (walletId == null) return null;
      
      final userId = await AuthService.getUserId();
      final boxName = DummyDataService.getTransactionsBoxName(userId: userId, walletId: walletId);
      await Hive.openBox<Transaction>(boxName);
      final transactionsBox = Hive.box<Transaction>(boxName);
      final transaction = transactionsBox.get(id);
      
      // Verify transaction belongs to current wallet (or is legacy data)
      if (transaction != null && transaction.walletId != null && transaction.walletId != walletId) {
        return null; // Transaction belongs to different wallet
      }
      
      return transaction;
    } catch (e) {
      print('Error reading transaction: $e');
      return null;
    }
  }

  static Future<List<Transaction>> getTransactionsByContact(String contactId) async {
    if (kIsWeb) return [];
    
    try {
      final walletId = WalletService.getCurrentWalletId();
      if (walletId == null) {
        return [];
      }
      
      final userId = await AuthService.getUserId();
      final boxName = DummyDataService.getTransactionsBoxName(userId: userId, walletId: walletId);
      await Hive.openBox<Transaction>(boxName);
      final transactionsBox = Hive.box<Transaction>(boxName);
      return transactionsBox.values
          .where((t) => t.contactId == contactId && (t.walletId == walletId || t.walletId == null))
          .toList();
    } catch (e) {
      print('Error reading transactions by contact: $e');
      return [];
    }
  }

  // ========== WRITE OPERATIONS ==========
  // All writes create events, then rebuild state

  static Future<Contact> createContact(Contact contact, {String? comment}) async {
    if (kIsWeb) return contact;
    
    try {
      // 1. Ensure wallet_id is set on contact
      final walletId = await WalletService.ensureCurrentWallet();
      final contactWithWallet = contact.copyWith(walletId: walletId ?? contact.walletId);
      
      // 2. Create event
      final eventData = {
        'name': contactWithWallet.name,
        'username': contactWithWallet.username,
        'phone': contactWithWallet.phone,
        'email': contactWithWallet.email,
        'notes': contactWithWallet.notes,
        'comment': comment ?? 'Contact created',
        'timestamp': DateTime.now().toIso8601String(),
        'wallet_id': walletId, // Include wallet_id in event data
      };

      await EventStoreService.appendEvent(
        aggregateType: 'contact',
        aggregateId: contactWithWallet.id,
        eventType: 'CREATED',
        eventData: eventData,
      );

      // 3. Rebuild state
      await _rebuildState();

      // 4. Trigger automatic sync to server (like Firebase - immediate push)
      SyncServiceV2.startLocalToServerSync();

      print('✅ Contact created: ${contactWithWallet.name}');
      return contactWithWallet;
    } catch (e) {
      print('Error creating contact: $e');
      rethrow;
    }
  }

  static Future<Contact> updateContact(Contact contact, {String? comment}) async {
    if (kIsWeb) return contact;
    
    try {
      // 1. Create event
      final walletId = await WalletService.ensureCurrentWallet();
      final eventData = {
        'name': contact.name,
        'username': contact.username,
        'phone': contact.phone,
        'email': contact.email,
        'notes': contact.notes,
        'comment': comment ?? 'Contact updated',
        'timestamp': DateTime.now().toIso8601String(),
        'wallet_id': walletId, // Include wallet_id in event data
      };

      await EventStoreService.appendEvent(
        aggregateType: 'contact',
        aggregateId: contact.id,
        eventType: 'UPDATED',
        eventData: eventData,
      );

      // 2. Rebuild state
      await _rebuildState();

      // 3. Trigger automatic sync to server (like Firebase - immediate push)
      SyncServiceV2.startLocalToServerSync();

      print('✅ Contact updated: ${contact.name}');
      return contact;
    } catch (e) {
      print('Error updating contact: $e');
      rethrow;
    }
  }

  static Future<void> deleteContact(String contactId, {String? comment}) async {
    if (kIsWeb) return;
    
    try {
      // 1. Create event
      final walletId = await WalletService.ensureCurrentWallet();
      final eventData = {
        'comment': comment ?? 'Contact deleted',
        'timestamp': DateTime.now().toIso8601String(),
        'wallet_id': walletId, // Include wallet_id in event data
      };

      await EventStoreService.appendEvent(
        aggregateType: 'contact',
        aggregateId: contactId,
        eventType: 'DELETED',
        eventData: eventData,
      );

      // 2. Rebuild state
      await _rebuildState();

      // 3. Trigger automatic sync to server (like Firebase - immediate push)
      SyncServiceV2.startLocalToServerSync();

      print('✅ Contact deleted: $contactId');
    } catch (e) {
      print('Error deleting contact: $e');
      rethrow;
    }
  }

  static Future<Transaction> createTransaction(Transaction transaction) async {
    if (kIsWeb) return transaction;
    
    try {
      // 1. Ensure wallet_id is set on transaction
      final walletId = await WalletService.ensureCurrentWallet();
      final transactionWithWallet = Transaction(
        id: transaction.id,
        contactId: transaction.contactId,
        type: transaction.type,
        direction: transaction.direction,
        amount: transaction.amount,
        currency: transaction.currency,
        description: transaction.description,
        transactionDate: transaction.transactionDate,
        dueDate: transaction.dueDate,
        imagePaths: transaction.imagePaths,
        createdAt: transaction.createdAt,
        updatedAt: transaction.updatedAt,
        isSynced: transaction.isSynced,
        walletId: walletId ?? transaction.walletId,
      );
      
      // 2. Create event
      final eventData = {
        'contact_id': transactionWithWallet.contactId,
        'type': transactionWithWallet.type == TransactionType.item ? 'item' : 'money',
        'direction': transactionWithWallet.direction == TransactionDirection.lent ? 'lent' : 'owed',
        'amount': transactionWithWallet.amount,
        'currency': transactionWithWallet.currency,
        'description': transactionWithWallet.description,
        'transaction_date': transactionWithWallet.transactionDate.toIso8601String().split('T')[0],
        'due_date': transactionWithWallet.dueDate?.toIso8601String().split('T')[0],
        'timestamp': DateTime.now().toIso8601String(),
        'wallet_id': walletId, // Include wallet_id in event data
      };

      await EventStoreService.appendEvent(
        aggregateType: 'transaction',
        aggregateId: transactionWithWallet.id,
        eventType: 'CREATED',
        eventData: eventData,
      );

      // 3. Rebuild state
      await _rebuildState();

      // 4. Trigger automatic sync to server (like Firebase - immediate push)
      SyncServiceV2.startLocalToServerSync();

      print('✅ Transaction created: ${transactionWithWallet.id}');
      return transactionWithWallet;
    } catch (e) {
      print('Error creating transaction: $e');
      rethrow;
    }
  }

  static Future<Transaction> updateTransaction(Transaction transaction, {String? comment}) async {
    if (kIsWeb) return transaction;
    
    try {
      // Store previous state for undo (get last event before update)
      final events = await EventStoreService.getEventsForAggregate('transaction', transaction.id);
      final lastEventBeforeUpdate = events.isNotEmpty ? events.last : null;
      
      // 1. Create event
      final walletId = await WalletService.ensureCurrentWallet();
      final eventData = {
        'contact_id': transaction.contactId,
        'type': transaction.type == TransactionType.item ? 'item' : 'money',
        'direction': transaction.direction == TransactionDirection.lent ? 'lent' : 'owed',
        'amount': transaction.amount,
        'currency': transaction.currency,
        'description': transaction.description,
        'transaction_date': transaction.transactionDate.toIso8601String().split('T')[0],
        'due_date': transaction.dueDate?.toIso8601String().split('T')[0],
        'comment': comment ?? 'Transaction updated',
        'timestamp': DateTime.now().toIso8601String(),
        'wallet_id': walletId, // Include wallet_id in event data
      };

      final updateEvent = await EventStoreService.appendEvent(
        aggregateType: 'transaction',
        aggregateId: transaction.id,
        eventType: 'UPDATED',
        eventData: eventData,
      );

      // 2. Rebuild state
      await _rebuildState();

      // 3. Trigger automatic sync to server (like Firebase - immediate push)
      SyncServiceV2.startLocalToServerSync();

      print('✅ Transaction updated: ${transaction.id}');
      return transaction;
    } catch (e) {
      print('Error updating transaction: $e');
      rethrow;
    }
  }

  static Future<void> deleteTransaction(String transactionId, {String? comment}) async {
    if (kIsWeb) return;
    
    try {
      // Get all events for this transaction, sorted by timestamp
      final events = await EventStoreService.getEventsForAggregate('transaction', transactionId);
      if (events.isEmpty) {
        print('⚠️ No events found for transaction: $transactionId');
        return;
      }
      
      // Get the most recent event (last in sorted list)
      final lastEvent = events.last;
      
      final now = DateTime.now();
      final timeSinceLastEvent = now.difference(lastEvent.timestamp);
      final isWithinUndoWindow = timeSinceLastEvent.inSeconds < 5;
      
      // If within undo window, create an UNDO event instead of removing the event
      if (isWithinUndoWindow) {
      // Create UNDO event
      final walletId = await WalletService.ensureCurrentWallet();
      final undoEventData = {
        'undone_event_id': lastEvent.id,
        'comment': comment ?? 'Transaction deleted (undo)',
        'timestamp': DateTime.now().toIso8601String(),
        'wallet_id': walletId, // Include wallet_id in event data
      };

        final undoEvent = await EventStoreService.appendEvent(
          aggregateType: lastEvent.aggregateType,
          aggregateId: lastEvent.aggregateId,
          eventType: 'UNDO',
          eventData: undoEventData,
        );

        // Rebuild state (which will skip the undone event)
        await _rebuildState();

        // Trigger automatic sync to server
        SyncServiceV2.startLocalToServerSync();

        print('✅ Transaction undone (created UNDO event): $transactionId, event type: ${lastEvent.eventType}');
        return;
      }
      
      // Otherwise, create a DELETED event (normal deletion)
      // 1. Create event
      final walletId = await WalletService.ensureCurrentWallet();
      final eventData = {
        'comment': comment ?? 'Transaction deleted',
        'timestamp': DateTime.now().toIso8601String(),
        'wallet_id': walletId, // Include wallet_id in event data
      };

      await EventStoreService.appendEvent(
        aggregateType: 'transaction',
        aggregateId: transactionId,
        eventType: 'DELETED',
        eventData: eventData,
      );

      // 2. Rebuild state
      await _rebuildState();

      // 3. Trigger automatic sync to server (like Firebase - immediate push)
      SyncServiceV2.startLocalToServerSync();

      print('✅ Transaction deleted: $transactionId');
    } catch (e) {
      print('Error deleting transaction: $e');
      rethrow;
    }
  }
  
  /// Undo the last action for a transaction (create UNDO event)
  static Future<void> undoTransactionAction(String transactionId) async {
    if (kIsWeb) return;
    
    try {
      // Get all events for this transaction, sorted by timestamp
      final events = await EventStoreService.getEventsForAggregate('transaction', transactionId);
      if (events.isEmpty) {
        print('⚠️ No events found for transaction: $transactionId');
        throw Exception('No events found for transaction');
      }
      
      // Get the most recent event (last in sorted list)
      final lastEvent = events.last;
      
      // LOCAL CHECK FIRST - Check if event is within undo window (5 seconds)
      final now = DateTime.now();
      final timeSinceEvent = now.difference(lastEvent.timestamp);
      final isWithinUndoWindow = timeSinceEvent.inSeconds < 5;
      
      // Always check locally first - if too old, throw error immediately
      if (!isWithinUndoWindow) {
        throw Exception('Cannot undo: Action is too old (must be within 5 seconds)');
      }
      
      // Create UNDO event
      final walletId = await WalletService.ensureCurrentWallet();
      final undoEventData = {
        'undone_event_id': lastEvent.id,
        'comment': 'Action undone',
        'timestamp': DateTime.now().toIso8601String(),
        'wallet_id': walletId, // Include wallet_id in event data
      };

      final undoEvent = await EventStoreService.appendEvent(
        aggregateType: lastEvent.aggregateType,
        aggregateId: lastEvent.aggregateId,
        eventType: 'UNDO',
        eventData: undoEventData,
      );
      
      // Rebuild state (which will skip the undone event)
      await _rebuildState();
      
      // If the original event was synced, sync the UNDO event to server
      if (lastEvent.synced) {
        SyncServiceV2.manualSync().catchError((e) {
          print('⚠️ Error syncing UNDO event: $e');
        });
      }
      
      print('✅ Transaction action undone (created UNDO event): $transactionId, event type: ${lastEvent.eventType}, synced: ${lastEvent.synced}');
    } catch (e) {
      print('Error undoing transaction action: $e');
      rethrow;
    }
  }

  static Future<void> bulkDeleteContacts(List<String> contactIds) async {
    if (kIsWeb) return;
    
    for (final id in contactIds) {
      await deleteContact(id, comment: 'Bulk delete');
    }
  }

  /// Undo the last action for a contact (remove the last event)
  static Future<void> undoContactAction(String contactId) async {
    if (kIsWeb) return;
    
    try {
      // Get all events for this contact, sorted by timestamp
      final events = await EventStoreService.getEventsForAggregate('contact', contactId);
      if (events.isEmpty) {
        print('⚠️ No events found for contact: $contactId');
        throw Exception('No events found for contact');
      }
      
      // Get the most recent event (last in sorted list)
      final lastEvent = events.last;
      
      // Check if event is within undo window (5 seconds) - LOCAL CHECK FIRST
      final now = DateTime.now();
      final timeSinceEvent = now.difference(lastEvent.timestamp);
      final isWithinUndoWindow = timeSinceEvent.inSeconds < 5;
      
      // Always check locally first - if too old, throw error immediately
      if (!isWithinUndoWindow) {
        throw Exception('Cannot undo: Action is too old (must be within 5 seconds)');
      }
      
      // Create UNDO event
      final walletId = await WalletService.ensureCurrentWallet();
      final undoEventData = {
        'undone_event_id': lastEvent.id,
        'comment': 'Action undone',
        'timestamp': DateTime.now().toIso8601String(),
        'wallet_id': walletId, // Include wallet_id in event data
      };

      final undoEvent = await EventStoreService.appendEvent(
        aggregateType: lastEvent.aggregateType,
        aggregateId: lastEvent.aggregateId,
        eventType: 'UNDO',
        eventData: undoEventData,
      );
      
      // Rebuild state (which will skip the undone event)
      await _rebuildState();
      
      // If the original event was synced, sync the UNDO event to server
      if (lastEvent.synced) {
        SyncServiceV2.manualSync().catchError((e) {
          print('⚠️ Error syncing UNDO event: $e');
        });
      }
      
      print('✅ Contact action undone (created UNDO event): $contactId, event type: ${lastEvent.eventType}, synced: ${lastEvent.synced}');
    } catch (e) {
      print('Error undoing contact action: $e');
      rethrow;
    }
  }

  /// Undo multiple contact actions (for bulk delete)
  static Future<void> undoBulkContactActions(List<String> contactIds) async {
    if (kIsWeb) return;
    
    try {
      int successCount = 0;
      int failCount = 0;
      
      for (final contactId in contactIds) {
        try {
          await undoContactAction(contactId);
          successCount++;
        } catch (e) {
          print('⚠️ Failed to undo contact $contactId: $e');
          failCount++;
        }
      }
      
      print('✅ Bulk undo complete: $successCount succeeded, $failCount failed');
      
      // Note: Each undoContactAction() will delete events from server if synced
      // The server will automatically broadcast WebSocket notifications, so no need to call manualSync()
      // manualSync() should only be called when hash comparison shows we're out of sync
    } catch (e) {
      print('Error undoing bulk contact actions: $e');
      rethrow;
    }
  }

  static Future<void> bulkDeleteTransactions(List<String> transactionIds) async {
    if (kIsWeb) return;
    
    for (final id in transactionIds) {
      await deleteTransaction(id, comment: 'Bulk delete');
    }
  }

  /// Undo multiple transaction actions (for bulk delete)
  static Future<void> undoBulkTransactionActions(List<String> transactionIds) async {
    if (kIsWeb) return;
    
    try {
      int successCount = 0;
      int failCount = 0;
      
      for (final transactionId in transactionIds) {
        try {
          await undoTransactionAction(transactionId);
          successCount++;
        } catch (e) {
          print('⚠️ Failed to undo transaction $transactionId: $e');
          failCount++;
        }
      }
      
      print('✅ Bulk undo complete: $successCount succeeded, $failCount failed');
      
      // Note: Each undoTransactionAction() will delete events from server if synced
      // The server will automatically broadcast WebSocket notifications, so no need to call manualSync()
      // manualSync() should only be called when hash comparison shows we're out of sync
    } catch (e) {
      print('Error undoing bulk transaction actions: $e');
      rethrow;
    }
  }

  /// Rebuild state from all events
  /// Works the same way online and offline - no network dependency
  static Future<void> _rebuildState() async {
    if (kIsWeb) return;

    try {
      // Get all events ordered by timestamp (same as backend)
      // Backend: SELECT ... FROM events ORDER BY created_at ASC WHERE wallet_id = ?
      final walletId = WalletService.getCurrentWalletId();
      if (walletId == null) {
        print('⚠️ No current wallet set, skipping state rebuild');
        return;
      }
      
      final allEvents = await EventStoreService.getAllEvents();
      // Filter events by wallet_id (include null for migration)
      final events = allEvents.where((e) {
        final eventWalletId = e.eventData['wallet_id'] as String?;
        return eventWalletId == walletId || eventWalletId == null;
      }).toList();
      
      // Always use the same algorithm as backend: full rebuild from all events
      // Backend always does: rebuild_projections_from_events() which:
      // 1. Gets all events ordered by timestamp
      // 2. First pass: collect UNDO events to know which events to skip
      // 3. Second pass: process events, skipping UNDO events and undone events
      // 4. Clear projections and rebuild from scratch
      // This ensures consistent behavior between offline, online, and backend
      final state = StateBuilder.buildState(events);
      final lastEventId = events.isNotEmpty ? events.last.id : null;
      
      // Save to Hive boxes (same algorithm as backend: clear then rebuild)
      // Backend does: DELETE FROM transactions_projection, DELETE FROM contacts_projection, then INSERT
      final userId = await AuthService.getUserId();
      final contactsBoxName = DummyDataService.getContactsBoxName(userId: userId, walletId: walletId);
      final transactionsBoxName = DummyDataService.getTransactionsBoxName(userId: userId, walletId: walletId);
      final contactsBox = await Hive.openBox<Contact>(contactsBoxName);
      final transactionsBox = await Hive.openBox<Transaction>(transactionsBoxName);
      
      // Clear existing projections (same as backend: DELETE FROM ... WHERE true)
      await contactsBox.clear();
      await transactionsBox.clear();
      
      // Write new state (same as backend: INSERT INTO ...)
      for (final contact in state.contacts) {
        await contactsBox.put(contact.id, contact);
      }
      for (final transaction in state.transactions) {
        await transactionsBox.put(transaction.id, transaction);
      }
      
      // Save snapshot if needed (every 10 events or after UNDO)
      if (lastEventId != null) {
        final eventCount = events.length;
        final shouldSave = ProjectionSnapshotService.shouldCreateSnapshot(eventCount) || 
                         events.any((e) => e.eventType == 'UNDO');
        
        if (shouldSave) {
          await ProjectionSnapshotService.saveSnapshot(state, lastEventId, eventCount);
        }
      }
    } catch (e, stackTrace) {
      print('❌ Error rebuilding state: $e');
      print('Stack trace: $stackTrace');
      developer.log('State rebuild error', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Initialize and rebuild state on startup
  static Future<void> initialize() async {
    if (kIsWeb) return;

    try {
      // Rebuild state from events
      await _rebuildState();
      print('✅ LocalDatabaseServiceV2 initialized');
    } catch (e) {
      print('Error initializing LocalDatabaseServiceV2: $e');
    }
  }
}