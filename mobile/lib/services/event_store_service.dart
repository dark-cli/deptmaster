import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../models/event.dart';
import 'wallet_service.dart';
import 'package:uuid/uuid.dart';

/// Local EventStore service
/// Stores all events locally and provides event sourcing capabilities
class EventStoreService {
  static const String eventsBoxName = 'events';
  static const String lastSyncTimestampKey = 'last_sync_timestamp';
  static const uuid = Uuid();
  static Box<Event>? _eventsBox;

  /// Initialize event store
  static Future<void> initialize() async {
    if (kIsWeb) return;
    
    try {
      _eventsBox = await Hive.openBox<Event>(eventsBoxName);
      print('✅ EventStore initialized');
    } catch (e) {
      print('Error initializing EventStore: $e');
    }
  }

  /// Get all events
  static Future<List<Event>> getAllEvents() async {
    if (kIsWeb) return [];
    if (_eventsBox == null) await initialize();
    
    try {
      return _eventsBox!.values.toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    } catch (e) {
      print('Error getting events: $e');
      return [];
    }
  }

  /// Get a single event by ID
  static Future<Event?> getEvent(String eventId) async {
    if (kIsWeb) return null;
    if (_eventsBox == null) await initialize();
    
    try {
      return _eventsBox!.get(eventId);
    } catch (e) {
      print('Error getting event: $e');
      return null;
    }
  }

  /// Get events for a specific aggregate
  static Future<List<Event>> getEventsForAggregate(
    String aggregateType,
    String aggregateId,
  ) async {
    if (kIsWeb) return [];
    if (_eventsBox == null) await initialize();
    
    try {
      return _eventsBox!.values
          .where((e) =>
              e.aggregateType == aggregateType &&
              e.aggregateId == aggregateId)
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    } catch (e) {
      print('Error getting events for aggregate: $e');
      return [];
    }
  }

  /// Get events by type
  static Future<List<Event>> getEventsByType(String eventType) async {
    if (kIsWeb) return [];
    if (_eventsBox == null) await initialize();
    
    try {
      return _eventsBox!.values
          .where((e) => e.eventType == eventType)
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    } catch (e) {
      print('Error getting events by type: $e');
      return [];
    }
  }

  /// Get unsynced events (filtered by current wallet)
  static Future<List<Event>> getUnsyncedEvents() async {
    if (kIsWeb) return [];
    if (_eventsBox == null) await initialize();
    
    try {
      final walletId = WalletService.getCurrentWalletId();
      return _eventsBox!.values
          .where((e) {
            if (!e.synced) {
              // Filter by wallet_id if set, or include null for migration
              final eventWalletId = e.eventData['wallet_id'] as String?;
              return eventWalletId == walletId || (eventWalletId == null && walletId != null);
            }
            return false;
          })
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    } catch (e) {
      print('Error getting unsynced events: $e');
      return [];
    }
  }

  /// Append an event
  static Future<Event> appendEvent({
    required String aggregateType,
    required String aggregateId,
    required String eventType,
    required Map<String, dynamic> eventData,
    int version = 1,
  }) async {
    if (kIsWeb) {
      // For web, return a mock event
      return Event(
        id: uuid.v4(),
        aggregateType: aggregateType,
        aggregateId: aggregateId,
        eventType: eventType,
        eventData: eventData,
        timestamp: DateTime.now(),
        version: version,
        synced: false,
      );
    }

    if (_eventsBox == null) await initialize();

    final event = Event(
      id: uuid.v4(),
      aggregateType: aggregateType,
      aggregateId: aggregateId,
      eventType: eventType,
      eventData: eventData,
      timestamp: DateTime.now(),
      version: version,
      synced: false,
    );

    try {
      await _eventsBox!.put(event.id, event);
      print('✅ Event appended: $eventType for $aggregateType:$aggregateId');
      return event;
    } catch (e) {
      print('Error appending event: $e');
      rethrow;
    }
  }

  /// Mark event as synced
  static Future<void> markEventSynced(String eventId) async {
    if (kIsWeb) return;
    if (_eventsBox == null) await initialize();

    try {
      final event = _eventsBox!.get(eventId);
      if (event != null) {
        event.synced = true;
        await event.save();
      }
    } catch (e) {
      print('Error marking event as synced: $e');
    }
  }

  /// Get latest event version for an aggregate
  static Future<int> getLatestVersion(
    String aggregateType,
    String aggregateId,
  ) async {
    if (kIsWeb) return 0;
    if (_eventsBox == null) await initialize();

    try {
      final events = await getEventsForAggregate(aggregateType, aggregateId);
      if (events.isEmpty) return 0;
      return events.map((e) => e.version).reduce((a, b) => a > b ? a : b);
    } catch (e) {
      print('Error getting latest version: $e');
      return 0;
    }
  }

  /// Clear all events (for testing/reset)
  static Future<void> clearAllEvents() async {
    if (kIsWeb) return;
    if (_eventsBox == null) await initialize();

    try {
      await _eventsBox!.clear();
      print('✅ All events cleared');
    } catch (e) {
      print('Error clearing events: $e');
    }
  }

  /// Get event count (optionally for a single wallet only; for sync we compare with server per-wallet).
  static Future<int> getEventCount({String? walletId}) async {
    if (kIsWeb) return 0;
    if (_eventsBox == null) await initialize();

    try {
      final events = await _getEventsMaybeFiltered(walletId);
      return events.length;
    } catch (e) {
      print('Error getting event count: $e');
      return 0;
    }
  }

  /// Get hash of events (optionally for a single wallet; must match server's per-wallet hash).
  static Future<String> getEventHash({String? walletId}) async {
    if (kIsWeb) return '';
    if (_eventsBox == null) await initialize();

    try {
      final events = await _getEventsMaybeFiltered(walletId);
      final hasher = sha256;
      final buffer = StringBuffer();
      for (final event in events) {
        buffer.write(event.id);
        buffer.write(event.timestamp.toIso8601String());
      }
      final bytes = utf8.encode(buffer.toString());
      final digest = hasher.convert(bytes);
      return digest.toString();
    } catch (e) {
      print('Error getting event hash: $e');
      return '';
    }
  }

  /// Get events for a wallet (for rebuild). If walletId is null, returns all (caller beware).
  static Future<List<Event>> getEventsForWallet(String? walletId) async {
    return _getEventsMaybeFiltered(walletId);
  }

  static Future<List<Event>> _getEventsMaybeFiltered(String? walletId) async {
    if (kIsWeb) return [];
    if (_eventsBox == null) await initialize();
    try {
      var events = _eventsBox!.values.toList();
      if (walletId != null && walletId.isNotEmpty) {
        events = events.where((e) {
          final eventWalletId = e.eventData['wallet_id'] as String?;
          return eventWalletId == walletId;
        }).toList();
      }
      events.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return events;
    } catch (e) {
      print('Error getting events: $e');
      return [];
    }
  }

  /// Get last sync timestamp
  static Future<DateTime?> getLastSyncTimestamp() async {
    if (kIsWeb) return null;

    try {
      final prefs = await SharedPreferences.getInstance();
      final timestampStr = prefs.getString(lastSyncTimestampKey);
      if (timestampStr == null) return null;
      return DateTime.parse(timestampStr);
    } catch (e) {
      print('Error getting last sync timestamp: $e');
      return null;
    }
  }

  /// Set last sync timestamp
  static Future<void> setLastSyncTimestamp(DateTime timestamp) async {
    if (kIsWeb) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(lastSyncTimestampKey, timestamp.toIso8601String());
    } catch (e) {
      print('Error setting last sync timestamp: $e');
    }
  }

  /// Clear last sync timestamp (e.g. when switching wallet so we full-sync the new wallet).
  static Future<void> clearLastSyncTimestamp() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(lastSyncTimestampKey);
    } catch (e) {
      print('Error clearing last sync timestamp: $e');
    }
  }

  /// Get events after a timestamp (for incremental sync)
  static Future<List<Event>> getEventsAfter(DateTime timestamp) async {
    if (kIsWeb) return [];
    if (_eventsBox == null) await initialize();

    try {
      return _eventsBox!.values
          .where((e) => e.timestamp.isAfter(timestamp))
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    } catch (e) {
      print('Error getting events after timestamp: $e');
      return [];
    }
  }
}
