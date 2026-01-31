import 'dart:async';

/// Test helper for RealtimeService to control reconnection behavior
/// This allows us to prevent auto-reconnection during offline simulation
class RealtimeServiceTestHelper {
  static bool _autoReconnectEnabled = true;
  static final List<Timer> _reconnectTimers = [];
  
  /// Disable auto-reconnection (for offline simulation)
  static void setAutoReconnectEnabled(bool enabled) {
    _autoReconnectEnabled = enabled;
    if (!enabled) {
      cancelReconnectTimers();
    }
    print('${enabled ? "✅" : "🚫"} RealtimeServiceTestHelper: Auto-reconnect ${enabled ? "enabled" : "disabled"}');
  }
  
  /// Check if auto-reconnect is enabled
  static bool get autoReconnectEnabled => _autoReconnectEnabled;
  
  /// Cancel all pending reconnection timers
  static void cancelReconnectTimers() {
    for (final timer in _reconnectTimers) {
      timer.cancel();
    }
    _reconnectTimers.clear();
  }
  
  /// Register a reconnection timer (to be cancelled when going offline)
  static void registerTimer(Timer timer) {
    _reconnectTimers.add(timer);
  }
  
  /// Check if reconnection should be allowed
  /// This should be called before RealtimeService._reconnect() executes
  static bool shouldAllowReconnect() {
    return _autoReconnectEnabled;
  }
  
  /// Reset helper state
  static void reset() {
    _autoReconnectEnabled = true;
    cancelReconnectTimers();
  }
}
