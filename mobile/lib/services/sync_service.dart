import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive_flutter/hive_flutter.dart';
import '../models/contact.dart';
import '../models/transaction.dart';
import 'api_service.dart';
import 'local_database_service.dart';
import 'realtime_service.dart';
import 'event_store_service.dart';
import 'projection_service.dart';

/// Pending operation types
enum PendingOperationType {
  create,
  update,
  delete,
}

/// Pending operation model
class PendingOperation {
  final String id;
  final PendingOperationType type;
  final String entityType; // 'contact' or 'transaction'
  final Map<String, dynamic>? data; // Entity data for create/update
  final DateTime timestamp;

  PendingOperation({
    required this.id,
    required this.type,
    required this.entityType,
    this.data,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.toString().split('.').last,
    'entityType': entityType,
    'data': data,
    'timestamp': timestamp.toIso8601String(),
  };

  factory PendingOperation.fromJson(Map<String, dynamic> json) => PendingOperation(
    id: json['id'] as String,
    type: PendingOperationType.values.firstWhere(
      (e) => e.toString().split('.').last == json['type'],
    ),
    entityType: json['entityType'] as String,
    data: json['data'] as Map<String, dynamic>?,
    timestamp: DateTime.parse(json['timestamp'] as String),
  );
}

/// Sync service for local-first architecture
/// Handles syncing local changes to server and pulling server changes
class SyncService {
  static const String _pendingOperationsBoxName = 'pending_operations';
  static Box<PendingOperation>? _pendingBox;
  static bool _isSyncing = false;
  static Timer? _periodicSyncTimer;
  static bool _wasConnected = false;

  /// Initialize sync service
  static Future<void> initialize() async {
    if (kIsWeb) return;
    
    try {
      // Register adapter for pending operations if not already registered
      try {
        if (!Hive.isAdapterRegistered(100)) {
          Hive.registerAdapter(_PendingOperationAdapter());
        }
      } catch (e) {
        // Adapter might already be registered, that's okay
        print('Adapter registration note: $e');
      }
      
      _pendingBox = await Hive.openBox<PendingOperation>(_pendingOperationsBoxName);
      
      // Start periodic sync check
      _startPeriodicSyncCheck();
      
      print('✅ SyncService initialized');
    } catch (e) {
      print('Error initializing SyncService: $e');
    }
  }

  /// Start periodic check for connection and sync
  static void _startPeriodicSyncCheck() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      final isConnected = RealtimeService.isConnected;
      
      // If just reconnected, trigger a sync
      if (isConnected && !_wasConnected) {
        print('🔄 Connection restored, triggering sync...');
        fullSync(); // Don't await, run in background
      }
      
      // If connected, sync pending changes periodically
      if (isConnected) {
        syncPendingChanges(); // Don't await, run in background
      }
      
      _wasConnected = isConnected;
    });
  }

  /// Stop periodic sync (for cleanup)
  static void stop() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
  }

  /// Add pending operation (called when local write happens)
  /// Returns a unique operation ID
  static Future<String> addPendingOperation({
    required String entityId,
    required PendingOperationType type,
    required String entityType,
    Map<String, dynamic>? data,
  }) async {
    if (kIsWeb) return entityId;
    
    try {
      if (_pendingBox == null) {
        await initialize();
      }
      
      // Create unique operation ID: entityType_entityId_type_timestamp
      final operationId = '${entityType}_${entityId}_${type.toString().split('.').last}_${DateTime.now().millisecondsSinceEpoch}';
      
      final operation = PendingOperation(
        id: operationId,
        type: type,
        entityType: entityType,
        data: data != null ? {...data, 'id': entityId} : null, // Ensure entity ID is in data
        timestamp: DateTime.now(),
      );
      
      await _pendingBox!.put(operationId, operation);
      print('✅ Added pending operation: ${type.toString().split('.').last} $entityType $entityId');
      
      // Try to sync immediately if online (don't await, let it run in background)
      if (RealtimeService.isConnected) {
        syncPendingChanges();
      }
      
      return operationId;
    } catch (e) {
      print('Error adding pending operation: $e');
      return entityId;
    }
  }

  /// Remove pending operation (called when sync succeeds)
  static Future<void> removePendingOperation(String id) async {
    if (kIsWeb || _pendingBox == null) return;
    
    try {
      await _pendingBox!.delete(id);
      print('✅ Removed pending operation: $id');
    } catch (e) {
      print('Error removing pending operation: $e');
    }
  }

  /// Get all pending operations
  static List<PendingOperation> getPendingOperations() {
    if (kIsWeb || _pendingBox == null) return [];
    return _pendingBox!.values.toList();
  }

  /// Sync pending changes to server
  static Future<void> syncPendingChanges() async {
    if (kIsWeb || _isSyncing) return;
    
    if (!RealtimeService.isConnected) {
      // Silently skip if not connected - app works offline
      return;
    }

    _isSyncing = true;

    try {
      final pendingOps = getPendingOperations();
      if (pendingOps.isEmpty) {
        _isSyncing = false;
        return;
      }

      // Sort operations: contacts first, then transactions
      // This ensures contacts exist on server before transactions that reference them
      final sortedOps = List<PendingOperation>.from(pendingOps);
      sortedOps.sort((a, b) {
        if (a.entityType == 'contact' && b.entityType == 'transaction') return -1;
        if (a.entityType == 'transaction' && b.entityType == 'contact') return 1;
        return 0; // Keep original order for same type
      });

      for (var op in sortedOps) {
        try {
          if (op.entityType == 'contact') {
            await _syncContactOperation(op);
          } else if (op.entityType == 'transaction') {
            await _syncTransactionOperation(op);
          }
          
          // Remove from pending after successful sync
          await removePendingOperation(op.id);
        } catch (e) {
          // Silently handle connection errors - keep in pending for retry later
          final errorStr = e.toString();
          if (!errorStr.contains('Connection refused') && 
              !errorStr.contains('Failed host lookup') &&
              !errorStr.contains('Network is unreachable')) {
            print('❌ Error syncing operation ${op.id}: $e');
          }
          // Keep in pending for retry later
        }
      }
    } catch (e) {
      // Silently handle connection errors
      final errorStr = e.toString();
      if (!errorStr.contains('Connection refused') && 
          !errorStr.contains('Failed host lookup') &&
          !errorStr.contains('Network is unreachable')) {
        print('❌ Error during sync: $e');
      }
    } finally {
      _isSyncing = false;
    }
  }

  /// Sync contact operation
  static Future<void> _syncContactOperation(PendingOperation op) async {
    try {
      if (op.type == PendingOperationType.create) {
        if (op.data != null) {
          final localContact = Contact.fromJson(op.data!);
          final localId = localContact.id;
          
          // Create on server (server will generate UUID)
          // Use default comment for synced operations
          final serverContact = await ApiService.createContact(
            localContact,
            comment: 'Synced from mobile app',
          );
          
          if (serverContact != null) {
            if (localId != serverContact.id) {
              // Contact ID changed - need to update all transactions that reference the old ID
              print('🔄 Contact ID changed from $localId to ${serverContact.id}, updating transactions...');
              
              // Get all transactions that reference the old contact ID
              final allTransactions = await LocalDatabaseService.getTransactions();
              final transactionsToUpdate = allTransactions.where((t) => t.contactId == localId).toList();
              
              // Update each transaction to use the new contact ID
              for (final transaction in transactionsToUpdate) {
                final updatedTransaction = Transaction(
                  id: transaction.id,
                  contactId: serverContact.id, // Use new contact ID
                  type: transaction.type,
                  direction: transaction.direction,
                  amount: transaction.amount,
                  currency: transaction.currency,
                  description: transaction.description,
                  transactionDate: transaction.transactionDate,
                  dueDate: transaction.dueDate,
                  createdAt: transaction.createdAt,
                  updatedAt: transaction.updatedAt,
                  isSynced: transaction.isSynced,
                );
                await LocalDatabaseService.updateTransaction(updatedTransaction);
              }
              
              // Update local database: delete old entry with local ID, add with server ID
              await LocalDatabaseService.deleteContact(localId);
            }
            // Mark as synced - create new contact with isSynced = true
            final syncedContact = Contact(
              id: serverContact.id,
              name: serverContact.name,
              username: serverContact.username,
              phone: serverContact.phone,
              email: serverContact.email,
              notes: serverContact.notes,
              createdAt: serverContact.createdAt,
              updatedAt: serverContact.updatedAt,
              isSynced: true,
              balance: serverContact.balance,
            );
            await LocalDatabaseService.updateContact(syncedContact);
            print('✅ Synced contact: ${serverContact.name}');
          }
        }
      } else if (op.type == PendingOperationType.update) {
        if (op.data != null) {
          // Extract entity ID from data or operation ID
          final entityId = op.data!['id'] as String? ?? op.id.split('_')[1];
          final contact = Contact.fromJson(op.data!);
          // Use default comment for synced operations
          await ApiService.updateContact(
            entityId,
            contact,
            comment: 'Synced from mobile app',
          );
          
          // Mark as synced after successful update
          final syncedContact = Contact(
            id: contact.id,
            name: contact.name,
            username: contact.username,
            phone: contact.phone,
            email: contact.email,
            notes: contact.notes,
            createdAt: contact.createdAt,
            updatedAt: contact.updatedAt,
            isSynced: true,
            balance: contact.balance,
          );
          await LocalDatabaseService.updateContact(syncedContact);
        }
      } else if (op.type == PendingOperationType.delete) {
        // Extract entity ID from operation ID (format: contact_entityId_delete_timestamp)
        final entityId = op.id.split('_')[1];
        // Use default comment for synced operations
        await ApiService.deleteContact(
          entityId,
          comment: 'Synced from mobile app',
        );
        
        // Mark the delete event as synced
        try {
          final allEvents = await EventStoreService.getAllEvents();
          final deleteEvent = allEvents.firstWhere(
            (e) => e.aggregateType == 'contact' && 
                   e.aggregateId == entityId && 
                   e.eventType == 'DELETED',
            orElse: () => throw Exception('Delete event not found'),
          );
          await EventStoreService.markEventSynced(deleteEvent.id);
          
          // Rebuild projections to update balances
          await ProjectionService.rebuildProjections();
        } catch (e) {
          print('⚠️ Could not mark delete event as synced: $e');
        }
      }
    } catch (e) {
      // Re-throw to be handled by caller
      rethrow;
    }
  }

  /// Sync transaction operation
  static Future<void> _syncTransactionOperation(PendingOperation op) async {
    try {
      if (op.type == PendingOperationType.create) {
        if (op.data != null) {
          // Get the current transaction from database (in case contact ID was updated)
          final transactionId = op.data!['id'] as String? ?? op.id.split('_')[1];
          final currentTransaction = await LocalDatabaseService.getTransaction(transactionId);
          
          if (currentTransaction == null) {
            print('⚠️ Transaction $transactionId not found in local database, skipping sync');
            return;
          }
          
          final localTransaction = currentTransaction; // Use current data, not stale pending data
          final localId = localTransaction.id;
          
          // Check if the contact exists on the server before syncing transaction
          // First check if contact is still pending
          final pendingOps = getPendingOperations();
          final contactPending = pendingOps.any((p) {
            if (p.entityType != 'contact') return false;
            // Extract entity ID from operation ID (format: contact_entityId_type_timestamp) or from data
            final contactId = p.data?['id'] as String? ?? 
                             (p.id.split('_').length > 1 ? p.id.split('_')[1] : null);
            return contactId == localTransaction.contactId;
          });
          
          if (contactPending) {
            print('⏳ Skipping transaction sync - contact ${localTransaction.contactId} is still pending');
            return; // Skip for now, will retry after contact syncs
          }
          
          // Also verify contact exists on server (in case sync failed or ID changed)
          try {
            final serverContacts = await ApiService.getContacts();
            final contactExists = serverContacts.any((c) => c.id == localTransaction.contactId);
            
            if (!contactExists) {
              print('⏳ Skipping transaction sync - contact ${localTransaction.contactId} not found on server');
              return; // Skip for now, will retry after contact syncs
            }
          } catch (e) {
            // If we can't check, try to sync anyway (might be offline)
            print('⚠️ Could not verify contact on server: $e');
          }
          
          // Create on server (server will generate UUID)
          // Use default comment for synced operations
          final serverTransaction = await ApiService.createTransaction(
            localTransaction,
            comment: 'Synced from mobile app',
          );
          
          if (serverTransaction != null) {
            if (localId != serverTransaction.id) {
              // Update local database: delete old entry with local ID, add with server ID
              await LocalDatabaseService.deleteTransaction(localId);
            }
            // Mark as synced - serverTransaction already has isSynced = true from fromJson
            await LocalDatabaseService.updateTransaction(serverTransaction);
            print('✅ Synced transaction: ${serverTransaction.id}');
          }
        }
      } else if (op.type == PendingOperationType.update) {
        if (op.data != null) {
          // Extract entity ID from data or operation ID
          final entityId = op.data!['id'] as String? ?? op.id.split('_')[1];
          
          // Get the current transaction from database (in case contact ID was updated)
          final currentTransaction = await LocalDatabaseService.getTransaction(entityId);
          if (currentTransaction == null) {
            print('⚠️ Transaction $entityId not found in local database, skipping sync');
            return;
          }
          
          final transaction = currentTransaction; // Use current data, not stale pending data
          await ApiService.updateTransaction(
            entityId,
            amount: transaction.amount,
            direction: transaction.direction,
            description: transaction.description,
            transactionDate: transaction.transactionDate,
            contactId: transaction.contactId,
            dueDate: transaction.dueDate,
            comment: 'Synced from mobile app',
          );
          
          // Mark as synced after successful update - create new transaction with isSynced = true
          final syncedTransaction = Transaction(
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
            isSynced: true,
          );
          await LocalDatabaseService.updateTransaction(syncedTransaction);
        }
      } else if (op.type == PendingOperationType.delete) {
        // Extract entity ID from operation ID (format: transaction_entityId_delete_timestamp)
        final entityId = op.id.split('_')[1];
        // Use default comment for synced operations
        await ApiService.deleteTransaction(entityId, comment: 'Synced from mobile app');
        
        // Mark the delete event as synced
        try {
          final allEvents = await EventStoreService.getAllEvents();
          final deleteEvent = allEvents.firstWhere(
            (e) => e.aggregateType == 'transaction' && 
                   e.aggregateId == entityId && 
                   e.eventType == 'DELETED',
            orElse: () => throw Exception('Delete event not found'),
          );
          await EventStoreService.markEventSynced(deleteEvent.id);
          
          // Rebuild projections to update balances
          await ProjectionService.rebuildProjections();
        } catch (e) {
          print('⚠️ Could not mark delete event as synced: $e');
        }
      }
    } catch (e) {
      // Re-throw to be handled by caller
      rethrow;
    }
  }

  /// Pull changes from server and update local database
  static Future<void> pullFromServer() async {
    if (kIsWeb || _isSyncing) return;

    _isSyncing = true;

    try {
      // Try to fetch latest from server (will return empty lists if offline)
      final contacts = await ApiService.getContacts();
      final transactions = await ApiService.getTransactions();

      // Update local database (only if we got data)
      if (contacts.isNotEmpty || transactions.isNotEmpty) {
        await LocalDatabaseService.syncContactsFromServer(contacts);
        await LocalDatabaseService.syncTransactionsFromServer(transactions);
        print('✅ Pulled ${contacts.length} contacts and ${transactions.length} transactions from server');
      } else {
        // Silently handle offline case - app works with local data
      }
    } catch (e) {
      // Silently handle connection errors - app works offline
      final errorStr = e.toString();
      if (!errorStr.contains('Connection refused') && 
          !errorStr.contains('Failed host lookup') &&
          !errorStr.contains('Network is unreachable')) {
        print('❌ Error pulling from server: $e');
      }
    } finally {
      _isSyncing = false;
    }
  }

  /// Full sync: push pending changes, then pull from server
  static Future<void> fullSync() async {
    if (kIsWeb) return;
    
    // Silently handle sync - don't spam console if offline
    try {
      // First push pending changes
      await syncPendingChanges();
      
      // Then pull latest from server
      await pullFromServer();
    } catch (e) {
      // Silently handle sync errors when offline
      final errorStr = e.toString();
      if (!errorStr.contains('Connection refused') && 
          !errorStr.contains('Failed host lookup') &&
          !errorStr.contains('Network is unreachable')) {
        print('❌ Sync error: $e');
      }
    }
  }
}

/// Hive adapter for PendingOperation
class _PendingOperationAdapter extends TypeAdapter<PendingOperation> {
  @override
  final int typeId = 100;

  @override
  PendingOperation read(BinaryReader reader) {
    final json = jsonDecode(reader.readString());
    return PendingOperation.fromJson(json);
  }

  @override
  void write(BinaryWriter writer, PendingOperation obj) {
    writer.writeString(jsonEncode(obj.toJson()));
  }
}
