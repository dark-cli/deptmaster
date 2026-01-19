import 'package:hive/hive.dart';
import 'dart:convert';

part 'contact.g.dart';

@HiveType(typeId: 0)
class Contact extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(9)
  String? username;

  @HiveField(2)
  String? phone;

  @HiveField(3)
  String? email;

  @HiveField(4)
  String? notes;

  @HiveField(5)
  DateTime createdAt;

  @HiveField(6)
  DateTime updatedAt;

  @HiveField(7)
  bool isSynced;

  @HiveField(8)
  int balance; // Net balance in cents: positive = they owe you, negative = you owe them

  Contact({
    required this.id,
    required this.name,
    this.username,
    this.phone,
    this.email,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.isSynced = false,
    this.balance = 0,
  });

  Contact copyWith({
    String? id,
    String? name,
    String? username,
    String? phone,
    String? email,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isSynced,
    int? balance,
  }) {
    return Contact(
      id: id ?? this.id,
      name: name ?? this.name,
      username: username ?? this.username,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
      balance: balance ?? this.balance,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'username': username,
      'phone': phone,
      'email': email,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Contact.fromJson(Map<String, dynamic> json) {
    // Handle NaiveDateTime format from API (no timezone)
    String createdAtStr = json['created_at'] as String;
    if (!createdAtStr.contains('T')) {
      createdAtStr = '${createdAtStr}T00:00:00';
    }
    
    return Contact(
      id: json['id'] as String,
      name: json['name'] as String,
      username: json['username'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(createdAtStr),
      updatedAt: DateTime.parse(createdAtStr), // API doesn't return updated_at, use created_at
      isSynced: true,
      balance: (json['balance'] as num?)?.toInt() ?? 0,
    );
  }
}
