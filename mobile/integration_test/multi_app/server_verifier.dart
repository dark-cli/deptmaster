import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:debt_tracker_mobile/api.dart';

/// Server verification utilities for testing
class ServerVerifier {
  final String serverUrl;
  String? _authToken;

  ServerVerifier({required this.serverUrl});

  Future<void> setAuthToken() async {
    _authToken = await Api.getToken();
  }

  Future<Map<String, String>> _getHeaders() async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (_authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    } else {
      await setAuthToken();
      if (_authToken != null) {
        headers['Authorization'] = 'Bearer $_authToken';
      }
    }
    final walletId = await Api.getCurrentWalletId();
    if (walletId != null && walletId.isNotEmpty) {
      headers['X-Wallet-Id'] = walletId;
    }
    return headers;
  }

  Future<List<Map<String, dynamic>>> getServerEvents({DateTime? since}) async {
    try {
      final baseUrl = await Api.getBaseUrl();
      var url = '$baseUrl/api/sync/events';
      final walletId = await Api.getCurrentWalletId();
      if (walletId != null) url += '?wallet_id=$walletId';
      if (since != null) {
        url += walletId != null ? '&' : '?';
        url += 'since=${since.toIso8601String()}';
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

  Future<String> getServerHash() async {
    try {
      final baseUrl = await Api.getBaseUrl();
      final walletId = await Api.getCurrentWalletId();
      var url = '$baseUrl/api/sync/hash';
      if (walletId != null) url += '?wallet_id=$walletId';
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

  Future<int> getServerEventCount() async {
    final events = await getServerEvents();
    return events.length;
  }

  Future<Map<String, dynamic>?> getServerContact(String id) async {
    try {
      final baseUrl = await Api.getBaseUrl();
      final url = '$baseUrl/api/contacts/$id';
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

  Future<Map<String, dynamic>?> getServerTransaction(String id) async {
    try {
      final baseUrl = await Api.getBaseUrl();
      final url = '$baseUrl/api/transactions/$id';
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

  Future<bool> verifyEventInDatabase(String eventId) async {
    try {
      final events = await getServerEvents();
      return events.any((e) => e['id'] == eventId);
    } catch (e) {
      print('❌ Error verifying event in database: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getServerContacts() async {
    try {
      final baseUrl = await Api.getBaseUrl();
      final url = '$baseUrl/api/contacts';
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

  Future<List<Map<String, dynamic>>> getServerTransactions() async {
    try {
      final baseUrl = await Api.getBaseUrl();
      final url = '$baseUrl/api/transactions';
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
