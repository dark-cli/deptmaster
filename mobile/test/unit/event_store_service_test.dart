import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:debt_tracker_mobile/services/event_store_service.dart';
import 'package:debt_tracker_mobile/models/event.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  group('EventStoreService Unit Tests', () {
    setUpAll(() async {
      // Use Hive.init() instead of Hive.initFlutter() for unit tests
      Hive.init('test/hive_test_data');
      // Register adapters (importing event.dart automatically imports event.g.dart)
      Hive.registerAdapter(EventAdapter());
    });

    setUp(() async {
      // Clear events before each test
      await EventStoreService.initialize();
      try {
        final box = await Hive.openBox<Event>('events');
        await box.clear();
      } catch (e) {
        // Events box might not exist yet
      }
    });

    tearDown(() async {
      // Clean up after each test
      try {
        await Hive.box<Event>('events').clear();
      } catch (e) {
        // Box might not exist
      }
    });

    test('appendEvent stores event correctly', () async {
      final now = DateTime.now();
      
      final event = await EventStoreService.appendEvent(
        aggregateType: 'contact',
        aggregateId: 'contact-1',
        eventType: 'CREATED',
        eventData: {
          'name': 'Test Contact',
          'timestamp': now.toIso8601String(),
        },
      );

      final allEvents = await EventStoreService.getAllEvents();
      expect(allEvents.length, 1);
      expect(allEvents.first.id, event.id);
      expect(allEvents.first.aggregateType, 'contact');
      expect(allEvents.first.aggregateId, 'contact-1');
      expect(allEvents.first.eventType, 'CREATED');
    });

    test('getEventsForAggregate returns only matching events', () async {
      final now = DateTime.now();
      
      await EventStoreService.appendEvent(
        aggregateType: 'contact',
        aggregateId: 'contact-1',
        eventType: 'CREATED',
        eventData: {'name': 'Contact 1', 'timestamp': now.toIso8601String()},
      );

      await EventStoreService.appendEvent(
        aggregateType: 'contact',
        aggregateId: 'contact-2',
        eventType: 'CREATED',
        eventData: {'name': 'Contact 2', 'timestamp': now.toIso8601String()},
      );

      await EventStoreService.appendEvent(
        aggregateType: 'contact',
        aggregateId: 'contact-1',
        eventType: 'UPDATED',
        eventData: {'name': 'Updated Contact 1', 'timestamp': now.add(const Duration(seconds: 1)).toIso8601String()},
      );

      final contact1Events = await EventStoreService.getEventsForAggregate('contact', 'contact-1');
      expect(contact1Events.length, 2);
      expect(contact1Events.any((e) => e.eventType == 'CREATED'), true);
      expect(contact1Events.any((e) => e.eventType == 'UPDATED'), true);
    });

    test('getEventsByType returns only matching event types', () async {
      final now = DateTime.now();
      
      await EventStoreService.appendEvent(
        aggregateType: 'contact',
        aggregateId: 'contact-1',
        eventType: 'CREATED',
        eventData: {'name': 'Contact 1', 'timestamp': now.toIso8601String()},
      );

      await EventStoreService.appendEvent(
        aggregateType: 'contact',
        aggregateId: 'contact-1',
        eventType: 'UPDATED',
        eventData: {'name': 'Updated Contact', 'timestamp': now.add(const Duration(seconds: 1)).toIso8601String()},
      );

      await EventStoreService.appendEvent(
        aggregateType: 'contact',
        aggregateId: 'contact-2',
        eventType: 'CREATED',
        eventData: {'name': 'Contact 2', 'timestamp': now.add(const Duration(seconds: 2)).toIso8601String()},
      );

      final createdEvents = await EventStoreService.getEventsByType('CREATED');
      expect(createdEvents.length, 2);
      expect(createdEvents.every((e) => e.eventType == 'CREATED'), true);
    });

    test('getUnsyncedEvents returns only unsynced events', () async {
      final now = DateTime.now();
      
      final unsyncedEvent = await EventStoreService.appendEvent(
        aggregateType: 'contact',
        aggregateId: 'contact-1',
        eventType: 'CREATED',
        eventData: {'name': 'Contact 1', 'timestamp': now.toIso8601String()},
      );

      final syncedEvent = await EventStoreService.appendEvent(
        aggregateType: 'contact',
        aggregateId: 'contact-2',
        eventType: 'CREATED',
        eventData: {'name': 'Contact 2', 'timestamp': now.toIso8601String()},
      );
      
      // Mark second event as synced
      await EventStoreService.markEventSynced(syncedEvent.id);

      final unsyncedEvents = await EventStoreService.getUnsyncedEvents();
      expect(unsyncedEvents.length, 1);
      expect(unsyncedEvents.first.id, unsyncedEvent.id);
      expect(unsyncedEvents.first.synced, false);
    });

    test('markEventSynced updates event synced status', () async {
      final now = DateTime.now();
      
      final event = await EventStoreService.appendEvent(
        aggregateType: 'contact',
        aggregateId: 'contact-1',
        eventType: 'CREATED',
        eventData: {'name': 'Contact 1', 'timestamp': now.toIso8601String()},
      );
      
      // Verify initially unsynced
      final unsyncedBefore = await EventStoreService.getUnsyncedEvents();
      expect(unsyncedBefore.length, 1);

      // Mark as synced
      await EventStoreService.markEventSynced(event.id);

      // Verify now synced
      final unsyncedAfter = await EventStoreService.getUnsyncedEvents();
      expect(unsyncedAfter, isEmpty);

      final allEvents = await EventStoreService.getAllEvents();
      final syncedEvent = allEvents.firstWhere((e) => e.id == event.id);
      expect(syncedEvent.synced, true);
    });

    test('getLatestVersion returns correct version for aggregate', () async {
      final now = DateTime.now();
      final contactId = 'contact-1';
      
      await EventStoreService.appendEvent(
        aggregateType: 'contact',
        aggregateId: contactId,
        eventType: 'CREATED',
        eventData: {'name': 'Contact 1', 'timestamp': now.toIso8601String()},
        version: 1,
      );

      await EventStoreService.appendEvent(
        aggregateType: 'contact',
        aggregateId: contactId,
        eventType: 'UPDATED',
        eventData: {'name': 'Updated Contact', 'timestamp': now.add(const Duration(seconds: 1)).toIso8601String()},
        version: 2,
      );

      final latestVersion = await EventStoreService.getLatestVersion('contact', contactId);
      expect(latestVersion, 2);
    });

    test('getEventCount returns correct count', () async {
      final now = DateTime.now();
      
      await EventStoreService.appendEvent(
        aggregateType: 'contact',
        aggregateId: 'contact-1',
        eventType: 'CREATED',
        eventData: {'name': 'Contact 1', 'timestamp': now.toIso8601String()},
      );

      await EventStoreService.appendEvent(
        aggregateType: 'contact',
        aggregateId: 'contact-2',
        eventType: 'CREATED',
        eventData: {'name': 'Contact 2', 'timestamp': now.toIso8601String()},
      );

      final count = await EventStoreService.getEventCount();
      expect(count, 2);
    });

    test('getEventsAfter returns events after timestamp', () async {
      final baseTime = DateTime.now();
      
      // Create first event
      await EventStoreService.appendEvent(
        aggregateType: 'contact',
        aggregateId: 'contact-1',
        eventType: 'CREATED',
        eventData: {'name': 'Contact 1'},
      );

      // Wait a bit to ensure different timestamps
      await Future.delayed(const Duration(milliseconds: 10));
      final cutoffTime = DateTime.now();
      await Future.delayed(const Duration(milliseconds: 10));

      // Create events after cutoff
      await EventStoreService.appendEvent(
        aggregateType: 'contact',
        aggregateId: 'contact-2',
        eventType: 'CREATED',
        eventData: {'name': 'Contact 2'},
      );

      await EventStoreService.appendEvent(
        aggregateType: 'contact',
        aggregateId: 'contact-3',
        eventType: 'CREATED',
        eventData: {'name': 'Contact 3'},
      );

      final eventsAfter = await EventStoreService.getEventsAfter(cutoffTime);
      expect(eventsAfter.length, 2);
      expect(eventsAfter.any((e) => e.aggregateId == 'contact-2'), true);
      expect(eventsAfter.any((e) => e.aggregateId == 'contact-3'), true);
      expect(eventsAfter.any((e) => e.aggregateId == 'contact-1'), false);
    });
  });
}
