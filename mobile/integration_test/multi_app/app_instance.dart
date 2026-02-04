import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:debt_tracker_mobile/services/event_store_service.dart';
import 'package:debt_tracker_mobile/services/local_database_service_v2.dart';
import 'package:debt_tracker_mobile/services/sync_service_v2.dart';
import 'package:debt_tracker_mobile/services/auth_service.dart';
import 'package:debt_tracker_mobile/services/backend_config_service.dart';
import 'package:debt_tracker_mobile/services/realtime_service.dart';
import 'package:debt_tracker_mobile/services/wallet_service.dart';
import 'package:debt_tracker_mobile/services/dummy_data_service.dart';
import 'package:debt_tracker_mobile/models/contact.dart';
import 'package:debt_tracker_mobile/models/transaction.dart';
import 'package:debt_tracker_mobile/models/event.dart';
import 'package:debt_tracker_mobile/models/wallet.dart';
import 'network_interceptor.dart';
import 'realtime_service_test_helper.dart';

/// Simulated app instance with isolated Hive database and real server connection
class AppInstance {
  final String id;
  final String serverUrl;
  final String username;
  final String password;
  final String hivePath;
  final String? userId;  // User ID after login
  final String? walletId;  // Wallet ID to use
  
  bool _simulatedOffline = false;
  bool _initialized = false;
  
  Box<Event>? eventsBox;
  Box<Contact>? contactsBox;
  Box<Transaction>? transactionsBox;
  
  NetworkInterceptor? networkInterceptor;
  
  AppInstance({
    required this.id,
    required this.serverUrl,
    required this.username,
    required this.password,
    required this.hivePath,
    this.userId,
    this.walletId,
  });
  
  /// Create a new app instance with isolated storage
  /// Each instance should have its own user and wallet for parallel testing
  static Future<AppInstance> create({
    required String id,
    String serverUrl = 'http://localhost:8000',
    String username = 'max',  // Default test user (or unique user per instance)
    String password = '12345678',  // Default test password
    String? walletId,  // Wallet ID to use (should be shared across test users)
  }) async {
    return AppInstance(
      id: id,
      serverUrl: serverUrl,
      username: username,
      password: password,
      hivePath: '', // Not used - we use namespaced boxes
      walletId: walletId,
    );
  }
  
  /// Initialize the app instance
  /// Note: Hive must be initialized globally before creating instances
  Future<void> initialize() async {
    if (_initialized) return;
    
    print('🔧 Initializing AppInstance $id...');
    
    // Ensure Hive is initialized (should be done globally in test setup)
    // We use shared boxes but isolated auth/config state
    
    // Register adapters if not already registered
    try {
      Hive.registerAdapter(ContactAdapter());
    } catch (e) {
      // Already registered
    }
    try {
      Hive.registerAdapter(TransactionAdapter());
    } catch (e) {
      // Already registered
    }
    try {
      Hive.registerAdapter(TransactionTypeAdapter());
    } catch (e) {
      // Already registered
    }
    try {
      Hive.registerAdapter(TransactionDirectionAdapter());
    } catch (e) {
      // Already registered
    }
    try {
      Hive.registerAdapter(EventAdapter());
    } catch (e) {
      // Already registered
    }
    try {
      Hive.registerAdapter(WalletAdapter());
    } catch (e) {
      // Already registered
    }
    
    // Open default boxes (for migration compatibility)
    // Namespaced boxes will be opened after login when we have userId and walletId
    try {
      contactsBox = await Hive.openBox<Contact>('contacts');
    } catch (e) {
      // Box already open
      contactsBox = Hive.box<Contact>('contacts');
    }
    
    try {
      transactionsBox = await Hive.openBox<Transaction>('transactions');
    } catch (e) {
      // Box already open
      transactionsBox = Hive.box<Transaction>('transactions');
    }
    
    try {
      eventsBox = await Hive.openBox<Event>('events');
    } catch (e) {
      // Box already open
      eventsBox = Hive.box<Event>('events');
    }
    
    try {
      await Hive.openBox<Wallet>('wallets');
    } catch (e) {
      // Box already open
    }
    
    // Note: Namespaced boxes (contacts_${userId}_${walletId}) will be opened
    // after login when we have both userId and walletId
    
    // Initialize services (they use the shared boxes)
    await EventStoreService.initialize();
    await LocalDatabaseServiceV2.initialize();
    await SyncServiceV2.initialize();
    
    // Create network interceptor
    networkInterceptor = NetworkInterceptor();
    
    // Configure backend (this is shared, but that's okay for testing)
    // Note: SharedPreferences doesn't work in unit tests, so we'll set it via environment
    // or skip if it fails (the server URL is already configured)
    final uri = Uri.parse(serverUrl);
    try {
      await BackendConfigService.setBackendConfig(uri.host, uri.port);
      await BackendConfigService.setUseHttps(uri.scheme == 'https');
    } catch (e) {
      // SharedPreferences not available in unit tests - that's okay
      // The backend config might already be set or will use defaults
      print('⚠️ Could not set backend config (SharedPreferences not available in tests): $e');
      print('   Continuing with existing/default backend configuration...');
    }
    
    _initialized = true;
    print('✅ AppInstance $id initialized');
  }
  
  /// Login to the real server
  /// Note: All instances share the same auth state (AuthService is static)
  /// This is fine for testing sync scenarios
  Future<void> login() async {
    if (!_initialized) {
      throw StateError('AppInstance must be initialized before login');
    }
    
    print('🔐 AppInstance $id: Logging in as $username...');
    
    try {
      // Use AuthService.login which handles everything (SharedPreferences works in integration tests)
      final result = await AuthService.login(username, password);
      
      if (result['success'] == true) {
        print('✅ AppInstance $id: Login successful');
        
        // Store userId from login result
        final loggedInUserId = result['user_id'] as String?;
        if (loggedInUserId != null) {
          // userId is stored in AppInstance but we can't modify final fields
          // It's stored in AuthService.getUserId() which we'll use
          print('✅ AppInstance $id: User ID: $loggedInUserId');
        }
        
        // Set wallet if provided
        final currentWalletId = walletId;
        if (currentWalletId != null) {
          await WalletService.setCurrentWalletId(currentWalletId);
          print('✅ AppInstance $id: Wallet set to: $currentWalletId');
          
          // Initialize namespaced boxes for this user and wallet
          final userId = await AuthService.getUserId();
          if (userId != null) {
            await DummyDataService.initializeForUserAndWallet(userId, currentWalletId);
            print('✅ AppInstance $id: Initialized namespaced boxes for user $userId and wallet $currentWalletId');
          }
        } else {
          // Try to get first wallet and set it
          try {
            final wallets = await WalletService.getUserWallets();
            if (wallets.isNotEmpty) {
              await WalletService.setCurrentWalletId(wallets.first.id);
              final userId = await AuthService.getUserId();
              if (userId != null) {
                await DummyDataService.initializeForUserAndWallet(userId, wallets.first.id);
                print('✅ AppInstance $id: Auto-selected wallet: ${wallets.first.id}');
              }
            }
          } catch (e) {
            print('⚠️ AppInstance $id: Could not set wallet: $e');
          }
        }
        
        // Skip WebSocket connection during login to speed up tests
        // WebSocket is not critical for sync (works over HTTP)
        // Sync loops will handle synchronization automatically
        print('⏭️ AppInstance $id: Skipping WebSocket connection (not needed for sync tests)');
        
        // Skip initial sync during login to speed up tests
        // Sync loops will handle synchronization automatically
        print('⏭️ AppInstance $id: Skipping initial sync (sync loops will handle it)');
        print('✅ AppInstance $id: Login complete');
      } else {
        throw Exception('Login failed: ${result['error'] ?? 'Unknown error'}');
      }
    } catch (e) {
      print('❌ AppInstance $id: Login failed: $e');
      rethrow;
    }
  }
  
  /// Wait for WebSocket connection
  Future<void> waitForConnection({Duration timeout = const Duration(seconds: 10)}) async {
    final startTime = DateTime.now();
    while (DateTime.now().difference(startTime) < timeout) {
      if (RealtimeService.isConnected) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
    throw TimeoutException('WebSocket connection timeout', timeout);
  }
  
  /// Create a contact
  Future<Contact> createContact({
    required String name,
    String? username,
    String? phone,
    String? email,
  }) async {
    // Use proper UUID format (server requires UUIDs)
    final contact = Contact(
      id: const Uuid().v4(), // Generate proper UUID
      name: name,
      username: username,
      phone: phone,
      email: email,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    
    return await LocalDatabaseServiceV2.createContact(contact);
  }
  
  /// Update a contact
  Future<void> updateContact(String contactId, Map<String, dynamic> updates) async {
    final contact = await LocalDatabaseServiceV2.getContact(contactId);
    if (contact == null) {
      throw Exception('Contact not found: $contactId');
    }
    
    // Apply updates
    final updated = Contact(
      id: contact.id,
      name: updates['name'] ?? contact.name,
      username: updates['username'] ?? contact.username,
      phone: updates['phone'] ?? contact.phone,
      email: updates['email'] ?? contact.email,
      createdAt: contact.createdAt,
      updatedAt: DateTime.now(),
    );
    
    await LocalDatabaseServiceV2.updateContact(updated);
  }
  
  /// Delete a contact
  Future<void> deleteContact(String contactId) async {
    await LocalDatabaseServiceV2.deleteContact(contactId);
  }
  
  /// Create a transaction
  Future<Transaction> createTransaction({
    required String contactId,
    required TransactionDirection direction,
    required int amount,
    String? description,
  }) async {
    final transaction = Transaction(
      id: const Uuid().v4(), // Use UUID for transaction ID (server requires UUIDs)
      contactId: contactId,
      type: TransactionType.money,
      direction: direction,
      amount: amount,
      currency: 'IQD',
      description: description,
      transactionDate: DateTime.now(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    
    return await LocalDatabaseServiceV2.createTransaction(transaction);
  }
  
  /// Update a transaction
  Future<void> updateTransaction(String transactionId, Map<String, dynamic> updates) async {
    // Retry mechanism: wait for transaction to appear (state rebuild might be in progress)
    Transaction? transaction;
    for (int i = 0; i < 10; i++) {
      transaction = await LocalDatabaseServiceV2.getTransaction(transactionId);
      if (transaction != null) {
        break;
      }
      // Wait a bit before retrying (state rebuild might be in progress)
      await Future.delayed(Duration(milliseconds: 50 * (i + 1)));
    }
    
    if (transaction == null) {
      throw Exception('Transaction not found: $transactionId');
    }
    
    // Apply updates
    final updated = Transaction(
      id: transaction.id,
      contactId: transaction.contactId,
      type: transaction.type,
      direction: transaction.direction,
      amount: updates['amount'] ?? transaction.amount,
      currency: transaction.currency,
      description: updates['description'] ?? transaction.description,
      transactionDate: updates['transactionDate'] ?? transaction.transactionDate,
      createdAt: transaction.createdAt,
      updatedAt: DateTime.now(),
    );
    
    await LocalDatabaseServiceV2.updateTransaction(updated);
  }
  
  /// Delete a transaction
  Future<void> deleteTransaction(String transactionId) async {
    await LocalDatabaseServiceV2.deleteTransaction(transactionId);
  }
  
  /// Undo last action for a contact
  Future<void> undoContactAction(String contactId) async {
    await LocalDatabaseServiceV2.undoContactAction(contactId);
  }
  
  /// Undo last action for a transaction
  Future<void> undoTransactionAction(String transactionId) async {
    await LocalDatabaseServiceV2.undoTransactionAction(transactionId);
  }
  
  /// Get all events
  Future<List<Event>> getEvents() async {
    return await EventStoreService.getAllEvents();
  }
  
  /// Get unsynced events
  Future<List<Event>> getUnsyncedEvents() async {
    return await EventStoreService.getUnsyncedEvents();
  }
  
  /// Get contacts
  Future<List<Contact>> getContacts() async {
    return await LocalDatabaseServiceV2.getContacts();
  }
  
  /// Get transactions
  Future<List<Transaction>> getTransactions() async {
    return await LocalDatabaseServiceV2.getTransactions();
  }
  
  /// Get current state
  Future<Map<String, dynamic>> getState() async {
    final contacts = await getContacts();
    final transactions = await getTransactions();
    final events = await getEvents();
    final unsynced = await getUnsyncedEvents();
    
    return {
      'contacts': contacts.length,
      'transactions': transactions.length,
      'events': events.length,
      'unsynced_events': unsynced.length,
      'is_online': !_simulatedOffline && RealtimeService.isConnected,
    };
  }
  
  /// Simulate going offline
  Future<void> goOffline() async {
    if (_simulatedOffline) return;
    
    _simulatedOffline = true;
    print('📴 AppInstance $id: Simulating offline...');
    
    // 1. Block all network calls
    networkInterceptor?.blockNetwork();
    
    // 2. Clear server reachability cache to force fresh check
    // Note: This helps, but HTTP calls still bypass the interceptor
    SyncServiceV2.clearServerReachabilityCache();
    
    // 3. Disconnect WebSocket
    await RealtimeService.disconnect();
    
    // 4. Prevent auto-reconnection
    RealtimeServiceTestHelper.setAutoReconnectEnabled(false);
    
    // 5. Clear any pending reconnection timers
    RealtimeServiceTestHelper.cancelReconnectTimers();
    
    print('📴 AppInstance $id: Simulated offline - all connections blocked');
    print('⚠️ Note: NetworkInterceptor exists but HTTP calls bypass it - offline simulation is limited');
  }
  
  /// Simulate going online
  Future<void> goOnline() async {
    if (!_simulatedOffline) return;
    
    _simulatedOffline = false;
    print('📶 AppInstance $id: Simulating online...');
    
    // 1. Re-enable auto-reconnection
    RealtimeServiceTestHelper.setAutoReconnectEnabled(true);
    
    // 2. Unblock network calls
    networkInterceptor?.unblockNetwork();
    
    // 3. Skip WebSocket connection in tests (not needed for sync tests)
    // WebSocket is not critical for sync (works over HTTP)
    print('⏭️ AppInstance $id: Skipping WebSocket connection (not needed for sync tests)');
    
    // 4. Trigger onBackOnline to reset backoff and sync
    SyncServiceV2.onBackOnline();
    
    print('📶 AppInstance $id: Simulated online - connections restored');
  }
  
  /// Clean disconnect
  Future<void> disconnect() async {
    await RealtimeService.disconnect();
    RealtimeServiceTestHelper.reset();
    networkInterceptor?.unblockNetwork();
    _simulatedOffline = false;
  }
  
  /// Cleanup resources
  /// Note: We don't close shared boxes as other instances may be using them
  Future<void> cleanup() async {
    await disconnect();
    _initialized = false;
  }
  
  /// Clear all data for this instance (for test isolation)
  /// Note: Since boxes are shared, this clears for all instances
  Future<void> clearData() async {
    try {
      if (contactsBox != null && contactsBox!.isOpen) {
        await contactsBox!.clear();
      }
      if (transactionsBox != null && transactionsBox!.isOpen) {
        await transactionsBox!.clear();
      }
      if (eventsBox != null && eventsBox!.isOpen) {
        await eventsBox!.clear();
      }
    } catch (e) {
      print('⚠️ Error clearing data: $e');
    }
  }
}