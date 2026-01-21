import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:debt_tracker_mobile/main.dart' as app;
import 'package:debt_tracker_mobile/services/event_store_service.dart';
import 'package:debt_tracker_mobile/services/local_database_service_v2.dart';
import 'package:debt_tracker_mobile/services/sync_service_v2.dart';
import 'package:debt_tracker_mobile/services/api_service.dart';
import 'package:debt_tracker_mobile/services/backend_config_service.dart';
import 'helpers/test_helpers.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:debt_tracker_mobile/models/contact.dart';
import 'package:debt_tracker_mobile/models/transaction.dart';
import 'package:debt_tracker_mobile/models/event.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('End-to-End App Integration Tests', () {
    setUpAll(() async {
      // Initialize test environment
      await initializeTestEnvironment();
    });

    setUp(() async {
      // Clean up before each test
      await cleanupTestEnvironment();
    });

    tearDown(() async {
      // Clean up after each test
      await cleanupTestEnvironment();
    });

    testWidgets('Create contact and verify event created locally', (WidgetTester tester) async {
      // Start app
      app.main();
      await tester.pumpAndSettle();

      // Navigate to contacts screen (assuming it's accessible)
      // This is a simplified test - in real scenario you'd navigate through UI
      
      // Create contact programmatically (for testing)
      final contact = await createTestContact(
        name: 'Integration Test Contact',
        username: 'testuser',
        phone: '123456789',
      );

      // Verify contact exists in projections
      final contacts = await LocalDatabaseServiceV2.getContacts();
      expect(contacts.any((c) => c.id == contact.id), true);
      expect(contacts.firstWhere((c) => c.id == contact.id).name, 'Integration Test Contact');

      // Verify event was created
      await verifyEventCreated(
        aggregateType: 'contact',
        aggregateId: contact.id,
        eventType: 'CREATED',
        expectedData: {
          'name': 'Integration Test Contact',
          'username': 'testuser',
          'phone': '123456789',
        },
      );

      // Verify event is unsynced initially
      final events = await EventStoreService.getEventsForAggregate('contact', contact.id);
      expect(events.first.synced, false);
    });

    testWidgets('Create transaction and verify balance updates', (WidgetTester tester) async {
      // Create contact first
      final contact = await createTestContact(name: 'Balance Test Contact');

      // Verify initial balance
      var contacts = await LocalDatabaseServiceV2.getContacts();
      expect(contacts.firstWhere((c) => c.id == contact.id).balance, 0);

      // Create transaction
      final transaction = await createTestTransaction(
        contactId: contact.id,
        direction: TransactionDirection.lent,
        amount: 150000,
        description: 'Integration test transaction',
      );

      // Verify transaction exists
      final transactions = await LocalDatabaseServiceV2.getTransactions();
      expect(transactions.any((t) => t.id == transaction.id), true);

      // Verify balance updated
      contacts = await LocalDatabaseServiceV2.getContacts();
      expect(contacts.firstWhere((c) => c.id == contact.id).balance, -150000);

      // Verify event was created
      await verifyEventCreated(
        aggregateType: 'transaction',
        aggregateId: transaction.id,
        eventType: 'CREATED',
        expectedData: {
          'contact_id': contact.id,
          'amount': 150000,
          'direction': 'lent',
        },
      );
    });

    testWidgets('Update contact and verify UPDATED event', (WidgetTester tester) async {
      // Create contact
      final contact = await createTestContact(name: 'Original Name');

      // Update contact
      final updated = contact.copyWith(
        name: 'Updated Name',
        phone: '987654321',
      );
      await LocalDatabaseServiceV2.updateContact(updated, comment: 'Test update');

      // Verify update in projections
      final contacts = await LocalDatabaseServiceV2.getContacts();
      expect(contacts.firstWhere((c) => c.id == contact.id).name, 'Updated Name');
      expect(contacts.firstWhere((c) => c.id == contact.id).phone, '987654321');

      // Verify UPDATED event was created
      final events = await EventStoreService.getEventsForAggregate('contact', contact.id);
      expect(events.any((e) => e.eventType == 'UPDATED'), true);
    });

    testWidgets('Delete transaction and verify balance resets', (WidgetTester tester) async {
      // Create contact and transaction
      final contact = await createTestContact(name: 'Delete Test Contact');
      final transaction = await createTestTransaction(
        contactId: contact.id,
        direction: TransactionDirection.lent,
        amount: 200000,
      );

      // Verify balance before deletion
      var contacts = await LocalDatabaseServiceV2.getContacts();
      expect(contacts.firstWhere((c) => c.id == contact.id).balance, -200000);

      // Delete transaction
      await LocalDatabaseServiceV2.deleteTransaction(transaction.id, comment: 'Test deletion');

      // Verify transaction removed
      final transactions = await LocalDatabaseServiceV2.getTransactions();
      expect(transactions.any((t) => t.id == transaction.id), false);

      // Verify balance reset
      contacts = await LocalDatabaseServiceV2.getContacts();
      expect(contacts.firstWhere((c) => c.id == contact.id).balance, 0);

      // Verify DELETED event was created
      final events = await EventStoreService.getEventsForAggregate('transaction', transaction.id);
      expect(events.any((e) => e.eventType == 'DELETED'), true);
    });

    testWidgets('Sync local events to server', (WidgetTester tester) async {
      // Check if backend is configured
      final isConfigured = await BackendConfigService.isConfigured();
      if (!isConfigured) {
        // Skip test if backend not configured
        return;
      }

      // Create local events
      final contact = await createTestContact(name: 'Sync Test Contact');
      final transaction = await createTestTransaction(
        contactId: contact.id,
        direction: TransactionDirection.lent,
        amount: 100000,
      );

      // Verify events are unsynced
      var unsyncedEvents = await EventStoreService.getUnsyncedEvents();
      expect(unsyncedEvents.length, greaterThanOrEqualTo(2));

      // Trigger sync
      await SyncServiceV2.sync();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Wait for sync to complete
      await waitForSync();

      // Verify events are now synced
      unsyncedEvents = await EventStoreService.getUnsyncedEvents();
      // Note: Some events might still be unsynced if sync failed, but contact and transaction should be synced
      
      // Verify events exist on server
      final contactEvents = await EventStoreService.getEventsForAggregate('contact', contact.id);
      final transactionEvents = await EventStoreService.getEventsForAggregate('transaction', transaction.id);
      
      // At least CREATED events should be synced
      final contactCreatedEvent = contactEvents.firstWhere((e) => e.eventType == 'CREATED');
      final transactionCreatedEvent = transactionEvents.firstWhere((e) => e.eventType == 'CREATED');
      
      expect(contactCreatedEvent.synced, true, reason: 'Contact CREATED event should be synced');
      expect(transactionCreatedEvent.synced, true, reason: 'Transaction CREATED event should be synced');
    });

    testWidgets('Compare local and server events after sync', (WidgetTester tester) async {
      // Check if backend is configured
      final isConfigured = await BackendConfigService.isConfigured();
      if (!isConfigured) {
        return;
      }

      // Create local events
      final contact = await createTestContact(name: 'Compare Test Contact');
      final transaction = await createTestTransaction(
        contactId: contact.id,
        direction: TransactionDirection.owed,
        amount: 75000,
      );

      // Sync to server
      await SyncServiceV2.sync();
      await waitForSync();

      // Compare local and server events
      await compareLocalAndServerEvents();
    });

    testWidgets('Test offline creation and online sync', (WidgetTester tester) async {
      // Check if backend is configured
      final isConfigured = await BackendConfigService.isConfigured();
      if (!isConfigured) {
        return;
      }

      // Get current backend config
      final originalIp = await BackendConfigService.getBackendIp();
      final originalPort = await BackendConfigService.getBackendPort();

      try {
        // Simulate offline by setting invalid backend
        await BackendConfigService.setBackendConfig('127.0.0.1', 9999);

        // Create contact while "offline"
        final contact = await createTestContact(name: 'Offline Contact');

        // Verify event is unsynced
        final events = await EventStoreService.getEventsForAggregate('contact', contact.id);
        expect(events.first.synced, false);

        // Restore backend config (simulate coming online)
        await BackendConfigService.setBackendConfig(originalIp, originalPort);

        // Sync
        await SyncServiceV2.sync();
        await waitForSync();

        // Verify event is now synced
        final updatedEvents = await EventStoreService.getEventsForAggregate('contact', contact.id);
        final createdEvent = updatedEvents.firstWhere((e) => e.eventType == 'CREATED');
        expect(createdEvent.synced, true);
      } finally {
        // Restore original config
        await BackendConfigService.setBackendConfig(originalIp, originalPort);
      }
    });

    testWidgets('Create multiple contacts and transactions from different flows', (WidgetTester tester) async {
      // Create multiple contacts
      final contact1 = await createTestContact(name: 'Contact 1', username: 'user1');
      final contact2 = await createTestContact(name: 'Contact 2', username: 'user2');
      final contact3 = await createTestContact(name: 'Contact 3', username: 'user3');

      // Create transactions for each contact
      final txn1 = await createTestTransaction(
        contactId: contact1.id,
        direction: TransactionDirection.lent,
        amount: 100000,
      );
      final txn2 = await createTestTransaction(
        contactId: contact2.id,
        direction: TransactionDirection.owed,
        amount: 50000,
      );
      final txn3 = await createTestTransaction(
        contactId: contact3.id,
        direction: TransactionDirection.lent,
        amount: 200000,
      );

      // Verify all contacts exist
      final contacts = await LocalDatabaseServiceV2.getContacts();
      expect(contacts.length, 3);

      // Verify all transactions exist
      final transactions = await LocalDatabaseServiceV2.getTransactions();
      expect(transactions.length, 3);

      // Verify balances
      // lent = positive balance (they owe you), owed = negative balance (you owe them)
      expect(contacts.firstWhere((c) => c.id == contact1.id).balance, 100000); // lent 100000
      expect(contacts.firstWhere((c) => c.id == contact2.id).balance, -50000); // owed 50000
      expect(contacts.firstWhere((c) => c.id == contact3.id).balance, 200000); // lent 200000

      // Verify all events created
      final allEvents = await EventStoreService.getAllEvents();
      expect(allEvents.length, 6); // 3 contacts + 3 transactions

      // Verify event types
      final contactEvents = allEvents.where((e) => e.aggregateType == 'contact').toList();
      final transactionEvents = allEvents.where((e) => e.aggregateType == 'transaction').toList();
      
      expect(contactEvents.length, 3);
      expect(transactionEvents.length, 3);
      expect(contactEvents.every((e) => e.eventType == 'CREATED'), true);
      expect(transactionEvents.every((e) => e.eventType == 'CREATED'), true);
    });

    testWidgets('Monitor local data during operations', (WidgetTester tester) async {
      // Get initial event count
      final initialEvents = await EventStoreService.getAllEvents();
      final initialCount = initialEvents.length;

      // Create contact
      final contact = await createTestContact(name: 'Monitor Test Contact');

      // Verify event count increased
      final afterContactEvents = await EventStoreService.getAllEvents();
      expect(afterContactEvents.length, initialCount + 1);

      // Create transaction
      await createTestTransaction(contactId: contact.id, amount: 50000);

      // Verify event count increased again
      final afterTransactionEvents = await EventStoreService.getAllEvents();
      expect(afterTransactionEvents.length, initialCount + 2);

      // Get event statistics
      final stats = await getEventStats();
      expect(stats['total'], initialCount + 2);
      expect(stats['contacts'], 1);
      expect(stats['transactions'], 1);
    });
  });
}
