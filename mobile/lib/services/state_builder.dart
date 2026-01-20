import '../models/contact.dart';
import '../models/transaction.dart';
import '../models/event.dart';
import 'event_store_service.dart';

/// Application state containing all contacts and transactions
class AppState {
  final List<Contact> contacts;
  final List<Transaction> transactions;
  final DateTime lastBuiltAt;

  AppState({
    required this.contacts,
    required this.transactions,
    required this.lastBuiltAt,
  });

  AppState copyWith({
    List<Contact>? contacts,
    List<Transaction>? transactions,
    DateTime? lastBuiltAt,
  }) {
    return AppState(
      contacts: contacts ?? this.contacts,
      transactions: transactions ?? this.transactions,
      lastBuiltAt: lastBuiltAt ?? this.lastBuiltAt,
    );
  }
}

/// StateBuilder - Simple, pure functions to build state from events
/// KISS principle: No side effects, easy to test, incremental updates
class StateBuilder {
  /// Build full state from all events
  static AppState buildState(List<Event> events) {
    // Sort events by timestamp to ensure correct order
    final sortedEvents = List<Event>.from(events)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final contacts = <String, Contact>{};
    final transactions = <String, Transaction>{};

    for (final event in sortedEvents) {
      if (event.aggregateType == 'contact') {
        _applyContactEvent(contacts, event);
      } else if (event.aggregateType == 'transaction') {
        _applyTransactionEvent(transactions, event, contacts);
      }
    }

    // Calculate balances for all contacts
    _calculateBalances(contacts, transactions.values.toList());

    return AppState(
      contacts: contacts.values.toList(),
      transactions: transactions.values.toList(),
      lastBuiltAt: DateTime.now(),
    );
  }

  /// Apply new events to existing state (incremental update)
  static AppState applyEvents(AppState currentState, List<Event> newEvents) {
    if (newEvents.isEmpty) return currentState;

    // Sort new events by timestamp
    final sortedNewEvents = List<Event>.from(newEvents)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Convert current state to maps for easier manipulation
    final contacts = Map<String, Contact>.fromEntries(
      currentState.contacts.map((c) => MapEntry(c.id, c)),
    );
    final transactions = Map<String, Transaction>.fromEntries(
      currentState.transactions.map((t) => MapEntry(t.id, t)),
    );

    // Apply new events
    for (final event in sortedNewEvents) {
      if (event.aggregateType == 'contact') {
        _applyContactEvent(contacts, event);
      } else if (event.aggregateType == 'transaction') {
        _applyTransactionEvent(transactions, event, contacts);
      }
    }

    // Recalculate balances (only affected contacts need recalculation)
    _calculateBalances(contacts, transactions.values.toList());

    return AppState(
      contacts: contacts.values.toList(),
      transactions: transactions.values.toList(),
      lastBuiltAt: DateTime.now(),
    );
  }

  /// Apply a contact event to the contacts map
  static void _applyContactEvent(Map<String, Contact> contacts, Event event) {
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
        createdAt: _parseTimestamp(eventData['timestamp']),
        updatedAt: _parseTimestamp(eventData['timestamp']),
        isSynced: event.synced,
        balance: 0, // Will be calculated later
      );
    } else if (event.eventType == 'UPDATED' && contacts.containsKey(contactId)) {
      final existing = contacts[contactId]!;
      contacts[contactId] = Contact(
        id: existing.id,
        name: eventData['name'] as String? ?? existing.name,
        username: eventData['username'] as String? ?? existing.username,
        phone: eventData['phone'] as String? ?? existing.phone,
        email: eventData['email'] as String? ?? existing.email,
        notes: eventData['notes'] as String? ?? existing.notes,
        createdAt: existing.createdAt,
        updatedAt: _parseTimestamp(eventData['timestamp']),
        isSynced: event.synced,
        balance: existing.balance, // Will be recalculated
      );
    } else if (event.eventType == 'DELETED' && contacts.containsKey(contactId)) {
      // Remove deleted contact (hard delete for simplicity)
      contacts.remove(contactId);
    }
  }

  /// Apply a transaction event to the transactions map
  static void _applyTransactionEvent(
    Map<String, Transaction> transactions,
    Event event,
    Map<String, Contact> contacts,
  ) {
    final transactionId = event.aggregateId;
    final eventData = event.eventData;

    if (event.eventType == 'CREATED') {
      final contactId = eventData['contact_id'] as String? ?? '';
      // Only create if contact exists
      if (contacts.containsKey(contactId)) {
        transactions[transactionId] = Transaction(
          id: transactionId,
          contactId: contactId,
          type: eventData['type'] == 'item'
              ? TransactionType.item
              : TransactionType.money,
          direction: eventData['direction'] == 'owed'
              ? TransactionDirection.owed
              : TransactionDirection.lent,
          amount: (eventData['amount'] as num?)?.toInt() ?? 0,
          currency: eventData['currency'] as String? ?? 'IQD',
          description: eventData['description'] as String?,
          transactionDate: _parseDate(eventData['transaction_date']) ?? DateTime.now(),
          dueDate: _parseDate(eventData['due_date']),
          createdAt: _parseTimestamp(eventData['timestamp']),
          updatedAt: _parseTimestamp(eventData['timestamp']),
          isSynced: event.synced,
        );
      }
    } else if (event.eventType == 'UPDATED' && transactions.containsKey(transactionId)) {
      final existing = transactions[transactionId]!;
      transactions[transactionId] = Transaction(
        id: existing.id,
        contactId: eventData['contact_id'] as String? ?? existing.contactId,
        type: eventData['type'] == 'item'
            ? TransactionType.item
            : (eventData['type'] == 'money' ? TransactionType.money : existing.type),
        direction: eventData['direction'] == 'owed'
            ? TransactionDirection.owed
            : (eventData['direction'] == 'lent'
                ? TransactionDirection.lent
                : existing.direction),
        amount: (eventData['amount'] as num?)?.toInt() ?? existing.amount,
        currency: eventData['currency'] as String? ?? existing.currency,
        description: eventData['description'] as String? ?? existing.description,
        transactionDate: _parseDate(eventData['transaction_date']) ?? existing.transactionDate,
        imagePaths: existing.imagePaths,
        dueDate: _parseDate(eventData['due_date']) ?? existing.dueDate,
        createdAt: existing.createdAt,
        updatedAt: _parseTimestamp(eventData['timestamp']),
        isSynced: event.synced,
      );
    } else if (event.eventType == 'DELETED' && transactions.containsKey(transactionId)) {
      // Remove transaction (hard delete for simplicity)
      transactions.remove(transactionId);
    }
  }

  /// Calculate balances for all contacts based on transactions
  static void _calculateBalances(
    Map<String, Contact> contacts,
    List<Transaction> transactions,
  ) {
    // Reset all balances
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

    // Calculate balance from transactions
    for (final transaction in transactions) {
      final contact = contacts[transaction.contactId];
      if (contact != null) {
        final amount = transaction.direction == TransactionDirection.lent
            ? transaction.amount
            : -transaction.amount;
        contacts[transaction.contactId] = Contact(
          id: contact.id,
          name: contact.name,
          username: contact.username,
          phone: contact.phone,
          email: contact.email,
          notes: contact.notes,
          createdAt: contact.createdAt,
          updatedAt: contact.updatedAt,
          isSynced: contact.isSynced,
          balance: contact.balance + amount,
        );
      }
    }
  }

  /// Parse timestamp from event data
  static DateTime _parseTimestamp(dynamic timestamp) {
    if (timestamp == null) return DateTime.now();
    if (timestamp is String) {
      try {
        return DateTime.parse(timestamp);
      } catch (e) {
        return DateTime.now();
      }
    }
    return DateTime.now();
  }

  /// Parse date from event data (YYYY-MM-DD format)
  static DateTime? _parseDate(dynamic date) {
    if (date == null) return null;
    if (date is String) {
      try {
        return DateTime.parse(date);
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  /// Calculate total debt at a specific timestamp
  /// Returns the sum of all contact balances up to that point in time
  static Future<int> calculateTotalDebtAtTime(DateTime timestamp) async {
    // Get all events up to the timestamp
    final allEvents = await EventStoreService.getAllEvents();
    final eventsUpToTime = allEvents
        .where((e) => e.timestamp.isBefore(timestamp) || e.timestamp.isAtSameMomentAs(timestamp))
        .toList();

    // Build state from events up to that time
    final state = buildState(eventsUpToTime);

    // Calculate total debt (sum of all contact balances)
    return state.contacts.fold<int>(0, (sum, contact) => sum + contact.balance);
  }
}
