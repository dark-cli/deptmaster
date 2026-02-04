import 'package:shared_preferences/shared_preferences.dart';

class BackendConfigService {
  static const String _keyBackendIp = 'backend_ip';
  static const String _keyBackendPort = 'backend_port';
  static const String _keyBackendUseHttps = 'backend_use_https';
  static const String _keyBackendConfigured = 'backend_configured';

  // Default values (localhost for local dev/integration tests)
  static String get defaultIp => 'localhost';

  static int get defaultPort => 8000;

  // Get backend IP
  static Future<String> getBackendIp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyBackendIp) ?? defaultIp;
  }

  // Get backend port
  static Future<int> getBackendPort() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyBackendPort) ?? defaultPort;
  }

  // Check if backend is configured
  static Future<bool> isConfigured() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyBackendConfigured) ?? false;
  }

  // Save backend configuration
  static Future<void> setBackendConfig(String ip, int port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBackendIp, ip);
    await prefs.setInt(_keyBackendPort, port);
    await prefs.setBool(_keyBackendConfigured, true);
  }

  // Check if HTTPS should be used
  static Future<bool> useHttps() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyBackendUseHttps) ?? false;
  }

  // Set HTTPS usage
  static Future<void> setUseHttps(bool useHttps) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBackendUseHttps, useHttps);
  }

  // Get full base URL (without /api/admin)
  static Future<String> getBaseUrl() async {
    final ip = await getBackendIp();
    final port = await getBackendPort();
    final https = await useHttps();
    final protocol = https ? 'https' : 'http';
    return '$protocol://$ip:$port';
  }

  // Get API base URL
  static Future<String> getApiBaseUrl() async {
    final baseUrl = await getBaseUrl();
    return '$baseUrl/api/admin';
  }

  // Get WebSocket URL
  static Future<String> getWebSocketUrl() async {
    final ip = await getBackendIp();
    final port = await getBackendPort();
    final https = await useHttps();
    final protocol = https ? 'wss' : 'ws';
    return '$protocol://$ip:$port/ws';
  }
}
