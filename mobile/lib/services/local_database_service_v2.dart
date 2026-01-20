import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive_flutter/hive_flutter.dart';
import '../models/contact.dart';
import '../models/transaction.dart';
import '../models/event.dart';
import 'event_store_service.dart';
import 'projection_service.dart';
import 'dummy_data_service.dart';
import 'package:uuid/uuid.dart';

/// Local-first database service with Event Sourcing
/// All writes create events, projections are rebuilt from events
class LocalDatabaseServiceV2 {
  static const uuid = Uuid();

  // ========== CONTACTS ==========

  static Future<List<Contact>> getContacts() async {
    if (kIsWeb) return [];
    
    try {
      // Rebuild projections to ensure they're up to date
      await ProjectionService.rebuildProjections();
      
      final contactsBox = Hive.box<Contact>(DummyDataService.contactsBoxName);
      return contactsBox.values.toList();
    } catch (e) {
      print('Error reading contacts: $e');
      return [];
    }
  }

  static Future<Contact?> getContact(String id) async {
    if (kIsWeb) return null;
    
    try {
      return await ProjectionService.rebuildContact(id);
    } catch (e) {
      print('Error reading contact: $e');
      return null;
    }
  }

  static Future<Contact> createContact({
    required String name,
    String? username,
    String? phone,
    String? email,
    String? notes,
    required String comment, // Required comment
  }) async {
    if (kIsWeb) {
      // For web, return a mock contact
      return Contact(
        id: uuid.v4(),
        name: name,
        username: username,
        phone: phone,
        email: email,
        notes: notes,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isSynced: false,
        balance: 0,
      );
    }

    final contactId = uuid.v4();
    final timestamp = DateTime.now().toIso8601String();

    // Create event
    await EventStoreService.appendEvent(
      aggregateType: 'contact',
      aggregateId: contactId,
      eventType: 'CREATED',
      eventData: {
        'name': name,
        'username': username,
        'phone': phone,
        'email': email,
        'notes': notes,
        'comment': comment,
        'timestamp': timestamp,
      },
    );

    // Rebuild projection
    await ProjectionService.rebuildProjections();

    final contact = await getContact(contactId);
    if (contact == null) {
      throw Exception('Failed to create contact');
    }
    return contact;
  }

  static Future<void> updateContact({
    required String contactId,
    String? name,
    String? username,
    String? phone,
    String? email,
    String? notes,
    required String comment, // Required comment
  }) async {
    if (kIsWeb) return;

    final timestamp = DateTime.now().toIso8601String();
    final eventData = <String, dynamic>{
      'comment': comment,
      'timestamp': timestamp,
    };

    if (name != null) eventData['name'] = name;
    if (username != null) eventData['username'] = username;
    if (phone != null) eventData['phone'] = phone;
    if (email != null) eventData['email'] = email;
    if (notes != null) eventData['notes'] = notes;

    // Get current contact for previous_values
    final current = await getContact(contactId);
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
      aggregateId: contactId,
      eventType: 'UPDATED',
      eventData: eventData,
    );

    // Rebuild projection
    await ProjectionService.rebuildProjections();
  }

  static Future<void> deleteContact({
    required String contactId,
    required String comment, // Required comment
  }) async {
    if (kIsWeb) return;

    final timestamp = DateTime.now().toIso8601String();

    // Get current contact for deleted_contact data
    final current = await getContact(contactId);
    final deletedContact = current != null ? {
      'name': current.name,
      'username': current.username,
      'phone': current.phone,
      'email': current.email,
      'notes': current.notes,
    } : null;

    // Create event
    await EventStoreService.appendEvent(
      aggregateType: 'contact',
      aggregateId: contactId,
      eventType: 'DELETED',
      eventData: {
        'comment': comment,
        'timestamp': timestamp,
        'deleted_contact': deletedContact,
      },
    );

    // Rebuild projection
    await ProjectionService.rebuildProjections();
  }

  // ========== TRANSACTIONS ==========

  static Future<List<Transaction>> getTransactions() async {
    if (kIsWeb) return [];
    
    try {
      // Rebuild projections to ensure they're up to date
      await ProjectionService.rebuildProjections();
      
      final transactionsBox = Hive.box<Transaction>(DummyDataService.transactionsBoxName);
      return transactionsBox.values.toList();
    } catch (e) {
      print('Error reading transactions: $e');
      return [];
    }
  }

  static Future<List<Transaction>> getTransactionsByContact(String contactId) async {
    if (kIsWeb) return [];
    
    try {
      final transactions = await getTransactions();
      return transactions.where((t) => t.contactId == contactId).toList();
    } catch (e) {
      print('Error reading transactions by contact: $e');
      return [];
    }
  }

  static Future<Transaction?> getTransaction(String id) async {
    if (kIsWeb) return null;
    
    try {
      await ProjectionService.rebuildProjections();
      final transactionsBox = Hive.box<Transaction>(DummyDataService.transactionsBoxName);
      return transactionsBox.get(id);
    } catch (e) {
      print('Error reading transaction: $e');
      return null;
    }
  }

  static Future<Transaction> createTransaction({
    required String contactId,
    required TransactionType type,
    required TransactionDirection direction,
    required int amount,
    required String currency,
    String? description,
    required DateTime transactionDate,
    DateTime? dueDate,
    required String comment, // Required comment
  }) async {
    if (kIsWeb) {
      // For web, return a mock transaction
      return Transaction(
        id: uuid.v4(),
        contactId: contactId,
        type: type,
        direction: direction,
        amount: amount,
        currency: currency,
        description: description,
        transactionDate: transactionDate,
        dueDate: dueDate,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isSynced: false,
      );
    }

    final transactionId = uuid.v4();
    final timestamp = DateTime.now().toIso8601String();

    // Create event
    await EventStoreService.appendEvent(
      aggregateType: 'transaction',
      aggregateId: transactionId,
      eventType: 'CREATED',
      eventData: {
        'contact_id': contactId,
        'type': type == TransactionType.money ? 'money' : 'item',
        'direction': direction == TransactionDirection.owed ? 'owed' : 'lent',
        'amount': amount,
        'currency': currency,
        'description': description,
        'transaction_date': transactionDate.toIso8601String().split('T')[0],
        'due_date': dueDate?.toIso8601String().split('T')[0],
        'comment': comment,
        'timestamp': timestamp,
      },
    );

    // Rebuild projection
    await ProjectionService.rebuildProjections();

    final transaction = await getTransaction(transactionId);
    if (transaction == null) {
      throw Exception('Failed to create transaction');
    }
    return transaction;
  }

  static Future<void> updateTransaction({
    required String transactionId,
    String? contactId,
    TransactionType? type,
    TransactionDirection? direction,
    int? amount,
    String? currency,
    String? description,
    DateTime? transactionDate,
    DateTime? dueDate,
    required String comment, // Required comment
  }) async {
    if (kIsWeb) return;

    final timestamp = DateTime.now().toIso8601String();
    final eventData = <String, dynamic>{
      'comment': comment,
      'timestamp': timestamp,
    };

    if (contactId != null) eventData['contact_id'] = contactId;
    if (type != null) eventData['type'] = type == TransactionType.money ? 'money' : 'item';
    if (direction != null) eventData['direction'] = direction == TransactionDirection.owed ? 'owed' : 'lent';
    if (amount != null) eventData['amount'] = amount;
    if (currency != null) eventData['currency'] = currency;
    if (description != null) eventData['description'] = description;
    if (transactionDate != null) eventData['transaction_date'] = transactionDate.toIso8601String().split('T')[0];
    if (dueDate != null) eventData['due_date'] = dueDate.toIso8601String().split('T')[0];

    // Get current transaction for previous_values
    final current = await getTransaction(transactionId);
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
      aggregateId: transactionId,
      eventType: 'UPDATED',
      eventData: eventData,
    );

    // Rebuild projection
    await ProjectionService.rebuildProjections();
  }

  static Future<void> deleteTransaction({
    required String transactionId,
    required String comment, // Required comment
  }) async {
    if (kIsWeb) return;

    final timestamp = DateTime.now().toIso8601String();

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

    // Create event
    await EventStoreService.appendEvent(
      aggregateType: 'transaction',
      aggregateId: transactionId,
      eventType: 'DELETED',
      eventData: {
        'comment': comment,
        'timestamp': timestamp,
        'deleted_transaction': deletedTransaction,
      },
    );

    // Rebuild projection
    await ProjectionService.rebuildProjections();
  }

  static Future<void> bulkDeleteTransactions({
    required List<String> transactionIds,
    required String comment, // Required comment
  }) async {
    if (kIsWeb) return;

    for (final id in transactionIds) {
      await deleteTransaction(transactionId: id, comment: '$comment (bulk delete)');
    }
  }
}
