import 'dart:io';
import 'package:http/http.dart' as http;

/// Network interceptor for testing - simulates network failures
/// IMPORTANT: Must throw exceptions that match retry logic patterns
/// When blocked, ALL network calls fail, keeping app in offline mode
class NetworkInterceptor {
  bool _blockNetwork = false;
  
  void blockNetwork() {
    _blockNetwork = true;
    print('🚫 NetworkInterceptor: Network blocked - all calls will fail');
  }
  
  void unblockNetwork() {
    _blockNetwork = false;
    print('✅ NetworkInterceptor: Network unblocked - calls will succeed');
  }
  
  bool get isBlocked => _blockNetwork;
  
  /// Wraps HTTP calls to simulate network failures
  /// Throws SocketException with "Connection refused" message
  /// This matches the retry logic's network error detection:
  /// - sync_service_v2.dart checks for "connection refused" or "socketexception"
  /// - Returns SyncResult.failed which triggers retry loops
  /// - Backoff logic is triggered correctly
  /// - IMPORTANT: Will ALWAYS fail while blocked, even on retries
  Future<http.Response> intercept(Future<http.Response> Function() call) async {
    if (_blockNetwork) {
      // Throw SocketException with "Connection refused" message
      // This matches the pattern checked in sync_service_v2.dart line 220-224
      // This will fail EVERY time while blocked, keeping app offline
      throw SocketException('Connection refused');
    }
    return await call();
  }
  
  /// Intercept server reachability check
  /// Returns false when network is blocked
  /// IMPORTANT: Will ALWAYS return false while blocked, even on retries
  Future<bool> interceptReachabilityCheck(Future<bool> Function() check) async {
    if (_blockNetwork) {
      return false; // Server appears unreachable - will keep failing
    }
    return await check();
  }
  
  /// Intercept WebSocket connection attempts
  /// Throws exception when network is blocked
  Future<void> interceptWebSocketConnect(Future<void> Function() connect) async {
    if (_blockNetwork) {
      throw SocketException('Connection refused');
    }
    return await connect();
  }
}
