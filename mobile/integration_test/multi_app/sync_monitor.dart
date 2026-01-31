// ignore_for_file: unused_import

import 'dart:async';
import 'package:debt_tracker_mobile/services/sync_service_v2.dart';
import 'package:debt_tracker_mobile/services/event_store_service.dart';
import 'app_instance.dart';

/// Monitor sync state across all app instances
class SyncMonitor {
  final List<AppInstance> instances;
  
  SyncMonitor(this.instances);
  
  /// Wait for all instances to sync
  Future<void> waitForSync({Duration timeout = const Duration(seconds: 60)}) async {
    print('⏳ Waiting for all instances to sync...');
    
    final startTime = DateTime.now();
    int iteration = 0;
    
    while (DateTime.now().difference(startTime) < timeout) {
      iteration++;
      final allSynced = await allInstancesSynced();
      if (allSynced) {
        print('✅ All instances synced');
        return;
      }
      
      // Print status every 5 seconds
      if (iteration % 5 == 0) {
        final unsyncedCounts = await getUnsyncedEventCounts();
        print('⏳ Still syncing... Unsynced counts: $unsyncedCounts');
      }
      
      await Future.delayed(const Duration(seconds: 1));
    }
    
    // Print final status before timeout
    final unsyncedCounts = await getUnsyncedEventCounts();
    final eventCounts = await getEventCounts();
    throw TimeoutException(
      'Sync timeout - not all instances synced within ${timeout.inSeconds} seconds. '
      'Unsynced counts: $unsyncedCounts, Total event counts: $eventCounts',
      timeout,
    );
  }
  
  /// Check if all instances are synced
  Future<bool> allInstancesSynced() async {
    for (final instance in instances) {
      final unsynced = await instance.getUnsyncedEvents();
      if (unsynced.isNotEmpty) {
        return false;
      }
    }
    return true;
  }
  
  /// Get event counts per instance
  Future<Map<String, int>> getEventCounts() async {
    final counts = <String, int>{};
    
    for (final instance in instances) {
      final events = await instance.getEvents();
      counts[instance.id] = events.length;
    }
    
    return counts;
  }
  
  /// Get unsynced event counts per instance
  Future<Map<String, int>> getUnsyncedEventCounts() async {
    final counts = <String, int>{};
    
    for (final instance in instances) {
      final unsynced = await instance.getUnsyncedEvents();
      counts[instance.id] = unsynced.length;
    }
    
    return counts;
  }
  
  /// Validate consistency across all instances
  Future<bool> validateConsistency() async {
    // Get all events from all instances
    final allEvents = <String, List<Map<String, dynamic>>>{};
    
    for (final instance in instances) {
      final events = await instance.getEvents();
      allEvents[instance.id] = events.map((e) => e.toJson()).toList();
    }
    
    // Check if all instances have the same number of events
    final eventCounts = allEvents.values.map((e) => e.length).toSet();
    if (eventCounts.length > 1) {
      print('❌ Inconsistent event counts: $eventCounts');
      return false;
    }
    
    // Check if all instances have the same events (by ID)
    final firstInstanceId = instances.first.id;
    final firstEvents = allEvents[firstInstanceId]!;
    final firstEventIds = firstEvents.map((e) => e['id'] as String).toSet();
    
    for (final instance in instances.skip(1)) {
      final instanceEvents = allEvents[instance.id]!;
      final instanceEventIds = instanceEvents.map((e) => e['id'] as String).toSet();
      
      if (firstEventIds.length != instanceEventIds.length) {
        print('❌ Instance ${instance.id} has different number of events');
        return false;
      }
      
      final missing = firstEventIds.difference(instanceEventIds);
      if (missing.isNotEmpty) {
        print('❌ Instance ${instance.id} missing events: $missing');
        return false;
      }
      
      final extra = instanceEventIds.difference(firstEventIds);
      if (extra.isNotEmpty) {
        print('❌ Instance ${instance.id} has extra events: $extra');
        return false;
      }
    }
    
    return true;
  }
  
  /// Detect conflicts between instances
  Future<List<String>> detectConflicts() async {
    final conflicts = <String>[];
    
    // Get all events grouped by aggregate
    final aggregateEvents = <String, Map<String, List<Map<String, dynamic>>>>{};
    
    for (final instance in instances) {
      final events = await instance.getEvents();
      for (final event in events) {
        final key = '${event.aggregateType}:${event.aggregateId}';
        aggregateEvents.putIfAbsent(key, () => {});
        aggregateEvents[key]!.putIfAbsent(instance.id, () => []);
        aggregateEvents[key]![instance.id]!.add(event.toJson());
      }
    }
    
    // Check for conflicts (different events for same aggregate)
    for (final entry in aggregateEvents.entries) {
      final aggregateKey = entry.key;
      final instanceEvents = entry.value;
      
      // Get all event IDs for this aggregate across all instances
      final allEventIds = <String>{};
      for (final events in instanceEvents.values) {
        for (final event in events) {
          allEventIds.add(event['id'] as String);
        }
      }
      
      // If instances have different events for same aggregate, it's a conflict
      final instanceEventIds = instanceEvents.map((id, events) => 
        MapEntry(id, events.map((e) => e['id'] as String).toSet())
      );
      
      final firstInstanceId = instanceEventIds.keys.first;
      final firstEventIds = instanceEventIds[firstInstanceId]!;
      
      for (final instanceId in instanceEventIds.keys.skip(1)) {
        final currentInstanceEventIds = instanceEventIds[instanceId]!;
        if (firstEventIds != currentInstanceEventIds) {
          conflicts.add('Conflict in $aggregateKey: ${firstInstanceId} vs $instanceId');
        }
      }
    }
    
    return conflicts;
  }
  
  /// Watch sync events (stream of sync status changes)
  Stream<SyncEvent> watchSyncEvents() {
    final controller = StreamController<SyncEvent>.broadcast();
    
    // Poll sync status periodically
    Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (controller.isClosed) {
        timer.cancel();
        return;
      }
      
      for (final instance in instances) {
        final unsynced = await instance.getUnsyncedEvents();
        final status = unsynced.isEmpty ? 'synced' : 'unsynced';
        
        controller.add(SyncEvent(
          instanceId: instance.id,
          status: status,
          unsyncedCount: unsynced.length,
          timestamp: DateTime.now(),
        ));
      }
    });
    
    return controller.stream;
  }
}

/// Sync event for monitoring
class SyncEvent {
  final String instanceId;
  final String status;
  final int unsyncedCount;
  final DateTime timestamp;
  
  SyncEvent({
    required this.instanceId,
    required this.status,
    required this.unsyncedCount,
    required this.timestamp,
  });
}