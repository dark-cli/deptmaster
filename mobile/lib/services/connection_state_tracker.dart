// ignore_for_file: unused_local_variable

import 'package:flutter/foundation.dart' show kIsWeb;
import 'backend_config_service.dart';
import 'sync_service_v2.dart';

/// Tracks connection state and only logs when state changes (offline <-> online)
class ConnectionStateTracker {
  static bool? _lastKnownState; // null = unknown, true = online, false = offline
  static String? _lastServerUrl;

  /// Log connection state change (only when state actually changes)
  /// Also triggers sync when coming back online
  static Future<void> logStateChange(bool isOnline) async {
    // Get server URL for logging
    String serverUrl = 'server';
    if (!kIsWeb) {
      try {
        final ip = await BackendConfigService.getBackendIp();
        final port = await BackendConfigService.getBackendPort();
        serverUrl = '$ip:$port';
      } catch (_) {
        // Use default if config unavailable
      }
    }

    // Track if we were offline before this state change
    final wasOffline = _lastKnownState == false;
    final stateChanged = _lastKnownState != isOnline || _lastServerUrl != serverUrl;
    
    if (stateChanged) {
      _lastKnownState = isOnline;
      _lastServerUrl = serverUrl;
      
      if (isOnline) {
        print('🟢 Back online - connected to $serverUrl');
        
        // Always trigger sync when coming back online
        // This ensures events created offline are synced when reconnecting
        // Trigger immediately (no delay) for faster sync
        if (!kIsWeb) {
          print('🔄 Triggering sync immediately after coming back online...');
          SyncServiceV2.manualSync().catchError((e) {
            // Check if it's an auth error
            final errorStr = e.toString();
            if (!errorStr.contains('Authentication') && 
                !errorStr.contains('expired') &&
                !errorStr.contains('Connection refused') &&
                !errorStr.contains('Failed host lookup') &&
                !errorStr.contains('Network is unreachable')) {
              print('⚠️ Sync error after coming online: $e');
            }
          });
        }
      } else {
        print('🔴 Gone offline - disconnected from $serverUrl');
      }
    } else if (isOnline && _lastKnownState == null) {
      // First time tracking state and we're online - trigger sync to be safe
      // This handles the case where app was started while already online
      // Trigger immediately (no delay) for faster sync
      if (!kIsWeb) {
        print('🔄 First connection detected - triggering sync immediately...');
        SyncServiceV2.manualSync().catchError((e) {
          final errorStr = e.toString();
          if (!errorStr.contains('Authentication') && 
              !errorStr.contains('expired') &&
              !errorStr.contains('Connection refused') &&
              !errorStr.contains('Failed host lookup') &&
              !errorStr.contains('Network is unreachable')) {
            print('⚠️ Sync error on first connection: $e');
          }
        });
      }
    }
  }

  /// Reset state (useful for testing or reconnection)
  static void reset() {
    _lastKnownState = null;
    _lastServerUrl = null;
  }
}