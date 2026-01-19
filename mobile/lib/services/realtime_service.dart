import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/contact.dart';
import '../models/transaction.dart';
import 'api_service.dart';
import 'dummy_data_service.dart';
import 'backend_config_service.dart';

class RealtimeService {
  static WebSocketChannel? _channel;
  static StreamSubscription? _subscription;
  static bool _isConnected = false;
  static final List<Function(Map<String, dynamic>)> _listeners = [];

  static Future<String> get _wsUrl async {
    return await BackendConfigService.getWebSocketUrl();
  }

  static Future<void> connect() async {
    if (_isConnected && _channel != null) {
      return;
    }

    try {
      final wsUrl = await _wsUrl;
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _isConnected = true;
      print('✅ WebSocket connected');

      _subscription = _channel!.stream.listen(
        (message) {
          try {
            final data = json.decode(message as String);
            _notifyListeners(data);
            _handleRealtimeUpdate(data);
          } catch (e) {
            print('Error parsing WebSocket message: $e');
          }
        },
        onError: (error) {
          // Only log if it's not a connection refused error (backend not running)
          if (error.toString().contains('Connection refused')) {
            // Silently handle - backend server is not running
            _isConnected = false;
            return; // Don't try to reconnect if server is not running
          }
          print('WebSocket error: $error');
          _isConnected = false;
          _reconnect();
        },
        onDone: () {
          // Only log if we were previously connected
          if (_isConnected) {
            print('WebSocket closed');
          }
          _isConnected = false;
          _reconnect();
        },
      );
    } catch (e) {
      // Only log if it's not a connection refused error
      if (!e.toString().contains('Connection refused')) {
        print('Failed to connect WebSocket: $e');
      }
      _isConnected = false;
    }
  }

  static void _reconnect() {
    Future.delayed(const Duration(seconds: 3), () {
      if (!_isConnected) {
        // Silently attempt reconnect - don't spam console if server is down
        connect();
      }
    });
  }

  static void _handleRealtimeUpdate(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    if (type == null) return;

    switch (type) {
      case 'contact_created':
      case 'contact_updated':
        _syncContact(data['data']);
        break;
      case 'transaction_created':
      case 'transaction_updated':
      case 'transaction_deleted':
        _syncTransaction(data['data']);
        break;
    }
  }

  static Future<void> _syncContact(Map<String, dynamic>? contactData) async {
    if (contactData == null) return;
    
    try {
      // Reload contacts from API to get latest data
      final contacts = await ApiService.getContacts();
      
      // Update Hive (for offline storage) - always update for offline-first
      if (!kIsWeb) {
        try {
          final contactsBox = Hive.box<Contact>(DummyDataService.contactsBoxName);
          await contactsBox.clear();
          for (var contact in contacts) {
            await contactsBox.put(contact.id, contact);
          }
        } catch (e) {
          // Hive might not be initialized, that's okay
          print('Could not update Hive for contacts: $e');
        }
      }
    } catch (e) {
      print('Error syncing contact: $e');
    }
  }

  static Future<void> _syncTransaction(Map<String, dynamic>? transactionData) async {
    if (transactionData == null) return;
    
    try {
      // Reload transactions from API to get latest data
      final transactions = await ApiService.getTransactions();
      
      // Update Hive (for offline storage) - always update for offline-first
      if (!kIsWeb) {
        try {
          final transactionsBox = Hive.box<Transaction>(DummyDataService.transactionsBoxName);
          await transactionsBox.clear();
          for (var transaction in transactions) {
            await transactionsBox.put(transaction.id, transaction);
          }
        } catch (e) {
          // Hive might not be initialized, that's okay
          print('Could not update Hive for transactions: $e');
        }
      }
    } catch (e) {
      print('Error syncing transaction: $e');
    }
  }

  static void addListener(Function(Map<String, dynamic>) listener) {
    _listeners.add(listener);
  }

  static void removeListener(Function(Map<String, dynamic>) listener) {
    _listeners.remove(listener);
  }

  static void _notifyListeners(Map<String, dynamic> data) {
    for (var listener in _listeners) {
      listener(data);
    }
  }

  static Future<void> disconnect() async {
    await _subscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    print('WebSocket disconnected');
  }

  static Future<void> syncWhenOnline() async {
    if (!_isConnected) {
      // Not online, data stays in Hive
      return;
    }

    try {
      // Sync contacts
      final contacts = await ApiService.getContacts();
      if (!kIsWeb) {
        final contactsBox = Hive.box<Contact>(DummyDataService.contactsBoxName);
        await contactsBox.clear();
        for (var contact in contacts) {
          await contactsBox.put(contact.id, contact);
        }
      }

      // Sync transactions
      final transactions = await ApiService.getTransactions();
      if (!kIsWeb) {
        final transactionsBox = Hive.box<Transaction>(DummyDataService.transactionsBoxName);
        await transactionsBox.clear();
        for (var transaction in transactions) {
          await transactionsBox.put(transaction.id, transaction);
        }
      }

      print('✅ Synced data when coming back online');
    } catch (e) {
      print('Error syncing when online: $e');
    }
  }
}
