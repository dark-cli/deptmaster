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

    // Only log if state actually changed
    final wasOffline = _lastKnownState == false;
    if (_lastKnownState != isOnline || _lastServerUrl != serverUrl) {
      _lastKnownState = isOnline;
      _lastServerUrl = serverUrl;
      
      if (isOnline) {
        print('🟢 Back online - connected to $serverUrl');
        
        // Trigger sync when coming back online
        if (wasOffline && !kIsWeb) {
          print('🔄 Triggering sync after coming back online...');
          SyncServiceV2.manualSync().catchError((e) {
            // Silently handle sync errors
            print('⚠️ Sync error after coming online: $e');
          });
        }
      } else {
        print('🔴 Gone offline - disconnected from $serverUrl');
      }
    }
  }

  /// Reset state (useful for testing or reconnection)
  static void reset() {
    _lastKnownState = null;
    _lastServerUrl = null;
  }
}
