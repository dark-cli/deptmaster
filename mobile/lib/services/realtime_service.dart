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

class RealtimeService {
  static WebSocketChannel? _channel;
  static StreamSubscription? _subscription;
  static bool _isConnected = false;
  static final List<Function(Map<String, dynamic>)> _listeners = [];

  static String get _wsUrl {
    if (kIsWeb) {
      return 'ws://localhost:8000/ws';
    } else if (Platform.isAndroid) {
      return 'ws://10.0.2.2:8000/ws';
    } else {
      return 'ws://localhost:8000/ws';
    }
  }

  static Future<void> connect() async {
    if (_isConnected && _channel != null) {
      return;
    }

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
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
          print('WebSocket error: $error');
          _isConnected = false;
          _reconnect();
        },
        onDone: () {
          print('WebSocket closed');
          _isConnected = false;
          _reconnect();
        },
      );
    } catch (e) {
      print('Failed to connect WebSocket: $e');
      _isConnected = false;
    }
  }

  static void _reconnect() {
    Future.delayed(const Duration(seconds: 3), () {
      if (!_isConnected) {
        print('Reconnecting WebSocket...');
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
