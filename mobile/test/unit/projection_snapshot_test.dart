import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:debt_tracker_mobile/services/projection_snapshot_service.dart';
import 'package:debt_tracker_mobile/services/state_builder.dart';
import 'package:debt_tracker_mobile/models/event.dart';
import 'package:debt_tracker_mobile/models/contact.dart';
import 'package:debt_tracker_mobile/models/transaction.dart';

void main() {
  group('ProjectionSnapshotService Tests', () {
    setUpAll(() async {
      // Use Hive.init() instead of Hive.initFlutter() for unit tests
      Hive.init('test/hive_test_data');
      Hive.registerAdapter(ContactAdapter());
      Hive.registerAdapter(TransactionAdapter());
      Hive.registerAdapter(TransactionTypeAdapter());
      Hive.registerAdapter(TransactionDirectionAdapter());
      Hive.registerAdapter(EventAdapter());
    });

    setUp(() async {
      // Clear snapshots box
      try {
        final box = await Hive.openBox<Map>('projection_snapshots');
        await box.clear();
      } catch (e) {
        // Box doesn't exist yet
      }
    });

    tearDown(() async {
      // Clean up
      try {
        final box = await Hive.openBox<Map>('projection_snapshots');
        await box.clear();
      } catch (e) {
        // Ignore
      }
    });

    test('shouldCreateSnapshot returns true for multiples of 10', () {
      expect(ProjectionSnapshotService.shouldCreateSnapshot(10), true);
      expect(ProjectionSnapshotService.shouldCreateSnapshot(20), true);
      expect(ProjectionSnapshotService.shouldCreateSnapshot(30), true);
      expect(ProjectionSnapshotService.shouldCreateSnapshot(9), false);
      expect(ProjectionSnapshotService.shouldCreateSnapshot(11), false);
      expect(ProjectionSnapshotService.shouldCreateSnapshot(0), true);
    });

    test('saveSnapshot and getLatestSnapshot work correctly', () async {
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

      final state = StateBuilder.buildState([event]);

      await ProjectionSnapshotService.saveSnapshot(state, 'event-1', 1);

      final snapshot = await ProjectionSnapshotService.getLatestSnapshot();
      expect(snapshot, isNotNull);
      expect(snapshot!.lastEventId, 'event-1');
      expect(snapshot.eventCount, 1);
      expect(snapshot.state.contacts.length, 1);
      expect(snapshot.state.contacts.first.name, 'Test Contact');
    });

    test('getSnapshotBeforeEvent finds correct snapshot', () async {
      final now = DateTime.now();
      final contactId = 'contact-1';
      
      // Create first snapshot
      final event1 = Event(
        id: 'event-1',
        aggregateType: 'contact',
        aggregateId: contactId,
        eventType: 'CREATED',
        eventData: {
          'name': 'Original',
          'timestamp': now.toIso8601String(),
        },
        timestamp: now,
      );

      final state1 = StateBuilder.buildState([event1]);
      await ProjectionSnapshotService.saveSnapshot(state1, 'event-1', 1);

      // Create second snapshot
      final event2 = Event(
        id: 'event-2',
        aggregateType: 'contact',
        aggregateId: contactId,
        eventType: 'UPDATED',
        eventData: {
          'name': 'Updated',
          'timestamp': now.add(const Duration(seconds: 1)).toIso8601String(),
        },
        timestamp: now.add(const Duration(seconds: 1)),
      );

      final state2 = StateBuilder.buildState([event1, event2]);
      await ProjectionSnapshotService.saveSnapshot(state2, 'event-2', 2);

      // Get snapshot before event-2
      final snapshot = await ProjectionSnapshotService.getSnapshotBeforeEvent('event-2');
      expect(snapshot, isNotNull);
      expect(snapshot!.lastEventId, 'event-1');
      expect(snapshot.state.contacts.first.name, 'Original');
    });

    test('cleanupOldSnapshots keeps only last 5 snapshots', () async {
      // Create 7 snapshots
      for (int i = 0; i < 7; i++) {
        final now = DateTime.now();
        final event = Event(
          id: 'event-$i',
          aggregateType: 'contact',
          aggregateId: 'contact-$i',
          eventType: 'CREATED',
          eventData: {
            'name': 'Contact $i',
            'timestamp': now.toIso8601String(),
          },
          timestamp: now,
        );

        final state = StateBuilder.buildState([event]);
        await ProjectionSnapshotService.saveSnapshot(state, 'event-$i', i + 1);
      }

      // Should have only 5 snapshots (last 5)
      final box = await Hive.openBox<Map>('projection_snapshots');
      expect(box.length, 5);

      // Latest snapshot should be for event-6
      final latest = await ProjectionSnapshotService.getLatestSnapshot();
      expect(latest, isNotNull);
      expect(latest!.lastEventId, 'event-6');
    });

    test('buildStateFromSnapshot filters undone events', () async {
      final now = DateTime.now();
      final contactId = 'contact-1';
      
      // Create initial snapshot
      final event1 = Event(
        id: 'event-1',
        aggregateType: 'contact',
        aggregateId: contactId,
        eventType: 'CREATED',
        eventData: {
          'name': 'Original',
          'timestamp': now.toIso8601String(),
        },
        timestamp: now,
      );

      final snapshotState = StateBuilder.buildState([event1]);
      final snapshot = ProjectionSnapshot(
        state: snapshotState,
        snapshotTimestamp: now,
        lastEventId: 'event-1',
        eventCount: 1,
        snapshotIndex: 0,
      );

      // Events after snapshot (including UNDO)
      final event2 = Event(
        id: 'event-2',
        aggregateType: 'contact',
        aggregateId: contactId,
        eventType: 'UPDATED',
        eventData: {
          'name': 'Updated',
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

      final result = await ProjectionSnapshotService.buildStateFromSnapshot(
        snapshot,
        [event2, undoEvent],
      );

      expect(result, isNotNull);
      // Update was undone, should have original name
      expect(result!.contacts.first.name, 'Original');
    });
  });
}
