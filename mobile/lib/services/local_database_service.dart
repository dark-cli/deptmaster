import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive_flutter/hive_flutter.dart';
import '../models/contact.dart';
import '../models/transaction.dart';
import 'dummy_data_service.dart';

/// Local-first database service
/// All reads and writes happen to local Hive database first
/// Sync to server happens in background via SyncService
class LocalDatabaseService {
  // Contacts
  static Future<List<Contact>> getContacts() async {
    if (kIsWeb) {
      // Web doesn't use Hive, return empty list (will be handled by screens)
      return [];
    }
    
    try {
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
      final contactsBox = Hive.box<Contact>(DummyDataService.contactsBoxName);
      return contactsBox.get(id);
    } catch (e) {
      print('Error reading contact from local database: $e');
      return null;
    }
  }

  static Future<Contact> createContact(Contact contact) async {
    if (kIsWeb) {
      // Web: return as-is, sync service will handle
      return contact;
    }
    
    try {
      final contactsBox = Hive.box<Contact>(DummyDataService.contactsBoxName);
      await contactsBox.put(contact.id, contact);
      print('✅ Contact saved locally: ${contact.name}');
      return contact;
    } catch (e) {
      print('Error saving contact to local database: $e');
      rethrow;
    }
  }

  static Future<void> updateContact(Contact contact) async {
    if (kIsWeb) return;
    
    try {
      final contactsBox = Hive.box<Contact>(DummyDataService.contactsBoxName);
      await contactsBox.put(contact.id, contact);
      print('✅ Contact updated locally: ${contact.name}');
    } catch (e) {
      print('Error updating contact in local database: $e');
      rethrow;
    }
  }

  static Future<void> deleteContact(String contactId) async {
    if (kIsWeb) return;
    
    try {
      final contactsBox = Hive.box<Contact>(DummyDataService.contactsBoxName);
      await contactsBox.delete(contactId);
      print('✅ Contact deleted locally: $contactId');
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

  static Future<Transaction> createTransaction(Transaction transaction) async {
    if (kIsWeb) {
      // Web: return as-is, sync service will handle
      return transaction;
    }
    
    try {
      final transactionsBox = Hive.box<Transaction>(DummyDataService.transactionsBoxName);
      await transactionsBox.put(transaction.id, transaction);
      print('✅ Transaction saved locally: ${transaction.id}');
      
      // Recalculate contact balance after creating transaction
      await _recalculateContactBalance(transaction.contactId);
      
      return transaction;
    } catch (e) {
      print('Error saving transaction to local database: $e');
      rethrow;
    }
  }

  static Future<void> updateTransaction(Transaction transaction) async {
    if (kIsWeb) return;
    
    try {
      final transactionsBox = Hive.box<Transaction>(DummyDataService.transactionsBoxName);
      
      // Get old transaction to check if contact changed
      final oldTransaction = transactionsBox.get(transaction.id);
      final oldContactId = oldTransaction?.contactId;
      
      await transactionsBox.put(transaction.id, transaction);
      print('✅ Transaction updated locally: ${transaction.id}');
      
      // Recalculate balance for both old and new contact (if contact changed)
      await _recalculateContactBalance(transaction.contactId);
      if (oldContactId != null && oldContactId != transaction.contactId) {
        await _recalculateContactBalance(oldContactId);
      }
    } catch (e) {
      print('Error updating transaction in local database: $e');
      rethrow;
    }
  }

  static Future<void> deleteTransaction(String transactionId) async {
    if (kIsWeb) return;
    
    try {
      final transactionsBox = Hive.box<Transaction>(DummyDataService.transactionsBoxName);
      
      // Get transaction before deleting to know which contact to update
      final transaction = transactionsBox.get(transactionId);
      final contactId = transaction?.contactId;
      
      await transactionsBox.delete(transactionId);
      print('✅ Transaction deleted locally: $transactionId');
      
      // Recalculate contact balance after deleting transaction
      if (contactId != null) {
        await _recalculateContactBalance(contactId);
      }
    } catch (e) {
      print('Error deleting transaction from local database: $e');
      rethrow;
    }
  }

  // Bulk operations
  static Future<void> bulkDeleteContacts(List<String> contactIds) async {
    if (kIsWeb) return;
    
    try {
      final contactsBox = Hive.box<Contact>(DummyDataService.contactsBoxName);
      for (final id in contactIds) {
        await contactsBox.delete(id);
      }
      print('✅ Bulk deleted ${contactIds.length} contacts locally');
    } catch (e) {
      print('Error bulk deleting contacts from local database: $e');
      rethrow;
    }
  }

  static Future<void> bulkDeleteTransactions(List<String> transactionIds) async {
    if (kIsWeb) return;
    
    try {
      final transactionsBox = Hive.box<Transaction>(DummyDataService.transactionsBoxName);
      final Set<String> affectedContactIds = {};
      
      // Get contact IDs before deleting
      for (final id in transactionIds) {
        final transaction = transactionsBox.get(id);
        if (transaction?.contactId != null) {
          affectedContactIds.add(transaction!.contactId);
        }
      }
      
      // Delete transactions
      for (final id in transactionIds) {
        await transactionsBox.delete(id);
      }
      print('✅ Bulk deleted ${transactionIds.length} transactions locally');
      
      // Recalculate balances for all affected contacts
      for (final contactId in affectedContactIds) {
        await _recalculateContactBalance(contactId);
      }
    } catch (e) {
      print('Error bulk deleting transactions from local database: $e');
      rethrow;
    }
  }

  // Sync operations (called by SyncService)
  static Future<void> syncContactsFromServer(List<Contact> contacts) async {
    if (kIsWeb) return;
    
    try {
      final contactsBox = Hive.box<Contact>(DummyDataService.contactsBoxName);
      int updated = 0;
      int skipped = 0;
      
      // Update or add contacts from server, but only if server data is newer
      for (var serverContact in contacts) {
        final localContact = contactsBox.get(serverContact.id);
        
        if (localContact == null) {
          // New contact from server - add it
          await contactsBox.put(serverContact.id, serverContact);
          updated++;
        } else {
          // Contact exists locally - check if we should update
          // Don't overwrite if:
          // 1. Local has unsynced changes (isSynced = false)
          // 2. Local is newer than server
          if (!localContact.isSynced) {
            // Local has pending changes - don't overwrite
            skipped++;
            continue;
          }
          
          // Compare timestamps - only update if server is newer
          if (serverContact.updatedAt.isAfter(localContact.updatedAt)) {
            await contactsBox.put(serverContact.id, serverContact);
            updated++;
          } else {
            skipped++;
          }
        }
      }
      
      if (updated > 0 || skipped > 0) {
        print('✅ Synced contacts: $updated updated, $skipped skipped (local has newer/unsynced data)');
      }
    } catch (e) {
      print('Error syncing contacts from server: $e');
      rethrow;
    }
  }

  static Future<void> syncTransactionsFromServer(List<Transaction> transactions) async {
    if (kIsWeb) return;
    
    try {
      final transactionsBox = Hive.box<Transaction>(DummyDataService.transactionsBoxName);
      final Set<String> affectedContactIds = {};
      int updated = 0;
      int skipped = 0;
      
      // Update or add transactions from server, but only if server data is newer
      for (var serverTransaction in transactions) {
        final localTransaction = transactionsBox.get(serverTransaction.id);
        
        if (localTransaction == null) {
          // New transaction from server - add it
          await transactionsBox.put(serverTransaction.id, serverTransaction);
          affectedContactIds.add(serverTransaction.contactId);
          updated++;
        } else {
          // Transaction exists locally - check if we should update
          // Don't overwrite if:
          // 1. Local has unsynced changes (isSynced = false)
          // 2. Local is newer than server
          if (!localTransaction.isSynced) {
            // Local has pending changes - don't overwrite
            skipped++;
            continue;
          }
          
          // Compare timestamps - only update if server is newer
          if (serverTransaction.updatedAt.isAfter(localTransaction.updatedAt)) {
            await transactionsBox.put(serverTransaction.id, serverTransaction);
            affectedContactIds.add(serverTransaction.contactId);
            updated++;
          } else {
            skipped++;
          }
        }
      }
      
      if (updated > 0 || skipped > 0) {
        print('✅ Synced transactions: $updated updated, $skipped skipped (local has newer/unsynced data)');
      }
      
      // Recalculate balances for all affected contacts
      for (final contactId in affectedContactIds) {
        await _recalculateContactBalance(contactId);
      }
    } catch (e) {
      print('Error syncing transactions from server: $e');
      rethrow;
    }
  }

  /// Recalculate contact balance from all transactions
  static Future<void> _recalculateContactBalance(String contactId) async {
    if (kIsWeb) return;
    
    try {
      final contactsBox = Hive.box<Contact>(DummyDataService.contactsBoxName);
      final transactionsBox = Hive.box<Transaction>(DummyDataService.transactionsBoxName);
      
      // Get all transactions for this contact
      final transactions = transactionsBox.values
          .where((t) => t.contactId == contactId)
          .toList();
      
      // Calculate balance: lent = +amount, owed = -amount
      int balance = 0;
      for (var transaction in transactions) {
        if (transaction.direction == TransactionDirection.lent) {
          balance += transaction.amount;
        } else if (transaction.direction == TransactionDirection.owed) {
          balance -= transaction.amount;
        }
      }
      
      // Update contact balance
      final contact = contactsBox.get(contactId);
      if (contact != null) {
        final updatedContact = contact.copyWith(
          balance: balance,
          updatedAt: DateTime.now(),
        );
        await contactsBox.put(contactId, updatedContact);
        print('✅ Recalculated balance for contact $contactId: $balance');
      }
    } catch (e) {
      print('Error recalculating contact balance: $e');
      // Don't rethrow - balance calculation failure shouldn't break the operation
    }
  }
}
