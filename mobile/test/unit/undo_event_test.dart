// ignore_for_file: unused_import, duplicate_ignore

import 'package:flutter_test/flutter_test.dart';
import 'package:debt_tracker_mobile/services/state_builder.dart';
import 'package:debt_tracker_mobile/models/event.dart';
// ignore: unused_import
import 'package:debt_tracker_mobile/models/contact.dart';
import 'package:debt_tracker_mobile/models/transaction.dart';

void main() {
  group('UNDO Event Tests', () {
    test('buildState skips UNDO events themselves', () {
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

      final undoEvent = Event(
        id: 'event-2',
        aggregateType: 'contact',
        aggregateId: contactId,
        eventType: 'UNDO',
        eventData: {
          'undone_event_id': 'event-1',
          'comment': 'Action undone',
          'timestamp': now.add(const Duration(seconds: 1)).toIso8601String(),
        },
        timestamp: now.add(const Duration(seconds: 1)),
      );

      final state = StateBuilder.buildState([createdEvent, undoEvent]);

      // UNDO event should not create/modify anything
      // But the original event should still be present (UNDO doesn't delete, just marks)
      // Actually, UNDO means skip the undone event, so contact should NOT exist
      expect(state.contacts, isEmpty);
    });

    test('buildState skips undone events', () {
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
          'undone_event_id': 'event-2', // Undo the update
          'comment': 'Action undone',
          'timestamp': now.add(const Duration(seconds: 2)).toIso8601String(),
        },
        timestamp: now.add(const Duration(seconds: 2)),
      );

      final state = StateBuilder.buildState([createdEvent, updatedEvent, undoEvent]);

      // Contact should exist with original name (update was undone)
      expect(state.contacts.length, 1);
      expect(state.contacts.first.name, 'Test Contact'); // Original name, not updated
    });

    test('buildState handles multiple UNDO events', () {
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

      final update1 = Event(
        id: 'event-2',
        aggregateType: 'contact',
        aggregateId: contactId,
        eventType: 'UPDATED',
        eventData: {
          'name': 'First Update',
          'timestamp': now.add(const Duration(seconds: 1)).toIso8601String(),
        },
        timestamp: now.add(const Duration(seconds: 1)),
      );

      final update2 = Event(
        id: 'event-3',
        aggregateType: 'contact',
        aggregateId: contactId,
        eventType: 'UPDATED',
        eventData: {
          'name': 'Second Update',
          'timestamp': now.add(const Duration(seconds: 2)).toIso8601String(),
        },
        timestamp: now.add(const Duration(seconds: 2)),
      );

      final undo1 = Event(
        id: 'event-4',
        aggregateType: 'contact',
        aggregateId: contactId,
        eventType: 'UNDO',
        eventData: {
          'undone_event_id': 'event-2',
          'timestamp': now.add(const Duration(seconds: 3)).toIso8601String(),
        },
        timestamp: now.add(const Duration(seconds: 3)),
      );

      final undo2 = Event(
        id: 'event-5',
        aggregateType: 'contact',
        aggregateId: contactId,
        eventType: 'UNDO',
        eventData: {
          'undone_event_id': 'event-3',
          'timestamp': now.add(const Duration(seconds: 4)).toIso8601String(),
        },
        timestamp: now.add(const Duration(seconds: 4)),
      );

      final state = StateBuilder.buildState([createdEvent, update1, update2, undo1, undo2]);

      // Both updates undone, should have original name
      expect(state.contacts.length, 1);
      expect(state.contacts.first.name, 'Original Name');
    });

    test('buildState handles UNDO for transactions', () {
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

    test('applyEvents handles UNDO events incrementally', () {
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

      final initialState = StateBuilder.buildState([createdEvent]);
      expect(initialState.contacts.first.name, 'Original Name');

      final updateEvent = Event(
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
          'timestamp': now.add(const Duration(seconds: 2)).toIso8601String(),
        },
        timestamp: now.add(const Duration(seconds: 2)),
      );

      // Apply update and undo together
      final updatedState = StateBuilder.applyEvents(initialState, [updateEvent, undoEvent]);

      // Update was undone, should still have original name
      expect(updatedState.contacts.first.name, 'Original Name');
    });
  });
}