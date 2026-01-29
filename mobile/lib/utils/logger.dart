import 'package:flutter/foundation.dart' show kDebugMode;

/// Simple logger utility that can be toggled on/off
class Logger {
  static const bool _enabled = kDebugMode; // Only log in debug mode
  static const bool _verboseEnabled = false; // Set to true for verbose logging
  
  static void log(String message, {bool verbose = false}) {
    if (!_enabled) return;
    if (verbose && !_verboseEnabled) return;
    print(message);
  }
  
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    if (!_enabled) return;
    print('❌ $message');
    if (error != null) {
      print('   Error: $error');
    }
    if (stackTrace != null) {
      print('   Stack: $stackTrace');
    }
  }
  
  static void warn(String message) {
    if (!_enabled) return;
    print('⚠️ $message');
  }
  
  static void info(String message) {
    if (!_enabled) return;
    print('ℹ️ $message');
  }
  
  static void success(String message) {
    if (!_enabled) return;
    print('✅ $message');
  }
  
  static void debug(String message, {bool verbose = false}) {
    if (!_enabled) return;
    if (verbose && !_verboseEnabled) return;
    print('🔍 $message');
  }
}
