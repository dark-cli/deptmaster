import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_service.dart';
import 'backend_config_service.dart';
import 'sync_service_v2.dart';
import 'state_builder.dart';
import 'event_store_service.dart';
import 'connection_manager.dart';
import 'connection_state_tracker.dart';

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
      
      // Create channel - WebSocketChannel.connect() throws asynchronously
      // The PlatformDispatcher.onError in main.dart will catch and suppress it
      WebSocketChannel? channel;
      try {
        channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      } catch (e) {
        // Synchronous error - log state change if needed
        if (_isConnected) {
          ConnectionStateTracker.logStateChange(false);
          _isConnected = false;
        }
        _reconnect();
        return;
      }
      
      // Check if channel is null (shouldn't happen, but safety check)
      if (channel == null) {
        if (_isConnected) {
          ConnectionStateTracker.logStateChange(false);
          _isConnected = false;
        }
        _reconnect();
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
              
              // Log state change (offline -> online)
              ConnectionStateTracker.logStateChange(true);
              
              // Trigger sync when connection is established to sync offline events
              if (!kIsWeb) {
                // Check for unsynced events and sync them
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
            final wasConnected = _isConnected;
            _isConnected = false;
            _channel = null;
            _subscription = null;
            
            // Log state change (online -> offline) only if we were connected
            if (wasConnected) {
              ConnectionStateTracker.logStateChange(false);
            }
            
            _reconnect();
          },
          onDone: () {
            final wasConnected = _isConnected;
            _isConnected = false;
            _channel = null;
            _subscription = null;
            
            // Log state change (online -> offline) only if we were connected
            if (wasConnected) {
              ConnectionStateTracker.logStateChange(false);
            }
            
            // Auto-reconnect immediately (like Firebase)
            _reconnect();
          },
          cancelOnError: false,
        );
        
        listenerSetup = true;
        _channel = channel;
        
        // Give a small delay to catch immediate connection failures
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        // Stream setup failed - log state change if needed
        if (_isConnected) {
          ConnectionStateTracker.logStateChange(false);
        }
        _isConnected = false;
        _channel = null;
        _subscription = null;
        if (listenerSetup) {
          _subscription?.cancel();
        }
        _reconnect();
      }
    } catch (e) {
      // Catch any other exceptions - log state change if needed
      if (_isConnected) {
        ConnectionStateTracker.logStateChange(false);
      }
      _isConnected = false;
      _channel = null;
      _subscription = null;
      _reconnect();
    }
  }

  static void _handleConnectionError(String message) {
    // Notify callback if set (for showing toast)
    _onConnectionError?.call(message);
  }
  

  static void _reconnect() {
    // Auto-reconnect with 5 second delay to avoid spamming server
    Future.delayed(const Duration(seconds: 5), () {
      if (!_isConnected) {
        // Silently attempt reconnect - don't spam console if server is down
        connect().catchError((e) {
          // Retry connection after delay
          _reconnect();
        });
      }
    });
  }

  static void _handleRealtimeUpdate(Map<String, dynamic> data) {
    // Trigger immediate sync for ANY WebSocket message
    // This ensures hot updates without waiting for periodic sync
    // WebSocket messages indicate server-side changes, so sync immediately
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
