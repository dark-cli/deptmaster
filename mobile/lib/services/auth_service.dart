import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'backend_config_service.dart';
import 'realtime_service.dart';
import 'event_store_service.dart';
import 'dummy_data_service.dart';
import 'projection_snapshot_service.dart';

class AuthService {
  static const String _keyToken = 'auth_token';
  static const String _keyUserId = 'user_id';
  static const String _keyUsername = 'username';
  static final LocalAuthentication _localAuth = LocalAuthentication();
  
  // Get secure storage instance (platform-specific configuration)
  // Note: On Linux, we skip secure storage due to build issues and use SharedPreferences
  static bool _shouldUseSecureStorage() {
    if (kIsWeb) return false;
    // Only use secure storage on Android and iOS
    // Linux has build issues with flutter_secure_storage, so we use SharedPreferences
    return !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || 
                       defaultTargetPlatform == TargetPlatform.iOS);
  }
  
  static FlutterSecureStorage? _getSecureStorage() {
    if (!_shouldUseSecureStorage()) {
      return null;
    }
    
    // Platform-specific secure storage configuration
    return const FlutterSecureStorage(
      aOptions: AndroidOptions(
        encryptedSharedPreferences: true,
      ),
    );
  }
  
  // Store value securely
  static Future<void> _storeSecure(String key, String? value) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Always use SharedPreferences (secure storage is optional)
    if (value == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
    
    // Also try secure storage if available (Android/iOS only)
    final storage = _getSecureStorage();
    if (storage != null) {
      try {
        if (value == null) {
          await storage.delete(key: key);
        } else {
          await storage.write(key: key, value: value);
        }
      } catch (e) {
        // Secure storage failed, that's okay - we have SharedPreferences
      }
    }
  }
  
  // Read value securely
  static Future<String?> _readSecure(String key) async {
    // Always try SharedPreferences first (works on all platforms)
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(key);
    
    // Also try secure storage if available (Android/iOS only)
    final storage = _getSecureStorage();
    if (storage != null) {
      try {
        final secureValue = await storage.read(key: key);
        if (secureValue != null) {
          // Migrate to SharedPreferences if not already there
          if (value == null) {
            await prefs.setString(key, secureValue);
          }
          return secureValue;
        }
      } catch (_) {
        // Secure storage failed, use SharedPreferences value
      }
    }
    
    return value;
  }
  
  // Remove value securely
  static Future<void> _removeSecure(String key) async {
    // Always remove from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
    
    // Also try secure storage if available
    final storage = _getSecureStorage();
    if (storage != null) {
      try {
        await storage.delete(key: key);
      } catch (_) {
        // Ignore errors
      }
    }
  }

  // Login
  static Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final baseUrl = await BackendConfigService.getBaseUrl();
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        if (response.body.isEmpty) {
          return {
            'success': false,
            'error': 'Empty response from server',
          };
        }
        try {
          final data = json.decode(response.body);
          // Store auth info securely
          await _storeSecure(_keyToken, data['token']);
          await _storeSecure(_keyUserId, data['user_id']);
          await _storeSecure(_keyUsername, data['username']);
          
          return {
            'success': true,
            'token': data['token'],
            'user_id': data['user_id'],
            'username': data['username'],
          };
        } catch (e) {
          return {
            'success': false,
            'error': 'Failed to parse server response: $e',
          };
        }
      } else {
        String errorMessage = 'Login failed';
        if (response.body.isNotEmpty) {
          try {
            final error = json.decode(response.body);
            errorMessage = error['error'] ?? errorMessage;
          } catch (_) {
            errorMessage = response.body;
          }
        }
        return {
          'success': false,
          'error': errorMessage,
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // Check if user is logged in
  static Future<bool> isLoggedIn() async {
    final token = await _readSecure(_keyToken);
    return token != null && token.isNotEmpty;
  }

  // Get current token
  static Future<String?> getToken() async {
    return await _readSecure(_keyToken);
  }

  // Get current user ID
  static Future<String?> getUserId() async {
    return await _readSecure(_keyUserId);
  }

  // Get current username
  static Future<String?> getUsername() async {
    return await _readSecure(_keyUsername);
  }

  // Callback for logout events (e.g., to navigate to login screen)
  static Function()? onLogout;

  // Validate token by making a test API call
  static Future<bool> validateAuth() async {
    final token = await getToken();
    if (token == null || token.isEmpty) {
      return false;
    }

    try {
      final baseUrl = await BackendConfigService.getBaseUrl();
      final response = await http.get(
        Uri.parse('$baseUrl/api/sync/hash'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 401) {
        // Token is invalid, logout
        print('⚠️ Token validation failed - logging out');
        await logout();
        return false;
      }

      return response.statusCode == 200;
    } catch (e) {
      // Network errors don't mean auth is invalid
      // Only logout on actual auth errors
      print('⚠️ Token validation check failed: $e');
      return true; // Assume token is valid if it's a network error
    }
  }

  // Logout - clears all auth data and local storage
  static Future<void> logout() async {
    print('🔒 Logging out user...');
    
    // Clear auth tokens
    await _removeSecure(_keyToken);
    await _removeSecure(_keyUserId);
    await _removeSecure(_keyUsername);
    
    // Clear all local data (Hive boxes)
    await _clearAllLocalData();
    
    // Disconnect WebSocket
    try {
      await RealtimeService.disconnect();
    } catch (e) {
      print('⚠️ Error disconnecting WebSocket: $e');
    }
    
    // Notify listeners
    if (onLogout != null) {
      onLogout!();
    }
    
    print('✅ Logout complete');
  }

  // Clear all local data from Hive boxes
  static Future<void> _clearAllLocalData() async {
    if (kIsWeb) return; // Web doesn't use Hive
    
    try {
      // Clear events box
      try {
        final eventsBox = await Hive.openBox(EventStoreService.eventsBoxName);
        await eventsBox.clear();
        print('✅ Cleared events box');
      } catch (e) {
        print('⚠️ Error clearing events box: $e');
      }
      
      // Clear contacts box
      try {
        final contactsBox = await Hive.openBox(DummyDataService.contactsBoxName);
        await contactsBox.clear();
        print('✅ Cleared contacts box');
      } catch (e) {
        print('⚠️ Error clearing contacts box: $e');
      }
      
      // Clear transactions box
      try {
        final transactionsBox = await Hive.openBox(DummyDataService.transactionsBoxName);
        await transactionsBox.clear();
        print('✅ Cleared transactions box');
      } catch (e) {
        print('⚠️ Error clearing transactions box: $e');
      }
      
      // Clear projection snapshots box
      try {
        final snapshotsBox = await Hive.openBox(ProjectionSnapshotService.boxName);
        await snapshotsBox.clear();
        print('✅ Cleared projection snapshots box');
      } catch (e) {
        print('⚠️ Error clearing projection snapshots box: $e');
      }
      
      // Clear pending operations box
      try {
        final pendingBox = await Hive.openBox('pending_operations');
        await pendingBox.clear();
        print('✅ Cleared pending operations box');
      } catch (e) {
        print('⚠️ Error clearing pending operations box: $e');
      }
      
      // Clear SharedPreferences sync timestamp
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('last_sync_timestamp');
        await prefs.remove(EventStoreService.lastSyncTimestampKey);
        print('✅ Cleared sync timestamp');
      } catch (e) {
        print('⚠️ Error clearing sync timestamp: $e');
      }
    } catch (e) {
      print('⚠️ Error clearing local data: $e');
    }
  }

  // Biometric authentication (mobile only)
  static Future<bool> authenticateWithBiometrics() async {
    if (kIsWeb) return false; // Not available on web
    
    try {
      // Check if biometrics are available
      final isAvailable = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      
      if (!isAvailable || !isDeviceSupported) {
        return false;
      }

      // Authenticate
      return await _localAuth.authenticate(
        localizedReason: 'Please authenticate to access your debt tracker',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (e) {
      print('Biometric authentication error: $e');
      return false;
    }
  }

  // Check if biometrics are available
  static Future<bool> isBiometricAvailable() async {
    if (kIsWeb) return false;
    
    try {
      final isAvailable = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      return isAvailable && isDeviceSupported;
    } catch (e) {
      return false;
    }
  }
}