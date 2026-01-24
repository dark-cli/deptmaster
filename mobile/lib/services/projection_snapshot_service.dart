import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive_flutter/hive_flutter.dart';
import '../models/contact.dart';
import '../models/transaction.dart';
import '../models/event.dart';
import 'state_builder.dart';
import 'event_store_service.dart';

/// Projection snapshot model stored in Hive
class ProjectionSnapshot {
  final AppState state;
  final DateTime snapshotTimestamp;
  final String lastEventId;
  final int eventCount;
  final int snapshotIndex;

  ProjectionSnapshot({
    required this.state,
    required this.snapshotTimestamp,
    required this.lastEventId,
    required this.eventCount,
    required this.snapshotIndex,
  });

  Map<String, dynamic> toJson() => {
        'contacts': state.contacts.map((c) => c.toJson()).toList(),
        'transactions': state.transactions.map((t) => t.toJson()).toList(),
        'snapshotTimestamp': snapshotTimestamp.toIso8601String(),
        'lastEventId': lastEventId,
        'eventCount': eventCount,
        'snapshotIndex': snapshotIndex,
      };

  factory ProjectionSnapshot.fromJson(Map<String, dynamic> json) {
    final contacts = (json['contacts'] as List)
        .map((c) => Contact.fromJson(c as Map<String, dynamic>))
        .toList();
    final transactions = (json['transactions'] as List)
        .map((t) => Transaction.fromJson(t as Map<String, dynamic>))
        .toList();

    return ProjectionSnapshot(
      state: AppState(
        contacts: contacts,
        transactions: transactions,
        lastBuiltAt: DateTime.parse(json['snapshotTimestamp'] as String),
      ),
      snapshotTimestamp: DateTime.parse(json['snapshotTimestamp'] as String),
      lastEventId: json['lastEventId'] as String,
      eventCount: json['eventCount'] as int,
      snapshotIndex: json['snapshotIndex'] as int,
    );
  }
}

/// Projection Snapshot Service
/// Manages projection snapshots for efficient state rebuilding
class ProjectionSnapshotService {
  static const String boxName = 'projection_snapshots';
  static const int maxSnapshots = 5; // Keep last 5 snapshots
  static const int snapshotInterval = 10; // Create snapshot every 10 events

  /// Save a snapshot
  static Future<void> saveSnapshot(
    AppState state,
    String lastEventId,
    int eventCount,
  ) async {
    if (kIsWeb) return;

    try {
      final box = await Hive.openBox<Map>(boxName);

      // Get current snapshot index
      int nextIndex = 0;
      if (box.isNotEmpty) {
        final lastSnapshot = box.values.last;
        if (lastSnapshot['snapshotIndex'] != null) {
          nextIndex = (lastSnapshot['snapshotIndex'] as int) + 1;
        }
      }

      final snapshot = ProjectionSnapshot(
        state: state,
        snapshotTimestamp: DateTime.now(),
        lastEventId: lastEventId,
        eventCount: eventCount,
        snapshotIndex: nextIndex,
      );

      // Save snapshot with index as key
      await box.put(nextIndex, snapshot.toJson());

      // Cleanup old snapshots
      await cleanupOldSnapshots();

      print('✅ Saved projection snapshot #$nextIndex (event count: $eventCount)');
    } catch (e) {
      print('Error saving projection snapshot: $e');
    }
  }

  /// Get snapshot before a specific event
  /// Returns the most recent snapshot where the snapshot's last event timestamp is before the target event timestamp
  static Future<ProjectionSnapshot?> getSnapshotBeforeEvent(String eventId) async {
    if (kIsWeb) return null;

    try {
      final box = await Hive.openBox<Map>(boxName);
      if (box.isEmpty) return null;

      // Get the target event to find its timestamp
      final targetEvent = await EventStoreService.getEvent(eventId);
      if (targetEvent == null) return null;

      // Get all snapshots sorted by index (descending - most recent first)
      final snapshots = box.values.toList()
        ..sort((a, b) => (b['snapshotIndex'] as int).compareTo(a['snapshotIndex'] as int));

      // Find the most recent snapshot where the snapshot's last event timestamp is before target event timestamp
      for (final snapshotData in snapshots) {
        final snapshot = ProjectionSnapshot.fromJson(Map<String, dynamic>.from(snapshotData));
        
        // Get the snapshot's last event to compare timestamps
        final snapshotLastEvent = await EventStoreService.getEvent(snapshot.lastEventId);
        if (snapshotLastEvent != null) {
          // Return snapshot if its last event is before the target event
          if (snapshotLastEvent.timestamp.isBefore(targetEvent.timestamp)) {
            return snapshot;
          }
        }
      }

      return null;
    } catch (e) {
      print('⚠️ Could not find snapshot before event (this is normal if no snapshots exist): $e');
      return null;
    }
  }

  /// Get the latest snapshot
  static Future<ProjectionSnapshot?> getLatestSnapshot() async {
    if (kIsWeb) return null;

    try {
      final box = await Hive.openBox<Map>(boxName);
      if (box.isEmpty) return null;

      // Get snapshot with highest index
      final snapshots = box.values.toList()
        ..sort((a, b) => (b['snapshotIndex'] as int).compareTo(a['snapshotIndex'] as int));

      if (snapshots.isEmpty) return null;

      return ProjectionSnapshot.fromJson(Map<String, dynamic>.from(snapshots.first));
    } catch (e) {
      print('Error getting latest snapshot: $e');
      return null;
    }
  }

  /// Cleanup old snapshots, keeping only the last maxSnapshots
  static Future<void> cleanupOldSnapshots() async {
    if (kIsWeb) return;

    try {
      final box = await Hive.openBox<Map>(boxName);
      if (box.length <= maxSnapshots) return;

      // Get all snapshots sorted by index (ascending - oldest first)
      final snapshots = box.values.toList()
        ..sort((a, b) => (a['snapshotIndex'] as int).compareTo(b['snapshotIndex'] as int));

      // Delete oldest snapshots, keeping only the last maxSnapshots
      final toDelete = snapshots.length - maxSnapshots;
      for (int i = 0; i < toDelete; i++) {
        final index = snapshots[i]['snapshotIndex'] as int;
        await box.delete(index);
      }

      print('🧹 Cleaned up ${toDelete} old snapshots, kept $maxSnapshots');
    } catch (e) {
      print('Error cleaning up snapshots: $e');
    }
  }

  /// Check if we should create a snapshot based on event count
  static bool shouldCreateSnapshot(int eventCount) {
    return eventCount % snapshotInterval == 0;
  }

  /// Build state from snapshot and events after snapshot
  static Future<AppState?> buildStateFromSnapshot(
    ProjectionSnapshot? snapshot,
    List<Event> eventsAfterSnapshot,
  ) async {
    if (snapshot == null) return null;

    // Filter out undone events and UNDO events
    final undoneEventIds = <String>{};
    for (final event in eventsAfterSnapshot) {
      if (event.eventType == 'UNDO') {
        final undoneEventId = event.eventData['undone_event_id'] as String?;
        if (undoneEventId != null) {
          undoneEventIds.add(undoneEventId);
        }
      }
    }

    final filteredEvents = eventsAfterSnapshot.where((event) {
      if (event.eventType == 'UNDO') return false;
      if (undoneEventIds.contains(event.id)) return false;
      return true;
    }).toList();

    // Apply filtered events to snapshot state
    return StateBuilder.applyEvents(snapshot.state, filteredEvents);
  }
}
