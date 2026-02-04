import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

/// Test helpers for creating users and wallets via API
/// These enable parallel testing by creating isolated users and wallets per test

class TestUserWalletHelpers {
  static const String defaultAdminUsername = 'max';
  static const String defaultAdminPassword = '12345678';
  
  /// Create a new user via admin API
  static Future<Map<String, String>> createUser({
    required String email,
    required String password,
    String serverUrl = 'http://localhost:8000',
    String adminUsername = defaultAdminUsername,
    String adminPassword = defaultAdminPassword,
  }) async {
    // First login as admin to get token
    final loginResponse = await http.post(
      Uri.parse('$serverUrl/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'username': adminUsername,
        'password': adminPassword,
      }),
    );
    
    if (loginResponse.statusCode != 200) {
      throw Exception('Failed to login as admin: ${loginResponse.body}');
    }
    
    final loginData = json.decode(loginResponse.body);
    final token = loginData['token'] as String;
    
    // Create user
    final createResponse = await http.post(
      Uri.parse('$serverUrl/api/admin/users'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode({
        'email': email,
        'password': password,
      }),
    );
    
    if (createResponse.statusCode != 201) {
      throw Exception('Failed to create user: ${createResponse.body}');
    }
    
    final userData = json.decode(createResponse.body);
    return {
      'id': userData['id'] as String,
      'email': userData['email'] as String,
    };
  }
  
  /// Create a new wallet via admin API
  static Future<Map<String, String>> createWallet({
    required String name,
    String? description,
    String serverUrl = 'http://localhost:8000',
    String adminUsername = defaultAdminUsername,
    String adminPassword = defaultAdminPassword,
  }) async {
    // First login as admin to get token
    final loginResponse = await http.post(
      Uri.parse('$serverUrl/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'username': adminUsername,
        'password': adminPassword,
      }),
    );
    
    if (loginResponse.statusCode != 200) {
      throw Exception('Failed to login as admin: ${loginResponse.body}');
    }
    
    final loginData = json.decode(loginResponse.body);
    final token = loginData['token'] as String;
    
    // Create wallet
    final createResponse = await http.post(
      Uri.parse('$serverUrl/api/admin/wallets'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode({
        'name': name,
        'description': description,
      }),
    );
    
    if (createResponse.statusCode != 201) {
      throw Exception('Failed to create wallet: ${createResponse.body}');
    }
    
    final walletData = json.decode(createResponse.body);
    return {
      'id': walletData['id'] as String,
      'name': walletData['name'] as String,
    };
  }
  
  /// Add a user to a wallet via admin API
  static Future<void> addUserToWallet({
    required String walletId,
    required String userId,
    String role = 'member', // 'owner', 'admin', 'member'
    String serverUrl = 'http://localhost:8000',
    String adminUsername = defaultAdminUsername,
    String adminPassword = defaultAdminPassword,
  }) async {
    // First login as admin to get token
    final loginResponse = await http.post(
      Uri.parse('$serverUrl/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'username': adminUsername,
        'password': adminPassword,
      }),
    );
    
    if (loginResponse.statusCode != 200) {
      throw Exception('Failed to login as admin: ${loginResponse.body}');
    }
    
    final loginData = json.decode(loginResponse.body);
    final token = loginData['token'] as String;
    
    // Add user to wallet
    final addResponse = await http.post(
      Uri.parse('$serverUrl/api/admin/wallets/$walletId/users'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode({
        'user_id': userId,
        'role': role,
      }),
    );
    
    if (addResponse.statusCode != 200 && addResponse.statusCode != 201) {
      throw Exception('Failed to add user to wallet: ${addResponse.body}');
    }
  }
  
  static const _uuid = Uuid();
  
  /// Create a unique test user with random UUID-based email
  /// This ensures no conflicts even if database is not reset between runs
  static Future<Map<String, String>> createTestUser({
    int? testIndex,  // Optional: for readability, but UUID ensures uniqueness
    String password = 'test123456',
    String serverUrl = 'http://localhost:8000',
  }) async {
    // Use UUID to ensure uniqueness across all test runs
    final uuid = _uuid.v4();
    final shortUuid = uuid.substring(0, 8); // Use first 8 chars for readability
    final email = testIndex != null 
        ? 'test_user_${testIndex}_$shortUuid@test.com'
        : 'test_user_$shortUuid@test.com';
    
    return await createUser(
      email: email,
      password: password,
      serverUrl: serverUrl,
    );
  }
  
  /// Create a unique test wallet with random UUID-based name
  /// This ensures no conflicts even if database is not reset between runs
  static Future<Map<String, String>> createTestWallet({
    int? testIndex,  // Optional: for readability, but UUID ensures uniqueness
    String? description,
    String serverUrl = 'http://localhost:8000',
  }) async {
    // Use UUID to ensure uniqueness across all test runs
    final uuid = _uuid.v4();
    final shortUuid = uuid.substring(0, 8); // Use first 8 chars for readability
    final name = testIndex != null
        ? 'Test Wallet $testIndex ($shortUuid)'
        : 'Test Wallet $shortUuid';
    
    return await createWallet(
      name: name,
      description: description ?? 'Test wallet for parallel testing (UUID: $uuid)',
      serverUrl: serverUrl,
    );
  }
}
