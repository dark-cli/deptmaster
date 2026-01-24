import 'package:flutter/foundation.dart' show kIsWeb;
import 'backend_config_service.dart';

/// Tracks connection state and only logs when state changes (offline <-> online)
class ConnectionStateTracker {
  static bool? _lastKnownState; // null = unknown, true = online, false = offline
  static String? _lastServerUrl;

  /// Log connection state change (only when state actually changes)
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
    if (_lastKnownState != isOnline || _lastServerUrl != serverUrl) {
      _lastKnownState = isOnline;
      _lastServerUrl = serverUrl;
      
      if (isOnline) {
        print('🟢 Back online - connected to $serverUrl');
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
