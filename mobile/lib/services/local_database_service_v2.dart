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
      final contactsBox = Hive.box<Contact>('contacts');
      return contactsBox.values.toList();
    } catch (e) {
      print('Error reading contacts: $e');
      return [];
    }
  }

  static Future<Contact?> getContact(String id) async {
    if (kIsWeb) return null;
    
    try {
      final contactsBox = Hive.box<Contact>('contacts');
      return contactsBox.get(id);
    } catch (e) {
      print('Error reading contact: $e');
      return null;
    }
  }

  static Future<List<Transaction>> getTransactions() async {
    if (kIsWeb) return [];
    
    try {
      final transactionsBox = Hive.box<Transaction>('transactions');
      return transactionsBox.values.toList();
    } catch (e) {
      print('Error reading transactions: $e');
      return [];
    }
  }

  static Future<Transaction?> getTransaction(String id) async {
    if (kIsWeb) return null;
    
    try {
      final transactionsBox = Hive.box<Transaction>('transactions');
      return transactionsBox.get(id);
    } catch (e) {
      print('Error reading transaction: $e');
      return null;
    }
  }

  static Future<List<Transaction>> getTransactionsByContact(String contactId) async {
    if (kIsWeb) return [];
    
    try {
      final transactionsBox = Hive.box<Transaction>('transactions');
      return transactionsBox.values
          .where((t) => t.contactId == contactId)
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
      // 1. Create event
      final eventData = {
        'name': contact.name,
        'username': contact.username,
        'phone': contact.phone,
        'email': contact.email,
        'notes': contact.notes,
        'comment': comment ?? 'Contact created',
        'timestamp': DateTime.now().toIso8601String(),
      };

      await EventStoreService.appendEvent(
        aggregateType: 'contact',
        aggregateId: contact.id,
        eventType: 'CREATED',
        eventData: eventData,
      );

      // 2. Rebuild state
      await _rebuildState();

      // 3. Trigger automatic sync to server (like Firebase - immediate push)
      SyncServiceV2.manualSync().catchError((e) {
        // Silently handle sync errors - will retry later
      });

      print('✅ Contact created: ${contact.name}');
      return contact;
    } catch (e) {
      print('Error creating contact: $e');
      rethrow;
    }
  }

  static Future<Contact> updateContact(Contact contact, {String? comment}) async {
    if (kIsWeb) return contact;
    
    try {
      // 1. Create event
      final eventData = {
        'name': contact.name,
        'username': contact.username,
        'phone': contact.phone,
        'email': contact.email,
        'notes': contact.notes,
        'comment': comment ?? 'Contact updated',
        'timestamp': DateTime.now().toIso8601String(),
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
      SyncServiceV2.manualSync().catchError((e) {
        // Silently handle sync errors - will retry later
      });

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
      final eventData = {
        'comment': comment ?? 'Contact deleted',
        'timestamp': DateTime.now().toIso8601String(),
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
      SyncServiceV2.manualSync().catchError((e) {
        // Silently handle sync errors - will retry later
      });

      print('✅ Contact deleted: $contactId');
    } catch (e) {
      print('Error deleting contact: $e');
      rethrow;
    }
  }

  static Future<Transaction> createTransaction(Transaction transaction) async {
    if (kIsWeb) return transaction;
    
    try {
      // 1. Create event
      final eventData = {
        'contact_id': transaction.contactId,
        'type': transaction.type == TransactionType.item ? 'item' : 'money',
        'direction': transaction.direction == TransactionDirection.lent ? 'lent' : 'owed',
        'amount': transaction.amount,
        'currency': transaction.currency,
        'description': transaction.description,
        'transaction_date': transaction.transactionDate.toIso8601String().split('T')[0],
        'due_date': transaction.dueDate?.toIso8601String().split('T')[0],
        'timestamp': DateTime.now().toIso8601String(),
      };

      await EventStoreService.appendEvent(
        aggregateType: 'transaction',
        aggregateId: transaction.id,
        eventType: 'CREATED',
        eventData: eventData,
      );

      // 2. Rebuild state
      await _rebuildState();

      // 3. Trigger automatic sync to server (like Firebase - immediate push)
      SyncServiceV2.manualSync().catchError((e) {
        // Silently handle sync errors - will retry later
      });

      print('✅ Transaction created: ${transaction.id}');
      return transaction;
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
      SyncServiceV2.manualSync().catchError((e) {
        // Silently handle sync errors - will retry later
      });

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
      
      // If within undo window and not synced, remove the last event (undo)
      if (isWithinUndoWindow && !lastEvent.synced) {
        // Remove the last event (this effectively undoes the last action)
        final eventsBox = await Hive.openBox<Event>(EventStoreService.eventsBoxName);
        await eventsBox.delete(lastEvent.id);
        
        // Rebuild state
        await _rebuildState();
        
        print('✅ Transaction undone (removed last event): $transactionId, event type: ${lastEvent.eventType}');
        return;
      }
      
      // Otherwise, create a DELETED event (normal deletion)
      // 1. Create event
      final eventData = {
        'comment': comment ?? 'Transaction deleted',
        'timestamp': DateTime.now().toIso8601String(),
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
      SyncServiceV2.manualSync().catchError((e) {
        // Silently handle sync errors - will retry later
      });

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
      final undoEventData = {
        'undone_event_id': lastEvent.id,
        'comment': 'Action undone',
        'timestamp': DateTime.now().toIso8601String(),
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
      final undoEventData = {
        'undone_event_id': lastEvent.id,
        'comment': 'Action undone',
        'timestamp': DateTime.now().toIso8601String(),
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
      print('🔄 Starting state rebuild...');
      
      // Get all events
      final events = await EventStoreService.getAllEvents();
      print('📊 Found ${events.length} events to process');
      
      AppState state;
      String? lastEventId;
      
      // Check for UNDO events - if present, always do full rebuild (same as when coming back online)
      // This ensures UNDO works correctly offline, just like it does when syncing online
      final undoEvents = events.where((e) => e.eventType == 'UNDO').toList();
      
      if (undoEvents.isNotEmpty) {
        // UNDO events present - always do full rebuild (same logic as SyncServiceV2._rebuildState)
        // This ensures correct handling of undone events, just like when coming back online
        state = StateBuilder.buildState(events);
        if (events.isNotEmpty) {
          lastEventId = events.last.id;
        }
      } else {
        // No UNDO events - safe to use snapshot optimization
        try {
          final latestSnapshot = await ProjectionSnapshotService.getLatestSnapshot();
          
          if (latestSnapshot != null && events.isNotEmpty) {
            // Get events after the snapshot
            final snapshotLastEvent = await EventStoreService.getEvent(latestSnapshot.lastEventId);
            if (snapshotLastEvent != null) {
              final eventsAfterSnapshot = events.where((e) => 
                e.timestamp.isAfter(snapshotLastEvent.timestamp) || 
                e.timestamp.isAtSameMomentAs(snapshotLastEvent.timestamp)
              ).toList();
              
              // Only use snapshot if there are events after it (otherwise snapshot is up to date)
              if (eventsAfterSnapshot.isNotEmpty) {
                final snapshotState = await ProjectionSnapshotService.buildStateFromSnapshot(
                  latestSnapshot,
                  eventsAfterSnapshot,
                );
                
                if (snapshotState != null) {
                  state = snapshotState;
                  lastEventId = events.last.id;
                } else {
                  // Snapshot build failed, fallback to full rebuild
                  throw Exception('Snapshot build returned null');
                }
              } else {
                // No new events, snapshot is current
                state = latestSnapshot.state;
                lastEventId = latestSnapshot.lastEventId;
              }
            } else {
              // Snapshot's last event not found, fallback to full rebuild
              throw Exception('Snapshot last event not found');
            }
          } else {
            // No snapshot available, do full rebuild
            throw Exception('No snapshot available');
          }
        } catch (e) {
          // Fallback to full rebuild if snapshot fails - this is normal and expected
          state = StateBuilder.buildState(events);
          if (events.isNotEmpty) {
            lastEventId = events.last.id;
          }
        }
      }
      
      // Save to Hive boxes
      final contactsBox = await Hive.openBox<Contact>('contacts');
      final transactionsBox = await Hive.openBox<Transaction>('transactions');
      
      // Get existing keys to identify what needs to be deleted
      final existingContactIds = contactsBox.keys.cast<String>().toSet();
      final existingTransactionIds = transactionsBox.keys.cast<String>().toSet();
      
      // Get new state IDs
      final newContactIds = state.contacts.map((c) => c.id).toSet();
      final newTransactionIds = state.transactions.map((t) => t.id).toSet();
      
      // Identify keys to delete (exist in old state but not in new state)
      final contactsToDelete = existingContactIds.difference(newContactIds);
      final transactionsToDelete = existingTransactionIds.difference(newTransactionIds);
      
      // CRITICAL: Write all new data FIRST, then delete old data
      // This ensures screens always see valid data, never empty state
      final allOperations = <Future>[];
      
      // 1. Write all new/updated contacts and transactions FIRST
      for (final contact in state.contacts) {
        allOperations.add(contactsBox.put(contact.id, contact));
      }
      for (final transaction in state.transactions) {
        allOperations.add(transactionsBox.put(transaction.id, transaction));
      }
      
      // 2. Wait for all writes to complete
      await Future.wait(allOperations);
      
      // 3. Now delete removed items (after new data is written)
      final deleteOperations = <Future>[];
      for (final id in contactsToDelete) {
        deleteOperations.add(contactsBox.delete(id));
      }
      for (final id in transactionsToDelete) {
        deleteOperations.add(transactionsBox.delete(id));
      }
      
      // 4. Wait for deletions to complete
      if (deleteOperations.isNotEmpty) {
        await Future.wait(deleteOperations);
      }
      
      // 5. Small delay to ensure Hive listeners process all changes
      // This ensures screens read data after all operations complete
      await Future.delayed(const Duration(milliseconds: 50));
      
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
