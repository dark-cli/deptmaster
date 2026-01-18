import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive_flutter/hive_flutter.dart';
import '../models/contact.dart';
import '../models/transaction.dart';
import 'api_service.dart';
import 'dummy_data_service.dart';

class DataService {
  static Future<void> loadFromApi() async {
    try {
      // Fetch contacts from API
      final contacts = await ApiService.getContacts();
      
      // For web, we don't use Hive - data is loaded directly in screens
      if (!kIsWeb) {
        final contactsBox = Hive.box<Contact>(DummyDataService.contactsBoxName);
        
        // Clear and add contacts
        await contactsBox.clear();
        for (var contact in contacts) {
          await contactsBox.put(contact.id, contact);
        }
        
        // Fetch transactions from API
        final transactions = await ApiService.getTransactions();
        final transactionsBox = Hive.box<Transaction>(DummyDataService.transactionsBoxName);
        
        // Clear and add transactions
        await transactionsBox.clear();
        for (var transaction in transactions) {
          await transactionsBox.put(transaction.id, transaction);
        }
        
        print('✅ Loaded ${contacts.length} contacts and ${transactions.length} transactions from API');
      } else {
        print('✅ Web: API data will be loaded directly in screens');
      }
    } catch (e) {
      print('❌ Error loading from API: $e');
      rethrow;
    }
  }
  
  static Future<void> syncWithApi() async {
    // Future: Implement sync logic (upload local changes, download remote changes)
    await loadFromApi();
  }
}
