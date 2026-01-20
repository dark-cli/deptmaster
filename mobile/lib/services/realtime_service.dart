import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_service.dart';
import 'backend_config_service.dart';
import 'sync_service_v2.dart';
import 'state_builder.dart';
import 'event_store_service.dart';

class RealtimeService {
  static WebSocketChannel? _channel;
  static StreamSubscription? _subscription;
  static bool _isConnected = false;
  static final List<Function(Map<String, dynamic>)> _listeners = [];
  static Function(String)? _onConnectionError;

  /// Check if WebSocket is connected
  static bool get isConnected => _isConnected;

  /// Set callback for connection errors (e.g., to show toast)
  static void setErrorCallback(Function(String) callback) {
    _onConnectionError = callback;
  }

  static Future<String> get _wsUrl async {
    return await BackendConfigService.getWebSocketUrl();
  }

  static Future<void> connect() async {
    if (_isConnected && _channel != null) {
      return;
    }

    // Wrap entire connection in try-catch to catch all exceptions
    try {
      final wsUrl = await _wsUrl;
      
      // Create channel - this may throw synchronously or asynchronously
      WebSocketChannel? channel;
      try {
        channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      } catch (e) {
        // Connection failed immediately
        _handleConnectionError(_formatConnectionError(e));
        return;
      }

      // Set up stream listener with error handling
      // Use a flag to track if we've set up the listener
      bool listenerSetup = false;
      
      try {
        _subscription = channel.stream.listen(
          (message) {
            // First message confirms connection is successful
            if (!_isConnected) {
              _isConnected = true;
              _channel = channel;
              print('✅ WebSocket connected');
              
              // Trigger sync when connection is established
              if (!kIsWeb) {
                SyncServiceV2.manualSync().catchError((e) {
                  // Silently handle sync errors
                });
              }
            }
            
            try {
              final data = json.decode(message as String);
              _notifyListeners(data);
              _handleRealtimeUpdate(data);
            } catch (e) {
              print('Error parsing WebSocket message: $e');
            }
          },
          onError: (error) {
            // Handle connection errors - this catches async exceptions
            _isConnected = false;
            _channel = null;
            _subscription = null;
            
            // Extract error code and create simple message
            String message = _formatConnectionError(error);
            _handleConnectionError(message);
            
            // Only reconnect for non-network errors
            final errorStr = error.toString();
            if (!errorStr.contains('Connection refused') && 
                !errorStr.contains('Failed host lookup') &&
                !errorStr.contains('Network is unreachable') &&
                !errorStr.contains('SocketException')) {
              _reconnect();
            }
          },
          onDone: () {
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
        
        listenerSetup = true;
        _channel = channel;
        
        // Give a small delay to catch immediate connection failures
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        // Stream setup failed
        _isConnected = false;
        _channel = null;
        _subscription = null;
        if (listenerSetup) {
          _subscription?.cancel();
        }
        _handleConnectionError(_formatConnectionError(e));
      }
    } catch (e) {
      // Catch any other exceptions (including async ones that bubble up)
      _isConnected = false;
      _channel = null;
      _subscription = null;
      _handleConnectionError(_formatConnectionError(e));
    }
  }

  static void _handleConnectionError(String message) {
    // Notify callback if set (for showing toast)
    _onConnectionError?.call(message);
  }

  static String _formatConnectionError(dynamic error) {
    // Extract error code if available (works for SocketException)
    String? errorCode;
    String simpleMessage = 'Cannot connect to server';
    
    // Try to extract error code using reflection (works on all platforms)
    try {
      // Check if error has osError property (SocketException)
      if (error != null) {
        final errorStr = error.toString();
        // Extract errno from error message if present (e.g., "errno = 111")
        final errnoMatch = RegExp(r'errno\s*=\s*(\d+)').firstMatch(errorStr);
        if (errnoMatch != null) {
          errorCode = errnoMatch.group(1);
        }
      }
    } catch (_) {
      // Ignore if reflection fails
    }
    
    // Determine simple message based on error content
    final errorStr = error.toString().toLowerCase();
    
    if (errorStr.contains('connection refused')) {
      simpleMessage = 'Connection refused';
    } else if (errorStr.contains('failed host lookup') || errorStr.contains('name resolution')) {
      simpleMessage = 'Server not found';
    } else if (errorStr.contains('network is unreachable')) {
      simpleMessage = 'Network unreachable';
    } else if (errorStr.contains('timeout')) {
      simpleMessage = 'Connection timeout';
    } else {
      simpleMessage = 'Connection failed';
    }
    
    // Add error code if available
    if (errorCode != null) {
      return '$simpleMessage (Error: $errorCode)';
    }
    return simpleMessage;
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
    
    // In new architecture, we sync events, not entities
    // Just trigger a sync to pull new events from server
    if (!kIsWeb) {
      SyncServiceV2.manualSync().catchError((e) {
        // Silently handle sync errors
      });
    }
  }

  static Future<void> _syncTransaction(Map<String, dynamic>? transactionData) async {
    if (transactionData == null) return;
    
    // In new architecture, we sync events, not entities
    // Just trigger a sync to pull new events from server
    if (!kIsWeb) {
      SyncServiceV2.manualSync().catchError((e) {
        // Silently handle sync errors
      });
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
      // Use SyncServiceV2 for sync (hash-based, event-driven)
      if (!kIsWeb) {
        await SyncServiceV2.manualSync();
      } else {
        // Web: just reload from API (web doesn't use local storage)
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
