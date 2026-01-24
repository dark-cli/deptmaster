import 'package:flutter_test/flutter_test.dart';
import 'package:debt_tracker_mobile/services/state_builder.dart';
import 'package:debt_tracker_mobile/models/event.dart';
import 'package:debt_tracker_mobile/models/contact.dart';
import 'package:debt_tracker_mobile/models/transaction.dart';

void main() {
  group('StateBuilder Unit Tests', () {
    test('buildState with empty events returns empty state', () {
      final state = StateBuilder.buildState([]);
      
      expect(state.contacts, isEmpty);
      expect(state.transactions, isEmpty);
    });

    test('buildState creates contact from CREATED event', () {
      final now = DateTime.now();
      final contactId = 'contact-1';
      final event = Event(
        id: 'event-1',
        aggregateType: 'contact',
        aggregateId: contactId,
        eventType: 'CREATED',
        eventData: {
          'name': 'Test Contact',
          'username': 'testuser',
          'phone': '123456789',
          'email': 'test@example.com',
          'notes': 'Test notes',
          'timestamp': now.toIso8601String(),
        },
        timestamp: now,
      );

      final state = StateBuilder.buildState([event]);

      expect(state.contacts.length, 1);
      expect(state.contacts.first.id, contactId);
      expect(state.contacts.first.name, 'Test Contact');
      expect(state.contacts.first.username, 'testuser');
      expect(state.contacts.first.phone, '123456789');
      expect(state.contacts.first.email, 'test@example.com');
      expect(state.contacts.first.notes, 'Test notes');
      expect(state.contacts.first.balance, 0);
    });

    test('buildState updates contact from UPDATED event', () {
      final now = DateTime.now();
      final contactId = 'contact-1';
      final createdEvent = Event(
        id: 'event-1',
        aggregateType: 'contact',
        aggregateId: contactId,
        eventType: 'CREATED',
        eventData: {
          'name': 'Original Name',
          'timestamp': now.toIso8601String(),
        },
        timestamp: now,
      );

      final updatedEvent = Event(
        id: 'event-2',
        aggregateType: 'contact',
        aggregateId: contactId,
        eventType: 'UPDATED',
        eventData: {
          'name': 'Updated Name',
          'phone': '987654321',
          'timestamp': now.add(const Duration(seconds: 1)).toIso8601String(),
        },
        timestamp: now.add(const Duration(seconds: 1)),
      );

      final state = StateBuilder.buildState([createdEvent, updatedEvent]);

      expect(state.contacts.length, 1);
      expect(state.contacts.first.name, 'Updated Name');
      expect(state.contacts.first.phone, '987654321');
    });

    test('buildState deletes contact from DELETED event', () {
      final now = DateTime.now();
      final contactId = 'contact-1';
      final createdEvent = Event(
        id: 'event-1',
        aggregateType: 'contact',
        aggregateId: contactId,
        eventType: 'CREATED',
        eventData: {
          'name': 'Test Contact',
          'timestamp': now.toIso8601String(),
        },
        timestamp: now,
      );

      final deletedEvent = Event(
        id: 'event-2',
        aggregateType: 'contact',
        aggregateId: contactId,
        eventType: 'DELETED',
        eventData: {
          'timestamp': now.add(const Duration(seconds: 1)).toIso8601String(),
        },
        timestamp: now.add(const Duration(seconds: 1)),
      );

      final state = StateBuilder.buildState([createdEvent, deletedEvent]);

      expect(state.contacts, isEmpty);
    });

    test('buildState creates transaction and calculates balance', () {
      final now = DateTime.now();
      final contactId = 'contact-1';
      final transactionId = 'transaction-1';
      
      final contactEvent = Event(
        id: 'event-1',
        aggregateType: 'contact',
        aggregateId: contactId,
        eventType: 'CREATED',
        eventData: {
          'name': 'Test Contact',
          'timestamp': now.toIso8601String(),
        },
        timestamp: now,
      );

      final transactionEvent = Event(
        id: 'event-2',
        aggregateType: 'transaction',
        aggregateId: transactionId,
        eventType: 'CREATED',
        eventData: {
          'contact_id': contactId,
          'type': 'money',
          'direction': 'lent',
          'amount': 100000,
          'currency': 'IQD',
          'description': 'Test transaction',
          'transaction_date': now.toIso8601String().split('T')[0],
          'timestamp': now.add(const Duration(seconds: 1)).toIso8601String(),
        },
        timestamp: now.add(const Duration(seconds: 1)),
      );

      final state = StateBuilder.buildState([contactEvent, transactionEvent]);

      expect(state.contacts.length, 1);
      expect(state.transactions.length, 1);
      expect(state.contacts.first.balance, 100000); // Positive = they owe you (lent)
    });

    test('buildState calculates balance correctly with multiple transactions', () {
      final now = DateTime.now();
      final contactId = 'contact-1';
      
      final contactEvent = Event(
        id: 'event-1',
        aggregateType: 'contact',
        aggregateId: contactId,
        eventType: 'CREATED',
        eventData: {
          'name': 'Test Contact',
          'timestamp': now.toIso8601String(),
        },
        timestamp: now,
      );

      final lentEvent = Event(
        id: 'event-2',
        aggregateType: 'transaction',
        aggregateId: 'txn-1',
        eventType: 'CREATED',
        eventData: {
          'contact_id': contactId,
          'type': 'money',
          'direction': 'lent',
          'amount': 100000,
          'currency': 'IQD',
          'transaction_date': now.toIso8601String().split('T')[0],
          'timestamp': now.add(const Duration(seconds: 1)).toIso8601String(),
        },
        timestamp: now.add(const Duration(seconds: 1)),
      );

      final owedEvent = Event(
        id: 'event-3',
        aggregateType: 'transaction',
        aggregateId: 'txn-2',
        eventType: 'CREATED',
        eventData: {
          'contact_id': contactId,
          'type': 'money',
          'direction': 'owed',
          'amount': 50000,
          'currency': 'IQD',
          'transaction_date': now.toIso8601String().split('T')[0],
          'timestamp': now.add(const Duration(seconds: 2)).toIso8601String(),
        },
        timestamp: now.add(const Duration(seconds: 2)),
      );

      final state = StateBuilder.buildState([contactEvent, lentEvent, owedEvent]);

      expect(state.contacts.length, 1);
      expect(state.transactions.length, 2);
      // Balance: +100000 (lent) - 50000 (owed) = +50000
      expect(state.contacts.first.balance, 50000);
    });

    test('buildState handles transaction deletion correctly', () {
      final now = DateTime.now();
      final contactId = 'contact-1';
      final transactionId = 'transaction-1';
      
      final contactEvent = Event(
        id: 'event-1',
        aggregateType: 'contact',
        aggregateId: contactId,
        eventType: 'CREATED',
        eventData: {
          'name': 'Test Contact',
          'timestamp': now.toIso8601String(),
        },
        timestamp: now,
      );

      final createdEvent = Event(
        id: 'event-2',
        aggregateType: 'transaction',
        aggregateId: transactionId,
        eventType: 'CREATED',
        eventData: {
          'contact_id': contactId,
          'type': 'money',
          'direction': 'lent',
          'amount': 100000,
          'currency': 'IQD',
          'transaction_date': now.toIso8601String().split('T')[0],
          'timestamp': now.add(const Duration(seconds: 1)).toIso8601String(),
        },
        timestamp: now.add(const Duration(seconds: 1)),
      );

      final deletedEvent = Event(
        id: 'event-3',
        aggregateType: 'transaction',
        aggregateId: transactionId,
        eventType: 'DELETED',
        eventData: {
          'timestamp': now.add(const Duration(seconds: 2)).toIso8601String(),
        },
        timestamp: now.add(const Duration(seconds: 2)),
      );

      final state = StateBuilder.buildState([contactEvent, createdEvent, deletedEvent]);

      expect(state.transactions, isEmpty);
      expect(state.contacts.first.balance, 0); // Balance reset after deletion
    });

    test('applyEvents updates existing state incrementally', () {
      final now = DateTime.now();
      final contactId = 'contact-1';
      
      // Initial state with one contact
      final initialEvent = Event(
        id: 'event-1',
        aggregateType: 'contact',
        aggregateId: contactId,
        eventType: 'CREATED',
        eventData: {
          'name': 'Initial Contact',
          'timestamp': now.toIso8601String(),
        },
        timestamp: now,
      );

      final initialState = StateBuilder.buildState([initialEvent]);
      expect(initialState.contacts.length, 1);
      expect(initialState.contacts.first.name, 'Initial Contact');

      // Apply new event
      final newEvent = Event(
        id: 'event-2',
        aggregateType: 'contact',
        aggregateId: contactId,
        eventType: 'UPDATED',
        eventData: {
          'name': 'Updated Contact',
          'timestamp': now.add(const Duration(seconds: 1)).toIso8601String(),
        },
        timestamp: now.add(const Duration(seconds: 1)),
      );

      final updatedState = StateBuilder.applyEvents(initialState, [newEvent]);

      expect(updatedState.contacts.length, 1);
      expect(updatedState.contacts.first.name, 'Updated Contact');
    });

    test('applyEvents with empty events returns same state', () {
      final now = DateTime.now();
      final contactId = 'contact-1';
      
      final event = Event(
        id: 'event-1',
        aggregateType: 'contact',
        aggregateId: contactId,
        eventType: 'CREATED',
        eventData: {
          'name': 'Test Contact',
          'timestamp': now.toIso8601String(),
        },
        timestamp: now,
      );

      final initialState = StateBuilder.buildState([event]);
      final updatedState = StateBuilder.applyEvents(initialState, []);

      expect(updatedState.contacts.length, initialState.contacts.length);
      expect(updatedState.contacts.first.name, initialState.contacts.first.name);
    });

    test('buildState handles events in correct chronological order', () {
      final baseTime = DateTime(2024, 1, 1);
      final contactId = 'contact-1';
      
      // Create events out of order
      final event3 = Event(
        id: 'event-3',
        aggregateType: 'contact',
        aggregateId: contactId,
        eventType: 'UPDATED',
        eventData: {
          'name': 'Third Name',
          'timestamp': baseTime.add(const Duration(seconds: 3)).toIso8601String(),
        },
        timestamp: baseTime.add(const Duration(seconds: 3)),
      );

      final event1 = Event(
        id: 'event-1',
        aggregateType: 'contact',
        aggregateId: contactId,
        eventType: 'CREATED',
        eventData: {
          'name': 'First Name',
          'timestamp': baseTime.toIso8601String(),
        },
        timestamp: baseTime,
      );

      final event2 = Event(
        id: 'event-2',
        aggregateType: 'contact',
        aggregateId: contactId,
        eventType: 'UPDATED',
        eventData: {
          'name': 'Second Name',
          'timestamp': baseTime.add(const Duration(seconds: 2)).toIso8601String(),
        },
        timestamp: baseTime.add(const Duration(seconds: 2)),
      );

      // Events provided out of order
      final state = StateBuilder.buildState([event3, event1, event2]);

      // Should apply in chronological order: CREATED -> UPDATED -> UPDATED
      expect(state.contacts.length, 1);
      expect(state.contacts.first.name, 'Third Name'); // Final state
    });

    test('buildState skips UNDO events and undone events', () {
      final now = DateTime.now();
      final contactId = 'contact-1';
      
      final createdEvent = Event(
        id: 'event-1',
        aggregateType: 'contact',
        aggregateId: contactId,
        eventType: 'CREATED',
        eventData: {
          'name': 'Original Name',
          'timestamp': now.toIso8601String(),
        },
        timestamp: now,
      );

      final updatedEvent = Event(
        id: 'event-2',
        aggregateType: 'contact',
        aggregateId: contactId,
        eventType: 'UPDATED',
        eventData: {
          'name': 'Updated Name',
          'timestamp': now.add(const Duration(seconds: 1)).toIso8601String(),
        },
        timestamp: now.add(const Duration(seconds: 1)),
      );

      final undoEvent = Event(
        id: 'event-3',
        aggregateType: 'contact',
        aggregateId: contactId,
        eventType: 'UNDO',
        eventData: {
          'undone_event_id': 'event-2',
          'comment': 'Action undone',
          'timestamp': now.add(const Duration(seconds: 2)).toIso8601String(),
        },
        timestamp: now.add(const Duration(seconds: 2)),
      );

      final state = StateBuilder.buildState([createdEvent, updatedEvent, undoEvent]);

      // Update was undone, should have original name
      expect(state.contacts.length, 1);
      expect(state.contacts.first.name, 'Original Name');
    });

    test('buildState handles UNDO for transaction correctly', () {
      final now = DateTime.now();
      final contactId = 'contact-1';
      final transactionId = 'transaction-1';
      
      final contactEvent = Event(
        id: 'event-1',
        aggregateType: 'contact',
        aggregateId: contactId,
        eventType: 'CREATED',
        eventData: {
          'name': 'Test Contact',
          'timestamp': now.toIso8601String(),
        },
        timestamp: now,
      );

      final transactionEvent = Event(
        id: 'event-2',
        aggregateType: 'transaction',
        aggregateId: transactionId,
        eventType: 'CREATED',
        eventData: {
          'contact_id': contactId,
          'type': 'money',
          'direction': 'lent',
          'amount': 100000,
          'currency': 'IQD',
          'transaction_date': now.toIso8601String().split('T')[0],
          'timestamp': now.add(const Duration(seconds: 1)).toIso8601String(),
        },
        timestamp: now.add(const Duration(seconds: 1)),
      );

      final undoEvent = Event(
        id: 'event-3',
        aggregateType: 'transaction',
        aggregateId: transactionId,
        eventType: 'UNDO',
        eventData: {
          'undone_event_id': 'event-2',
          'timestamp': now.add(const Duration(seconds: 2)).toIso8601String(),
        },
        timestamp: now.add(const Duration(seconds: 2)),
      );

      final state = StateBuilder.buildState([contactEvent, transactionEvent, undoEvent]);

      // Transaction should not exist (undone)
      expect(state.transactions, isEmpty);
      // Balance should be 0 (transaction was undone)
      expect(state.contacts.first.balance, 0);
    });
  });
}
