import 'package:hive_flutter/hive_flutter.dart';
import '../models/contact.dart';
import '../models/transaction.dart';
import 'package:uuid/uuid.dart';

class DummyDataService {
  static const String contactsBoxName = 'contacts';
  static const String transactionsBoxName = 'transactions';
  static const uuid = Uuid();

  static Future<void> initialize() async {
    // Open boxes
    await Hive.openBox<Contact>(contactsBoxName);
    await Hive.openBox<Transaction>(transactionsBoxName);

    // Check if dummy data already exists
    final contactsBox = Hive.box<Contact>(contactsBoxName);
    if (contactsBox.isEmpty) {
      await _createDummyData();
    }
  }

  static Future<void> _createDummyData() async {
    final contactsBox = Hive.box<Contact>(contactsBoxName);
    final transactionsBox = Hive.box<Transaction>(transactionsBoxName);
    final now = DateTime.now();

    // Create dummy contacts
    final contacts = [
      Contact(
        id: uuid.v4(),
        name: 'John Doe',
        phone: '+1234567890',
        email: 'john@example.com',
        notes: 'Friend from college',
        createdAt: now.subtract(const Duration(days: 30)),
        updatedAt: now.subtract(const Duration(days: 30)),
      ),
      Contact(
        id: uuid.v4(),
        name: 'Jane Smith',
        phone: '+0987654321',
        email: 'jane@example.com',
        notes: 'Colleague',
        createdAt: now.subtract(const Duration(days: 20)),
        updatedAt: now.subtract(const Duration(days: 20)),
      ),
      Contact(
        id: uuid.v4(),
        name: 'Bob Johnson',
        phone: '+1122334455',
        notes: 'Neighbor',
        createdAt: now.subtract(const Duration(days: 10)),
        updatedAt: now.subtract(const Duration(days: 10)),
      ),
      Contact(
        id: uuid.v4(),
        name: 'Alice Williams',
        email: 'alice@example.com',
        notes: 'Book club member',
        createdAt: now.subtract(const Duration(days: 5)),
        updatedAt: now.subtract(const Duration(days: 5)),
      ),
    ];

    // Save contacts
    for (var contact in contacts) {
      await contactsBox.put(contact.id, contact);
    }

    // Create dummy transactions
    final transactions = [
      // Money transactions
      Transaction(
        id: uuid.v4(),
        contactId: contacts[0].id,
        type: TransactionType.money,
        direction: TransactionDirection.owed,
        amount: 5000, // $50.00
        currency: 'USD',
        description: 'Lunch payment',
        transactionDate: now.subtract(const Duration(days: 15)),
        createdAt: now.subtract(const Duration(days: 15)),
        updatedAt: now.subtract(const Duration(days: 15)),
      ),
      Transaction(
        id: uuid.v4(),
        contactId: contacts[0].id,
        type: TransactionType.money,
        direction: TransactionDirection.lent,
        amount: 2500, // $25.00
        currency: 'USD',
        description: 'Coffee',
        transactionDate: now.subtract(const Duration(days: 5)),
        createdAt: now.subtract(const Duration(days: 5)),
        updatedAt: now.subtract(const Duration(days: 5)),
      ),
      Transaction(
        id: uuid.v4(),
        contactId: contacts[1].id,
        type: TransactionType.money,
        direction: TransactionDirection.owed,
        amount: 10000, // $100.00
        currency: 'USD',
        description: 'Concert tickets',
        transactionDate: now.subtract(const Duration(days: 8)),
        createdAt: now.subtract(const Duration(days: 8)),
        updatedAt: now.subtract(const Duration(days: 8)),
      ),
      // Item transactions
      Transaction(
        id: uuid.v4(),
        contactId: contacts[2].id,
        type: TransactionType.item,
        direction: TransactionDirection.lent,
        amount: 1,
        description: 'Book: "The Rust Programming Language"',
        transactionDate: now.subtract(const Duration(days: 12)),
        createdAt: now.subtract(const Duration(days: 12)),
        updatedAt: now.subtract(const Duration(days: 12)),
      ),
      Transaction(
        id: uuid.v4(),
        contactId: contacts[3].id,
        type: TransactionType.item,
        direction: TransactionDirection.owed,
        amount: 2,
        description: 'DVDs: Movie collection',
        transactionDate: now.subtract(const Duration(days: 3)),
        createdAt: now.subtract(const Duration(days: 3)),
        updatedAt: now.subtract(const Duration(days: 1)),
      ),
      Transaction(
        id: uuid.v4(),
        contactId: contacts[1].id,
        type: TransactionType.money,
        direction: TransactionDirection.lent,
        amount: 7500, // $75.00
        currency: 'USD',
        description: 'Dinner',
        transactionDate: now.subtract(const Duration(days: 2)),
        createdAt: now.subtract(const Duration(days: 2)),
        updatedAt: now.subtract(const Duration(days: 2)),
      ),
    ];

    // Save transactions
    for (var transaction in transactions) {
      await transactionsBox.put(transaction.id, transaction);
    }
  }

  static void clearDummyData() {
    Hive.box<Contact>(contactsBoxName).clear();
    Hive.box<Transaction>(transactionsBoxName).clear();
  }
}
