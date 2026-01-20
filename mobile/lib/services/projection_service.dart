import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive_flutter/hive_flutter.dart';
import '../models/contact.dart';
import '../models/transaction.dart';
import '../models/event.dart';
import 'event_store_service.dart';
import 'dummy_data_service.dart';
import 'package:uuid/uuid.dart';

/// Projection Service
/// Rebuilds local state (contacts/transactions) from events
class ProjectionService {
  static const uuid = Uuid();
  static bool _isRebuilding = false;

  /// Rebuild all projections from events
  static Future<void> rebuildProjections() async {
    if (kIsWeb) return;
    
    // Prevent infinite loops by skipping if already rebuilding
    if (_isRebuilding) {
      print('⚠️ Projection rebuild already in progress, skipping...');
      return;
    }

    _isRebuilding = true;
    print('🔄 Rebuilding projections from events...');

    try {
      // Get all events sorted by timestamp
      final events = await EventStoreService.getAllEvents();

      // Clear existing projections
      await _clearProjections();

      // Rebuild contacts
      final contactEvents = events.where((e) => e.aggregateType == 'contact').toList();
      await _rebuildContacts(contactEvents);

      // Rebuild transactions
      final transactionEvents = events.where((e) => e.aggregateType == 'transaction').toList();
      await _rebuildTransactions(transactionEvents);

      print('✅ Projections rebuilt from ${events.length} events');
    } catch (e) {
      print('Error rebuilding projections: $e');
      rethrow;
    } finally {
      _isRebuilding = false;
    }
  }

  /// Clear all projections
  static Future<void> _clearProjections() async {
    if (kIsWeb) return;

    try {
      final contactsBox = Hive.box<Contact>(DummyDataService.contactsBoxName);
      final transactionsBox = Hive.box<Transaction>(DummyDataService.transactionsBoxName);

      await contactsBox.clear();
      await transactionsBox.clear();
    } catch (e) {
      print('Error clearing projections: $e');
    }
  }

  /// Rebuild contacts from events
  static Future<void> _rebuildContacts(List<Event> events) async {
    if (kIsWeb) return;

    final contactsBox = await Hive.openBox<Contact>('contacts');
    final Map<String, Contact> contacts = {};

    for (final event in events) {
      final contactId = event.aggregateId;
      final eventData = event.eventData;

      if (event.eventType == 'CREATED') {
        contacts[contactId] = Contact(
          id: contactId,
          name: eventData['name'] as String? ?? '',
          username: eventData['username'] as String?,
          phone: eventData['phone'] as String?,
          email: eventData['email'] as String?,
          notes: eventData['notes'] as String?,
          createdAt: DateTime.parse(eventData['timestamp'] as String? ?? DateTime.now().toIso8601String()),
          updatedAt: DateTime.parse(eventData['timestamp'] as String? ?? DateTime.now().toIso8601String()),
          isSynced: event.synced,
          balance: 0,
        );
      } else if (event.eventType == 'UPDATED' && contacts.containsKey(contactId)) {
        final contact = contacts[contactId]!;
        contacts[contactId] = Contact(
          id: contact.id,
          name: eventData['name'] as String? ?? contact.name,
          username: eventData['username'] as String? ?? contact.username,
          phone: eventData['phone'] as String? ?? contact.phone,
          email: eventData['email'] as String? ?? contact.email,
          notes: eventData['notes'] as String? ?? contact.notes,
          createdAt: contact.createdAt,
          updatedAt: DateTime.parse(eventData['timestamp'] as String? ?? DateTime.now().toIso8601String()),
          isSynced: event.synced,
          balance: contact.balance,
        );
      } else if (event.eventType == 'DELETED' && contacts.containsKey(contactId)) {
        contacts.remove(contactId);
      }
    }

    // Calculate balances from transactions (including DELETED events)
    // We need to process all transaction events in chronological order to correctly calculate balances
    final allTransactionEvents = await EventStoreService.getAllEvents();
    final transactionEvents = allTransactionEvents
        .where((e) => e.aggregateType == 'transaction')
        .toList();
    
    // Sort by timestamp to process in order
    transactionEvents.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    
    // Reset all balances to 0 first
    for (final contact in contacts.values) {
      contacts[contact.id] = Contact(
        id: contact.id,
        name: contact.name,
        username: contact.username,
        phone: contact.phone,
        email: contact.email,
        notes: contact.notes,
        createdAt: contact.createdAt,
        updatedAt: contact.updatedAt,
        isSynced: contact.isSynced,
        balance: 0,
      );
    }
    
    // Process transaction events in order
    for (final event in transactionEvents) {
      final eventData = event.eventData;
      String? contactId;
      
      // Get contact_id based on event type
      if (event.eventType == 'CREATED' || event.eventType == 'UPDATED') {
        contactId = eventData['contact_id'] as String?;
      } else if (event.eventType == 'DELETED') {
        // For DELETED events, contact_id is inside deleted_transaction
        final deletedTransaction = eventData['deleted_transaction'] as Map<String, dynamic>?;
        contactId = deletedTransaction?['contact_id'] as String?;
      }
      
      if (contactId != null && contacts.containsKey(contactId)) {
        if (event.eventType == 'CREATED') {
          final direction = eventData['direction'] as String?;
          final amount = (eventData['amount'] as num?)?.toInt() ?? 0;
          
          if (direction == 'lent') {
            contacts[contactId]!.balance += amount;
          } else if (direction == 'owed') {
            contacts[contactId]!.balance -= amount;
          }
        } else if (event.eventType == 'UPDATED') {
          // For updates, we need to recalculate the balance for this contact
          // by replaying all transactions for this contact up to this point
          int balance = 0;
          for (final txEvent in transactionEvents) {
            String? txContactId;
            if (txEvent.eventType == 'CREATED' || txEvent.eventType == 'UPDATED') {
              txContactId = txEvent.eventData['contact_id'] as String?;
            } else if (txEvent.eventType == 'DELETED') {
              final deletedTx = txEvent.eventData['deleted_transaction'] as Map<String, dynamic>?;
              txContactId = deletedTx?['contact_id'] as String?;
            }
            
            if (txContactId == contactId &&
                (txEvent.timestamp.isBefore(event.timestamp) || 
                 txEvent.timestamp.isAtSameMomentAs(event.timestamp))) {
              if (txEvent.eventType == 'CREATED') {
                final txDirection = txEvent.eventData['direction'] as String?;
                final txAmount = (txEvent.eventData['amount'] as num?)?.toInt() ?? 0;
                if (txDirection == 'lent') {
                  balance += txAmount;
                } else if (txDirection == 'owed') {
                  balance -= txAmount;
                }
              } else if (txEvent.eventType == 'DELETED') {
                // Subtract deleted transaction
                final deletedTx = txEvent.eventData['deleted_transaction'] as Map<String, dynamic>?;
                if (deletedTx != null) {
                  final txDirection = deletedTx['direction'] as String?;
                  final txAmount = (deletedTx['amount'] as num?)?.toInt() ?? 0;
                  if (txDirection == 'lent') {
                    balance -= txAmount;
                  } else if (txDirection == 'owed') {
                    balance += txAmount;
                  }
                }
              }
            }
          }
          contacts[contactId]!.balance = balance;
        } else if (event.eventType == 'DELETED') {
          // Subtract deleted transaction from balance
          final deletedTransaction = eventData['deleted_transaction'] as Map<String, dynamic>?;
          if (deletedTransaction != null) {
            final direction = deletedTransaction['direction'] as String?;
            final amount = (deletedTransaction['amount'] as num?)?.toInt() ?? 0;
            
            if (direction == 'lent') {
              contacts[contactId]!.balance -= amount;
            } else if (direction == 'owed') {
              contacts[contactId]!.balance += amount;
            }
          }
        }
      }
    }

    // Save all contacts
    for (final contact in contacts.values) {
      await contactsBox.put(contact.id, contact);
    }
  }

  /// Rebuild transactions from events
  static Future<void> _rebuildTransactions(List<Event> events) async {
    if (kIsWeb) return;

    final transactionsBox = await Hive.openBox<Transaction>('transactions');
    
    // Clear all existing transactions first to ensure deleted ones are removed
    await transactionsBox.clear();
    
    final Map<String, Transaction> transactions = {};

    for (final event in events) {
      final transactionId = event.aggregateId;
      final eventData = event.eventData;

      if (event.eventType == 'CREATED') {
        final transactionDate = eventData['transaction_date'] as String?;
        final dueDate = eventData['due_date'] as String?;
        
        transactions[transactionId] = Transaction(
          id: transactionId,
          contactId: eventData['contact_id'] as String? ?? '',
          type: eventData['type'] == 'item' ? TransactionType.item : TransactionType.money,
          direction: eventData['direction'] == 'owed' ? TransactionDirection.owed : TransactionDirection.lent,
          amount: (eventData['amount'] as num?)?.toInt() ?? 0,
          currency: eventData['currency'] as String? ?? 'IQD',
          description: eventData['description'] as String?,
          transactionDate: transactionDate != null
              ? DateTime.parse(transactionDate)
              : DateTime.now(),
          dueDate: dueDate != null ? DateTime.parse(dueDate) : null,
          createdAt: DateTime.parse(eventData['timestamp'] as String? ?? DateTime.now().toIso8601String()),
          updatedAt: DateTime.parse(eventData['timestamp'] as String? ?? DateTime.now().toIso8601String()),
          isSynced: event.synced,
        );
      } else if (event.eventType == 'UPDATED' && transactions.containsKey(transactionId)) {
        final oldTransaction = transactions[transactionId]!;
        final transactionDate = eventData['transaction_date'] as String?;
        final dueDate = eventData['due_date'] as String?;
        
        transactions[transactionId] = Transaction(
          id: transactionId,
          contactId: eventData['contact_id'] as String? ?? oldTransaction.contactId,
          type: eventData['type'] == 'item' ? TransactionType.item : TransactionType.money,
          direction: eventData['direction'] == 'owed' ? TransactionDirection.owed : TransactionDirection.lent,
          amount: (eventData['amount'] as num?)?.toInt() ?? oldTransaction.amount,
          currency: eventData['currency'] as String? ?? oldTransaction.currency,
          description: eventData['description'] as String? ?? oldTransaction.description,
          transactionDate: transactionDate != null
              ? DateTime.parse(transactionDate)
              : oldTransaction.transactionDate,
          dueDate: dueDate != null ? DateTime.parse(dueDate) : (eventData['due_date'] == null ? null : oldTransaction.dueDate),
          createdAt: oldTransaction.createdAt,
          updatedAt: DateTime.parse(eventData['timestamp'] as String? ?? DateTime.now().toIso8601String()),
          isSynced: event.synced,
        );
      } else if (event.eventType == 'DELETED' && transactions.containsKey(transactionId)) {
        transactions.remove(transactionId);
      }
    }

    // Save all transactions
    for (final transaction in transactions.values) {
      await transactionsBox.put(transaction.id, transaction);
    }
  }

  /// Calculate total debt at a specific point in time (by replaying events up to that timestamp)
  static Future<int> calculateTotalDebtAtTime(DateTime upToTimestamp) async {
    if (kIsWeb) return 0;
    
    try {
      // Get all events up to the specified timestamp
      final allEvents = await EventStoreService.getAllEvents();
      final eventsUpToTime = allEvents
          .where((e) => e.timestamp.isBefore(upToTimestamp) || 
                       e.timestamp.isAtSameMomentAs(upToTimestamp))
          .toList();
      
      // Sort by timestamp
      eventsUpToTime.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      
      // Replay events to calculate balances
      final Map<String, int> contactBalances = {};
      
      // Process contact events
      for (final event in eventsUpToTime) {
        if (event.aggregateType == 'contact') {
          final contactId = event.aggregateId;
          
          if (event.eventType == 'CREATED') {
            contactBalances[contactId] = 0;
          } else if (event.eventType == 'DELETED') {
            contactBalances.remove(contactId);
          }
        }
      }
      
      // Process transaction events to calculate balances
      for (final event in eventsUpToTime) {
        if (event.aggregateType == 'transaction') {
          final eventData = event.eventData;
          final contactId = eventData['contact_id'] as String?;
          
          if (contactId != null && contactBalances.containsKey(contactId)) {
            if (event.eventType == 'CREATED') {
              final direction = eventData['direction'] as String?;
              final amount = (eventData['amount'] as num?)?.toInt() ?? 0;
              
              if (direction == 'lent') {
                contactBalances[contactId] = (contactBalances[contactId] ?? 0) + amount;
              } else if (direction == 'owed') {
                contactBalances[contactId] = (contactBalances[contactId] ?? 0) - amount;
              }
            } else if (event.eventType == 'UPDATED') {
              // For updates, we need to recalculate from all transactions for this contact
              // This is simplified - in a real system, you'd track the previous transaction
              final direction = eventData['direction'] as String?;
              final amount = (eventData['amount'] as num?)?.toInt() ?? 0;
              
              // Recalculate balance for this contact from all its transactions up to this point
              int balance = 0;
              for (final txEvent in eventsUpToTime) {
                if (txEvent.aggregateType == 'transaction' &&
                    txEvent.eventData['contact_id'] == contactId &&
                    txEvent.timestamp.isBefore(event.timestamp) || 
                    txEvent.timestamp.isAtSameMomentAs(event.timestamp)) {
                  if (txEvent.eventType == 'CREATED') {
                    final txDirection = txEvent.eventData['direction'] as String?;
                    final txAmount = (txEvent.eventData['amount'] as num?)?.toInt() ?? 0;
                    if (txDirection == 'lent') {
                      balance += txAmount;
                    } else if (txDirection == 'owed') {
                      balance -= txAmount;
                    }
                  }
                }
              }
              contactBalances[contactId] = balance;
            } else if (event.eventType == 'DELETED') {
              // Recalculate balance excluding this transaction
              int balance = 0;
              for (final txEvent in eventsUpToTime) {
                if (txEvent.aggregateType == 'transaction' &&
                    txEvent.eventData['contact_id'] == contactId &&
                    txEvent.id != event.id &&
                    (txEvent.timestamp.isBefore(event.timestamp) || 
                     txEvent.timestamp.isAtSameMomentAs(event.timestamp))) {
                  if (txEvent.eventType == 'CREATED') {
                    final txDirection = txEvent.eventData['direction'] as String?;
                    final txAmount = (txEvent.eventData['amount'] as num?)?.toInt() ?? 0;
                    if (txDirection == 'lent') {
                      balance += txAmount;
                    } else if (txDirection == 'owed') {
                      balance -= txAmount;
                    }
                  }
                }
              }
              contactBalances[contactId] = balance;
            }
          }
        }
      }
      
      // Sum all contact balances
      return contactBalances.values.fold<int>(0, (sum, balance) => sum + balance);
    } catch (e) {
      print('Error calculating total debt at time: $e');
      return 0;
    }
  }

  /// Rebuild a single contact from its events
  static Future<Contact?> rebuildContact(String contactId) async {
    if (kIsWeb) return null;

    final events = await EventStoreService.getEventsForAggregate('contact', contactId);
    if (events.isEmpty) return null;

    Contact? contact;

    for (final event in events) {
      final eventData = event.eventData;

      if (event.eventType == 'CREATED') {
        contact = Contact(
          id: contactId,
          name: eventData['name'] as String? ?? '',
          username: eventData['username'] as String?,
          phone: eventData['phone'] as String?,
          email: eventData['email'] as String?,
          notes: eventData['notes'] as String?,
          createdAt: DateTime.parse(eventData['timestamp'] as String? ?? DateTime.now().toIso8601String()),
          updatedAt: DateTime.parse(eventData['timestamp'] as String? ?? DateTime.now().toIso8601String()),
          isSynced: event.synced,
          balance: 0,
        );
      } else if (event.eventType == 'UPDATED' && contact != null) {
        contact = Contact(
          id: contact.id,
          name: eventData['name'] as String? ?? contact.name,
          username: eventData['username'] as String? ?? contact.username,
          phone: eventData['phone'] as String? ?? contact.phone,
          email: eventData['email'] as String? ?? contact.email,
          notes: eventData['notes'] as String? ?? contact.notes,
          createdAt: contact.createdAt,
          updatedAt: DateTime.parse(eventData['timestamp'] as String? ?? DateTime.now().toIso8601String()),
          isSynced: event.synced,
          balance: contact.balance,
        );
      } else if (event.eventType == 'DELETED') {
        return null; // Contact was deleted
      }
    }

    // Calculate balance from transactions
    if (contact != null) {
      final transactionEvents = await EventStoreService.getAllEvents();
      int balance = 0;
      for (final event in transactionEvents) {
        if (event.aggregateType == 'transaction' && 
            event.eventData['contact_id'] == contactId &&
            event.eventType != 'DELETED') {
          final direction = event.eventData['direction'] as String?;
          final amount = (event.eventData['amount'] as num?)?.toInt() ?? 0;
          
          if (direction == 'lent') {
            balance += amount;
          } else if (direction == 'owed') {
            balance -= amount;
          }
        }
      }
      contact.balance = balance;
    }

    return contact;
  }
}
