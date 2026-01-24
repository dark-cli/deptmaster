import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'backend_config_service.dart';

/// Centralized Connection Manager
/// Handles all network connections (HTTP, WebSocket) with unified error handling
class ConnectionManager {
  /// Format connection error with service name, server URL, and error code
  static Future<String> formatConnectionError(
    dynamic error, {
    required String serviceName,
    String? serverUrl,
  }) async {
    // Extract server URL if not provided
    String url = serverUrl ?? 'server';
    if (serverUrl == null && !kIsWeb) {
      try {
        final ip = await BackendConfigService.getBackendIp();
        final port = await BackendConfigService.getBackendPort();
        url = '$ip:$port';
      } catch (_) {
        // Use default if config unavailable
      }
    }

    // Extract error code (errno) from error message
    String? errorCode;
    String errorMessage = error.toString();
    
    // Try to extract errno (e.g., "errno = 113")
    final errnoMatch = RegExp(r'errno\s*=\s*(\d+)').firstMatch(errorMessage);
    if (errnoMatch != null) {
      errorCode = errnoMatch.group(1);
    }

    // Extract OS Error message if available
    String? osError;
    final osErrorMatch = RegExp(r'OS Error:\s*([^,)]+)').firstMatch(errorMessage);
    if (osErrorMatch != null) {
      osError = osErrorMatch.group(1)?.trim();
    }

    // Build simple message
    String message = '[$serviceName] Connection failed to $url';
    if (errorCode != null) {
      message += ' (errno: $errorCode';
      if (osError != null) {
        message += ', $osError';
      }
      message += ')';
    } else if (osError != null) {
      message += ' ($osError)';
    }

    return message;
  }

  /// Wrap connection attempt with error handling
  /// Suppresses stack traces and shows simple error message
  static Future<T> safeConnect<T>({
    required Future<T> Function() connectFn,
    required String serviceName,
    String? serverUrl,
  }) async {
    try {
      return await connectFn();
    } catch (e, stackTrace) {
      // Suppress stack trace - only show simple message
      final message = await formatConnectionError(
        e,
        serviceName: serviceName,
        serverUrl: serverUrl,
      );
      print('⚠️ $message');
      
      // Re-throw a simple exception without stack trace
      throw ConnectionException(message);
    }
  }

  /// Check if error is a network error (should be suppressed)
  static bool isNetworkError(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    return errorStr.contains('socketexception') ||
        errorStr.contains('connection refused') ||
        errorStr.contains('failed host lookup') ||
        errorStr.contains('network is unreachable') ||
        errorStr.contains('no route to host') ||
        errorStr.contains('connection timed out') ||
        errorStr.contains('connection reset');
  }
}

/// Simple connection exception without stack trace
class ConnectionException implements Exception {
  final String message;
  ConnectionException(this.message);
  
  @override
  String toString() => message;
}
