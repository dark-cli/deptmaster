import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'backend_config_service.dart';

class AuthService {
  static const String _keyToken = 'auth_token';
  static const String _keyUserId = 'user_id';
  static const String _keyUsername = 'username';
  static final LocalAuthentication _localAuth = LocalAuthentication();

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
          // Store auth info
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_keyToken, data['token']);
          await prefs.setString(_keyUserId, data['user_id']);
          await prefs.setString(_keyUsername, data['username']);
          
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
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_keyToken);
    return token != null && token.isNotEmpty;
  }

  // Get current token
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyToken);
  }

  // Get current user ID
  static Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserId);
  }

  // Get current username
  static Future<String?> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUsername);
  }

  // Logout
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyToken);
    await prefs.remove(_keyUserId);
    await prefs.remove(_keyUsername);
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
