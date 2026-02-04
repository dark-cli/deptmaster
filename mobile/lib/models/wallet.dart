import 'package:hive/hive.dart';

part 'wallet.g.dart';

@HiveType(typeId: 5)
class Wallet extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String? description;

  @HiveField(3)
  DateTime createdAt;

  @HiveField(4)
  DateTime updatedAt;

  @HiveField(5)
  bool isActive;

  @HiveField(6)
  String? createdBy;

  Wallet({
    required this.id,
    required this.name,
    this.description,
    required this.createdAt,
    required this.updatedAt,
    this.isActive = true,
    this.createdBy,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_active': isActive,
      'created_by': createdBy,
    };
  }

  /// Normalize server date strings to ISO 8601 for DateTime.parse.
  /// Handles: "2026-02-04 03:43:59.938107" (PostgreSQL) and "2026-02-04" (date-only).
  static String _parseDateTime(String value) {
    if (value.contains('T')) {
      return value;
    }
    if (value.contains(' ')) {
      return value.replaceFirst(' ', 'T');
    }
    return '${value}T00:00:00';
  }

  factory Wallet.fromJson(Map<String, dynamic> json) {
    String createdAtStr = _parseDateTime((json['created_at'] as String));
    String updatedAtStr = _parseDateTime((json['updated_at'] ?? json['created_at']).toString());

    return Wallet(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      createdAt: DateTime.parse(createdAtStr),
      updatedAt: DateTime.parse(updatedAtStr),
      isActive: json['is_active'] as bool? ?? true,
      createdBy: json['created_by'] as String?,
    );
  }
}
