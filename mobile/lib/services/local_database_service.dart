import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive_flutter/hive_flutter.dart';
import '../models/contact.dart';
import '../models/transaction.dart';
import '../models/event.dart';
import 'dummy_data_service.dart';
import 'event_store_service.dart';
import 'projection_service.dart';
import 'package:uuid/uuid.dart';

/// Local-first database service with Event Sourcing
/// All writes create events, projections are rebuilt from events
/// Sync to server happens in background via SyncService
class LocalDatabaseService {
  static const uuid = Uuid();
  // Contacts
  static Future<List<Contact>> getContacts() async {
    if (kIsWeb) {
      // Web doesn't use Hive, return empty list (will be handled by screens)
      return [];
    }
    
    try {
      // Don't rebuild on every read - only read from projections
      // Projections are rebuilt when events are added/updated
      final contactsBox = Hive.box<Contact>(DummyDataService.contactsBoxName);
      return contactsBox.values.toList();
    } catch (e) {
      print('Error reading contacts from local database: $e');
      return [];
    }
  }

  static Future<Contact?> getContact(String id) async {
    if (kIsWeb) return null;
    
    try {
      // Don't rebuild on every read - only read from projections
      final contactsBox = Hive.box<Contact>(DummyDataService.contactsBoxName);
      return contactsBox.get(id);
    } catch (e) {
      print('Error reading contact from local database: $e');
      return null;
    }
  }

  static Future<Contact> createContact(Contact contact, {String? comment}) async {
    if (kIsWeb) {
      // Web: return as-is, sync service will handle
      return contact;
    }
    
    try {
      final timestamp = DateTime.now();
      final timestampStr = timestamp.toIso8601String();
      
      // Create event data
      final eventData = {
        'name': contact.name,
        'username': contact.username,
        'phone': contact.phone,
        'email': contact.email,
        'notes': contact.notes,
        'comment': comment ?? 'Contact created via mobile app',
        'timestamp': timestampStr,
      };
      
      // Create event
      await EventStoreService.appendEvent(
        aggregateType: 'contact',
        aggregateId: contact.id,
        eventType: 'CREATED',
        eventData: eventData,
      );

      // Rebuild projection
      await ProjectionService.rebuildProjections();
      
      // Calculate total debt AFTER the action
      final totalDebt = await ProjectionService.calculateTotalDebtAtTime(timestamp);
      
      // Update event with total_debt by recreating it (Hive events are immutable)
      // Get the event we just created
      final allEvents = await EventStoreService.getAllEvents();
      final matchingEvents = allEvents.where(
        (e) => e.aggregateId == contact.id && 
               e.eventType == 'CREATED' &&
               e.timestamp.isAtSameMomentAs(timestamp),
      ).toList();
      final thisEvent = matchingEvents.isNotEmpty ? matchingEvents.first : null;
      
      if (thisEvent != null) {
        // Create updated event data with total_debt
        final updatedEventData = Map<String, dynamic>.from(eventData);
        updatedEventData['total_debt'] = totalDebt;
        
        // Delete old event and create new one with total_debt
        // We need to access the events box directly to delete
        final eventsBox = await Hive.openBox<Event>(EventStoreService.eventsBoxName);
        await eventsBox.delete(thisEvent.id);
        await EventStoreService.appendEvent(
          aggregateType: 'contact',
          aggregateId: contact.id,
          eventType: 'CREATED',
          eventData: updatedEventData,
        );
      }
      
      final created = await getContact(contact.id);
      if (created == null) {
        throw Exception('Failed to create contact');
      }
      print('✅ Contact saved locally with event: ${contact.name}');
      return created;
    } catch (e) {
      print('Error saving contact to local database: $e');
      rethrow;
    }
  }

  static Future<void> updateContact(Contact contact, {String? comment}) async {
    if (kIsWeb) return;
    
    try {
      final timestamp = DateTime.now();
      final timestampStr = timestamp.toIso8601String();
      
      // Get current contact for previous_values
      final current = await getContact(contact.id);
      
      final eventData = <String, dynamic>{
        'name': contact.name,
        'username': contact.username,
        'phone': contact.phone,
        'email': contact.email,
        'notes': contact.notes,
        'comment': comment ?? 'Contact updated via mobile app',
        'timestamp': timestampStr,
      };
      
      if (current != null) {
        eventData['previous_values'] = {
          'name': current.name,
          'username': current.username,
          'phone': current.phone,
          'email': current.email,
          'notes': current.notes,
        };
      }

      // Create event
      await EventStoreService.appendEvent(
        aggregateType: 'contact',
        aggregateId: contact.id,
        eventType: 'UPDATED',
        eventData: eventData,
      );

      // Rebuild projection
      await ProjectionService.rebuildProjections();
      
      // Calculate total debt AFTER the action
      final totalDebt = await ProjectionService.calculateTotalDebtAtTime(timestamp);
      
      // Update event with total_debt by recreating it
      final allEvents = await EventStoreService.getAllEvents();
      final matchingEvents = allEvents.where(
        (e) => e.aggregateId == contact.id && 
               e.eventType == 'UPDATED' &&
               e.timestamp.isAtSameMomentAs(timestamp),
      ).toList();
      final thisEvent = matchingEvents.isNotEmpty ? matchingEvents.first : null;
      
      if (thisEvent != null) {
        // Create updated event data with total_debt
        final updatedEventData = Map<String, dynamic>.from(eventData);
        updatedEventData['total_debt'] = totalDebt;
        
        // Delete old event and create new one with total_debt
        final eventsBox = await Hive.openBox<Event>(EventStoreService.eventsBoxName);
        await eventsBox.delete(thisEvent.id);
        await EventStoreService.appendEvent(
          aggregateType: 'contact',
          aggregateId: contact.id,
          eventType: 'UPDATED',
          eventData: updatedEventData,
        );
      }
      
      print('✅ Contact updated locally with event: ${contact.name}');
    } catch (e) {
      print('Error updating contact in local database: $e');
      rethrow;
    }
  }

  static Future<void> deleteContact(String contactId, {String? comment}) async {
    if (kIsWeb) return;
    
    try {
      final timestamp = DateTime.now();
      final timestampStr = timestamp.toIso8601String();
      
      // Get current contact for deleted_contact data
      final current = await getContact(contactId);
      final deletedContact = current != null ? {
        'name': current.name,
        'username': current.username,
        'phone': current.phone,
        'email': current.email,
        'notes': current.notes,
      } : null;

      // Create event data
      final eventData = {
        'comment': comment ?? 'Contact deleted via mobile app',
        'timestamp': timestampStr,
        'deleted_contact': deletedContact,
      };

      // Create event
      await EventStoreService.appendEvent(
        aggregateType: 'contact',
        aggregateId: contactId,
        eventType: 'DELETED',
        eventData: eventData,
      );

      // Rebuild projection
      await ProjectionService.rebuildProjections();
      
      // Calculate total debt AFTER the action
      final totalDebt = await ProjectionService.calculateTotalDebtAtTime(timestamp);
      
      // Update event with total_debt by recreating it
      final allEvents = await EventStoreService.getAllEvents();
      final matchingEvents = allEvents.where(
        (e) => e.aggregateId == contactId && 
               e.eventType == 'DELETED' &&
               e.timestamp.isAtSameMomentAs(timestamp),
      ).toList();
      final thisEvent = matchingEvents.isNotEmpty ? matchingEvents.first : null;
      
      if (thisEvent != null) {
        // Create updated event data with total_debt
        final updatedEventData = Map<String, dynamic>.from(eventData);
        updatedEventData['total_debt'] = totalDebt;
        
        // Delete old event and create new one with total_debt
        final eventsBox = await Hive.openBox<Event>(EventStoreService.eventsBoxName);
        await eventsBox.delete(thisEvent.id);
        await EventStoreService.appendEvent(
          aggregateType: 'contact',
          aggregateId: contactId,
          eventType: 'DELETED',
          eventData: updatedEventData,
        );
      }
      
      print('✅ Contact deleted locally with event: $contactId');
    } catch (e) {
      print('Error deleting contact from local database: $e');
      rethrow;
    }
  }

  // Transactions
  static Future<List<Transaction>> getTransactions() async {
    if (kIsWeb) {
      // Web doesn't use Hive, return empty list (will be handled by screens)
      return [];
    }
    
    try {
      // Don't rebuild on every read - only read from projections
      // Projections are rebuilt when events are added/updated
      final transactionsBox = Hive.box<Transaction>(DummyDataService.transactionsBoxName);
      return transactionsBox.values.toList();
    } catch (e) {
      print('Error reading transactions from local database: $e');
      return [];
    }
  }

  static Future<List<Transaction>> getTransactionsByContact(String contactId) async {
    if (kIsWeb) return [];
    
    try {
      final transactionsBox = Hive.box<Transaction>(DummyDataService.transactionsBoxName);
      return transactionsBox.values
          .where((t) => t.contactId == contactId)
          .toList();
    } catch (e) {
      print('Error reading transactions by contact from local database: $e');
      return [];
    }
  }

  static Future<Transaction?> getTransaction(String id) async {
    if (kIsWeb) return null;
    
    try {
      final transactionsBox = Hive.box<Transaction>(DummyDataService.transactionsBoxName);
      return transactionsBox.get(id);
    } catch (e) {
      print('Error reading transaction from local database: $e');
      return null;
    }
  }

  static Future<Transaction> createTransaction(Transaction transaction, {String? comment}) async {
    if (kIsWeb) {
      // Web: return as-is, sync service will handle
      return transaction;
    }
    
    try {
      final timestamp = DateTime.now();
      final timestampStr = timestamp.toIso8601String();
      
      // Create event data
      final eventData = {
        'contact_id': transaction.contactId,
        'type': transaction.type == TransactionType.money ? 'money' : 'item',
        'direction': transaction.direction == TransactionDirection.owed ? 'owed' : 'lent',
        'amount': transaction.amount,
        'currency': transaction.currency,
        'description': transaction.description,
        'transaction_date': transaction.transactionDate.toIso8601String().split('T')[0],
        'due_date': transaction.dueDate?.toIso8601String().split('T')[0],
        'comment': comment ?? 'Transaction created via mobile app',
        'timestamp': timestampStr,
      };
      
      // Create event
      await EventStoreService.appendEvent(
        aggregateType: 'transaction',
        aggregateId: transaction.id,
        eventType: 'CREATED',
        eventData: eventData,
      );
      
      // Rebuild projection (this will recalculate balances)
      await ProjectionService.rebuildProjections();
      
      // Calculate total debt AFTER the action
      final totalDebt = await ProjectionService.calculateTotalDebtAtTime(timestamp);
      
      // Update event with total_debt by recreating it
      final allEvents = await EventStoreService.getAllEvents();
      final matchingEvents = allEvents.where(
        (e) => e.aggregateId == transaction.id && 
               e.eventType == 'CREATED' &&
               e.timestamp.isAtSameMomentAs(timestamp),
      ).toList();
      final thisEvent = matchingEvents.isNotEmpty ? matchingEvents.first : null;
      
      if (thisEvent != null) {
        // Create updated event data with total_debt
        final updatedEventData = Map<String, dynamic>.from(eventData);
        updatedEventData['total_debt'] = totalDebt;
        
        // Delete old event and create new one with total_debt
        final eventsBox = await Hive.openBox<Event>(EventStoreService.eventsBoxName);
        await eventsBox.delete(thisEvent.id);
        await EventStoreService.appendEvent(
          aggregateType: 'transaction',
          aggregateId: transaction.id,
          eventType: 'CREATED',
          eventData: updatedEventData,
        );
      }
      
      final created = await getTransaction(transaction.id);
      if (created == null) {
        throw Exception('Failed to create transaction');
      }
      print('✅ Transaction saved locally with event: ${transaction.id}');
      return created;
    } catch (e) {
      print('Error saving transaction to local database: $e');
      rethrow;
    }
  }

  static Future<void> updateTransaction(Transaction transaction, {String? comment}) async {
    if (kIsWeb) return;
    
    try {
      final timestamp = DateTime.now();
      final timestampStr = timestamp.toIso8601String();
      
      // Get current transaction for previous_values
      final current = await getTransaction(transaction.id);
      
      final eventData = <String, dynamic>{
        'contact_id': transaction.contactId,
        'type': transaction.type == TransactionType.money ? 'money' : 'item',
        'direction': transaction.direction == TransactionDirection.owed ? 'owed' : 'lent',
        'amount': transaction.amount,
        'currency': transaction.currency,
        'description': transaction.description,
        'transaction_date': transaction.transactionDate.toIso8601String().split('T')[0],
        'due_date': transaction.dueDate?.toIso8601String().split('T')[0],
        'comment': comment ?? 'Transaction updated via mobile app',
        'timestamp': timestampStr,
      };
      
      if (current != null) {
        eventData['previous_values'] = {
          'contact_id': current.contactId,
          'type': current.type == TransactionType.money ? 'money' : 'item',
          'direction': current.direction == TransactionDirection.owed ? 'owed' : 'lent',
          'amount': current.amount,
          'currency': current.currency,
          'description': current.description,
          'transaction_date': current.transactionDate.toIso8601String().split('T')[0],
          'due_date': current.dueDate?.toIso8601String().split('T')[0],
        };
      }

      // Create event
      await EventStoreService.appendEvent(
        aggregateType: 'transaction',
        aggregateId: transaction.id,
        eventType: 'UPDATED',
        eventData: eventData,
      );
      
      // Rebuild projection (this will recalculate balances)
      await ProjectionService.rebuildProjections();
      
      // Calculate total debt AFTER the action
      final totalDebt = await ProjectionService.calculateTotalDebtAtTime(timestamp);
      
      // Update event with total_debt by recreating it
      final allEvents = await EventStoreService.getAllEvents();
      final matchingEvents = allEvents.where(
        (e) => e.aggregateId == transaction.id && 
               e.eventType == 'UPDATED' &&
               e.timestamp.isAtSameMomentAs(timestamp),
      ).toList();
      final thisEvent = matchingEvents.isNotEmpty ? matchingEvents.first : null;
      
      if (thisEvent != null) {
        // Create updated event data with total_debt
        final updatedEventData = Map<String, dynamic>.from(eventData);
        updatedEventData['total_debt'] = totalDebt;
        
        // Delete old event and create new one with total_debt
        final eventsBox = await Hive.openBox<Event>(EventStoreService.eventsBoxName);
        await eventsBox.delete(thisEvent.id);
        await EventStoreService.appendEvent(
          aggregateType: 'transaction',
          aggregateId: transaction.id,
          eventType: 'UPDATED',
          eventData: updatedEventData,
        );
      }
      
      print('✅ Transaction updated locally with event: ${transaction.id}');
    } catch (e) {
      print('Error updating transaction in local database: $e');
      rethrow;
    }
  }

  static Future<void> deleteTransaction(String transactionId, {String? comment}) async {
    if (kIsWeb) return;
    
    try {
      final timestamp = DateTime.now();
      final timestampStr = timestamp.toIso8601String();
      
      // Get current transaction for deleted_transaction data
      final current = await getTransaction(transactionId);
      final deletedTransaction = current != null ? {
        'contact_id': current.contactId,
        'type': current.type == TransactionType.money ? 'money' : 'item',
        'direction': current.direction == TransactionDirection.owed ? 'owed' : 'lent',
        'amount': current.amount,
        'currency': current.currency,
        'description': current.description,
        'transaction_date': current.transactionDate.toIso8601String().split('T')[0],
        'due_date': current.dueDate?.toIso8601String().split('T')[0],
      } : null;

      // Create event data
      final eventData = {
        'comment': comment ?? 'Transaction deleted via mobile app',
        'timestamp': timestampStr,
        'deleted_transaction': deletedTransaction,
      };

      // Create event
      await EventStoreService.appendEvent(
        aggregateType: 'transaction',
        aggregateId: transactionId,
        eventType: 'DELETED',
        eventData: eventData,
      );
      
      // Rebuild projection (this will recalculate balances)
      await ProjectionService.rebuildProjections();
      
      // Calculate total debt AFTER the action
      final totalDebt = await ProjectionService.calculateTotalDebtAtTime(timestamp);
      
      // Update event with total_debt by recreating it
      final allEvents = await EventStoreService.getAllEvents();
      final matchingEvents = allEvents.where(
        (e) => e.aggregateId == transactionId && 
               e.eventType == 'DELETED' &&
               e.timestamp.isAtSameMomentAs(timestamp),
      ).toList();
      final thisEvent = matchingEvents.isNotEmpty ? matchingEvents.first : null;
      
      if (thisEvent != null) {
        // Create updated event data with total_debt
        final updatedEventData = Map<String, dynamic>.from(eventData);
        updatedEventData['total_debt'] = totalDebt;
        
        // Delete old event and create new one with total_debt
        final eventsBox = await Hive.openBox<Event>(EventStoreService.eventsBoxName);
        await eventsBox.delete(thisEvent.id);
        await EventStoreService.appendEvent(
          aggregateType: 'transaction',
          aggregateId: transactionId,
          eventType: 'DELETED',
          eventData: updatedEventData,
        );
      }
      
      print('✅ Transaction deleted locally with event: $transactionId');
    } catch (e) {
      print('Error deleting transaction from local database: $e');
      rethrow;
    }
  }

  // Bulk operations
  static Future<void> bulkDeleteContacts(List<String> contactIds, {String? comment}) async {
    if (kIsWeb) return;
    
    try {
      // Delete each contact with an event
      for (final id in contactIds) {
        await deleteContact(id, comment: comment ?? 'Bulk delete via mobile app');
      }
      print('✅ Bulk deleted ${contactIds.length} contacts locally with events');
    } catch (e) {
      print('Error bulk deleting contacts from local database: $e');
      rethrow;
    }
  }

  static Future<void> bulkDeleteTransactions(List<String> transactionIds, {String? comment}) async {
    if (kIsWeb) return;
    
    try {
      // Delete each transaction with an event
      for (final id in transactionIds) {
        await deleteTransaction(id, comment: comment ?? 'Bulk delete via mobile app');
      }
      print('✅ Bulk deleted ${transactionIds.length} transactions locally with events');
    } catch (e) {
      print('Error bulk deleting transactions from local database: $e');
      rethrow;
    }
  }

  // Sync operations (called by SyncService)
  static Future<void> syncContactsFromServer(List<Contact> contacts) async {
    if (kIsWeb) return;
    
    try {
      int updated = 0;
      int skipped = 0;
      
      // Check existing events to see what we already have
      final existingEvents = await EventStoreService.getAllEvents();
      final existingContactIds = existingEvents
          .where((e) => e.aggregateType == 'contact' && e.eventType == 'CREATED')
          .map((e) => e.aggregateId)
          .toSet();
      
      // Update or add contacts from server, but only if server data is newer
      for (var serverContact in contacts) {
        final hasLocalEvent = existingContactIds.contains(serverContact.id);
        
        if (!hasLocalEvent) {
          // New contact from server - create event
          final timestamp = serverContact.createdAt.toIso8601String();
          final event = await EventStoreService.appendEvent(
            aggregateType: 'contact',
            aggregateId: serverContact.id,
            eventType: 'CREATED',
            eventData: {
              'name': serverContact.name,
              'username': serverContact.username,
              'phone': serverContact.phone,
              'email': serverContact.email,
              'notes': serverContact.notes,
              'comment': 'Synced from server',
              'timestamp': timestamp,
            },
            version: 1,
          );
          // Mark as synced immediately since it came from server
          await EventStoreService.markEventSynced(event.id);
          updated++;
        } else {
          // Contact exists locally - check if we should update
          final localEvents = await EventStoreService.getEventsForAggregate('contact', serverContact.id);
          final hasUnsyncedEvents = localEvents.any((e) => !e.synced);
          
          if (hasUnsyncedEvents) {
            // Local has pending changes - don't overwrite
            skipped++;
            continue;
          }
          
          // Check if server is newer by comparing updatedAt
          final localContact = await getContact(serverContact.id);
          if (localContact != null && serverContact.updatedAt.isAfter(localContact.updatedAt)) {
            // Server is newer - create update event
            final timestamp = serverContact.updatedAt.toIso8601String();
            final event = await EventStoreService.appendEvent(
              aggregateType: 'contact',
              aggregateId: serverContact.id,
              eventType: 'UPDATED',
              eventData: {
                'name': serverContact.name,
                'username': serverContact.username,
                'phone': serverContact.phone,
                'email': serverContact.email,
                'notes': serverContact.notes,
                'comment': 'Synced from server',
                'timestamp': timestamp,
                'previous_values': {
                  'name': localContact.name,
                  'username': localContact.username,
                  'phone': localContact.phone,
                  'email': localContact.email,
                  'notes': localContact.notes,
                },
              },
            );
            // Mark as synced immediately since it came from server
            await EventStoreService.markEventSynced(event.id);
            updated++;
          } else {
            skipped++;
          }
        }
      }
      
      if (updated > 0 || skipped > 0) {
        print('✅ Synced contacts: $updated updated, $skipped skipped (local has newer/unsynced data)');
        // Rebuild projections to ensure balances are correct
        await ProjectionService.rebuildProjections();
      }
    } catch (e) {
      print('Error syncing contacts from server: $e');
      rethrow;
    }
  }

  static Future<void> syncTransactionsFromServer(List<Transaction> transactions) async {
    if (kIsWeb) return;
    
    try {
      int updated = 0;
      int skipped = 0;
      
      // Check existing events to see what we already have
      final existingEvents = await EventStoreService.getAllEvents();
      final existingTransactionIds = existingEvents
          .where((e) => e.aggregateType == 'transaction' && e.eventType == 'CREATED')
          .map((e) => e.aggregateId)
          .toSet();
      
      // Update or add transactions from server, but only if server data is newer
      for (var serverTransaction in transactions) {
        final hasLocalEvent = existingTransactionIds.contains(serverTransaction.id);
        
        if (!hasLocalEvent) {
          // New transaction from server - create event
          final timestamp = serverTransaction.createdAt.toIso8601String();
          final event = await EventStoreService.appendEvent(
            aggregateType: 'transaction',
            aggregateId: serverTransaction.id,
            eventType: 'CREATED',
            eventData: {
              'contact_id': serverTransaction.contactId,
              'type': serverTransaction.type == TransactionType.money ? 'money' : 'item',
              'direction': serverTransaction.direction == TransactionDirection.owed ? 'owed' : 'lent',
              'amount': serverTransaction.amount,
              'currency': serverTransaction.currency,
              'description': serverTransaction.description,
              'transaction_date': serverTransaction.transactionDate.toIso8601String().split('T')[0],
              'due_date': serverTransaction.dueDate?.toIso8601String().split('T')[0],
              'comment': 'Synced from server',
              'timestamp': timestamp,
            },
            version: 1,
          );
          // Mark as synced immediately since it came from server
          await EventStoreService.markEventSynced(event.id);
          updated++;
        } else {
          // Transaction exists locally - check if we should update
          final localEvents = await EventStoreService.getEventsForAggregate('transaction', serverTransaction.id);
          final hasUnsyncedEvents = localEvents.any((e) => !e.synced);
          
          if (hasUnsyncedEvents) {
            // Local has pending changes - don't overwrite
            skipped++;
            continue;
          }
          
          // Check if server is newer by comparing updatedAt
          final localTransaction = await getTransaction(serverTransaction.id);
          if (localTransaction != null && serverTransaction.updatedAt.isAfter(localTransaction.updatedAt)) {
            // Server is newer - create update event
            final timestamp = serverTransaction.updatedAt.toIso8601String();
            final event = await EventStoreService.appendEvent(
              aggregateType: 'transaction',
              aggregateId: serverTransaction.id,
              eventType: 'UPDATED',
              eventData: {
                'contact_id': serverTransaction.contactId,
                'type': serverTransaction.type == TransactionType.money ? 'money' : 'item',
                'direction': serverTransaction.direction == TransactionDirection.owed ? 'owed' : 'lent',
                'amount': serverTransaction.amount,
                'currency': serverTransaction.currency,
                'description': serverTransaction.description,
                'transaction_date': serverTransaction.transactionDate.toIso8601String().split('T')[0],
                'due_date': serverTransaction.dueDate?.toIso8601String().split('T')[0],
                'comment': 'Synced from server',
                'timestamp': timestamp,
                'previous_values': {
                  'contact_id': localTransaction.contactId,
                  'type': localTransaction.type == TransactionType.money ? 'money' : 'item',
                  'direction': localTransaction.direction == TransactionDirection.owed ? 'owed' : 'lent',
                  'amount': localTransaction.amount,
                  'currency': localTransaction.currency,
                  'description': localTransaction.description,
                  'transaction_date': localTransaction.transactionDate.toIso8601String().split('T')[0],
                  'due_date': localTransaction.dueDate?.toIso8601String().split('T')[0],
                },
              },
            );
            // Mark as synced immediately since it came from server
            await EventStoreService.markEventSynced(event.id);
            updated++;
          } else {
            skipped++;
          }
        }
      }
      
      if (updated > 0 || skipped > 0) {
        print('✅ Synced transactions: $updated updated, $skipped skipped (local has newer/unsynced data)');
      }
      
      // Rebuild projections to recalculate balances
      await ProjectionService.rebuildProjections();
    } catch (e) {
      print('Error syncing transactions from server: $e');
      rethrow;
    }
  }

  // Balance calculation is now handled by ProjectionService.rebuildProjections()
  // which calculates balances from transaction events
}
