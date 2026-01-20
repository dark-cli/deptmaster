import 'package:hive/hive.dart';

part 'event.g.dart';

/// Local event model for event sourcing
/// All changes to data are stored as events
@HiveType(typeId: 4)
class Event extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String aggregateType; // 'contact' or 'transaction'

  @HiveField(2)
  final String aggregateId; // ID of the contact or transaction

  @HiveField(3)
  final String eventType; // 'CREATED', 'UPDATED', 'DELETED'

  @HiveField(4)
  final Map<String, dynamic> eventData; // Full event data including comment

  @HiveField(5)
  final DateTime timestamp;

  @HiveField(6)
  final int version; // Event version for ordering

  @HiveField(7)
  bool synced; // Whether this event has been synced to server

  Event({
    required this.id,
    required this.aggregateType,
    required this.aggregateId,
    required this.eventType,
    required this.eventData,
    required this.timestamp,
    this.version = 1,
    this.synced = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'aggregate_type': aggregateType,
        'aggregate_id': aggregateId,
        'event_type': eventType,
        'event_data': eventData,
        'timestamp': timestamp.toIso8601String(),
        'version': version,
        'synced': synced,
      };

  factory Event.fromJson(Map<String, dynamic> json) => Event(
        id: json['id'] as String,
        aggregateType: json['aggregate_type'] as String,
        aggregateId: json['aggregate_id'] as String,
        eventType: json['event_type'] as String,
        eventData: Map<String, dynamic>.from(json['event_data'] as Map),
        timestamp: DateTime.parse(json['timestamp'] as String),
        version: json['version'] as int? ?? 1,
        synced: json['synced'] as bool? ?? false,
      );
}
