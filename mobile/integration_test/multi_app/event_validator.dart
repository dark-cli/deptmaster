import 'package:debt_tracker_mobile/models/event.dart';
import 'app_instance.dart';

/// Validates event consistency, ordering, and data integrity across instances
class EventValidator {
  /// Validate event consistency across all instances
  Future<bool> validateEventConsistency(List<AppInstance> instances) async {
    print('🔍 Validating event consistency across ${instances.length} instances...');
    
    // Get all events from all instances
    final allEvents = <String, List<Event>>{};
    
    for (final instance in instances) {
      final events = await instance.getEvents();
      allEvents[instance.id] = events;
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
    final firstEventIds = firstEvents.map((e) => e.id).toSet();
    
    for (final instance in instances.skip(1)) {
      final instanceEvents = allEvents[instance.id]!;
      final instanceEventIds = instanceEvents.map((e) => e.id).toSet();
      
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
    
    print('✅ Event consistency validated');
    return true;
  }
  
  /// Validate event ordering (events should be in chronological order)
  Future<bool> validateEventOrdering(List<AppInstance> instances) async {
    print('🔍 Validating event ordering...');
    
    for (final instance in instances) {
      final events = await instance.getEvents();
      
      // Sort events by timestamp
      final sortedEvents = List<Event>.from(events)
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      
      // Check if events are already in order
      bool isOrdered = true;
      for (int i = 0; i < events.length; i++) {
        if (events[i].id != sortedEvents[i].id) {
          isOrdered = false;
          break;
        }
      }
      
      if (!isOrdered) {
        print('❌ Instance ${instance.id} has events out of order');
        return false;
      }
    }
    
    print('✅ Event ordering validated');
    return true;
  }
  
  /// Find duplicate events across instances
  Future<List<String>> findDuplicates(List<AppInstance> instances) async {
    print('🔍 Finding duplicate events...');
    
    final eventIds = <String, List<String>>{}; // eventId -> list of instance IDs
    
    for (final instance in instances) {
      final events = await instance.getEvents();
      for (final event in events) {
        eventIds.putIfAbsent(event.id, () => []).add(instance.id);
      }
    }
    
    final duplicates = <String>[];
    
    for (final entry in eventIds.entries) {
      final eventId = entry.key;
      final instanceIds = entry.value;
      
      // Check if same event appears multiple times in same instance
      final instanceCounts = <String, int>{};
      for (final instanceId in instanceIds) {
        instanceCounts[instanceId] = (instanceCounts[instanceId] ?? 0) + 1;
      }
      
      for (final instanceEntry in instanceCounts.entries) {
        if (instanceEntry.value > 1) {
          duplicates.add('Event $eventId appears ${instanceEntry.value} times in ${instanceEntry.key}');
        }
      }
    }
    
    if (duplicates.isNotEmpty) {
      print('❌ Found duplicates: $duplicates');
    } else {
      print('✅ No duplicates found');
    }
    
    return duplicates;
  }
  
  /// Validate event data integrity
  Future<bool> validateEventData(List<AppInstance> instances) async {
    print('🔍 Validating event data integrity...');
    
    // Get all events from all instances
    final allEvents = <String, Map<String, Event>>{}; // instanceId -> eventId -> Event
    
    for (final instance in instances) {
      final events = await instance.getEvents();
      allEvents[instance.id] = {for (var e in events) e.id: e};
    }
    
    // Check if events with same ID have same data across instances
    final firstInstanceId = instances.first.id;
    final firstEvents = allEvents[firstInstanceId]!;
    
    for (final eventId in firstEvents.keys) {
      final firstEvent = firstEvents[eventId]!;
      
      for (final instance in instances.skip(1)) {
        final instanceEvents = allEvents[instance.id]!;
        final instanceEvent = instanceEvents[eventId];
        
        if (instanceEvent == null) {
          print('❌ Event $eventId missing in instance ${instance.id}');
          return false;
        }
        
        // Compare event data
        if (firstEvent.aggregateType != instanceEvent.aggregateType ||
            firstEvent.aggregateId != instanceEvent.aggregateId ||
            firstEvent.eventType != instanceEvent.eventType ||
            firstEvent.version != instanceEvent.version) {
          print('❌ Event $eventId has different data in instance ${instance.id}');
          return false;
        }
        
        // Compare event data map (deep comparison)
        if (!_mapsEqual(firstEvent.eventData, instanceEvent.eventData)) {
          print('❌ Event $eventId has different eventData in instance ${instance.id}');
          return false;
        }
      }
    }
    
    print('✅ Event data integrity validated');
    return true;
  }
  
  /// Deep compare two maps
  bool _mapsEqual(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      
      final aValue = a[key];
      final bValue = b[key];
      
      if (aValue is Map && bValue is Map) {
        if (!_mapsEqual(Map<String, dynamic>.from(aValue), Map<String, dynamic>.from(bValue))) {
          return false;
        }
      } else if (aValue != bValue) {
        return false;
      }
    }
    
    return true;
  }
  
  /// Generate validation report
  Future<ValidationReport> generateReport(List<AppInstance> instances) async {
    final report = ValidationReport();
    
    report.consistency = await validateEventConsistency(instances);
    report.ordering = await validateEventOrdering(instances);
    report.duplicates = await findDuplicates(instances);
    report.dataIntegrity = await validateEventData(instances);
    
    // Get event counts
    for (final instance in instances) {
      final events = await instance.getEvents();
      final unsynced = await instance.getUnsyncedEvents();
      report.eventCounts[instance.id] = events.length;
      report.unsyncedCounts[instance.id] = unsynced.length;
    }
    
    report.isValid = report.consistency && 
                     report.ordering && 
                     report.duplicates.isEmpty && 
                     report.dataIntegrity;
    
    return report;
  }
}

/// Validation report
class ValidationReport {
  bool consistency = false;
  bool ordering = false;
  List<String> duplicates = [];
  bool dataIntegrity = false;
  bool isValid = false;
  Map<String, int> eventCounts = {};
  Map<String, int> unsyncedCounts = {};
  
  @override
  String toString() {
    return '''
Validation Report:
  Consistency: $consistency
  Ordering: $ordering
  Duplicates: ${duplicates.length}
  Data Integrity: $dataIntegrity
  Valid: $isValid
  Event Counts: $eventCounts
  Unsynced Counts: $unsyncedCounts
''';
  }
}
