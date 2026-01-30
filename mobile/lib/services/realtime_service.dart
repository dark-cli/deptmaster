import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_service.dart';
import 'backend_config_service.dart';
import 'sync_service_v2.dart' show SyncServiceV2, SyncResult;
import 'state_builder.dart';
import 'event_store_service.dart';
import 'connection_manager.dart';
import 'connection_state_tracker.dart';
import 'auth_service.dart';

class RealtimeService {
  static WebSocketChannel? _channel;
  static StreamSubscription? _subscription;
  static bool _isConnected = false;
  static bool _isConnecting = false; // Guard to prevent multiple simultaneous connections
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
    // If we are already connected, don't reconnect.
    if (_isConnected && _channel != null) {
      print('🔌 WebSocket already connected, skipping connection attempt');
      return;
    }
    
    // Prevent multiple simultaneous connection attempts
    if (_isConnecting) {
      print('🔌 WebSocket connection already in progress, skipping duplicate attempt');
      return;
    }
    
    _isConnecting = true;

    // Track if we were offline before connecting
    final wasOffline = !_isConnected;

    // Only attempt WebSocket connection if the user is logged in (has a token)
    final token = await AuthService.getToken();
    if (token == null || token.isEmpty) {
      // No auth token -> don't spam the server with unauthorized WebSocket attempts
      print('⚠️ Cannot connect WebSocket - no auth token available');
      _isConnecting = false; // Clear connecting flag if no token
      _isConnected = false;
      _channel = null;
      _subscription = null;
      return;
    }
    
    print('🔌 Attempting WebSocket connection with token (length: ${token.length})...');

    // Wrap entire connection in try-catch to catch all exceptions
    try {
      final wsUrl = await _wsUrl;
      
      // Append token as query parameter (backend supports token via query param or Authorization header)
      // Use Uri.parse and Uri.replace to properly encode the token
      final uri = Uri.parse(wsUrl);
      final authenticatedUrl = uri.replace(queryParameters: {
        ...uri.queryParameters,
        'token': token, // Uri.replace will automatically encode the token
      });
      
      print('🔌 Connecting to WebSocket: ${authenticatedUrl.toString().replaceAll(RegExp(r'token=[^&]+'), 'token=***')}');
      
      // Create channel - WebSocketChannel.connect() throws asynchronously
      // The PlatformDispatcher.onError in main.dart will catch and suppress it
      WebSocketChannel? channel;
      try {
        // Include JWT token as query parameter so backend can authenticate /ws
        channel = WebSocketChannel.connect(authenticatedUrl);
      } catch (e) {
        // Synchronous error - handle gracefully without crashing
        print('WebSocket connection error (sync): $e');
        _isConnecting = false; // Clear connecting flag on error
        if (_isConnected) {
          ConnectionStateTracker.logStateChange(false);
          _isConnected = false;
        }
        _reconnect();
        return;
      }
      
      // Wrap channel operations in additional error handling
      if (channel == null) {
        _isConnecting = false; // Clear connecting flag if channel is null
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
              _isConnecting = false; // Clear connecting flag on successful connection
              _isConnected = true;
              _channel = channel;
              
              print('✅ WebSocket connected successfully for real-time updates');
              
              // Log state change (offline -> online) - don't await in callback
              ConnectionStateTracker.logStateChange(true);
              
              // Always trigger sync when reconnecting to sync offline events
              // This ensures events created offline are synced when back online
              if (!kIsWeb) {
                print('🔄 Connection established - triggering sync...');
                SyncServiceV2.onBackOnline();
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
            
            // Check if it's an authentication error (401)
            final errorStr = error.toString().toLowerCase();
            if (errorStr.contains('401') || errorStr.contains('unauthorized')) {
              print('⚠️ WebSocket authentication failed (401) - token may be expired');
              _isConnecting = false; // Clear connecting flag
              // Don't reconnect if auth failed - user needs to login again
              // The app will reconnect when user logs in again
              return;
            }
            
            // Log state change (online -> offline) only if we were connected
            if (wasConnected) {
              ConnectionStateTracker.logStateChange(false);
            }
            
            _reconnect();
          },
          onDone: () {
            final wasConnected = _isConnected;
            _isConnected = false;
            _isConnecting = false; // Clear connecting flag when done
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
        _isConnecting = false; // Clear connecting flag on error
        if (_isConnected) {
          ConnectionStateTracker.logStateChange(false);
        }
        _isConnected = false;
        _channel = null;
        _subscription = null;
        if (listenerSetup) {
          try {
            _subscription?.cancel();
          } catch (_) {
            // Ignore cancel errors
          }
        }
        _reconnect();
      }
    } catch (e) {
      // Catch any other exceptions - handle gracefully without crashing
      _isConnecting = false; // Clear connecting flag on error
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
    // Check if user is still logged in before reconnecting
    AuthService.getToken().then((token) {
      if (token == null || token.isEmpty) {
        // User logged out, don't reconnect
        print('⚠️ Not reconnecting WebSocket - user logged out');
        return;
      }
      
      // Auto-reconnect with 5 second delay to avoid spamming server
      Future.delayed(const Duration(seconds: 5), () {
        if (!_isConnected) {
          // Silently attempt reconnect - don't spam console if server is down
          connect().then((_) {
            // After successful reconnection, sync will be triggered automatically
            // by the connection handler
          }).catchError((e) {
            // Check if it's an auth error - don't retry if auth failed
            final errorStr = e.toString().toLowerCase();
            if (!errorStr.contains('401') && !errorStr.contains('unauthorized')) {
              // Retry connection after delay (only if not auth error)
              _reconnect();
            } else {
              print('⚠️ WebSocket reconnection failed due to auth error - stopping retries');
            }
          });
        }
      });
    }).catchError((e) {
      // If we can't get token, don't reconnect
      print('⚠️ Cannot check auth token for WebSocket reconnection: $e');
    });
  }

  static void _handleRealtimeUpdate(Map<String, dynamic> data) {
    // Trigger server-to-local sync for WebSocket notifications
    // WebSocket messages indicate server-side changes
    if (!kIsWeb) {
      // Trigger server to local sync (to get new events from server)
      SyncServiceV2.handleServerToLocalSyncRequest();
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
    try {
      await _subscription?.cancel();
    } catch (_) {
      // Ignore cancel errors
    }
    try {
      await _channel?.sink.close();
    } catch (_) {
      // Ignore close errors
    }
    _channel = null;
    _isConnected = false;
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
