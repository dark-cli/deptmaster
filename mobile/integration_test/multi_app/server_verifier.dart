import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:debt_tracker_mobile/services/auth_service.dart';
import 'package:debt_tracker_mobile/services/backend_config_service.dart';

/// Server verification utilities for testing
class ServerVerifier {
  final String serverUrl;
  String? _authToken;
  
  ServerVerifier({required this.serverUrl});
  
  /// Set auth token
  Future<void> setAuthToken() async {
    _authToken = await AuthService.getToken();
  }
  
  /// Get auth headers
  Future<Map<String, String>> _getHeaders() async {
    final headers = {'Content-Type': 'application/json'};
    if (_authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    } else {
      await setAuthToken();
      if (_authToken != null) {
        headers['Authorization'] = 'Bearer $_authToken';
      }
    }
    return headers;
  }
  
  /// Get server events
  Future<List<Map<String, dynamic>>> getServerEvents({DateTime? since}) async {
    try {
      final baseUrl = await BackendConfigService.getBaseUrl();
      var url = '$baseUrl/api/sync/events';
      
      if (since != null) {
        url += '?since=${since.toIso8601String()}';
      }
      
      final headers = await _getHeaders();
      final response = await http.get(Uri.parse(url), headers: headers);
      
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((e) => Map<String, dynamic>.from(e)).toList();
      } else {
        throw Exception('Failed to get server events: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('❌ Error getting server events: $e');
      rethrow;
    }
  }
  
  /// Get server sync hash
  Future<String> getServerHash() async {
    try {
      final baseUrl = await BackendConfigService.getBaseUrl();
      final url = '$baseUrl/api/sync/hash';
      
      final headers = await _getHeaders();
      final response = await http.get(Uri.parse(url), headers: headers);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['hash'] as String;
      } else {
        throw Exception('Failed to get server hash: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('❌ Error getting server hash: $e');
      rethrow;
    }
  }
  
  /// Get server event count
  Future<int> getServerEventCount() async {
    final events = await getServerEvents();
    return events.length;
  }
  
  /// Get server contact
  Future<Map<String, dynamic>?> getServerContact(String id) async {
    try {
      final baseUrl = await BackendConfigService.getApiBaseUrl();
      final url = '$baseUrl/contacts/$id';
      
      final headers = await _getHeaders();
      final response = await http.get(Uri.parse(url), headers: headers);
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw Exception('Failed to get server contact: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('❌ Error getting server contact: $e');
      rethrow;
    }
  }
  
  /// Get server transaction
  Future<Map<String, dynamic>?> getServerTransaction(String id) async {
    try {
      final baseUrl = await BackendConfigService.getApiBaseUrl();
      final url = '$baseUrl/transactions/$id';
      
      final headers = await _getHeaders();
      final response = await http.get(Uri.parse(url), headers: headers);
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw Exception('Failed to get server transaction: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('❌ Error getting server transaction: $e');
      rethrow;
    }
  }
  
  /// Verify event exists in database (via API)
  Future<bool> verifyEventInDatabase(String eventId) async {
    try {
      final events = await getServerEvents();
      return events.any((e) => e['id'] == eventId);
    } catch (e) {
      print('❌ Error verifying event in database: $e');
      return false;
    }
  }
  
  /// Get all server contacts
  Future<List<Map<String, dynamic>>> getServerContacts() async {
    try {
      final baseUrl = await BackendConfigService.getApiBaseUrl();
      final url = '$baseUrl/contacts';
      
      final headers = await _getHeaders();
      final response = await http.get(Uri.parse(url), headers: headers);
      
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((e) => Map<String, dynamic>.from(e)).toList();
      } else {
        throw Exception('Failed to get server contacts: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('❌ Error getting server contacts: $e');
      rethrow;
    }
  }
  
  /// Get all server transactions
  Future<List<Map<String, dynamic>>> getServerTransactions() async {
    try {
      final baseUrl = await BackendConfigService.getApiBaseUrl();
      final url = '$baseUrl/transactions';
      
      final headers = await _getHeaders();
      final response = await http.get(Uri.parse(url), headers: headers);
      
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((e) => Map<String, dynamic>.from(e)).toList();
      } else {
        throw Exception('Failed to get server transactions: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('❌ Error getting server transactions: $e');
      rethrow;
    }
  }
}
