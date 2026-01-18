import 'package:hive/hive.dart';
import 'dart:convert';

part 'transaction.g.dart';

@HiveType(typeId: 2)
enum TransactionType {
  @HiveField(0)
  money,
  @HiveField(1)
  item
}

@HiveType(typeId: 3)
enum TransactionDirection {
  @HiveField(0)
  owed,
  @HiveField(1)
  lent
}

@HiveType(typeId: 1)
class Transaction extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String contactId;

  @HiveField(2)
  TransactionType type;

  @HiveField(3)
  TransactionDirection direction;

  @HiveField(4)
  int amount; // Stored as integer (cents for money)

  @HiveField(5)
  String currency;

  @HiveField(6)
  String? description;

  @HiveField(7)
  DateTime transactionDate;

  @HiveField(12)
  DateTime? dueDate; // Optional due date

  @HiveField(8)
  List<String> imagePaths;

  @HiveField(9)
  DateTime createdAt;

  @HiveField(10)
  DateTime updatedAt;

  @HiveField(11)
  bool isSynced;

  Transaction({
    required this.id,
    required this.contactId,
    required this.type,
    required this.direction,
    required this.amount,
    this.currency = 'USD',
    this.description,
    required this.transactionDate,
    this.dueDate,
    this.imagePaths = const [],
    required this.createdAt,
    required this.updatedAt,
    this.isSynced = false,
  });

  String getFormattedAmount(int decimals) {
    // Always money (items removed)
    // Amount is stored as whole units (IQD), not cents
    // Format with commas for thousands
    final formatted = amount.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return '$formatted IQD';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'contact_id': contactId,
      'type': type == TransactionType.money ? 'money' : 'item',
      'direction': direction == TransactionDirection.owed ? 'owed' : 'lent',
      'amount': amount,
      'currency': currency,
      'description': description,
      'transaction_date': transactionDate.toIso8601String().split('T')[0],
      'due_date': dueDate?.toIso8601String().split('T')[0],
      'image_paths': imagePaths,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Transaction.fromJson(Map<String, dynamic> json) {
    try {
      // Handle transaction_date - can be Date string or DateTime string
      String dateStr = json['transaction_date']?.toString() ?? '';
      DateTime transactionDate;
      if (dateStr.isEmpty) {
        transactionDate = DateTime.now();
      } else if (!dateStr.contains('T') && !dateStr.contains(' ')) {
        // Just a date like "2026-01-18"
        dateStr = '${dateStr}T00:00:00';
        transactionDate = DateTime.parse(dateStr);
      } else {
        transactionDate = DateTime.parse(dateStr);
      }
      
      // Handle created_at and updated_at - may not be present in API response
      String createdAtStr = json['created_at']?.toString() ?? '';
      DateTime createdAt;
      if (createdAtStr.isEmpty) {
        createdAt = transactionDate;
      } else if (!createdAtStr.contains('T') && !createdAtStr.contains(' ')) {
        createdAtStr = '${createdAtStr}T00:00:00';
        createdAt = DateTime.parse(createdAtStr);
      } else {
        createdAt = DateTime.parse(createdAtStr);
      }
      
      String updatedAtStr = json['updated_at']?.toString() ?? createdAtStr;
      DateTime updatedAt;
      if (updatedAtStr.isEmpty) {
        updatedAt = createdAt;
      } else if (!updatedAtStr.contains('T') && !updatedAtStr.contains(' ')) {
        updatedAtStr = '${updatedAtStr}T00:00:00';
        updatedAt = DateTime.parse(updatedAtStr);
      } else {
        updatedAt = DateTime.parse(updatedAtStr);
      }
      
      return Transaction(
        id: json['id']?.toString() ?? '',
        contactId: json['contact_id']?.toString() ?? '',
        type: (json['type']?.toString() ?? 'money') == 'money' ? TransactionType.money : TransactionType.item,
        direction: (json['direction']?.toString() ?? 'owed') == 'owed' ? TransactionDirection.owed : TransactionDirection.lent,
        amount: (json['amount'] as num?)?.toInt() ?? 0,
        currency: json['currency']?.toString() ?? 'USD',
        description: json['description']?.toString(),
        transactionDate: transactionDate,
        dueDate: json['due_date'] != null 
            ? DateTime.parse(json['due_date'].toString().contains('T') 
                ? json['due_date'].toString() 
                : '${json['due_date']}T00:00:00')
            : null,
        imagePaths: (json['image_paths'] as List<dynamic>?)?.cast<String>() ?? [],
        createdAt: createdAt,
        updatedAt: updatedAt,
        isSynced: true,
      );
    } catch (e, stackTrace) {
      print('❌ Error parsing transaction JSON: $e');
      print('JSON data: $json');
      print('Stack: $stackTrace');
      rethrow;
    }
  }
}
