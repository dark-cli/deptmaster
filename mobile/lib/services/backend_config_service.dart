import 'package:shared_preferences/shared_preferences.dart';

class BackendConfigService {
  static const String _keyBackendIp = 'backend_ip';
  static const String _keyBackendPort = 'backend_port';
  static const String _keyBackendConfigured = 'backend_configured';

  // Default values (temporary defaults for development)
  static String get defaultIp => '10.95.12.45';

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

  // Get full base URL (without /api/admin)
  static Future<String> getBaseUrl() async {
    final ip = await getBackendIp();
    final port = await getBackendPort();
    return 'http://$ip:$port';
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
    return 'ws://$ip:$port/ws';
  }
}
