import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:debt_tracker_mobile/api.dart';
import 'package:debt_tracker_mobile/models/contact.dart';
import 'package:debt_tracker_mobile/models/transaction.dart';
import 'package:debt_tracker_mobile/models/event.dart';
import 'package:debt_tracker_mobile/models/wallet.dart';
import 'network_interceptor.dart';
import 'realtime_service_test_helper.dart';

/// Simulated app instance using Api (Rust backend). All instances share the same process storage.
class AppInstance {
  final String id;
  final String serverUrl;
  final String username;
  final String password;
  final String hivePath;
  final String? userId;
  final String? walletId;

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

  static Future<AppInstance> create({
    required String id,
    String serverUrl = 'http://localhost:8000',
    String username = 'max',
    String password = '12345678',
    String? walletId,
  }) async {
    return AppInstance(
      id: id,
      serverUrl: serverUrl,
      username: username,
      password: password,
      hivePath: '',
      walletId: walletId,
    );
  }

  Future<void> initialize() async {
    if (_initialized) return;

    print('🔧 Initializing AppInstance $id...');

    try {
      Hive.registerAdapter(ContactAdapter());
    } catch (_) {}
    try {
      Hive.registerAdapter(TransactionAdapter());
    } catch (_) {}
    try {
      Hive.registerAdapter(TransactionTypeAdapter());
    } catch (_) {}
    try {
      Hive.registerAdapter(TransactionDirectionAdapter());
    } catch (_) {}
    try {
      Hive.registerAdapter(EventAdapter());
    } catch (_) {}
    try {
      Hive.registerAdapter(WalletAdapter());
    } catch (_) {}

    await Api.init();
    final dir = await getTemporaryDirectory();
    await Api.initStorage(dir.path);

    networkInterceptor = NetworkInterceptor();

    final uri = Uri.parse(serverUrl);
    await Api.setBackendConfig(uri.host, uri.port);
    await Api.setUseHttps(uri.scheme == 'https');

    _initialized = true;
    print('✅ AppInstance $id initialized');
  }

  Future<void> login() async {
    if (!_initialized) throw StateError('AppInstance must be initialized before login');

    print('🔐 AppInstance $id: Logging in as $username...');

    try {
      await Api.login(username, password);
      print('✅ AppInstance $id: Login successful');

      final currentWalletId = walletId;
      if (currentWalletId != null) {
        await Api.setCurrentWalletId(currentWalletId);
        print('✅ AppInstance $id: Wallet set to: $currentWalletId');
      } else {
        try {
          final wallets = await Api.getWallets();
          if (wallets.isNotEmpty) {
            final firstId = wallets.first['id'] as String?;
            if (firstId != null) {
              await Api.setCurrentWalletId(firstId);
              print('✅ AppInstance $id: Auto-selected wallet: $firstId');
            }
          }
        } catch (e) {
          print('⚠️ AppInstance $id: Could not set wallet: $e');
        }
      }

      print('✅ AppInstance $id: Login complete');
    } catch (e) {
      print('❌ AppInstance $id: Login failed: $e');
      rethrow;
    }
  }

  Future<void> waitForConnection({Duration timeout = const Duration(seconds: 10)}) async {
    final startTime = DateTime.now();
    while (DateTime.now().difference(startTime) < timeout) {
      if (Api.isRealtimeConnected) return;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    throw TimeoutException('WebSocket connection timeout', timeout);
  }

  Future<Contact> createContact({
    required String name,
    String? username,
    String? phone,
    String? email,
  }) async {
    final jsonStr = await Api.createContact(
      name: name,
      username: username,
      phone: phone,
      email: email,
    );
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    return Contact.fromJson(map);
  }

  Future<void> updateContact(String contactId, Map<String, dynamic> updates) async {
    final contactJson = await Api.getContact(contactId);
    if (contactJson == null) throw Exception('Contact not found: $contactId');
    final contact = Contact.fromJson(jsonDecode(contactJson) as Map<String, dynamic>);
    await Api.updateContact(
      id: contactId,
      name: updates['name'] ?? contact.name,
      username: updates['username'] ?? contact.username,
      phone: updates['phone'] ?? contact.phone,
      email: updates['email'] ?? contact.email,
    );
  }

  Future<void> deleteContact(String contactId) async {
    await Api.deleteContact(contactId);
  }

  Future<Transaction> createTransaction({
    required String contactId,
    required TransactionDirection direction,
    required int amount,
    String? description,
  }) async {
    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final jsonStr = await Api.createTransaction(
      contactId: contactId,
      type: 'money',
      direction: direction == TransactionDirection.owed ? 'owed' : 'lent',
      amount: amount,
      currency: 'IQD',
      description: description,
      transactionDate: dateStr,
      dueDate: null,
    );
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    return Transaction.fromJson(map);
  }

  Future<void> updateTransaction(String transactionId, Map<String, dynamic> updates) async {
    Transaction? transaction;
    for (int i = 0; i < 10; i++) {
      final jsonStr = await Api.getTransaction(transactionId);
      if (jsonStr != null) {
        transaction = Transaction.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
        break;
      }
      await Future.delayed(Duration(milliseconds: 50 * (i + 1)));
    }
    if (transaction == null) throw Exception('Transaction not found: $transactionId');
    final now = DateTime.now();
    final dateStr = transaction.transactionDate.toIso8601String().split('T')[0];
    await Api.updateTransaction(
      id: transactionId,
      contactId: transaction.contactId,
      type: 'money',
      direction: transaction.direction == TransactionDirection.owed ? 'owed' : 'lent',
      amount: updates['amount'] ?? transaction.amount,
      currency: transaction.currency,
      description: updates['description'] ?? transaction.description,
      transactionDate: dateStr,
      dueDate: transaction.dueDate?.toIso8601String().split('T')[0],
    );
  }

  Future<void> deleteTransaction(String transactionId) async {
    await Api.deleteTransaction(transactionId);
  }

  Future<void> undoContactAction(String contactId) async {
    await Api.undoContactAction(contactId);
  }

  Future<void> undoTransactionAction(String transactionId) async {
    await Api.undoTransactionAction(transactionId);
  }

  Future<List<Event>> getEvents() async {
    final jsonStr = await Api.getEvents();
    final list = jsonDecode(jsonStr) as List<dynamic>? ?? [];
    return list.map((e) => Event.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Unsynced events are not exposed by Api; assume synced after manualSync.
  Future<List<Event>> getUnsyncedEvents() async {
    return [];
  }

  Future<List<Contact>> getContacts() async {
    final jsonStr = await Api.getContacts();
    final list = jsonDecode(jsonStr) as List<dynamic>? ?? [];
    return list.map((e) => Contact.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Transaction>> getTransactions() async {
    final jsonStr = await Api.getTransactions();
    final list = jsonDecode(jsonStr) as List<dynamic>? ?? [];
    return list.map((e) => Transaction.fromJson(e as Map<String, dynamic>)).toList();
  }

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
      'is_online': !_simulatedOffline && Api.isRealtimeConnected,
    };
  }

  Future<void> goOffline() async {
    if (_simulatedOffline) return;
    _simulatedOffline = true;
    print('📴 AppInstance $id: Simulating offline...');
    networkInterceptor?.blockNetwork();
    await Api.disconnectRealtime();
    RealtimeServiceTestHelper.setAutoReconnectEnabled(false);
    RealtimeServiceTestHelper.cancelReconnectTimers();
    print('📴 AppInstance $id: Simulated offline');
  }

  Future<void> goOnline() async {
    if (!_simulatedOffline) return;
    _simulatedOffline = false;
    print('📶 AppInstance $id: Simulating online...');
    RealtimeServiceTestHelper.setAutoReconnectEnabled(true);
    networkInterceptor?.unblockNetwork();
    print('📶 AppInstance $id: Simulated online');
  }

  Future<void> disconnect() async {
    await Api.disconnectRealtime();
    RealtimeServiceTestHelper.reset();
    networkInterceptor?.unblockNetwork();
    _simulatedOffline = false;
  }

  Future<void> cleanup() async {
    await disconnect();
    _initialized = false;
  }

  Future<void> clearData() async {
    try {
      if (contactsBox != null && contactsBox!.isOpen) await contactsBox!.clear();
      if (transactionsBox != null && transactionsBox!.isOpen) await transactionsBox!.clear();
      if (eventsBox != null && eventsBox!.isOpen) await eventsBox!.clear();
    } catch (_) {}
  }

  Future<void> sync() async {
    await Api.manualSync();
  }
}
