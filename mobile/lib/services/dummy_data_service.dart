import 'package:hive_flutter/hive_flutter.dart';
import '../models/contact.dart';
import '../models/transaction.dart';
import 'package:uuid/uuid.dart';
import 'wallet_service.dart';
import 'auth_service.dart';

import 'wallet_service.dart';

class DummyDataService {
  static const String contactsBoxName = 'contacts';
  static const String transactionsBoxName = 'transactions';
  static const uuid = Uuid();

  /// Get namespaced box name for contacts (user_id_wallet_id)
  static String getContactsBoxName({String? userId, String? walletId}) {
    if (userId != null && walletId != null) {
      return 'contacts_${userId}_$walletId';
    }
    return contactsBoxName; // Fallback to default for migration
  }

  /// Get namespaced box name for transactions (user_id_wallet_id)
  static String getTransactionsBoxName({String? userId, String? walletId}) {
    if (userId != null && walletId != null) {
      return 'transactions_${userId}_$walletId';
    }
    return transactionsBoxName; // Fallback to default for migration
  }

  static Future<void> initialize() async {
    // Open default boxes for migration compatibility
    // New code should use getContactsBoxName/getTransactionsBoxName with user/wallet IDs
    await Hive.openBox<Contact>(contactsBoxName);
    await Hive.openBox<Transaction>(transactionsBoxName);
  }

  /// Initialize namespaced boxes for a specific user and wallet
  static Future<void> initializeForUserAndWallet(String userId, String walletId) async {
    final contactsBoxName = getContactsBoxName(userId: userId, walletId: walletId);
    final transactionsBoxName = getTransactionsBoxName(userId: userId, walletId: walletId);
    await Hive.openBox<Contact>(contactsBoxName);
    await Hive.openBox<Transaction>(transactionsBoxName);
  }

  static void clearDummyData() {
    Hive.box<Contact>(contactsBoxName).clear();
    Hive.box<Transaction>(transactionsBoxName).clear();
  }

  /// Clear namespaced data for a specific user and wallet
  static void clearDataForUserAndWallet(String userId, String walletId) {
    final contactsBoxName = getContactsBoxName(userId: userId, walletId: walletId);
    final transactionsBoxName = getTransactionsBoxName(userId: userId, walletId: walletId);
    try {
      Hive.box<Contact>(contactsBoxName).clear();
      Hive.box<Transaction>(transactionsBoxName).clear();
    } catch (e) {
      // Boxes might not exist
    }
  }
}
