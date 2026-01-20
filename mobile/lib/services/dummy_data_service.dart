import 'package:hive_flutter/hive_flutter.dart';
import '../models/contact.dart';
import '../models/transaction.dart';
import 'package:uuid/uuid.dart';

class DummyDataService {
  static const String contactsBoxName = 'contacts';
  static const String transactionsBoxName = 'transactions';
  static const uuid = Uuid();

  static Future<void> initialize() async {
    // Open boxes only - no dummy data creation
    // User will import their own data or sync from server
    await Hive.openBox<Contact>(contactsBoxName);
    await Hive.openBox<Transaction>(transactionsBoxName);
  }

  static void clearDummyData() {
    Hive.box<Contact>(contactsBoxName).clear();
    Hive.box<Transaction>(transactionsBoxName).clear();
  }
}
