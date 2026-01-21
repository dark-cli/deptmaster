import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:debt_tracker_mobile/services/local_database_service_v2.dart';
import 'package:debt_tracker_mobile/services/event_store_service.dart';
import 'package:debt_tracker_mobile/models/contact.dart';
import 'package:debt_tracker_mobile/models/transaction.dart';
import 'package:debt_tracker_mobile/models/event.dart';

void main() {
  group('LocalDatabaseServiceV2 Unit Tests', () {
    setUpAll(() async {
      // Initialize Hive for testing
      await Hive.initFlutter();
      // Register adapters (importing models automatically imports generated adapters)
      Hive.registerAdapter(ContactAdapter());
      Hive.registerAdapter(TransactionAdapter());
      Hive.registerAdapter(TransactionTypeAdapter());
      Hive.registerAdapter(TransactionDirectionAdapter());
      Hive.registerAdapter(EventAdapter());
    });

    setUp(() async {
      // Initialize services
      await EventStoreService.initialize();
      
      // Open Hive boxes if not already open
      try {
        await Hive.openBox<Contact>('contacts');
      } catch (e) {
        // Box already open
      }
      try {
        await Hive.openBox<Transaction>('transactions');
      } catch (e) {
        // Box already open
      }
      
      await LocalDatabaseServiceV2.initialize();
      
      // Clear all data
      await Hive.box<Contact>('contacts').clear();
      await Hive.box<Transaction>('transactions').clear();
      final events = await EventStoreService.getAllEvents();
      for (final event in events) {
        await event.delete();
      }
    });

    tearDown(() async {
      // Clean up after each test
      try {
        await Hive.box<Contact>('contacts').clear();
        await Hive.box<Transaction>('transactions').clear();
        await Hive.box<Event>('events').clear();
      } catch (e) {
        // Boxes might not exist
      }
    });

    test('createContact creates event and updates projections', () async {
      final contact = Contact(
        id: 'contact-1',
        name: 'Test Contact',
        username: 'testuser',
        phone: '123456789',
        email: 'test@example.com',
        notes: 'Test notes',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final created = await LocalDatabaseServiceV2.createContact(contact, comment: 'Test creation');

      // Verify contact in projections
      final contacts = await LocalDatabaseServiceV2.getContacts();
      expect(contacts.length, 1);
      expect(contacts.first.id, 'contact-1');
      expect(contacts.first.name, 'Test Contact');

      // Verify event was created
      final events = await EventStoreService.getEventsForAggregate('contact', 'contact-1');
      expect(events.length, 1);
      expect(events.first.eventType, 'CREATED');
      expect(events.first.eventData['name'], 'Test Contact');
      expect(events.first.synced, false); // Initially unsynced
    });

    test('updateContact creates UPDATED event', () async {
      // Create initial contact
      final contact = Contact(
        id: 'contact-1',
        name: 'Original Name',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await LocalDatabaseServiceV2.createContact(contact);

      // Update contact
      final updated = contact.copyWith(name: 'Updated Name', phone: '987654321');
      await LocalDatabaseServiceV2.updateContact(updated, comment: 'Test update');

      // Verify update in projections
      final contacts = await LocalDatabaseServiceV2.getContacts();
      expect(contacts.first.name, 'Updated Name');
      expect(contacts.first.phone, '987654321');

      // Verify UPDATED event was created
      final events = await EventStoreService.getEventsForAggregate('contact', 'contact-1');
      expect(events.length, 2);
      expect(events.any((e) => e.eventType == 'UPDATED'), true);
    });

    test('deleteContact creates DELETED event', () async {
      // Create contact
      final contact = Contact(
        id: 'contact-1',
        name: 'Test Contact',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await LocalDatabaseServiceV2.createContact(contact);

      // Delete contact
      await LocalDatabaseServiceV2.deleteContact('contact-1', comment: 'Test deletion');

      // Verify contact removed from projections
      final contacts = await LocalDatabaseServiceV2.getContacts();
      expect(contacts, isEmpty);

      // Verify DELETED event was created
      final events = await EventStoreService.getEventsForAggregate('contact', 'contact-1');
      expect(events.length, 2);
      expect(events.any((e) => e.eventType == 'DELETED'), true);
    });

    test('createTransaction creates event and updates balance', () async {
      // Create contact first
      final contact = Contact(
        id: 'contact-1',
        name: 'Test Contact',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await LocalDatabaseServiceV2.createContact(contact);

      // Create transaction
      final transaction = Transaction(
        id: 'transaction-1',
        contactId: 'contact-1',
        type: TransactionType.money,
        direction: TransactionDirection.lent,
        amount: 100000,
        currency: 'IQD',
        description: 'Test transaction',
        transactionDate: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await LocalDatabaseServiceV2.createTransaction(transaction);

      // Verify transaction in projections
      final transactions = await LocalDatabaseServiceV2.getTransactions();
      expect(transactions.length, 1);
      expect(transactions.first.id, 'transaction-1');

      // Verify contact balance updated
      final contacts = await LocalDatabaseServiceV2.getContacts();
      expect(contacts.first.balance, -100000); // Negative = they owe you

      // Verify event was created
      final events = await EventStoreService.getEventsForAggregate('transaction', 'transaction-1');
      expect(events.length, 1);
      expect(events.first.eventType, 'CREATED');
      expect(events.first.eventData['amount'], 100000);
    });

    test('deleteTransaction updates contact balance', () async {
      // Create contact and transaction
      final contact = Contact(
        id: 'contact-1',
        name: 'Test Contact',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await LocalDatabaseServiceV2.createContact(contact);

      final transaction = Transaction(
        id: 'transaction-1',
        contactId: 'contact-1',
        type: TransactionType.money,
        direction: TransactionDirection.lent,
        amount: 100000,
        currency: 'IQD',
        transactionDate: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await LocalDatabaseServiceV2.createTransaction(transaction);

      // Verify balance before deletion
      var contacts = await LocalDatabaseServiceV2.getContacts();
      expect(contacts.first.balance, -100000);

      // Delete transaction
      await LocalDatabaseServiceV2.deleteTransaction('transaction-1', comment: 'Test deletion');

      // Verify transaction removed
      final transactions = await LocalDatabaseServiceV2.getTransactions();
      expect(transactions, isEmpty);

      // Verify balance reset
      contacts = await LocalDatabaseServiceV2.getContacts();
      expect(contacts.first.balance, 0);

      // Verify DELETED event was created
      final events = await EventStoreService.getEventsForAggregate('transaction', 'transaction-1');
      expect(events.length, 2);
      expect(events.any((e) => e.eventType == 'DELETED'), true);
    });

    test('getTransactionsByContact returns only matching transactions', () async {
      // Create contacts
      final contact1 = Contact(
        id: 'contact-1',
        name: 'Contact 1',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final contact2 = Contact(
        id: 'contact-2',
        name: 'Contact 2',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await LocalDatabaseServiceV2.createContact(contact1);
      await LocalDatabaseServiceV2.createContact(contact2);

      // Create transactions
      final txn1 = Transaction(
        id: 'txn-1',
        contactId: 'contact-1',
        type: TransactionType.money,
        direction: TransactionDirection.lent,
        amount: 50000,
        currency: 'IQD',
        transactionDate: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final txn2 = Transaction(
        id: 'txn-2',
        contactId: 'contact-2',
        type: TransactionType.money,
        direction: TransactionDirection.lent,
        amount: 30000,
        currency: 'IQD',
        transactionDate: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await LocalDatabaseServiceV2.createTransaction(txn1);
      await LocalDatabaseServiceV2.createTransaction(txn2);

      // Get transactions for contact-1
      final contact1Transactions = await LocalDatabaseServiceV2.getTransactionsByContact('contact-1');
      expect(contact1Transactions.length, 1);
      expect(contact1Transactions.first.id, 'txn-1');
    });
  });
}
