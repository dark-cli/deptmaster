import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_service.dart';
import 'backend_config_service.dart';
import 'local_database_service.dart';
import 'sync_service.dart';

class RealtimeService {
  static WebSocketChannel? _channel;
  static StreamSubscription? _subscription;
  static bool _isConnected = false;
  static final List<Function(Map<String, dynamic>)> _listeners = [];

  /// Check if WebSocket is connected
  static bool get isConnected => _isConnected;

  static Future<String> get _wsUrl async {
    return await BackendConfigService.getWebSocketUrl();
  }

  static Future<void> connect() async {
    if (_isConnected && _channel != null) {
      return;
    }

    try {
      final wsUrl = await _wsUrl;
      
      // Wrap connection in try-catch to handle immediate connection failures
      try {
        _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      } catch (e) {
        // Connection failed immediately (e.g., invalid URL)
        _isConnected = false;
        if (!e.toString().contains('Connection refused')) {
          print('Failed to create WebSocket connection: $e');
        }
        return;
      }

      // Set up stream listener with error handling
      try {
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
            // Silently handle connection refused errors (backend not running)
            final errorStr = error.toString();
            if (errorStr.contains('Connection refused') || 
                errorStr.contains('Failed host lookup') ||
                errorStr.contains('Network is unreachable')) {
              _isConnected = false;
              _channel = null;
              _subscription = null;
              return; // Don't try to reconnect if server is not available
            }
            print('WebSocket error: $error');
            _isConnected = false;
            _channel = null;
            _subscription = null;
            _reconnect();
          },
          onDone: () {
            // Only log if we were previously connected
            if (_isConnected) {
              print('WebSocket closed');
            }
            _isConnected = false;
            _channel = null;
            _subscription = null;
            _reconnect();
          },
          cancelOnError: false,
        );
        
        // Mark as connected only after listener is set up successfully
        _isConnected = true;
        print('✅ WebSocket connected');

        // Trigger sync when connection is established
        if (!kIsWeb) {
          // Sync in background when connected
          SyncService.fullSync().catchError((e) {
            // Silently handle sync errors when offline
            if (!e.toString().contains('Connection refused')) {
              print('Background sync error: $e');
            }
          });
        }
      } catch (e) {
        // Stream setup failed
        _isConnected = false;
        _channel = null;
        _subscription = null;
        if (!e.toString().contains('Connection refused')) {
          print('Failed to set up WebSocket stream: $e');
        }
      }
    } catch (e) {
      // General error
      _isConnected = false;
      _channel = null;
      _subscription = null;
      if (!e.toString().contains('Connection refused')) {
        print('Failed to connect WebSocket: $e');
      }
    }
  }

  static void _reconnect() {
    Future.delayed(const Duration(seconds: 5), () {
      if (!_isConnected) {
        // Silently attempt reconnect - don't spam console if server is down
        connect().catchError((e) {
          // Silently handle reconnection errors
        });
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
      
      // Update local database using LocalDatabaseService
      if (!kIsWeb) {
        await LocalDatabaseService.syncContactsFromServer(contacts);
      }
    } catch (e) {
      // Silently handle connection errors
      final errorStr = e.toString();
      if (!errorStr.contains('Connection refused') && 
          !errorStr.contains('Failed host lookup') &&
          !errorStr.contains('Network is unreachable')) {
        print('Error syncing contact: $e');
      }
    }
  }

  static Future<void> _syncTransaction(Map<String, dynamic>? transactionData) async {
    if (transactionData == null) return;
    
    try {
      // Reload transactions from API to get latest data
      final transactions = await ApiService.getTransactions();
      
      // Update local database using LocalDatabaseService
      if (!kIsWeb) {
        await LocalDatabaseService.syncTransactionsFromServer(transactions);
      }
    } catch (e) {
      // Silently handle connection errors
      final errorStr = e.toString();
      if (!errorStr.contains('Connection refused') && 
          !errorStr.contains('Failed host lookup') &&
          !errorStr.contains('Network is unreachable')) {
        print('Error syncing transaction: $e');
      }
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
      // Not online, data stays in local database
      return;
    }

    try {
      // Use SyncService for full sync (push pending changes, then pull from server)
      if (!kIsWeb) {
        await SyncService.fullSync();
      } else {
        // Web: just reload from API
        await ApiService.getContacts();
        await ApiService.getTransactions();
      }
    } catch (e) {
      // Silently handle connection errors
      final errorStr = e.toString();
      if (!errorStr.contains('Connection refused') && 
          !errorStr.contains('Failed host lookup') &&
          !errorStr.contains('Network is unreachable')) {
        print('Error syncing when online: $e');
      }
    }
  }
}
