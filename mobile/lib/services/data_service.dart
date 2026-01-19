import 'package:flutter/foundation.dart' show kIsWeb;
import 'local_database_service.dart';
import 'api_service.dart';
import 'sync_service.dart';

class DataService {
  /// Load data from API and sync to local database
  static Future<void> loadFromApi() async {
    try {
      // Fetch contacts from API
      final contacts = await ApiService.getContacts();
      
      // Fetch transactions from API
      final transactions = await ApiService.getTransactions();
      
      // Sync to local database (for mobile/desktop)
      if (!kIsWeb) {
        await LocalDatabaseService.syncContactsFromServer(contacts);
        await LocalDatabaseService.syncTransactionsFromServer(transactions);
        print('✅ Loaded ${contacts.length} contacts and ${transactions.length} transactions from API to local');
      } else {
        print('✅ Web: Loaded ${contacts.length} contacts and ${transactions.length} transactions from API');
      }
    } catch (e) {
      print('❌ Error loading from API: $e');
      rethrow;
    }
  }
  
  /// Sync with API: push pending changes, then pull latest
  static Future<void> syncWithApi() async {
    if (kIsWeb) {
      // Web: just reload from API
      await loadFromApi();
    } else {
      // Mobile/Desktop: full sync (push pending, then pull)
      await SyncService.fullSync();
    }
  }
}
