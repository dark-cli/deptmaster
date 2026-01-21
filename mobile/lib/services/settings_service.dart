import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'backend_config_service.dart';

class SettingsService {
  static const String _keyDarkMode = 'dark_mode';
  static const String _keyDefaultDirection = 'default_direction'; // 'give' or 'received'
  static const String _keyFlipColors = 'flip_colors';
  static const String _keyDueDateEnabled = 'due_date_enabled';
  static const String _keyDefaultDueDateDays = 'default_due_date_days';
  static const String _keyDefaultDueDateSwitch = 'default_due_date_switch'; // Default state of due date switch in transaction form

  // Dark mode
  static Future<bool> getDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    // Default to true (dark mode enabled)
    return prefs.getBool(_keyDarkMode) ?? true;
  }

  static Future<void> setDarkMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDarkMode, enabled);
    // Also sync to backend
    try {
      final baseUrl = await _getBaseUrl();
      final headers = <String, String>{'Content-Type': 'application/json'};
      try {
        final token = await AuthService.getToken();
        if (token != null) {
          headers['Authorization'] = 'Bearer $token';
        }
      } catch (_) {}
      await http.put(
        Uri.parse('${baseUrl.replaceAll('/admin', '')}/settings/dark_mode'),
        headers: headers,
        body: json.encode({'value': enabled.toString()}),
      );
    } catch (e) {
      print('⚠️ Failed to sync setting to backend: $e');
    }
  }

  // Default direction: 'give' or 'received'
  static Future<String> getDefaultDirection() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDefaultDirection) ?? 'give'; // Default to 'give' (Gave)
  }

  static Future<void> setDefaultDirection(String direction) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDefaultDirection, direction);
    // Also sync to backend
    try {
      final baseUrl = await _getBaseUrl();
      final headers = <String, String>{'Content-Type': 'application/json'};
      try {
        final token = await AuthService.getToken();
        if (token != null) {
          headers['Authorization'] = 'Bearer $token';
        }
      } catch (_) {}
      await http.put(
        Uri.parse('${baseUrl.replaceAll('/admin', '')}/settings/default_direction'),
        headers: headers,
        body: json.encode({'value': direction}),
      );
    } catch (e) {
      print('⚠️ Failed to sync setting to backend: $e');
    }
  }

  // Flip colors
  static Future<bool> getFlipColors() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyFlipColors) ?? false;
  }

  static Future<void> setFlipColors(bool flip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyFlipColors, flip);
    // Also sync to backend
    try {
      final baseUrl = await _getBaseUrl();
      final headers = <String, String>{'Content-Type': 'application/json'};
      try {
        final token = await AuthService.getToken();
        if (token != null) {
          headers['Authorization'] = 'Bearer $token';
        }
      } catch (_) {}
      await http.put(
        Uri.parse('${baseUrl.replaceAll('/admin', '')}/settings/flip_colors'),
        headers: headers,
        body: json.encode({'value': flip.toString()}),
      );
    } catch (e) {
      print('⚠️ Failed to sync setting to backend: $e');
    }
  }

  // Due date enabled
  static Future<bool> getDueDateEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyDueDateEnabled) ?? true; // Default ON
  }

  static Future<void> setDueDateEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDueDateEnabled, enabled);
    // Also sync to backend
    try {
      final baseUrl = await _getBaseUrl();
      final headers = <String, String>{'Content-Type': 'application/json'};
      try {
        final token = await AuthService.getToken();
        if (token != null) {
          headers['Authorization'] = 'Bearer $token';
        }
      } catch (_) {}
      await http.put(
        Uri.parse('${baseUrl.replaceAll('/admin', '')}/settings/due_date_enabled'),
        headers: headers,
        body: json.encode({'value': enabled.toString()}),
      );
    } catch (e) {
      print('⚠️ Failed to sync setting to backend: $e');
    }
  }

  // Default due date days
  static Future<int> getDefaultDueDateDays() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyDefaultDueDateDays) ?? 14; // Default 14 days (2 weeks)
  }

  static Future<void> setDefaultDueDateDays(int days) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyDefaultDueDateDays, days);
    // Also sync to backend
    try {
      final baseUrl = await _getBaseUrl();
      final headers = <String, String>{'Content-Type': 'application/json'};
      try {
        final token = await AuthService.getToken();
        if (token != null) {
          headers['Authorization'] = 'Bearer $token';
        }
      } catch (_) {}
      await http.put(
        Uri.parse('${baseUrl.replaceAll('/admin', '')}/settings/default_due_date_days'),
        headers: headers,
        body: json.encode({'value': days.toString()}),
      );
    } catch (e) {
      print('⚠️ Failed to sync setting to backend: $e');
    }
  }

  // Default due date switch state (on/off in transaction form)
  static Future<bool> getDefaultDueDateSwitch() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyDefaultDueDateSwitch) ?? true; // Default ON
  }

  static Future<void> setDefaultDueDateSwitch(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDefaultDueDateSwitch, enabled);
    // Also sync to backend
    try {
      final baseUrl = await _getBaseUrl();
      final headers = <String, String>{'Content-Type': 'application/json'};
      try {
        final token = await AuthService.getToken();
        if (token != null) {
          headers['Authorization'] = 'Bearer $token';
        }
      } catch (_) {}
      await http.put(
        Uri.parse('${baseUrl.replaceAll('/admin', '')}/settings/default_due_date_switch'),
        headers: headers,
        body: json.encode({'value': enabled.toString()}),
      );
    } catch (e) {
      print('⚠️ Failed to sync setting to backend: $e');
    }
  }

  // Load settings from backend on app start
  static Future<void> loadSettingsFromBackend() async {
    try {
      final baseUrl = await _getBaseUrl();
      final headers = <String, String>{'Content-Type': 'application/json'};
      // Add auth token if available
      try {
        final token = await AuthService.getToken();
        if (token != null) {
          headers['Authorization'] = 'Bearer $token';
        }
      } catch (_) {
        // Auth service might not be initialized yet
      }
      final response = await http.get(
        Uri.parse('${baseUrl.replaceAll('/admin', '')}/settings'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_keyDarkMode, data['dark_mode'] ?? true);
        await prefs.setString(_keyDefaultDirection, data['default_direction'] ?? 'give');
        await prefs.setBool(_keyFlipColors, data['flip_colors'] ?? false);
        await prefs.setBool(_keyDueDateEnabled, data['due_date_enabled'] ?? true); // Default ON
        await prefs.setInt(_keyDefaultDueDateDays, data['default_due_date_days'] ?? 14); // Default 14 days
        await prefs.setBool(_keyDefaultDueDateSwitch, data['default_due_date_switch'] ?? true); // Default ON
      }
    } catch (e) {
      print('⚠️ Failed to load settings from backend: $e');
      // Continue with local defaults if backend is unavailable
    }
  }

  static Future<String> _getBaseUrl() async {
    final baseUrl = await BackendConfigService.getBaseUrl();
    return '$baseUrl/admin';
  }
}
