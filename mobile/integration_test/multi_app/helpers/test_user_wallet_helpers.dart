import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

/// Test helpers for creating users and wallets via API
/// These enable parallel testing by creating isolated users and wallets per test.
/// Admin API (create user, wallet, add user to wallet) requires /api/auth/admin/login.

class TestUserWalletHelpers {
  /// Admin panel credentials (admin_users table). Use for admin API only.
  static const String adminPanelUsername = 'admin';
  static const String adminPanelPassword = 'admin123';

  /// Obtain admin JWT via /api/auth/admin/login (required for /api/admin/*).
  /// Retries on 429 (rate limit) with 5s delay, up to 3 attempts.
  static Future<String> _getAdminToken({
    String serverUrl = 'http://localhost:8000',
    String username = adminPanelUsername,
    String password = adminPanelPassword,
  }) async {
    const maxAttempts = 3;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      final loginResponse = await http.post(
        Uri.parse('$serverUrl/api/auth/admin/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'password': password,
        }),
      );

      if (loginResponse.statusCode == 429 && attempt < maxAttempts) {
        await Future.delayed(const Duration(seconds: 5));
        continue;
      }

      if (loginResponse.statusCode != 200) {
        throw Exception(
          'Failed to login as admin: ${loginResponse.statusCode} ${loginResponse.body}',
        );
      }

      final loginData = json.decode(loginResponse.body) as Map<String, dynamic>;
      final token = loginData['token'] as String?;
      if (token == null || token.isEmpty) {
        throw Exception('Admin login response missing token: $loginData');
      }
      return token;
    }
    throw StateError('_getAdminToken retry exhausted');
  }

  /// Create a new user via admin API. Retries on 429 (rate limit).
  static Future<Map<String, String>> createUser({
    required String email,
    required String password,
    String serverUrl = 'http://localhost:8000',
    String? adminUsername,
    String? adminPassword,
  }) async {
    const maxAttempts = 4;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final token = await _getAdminToken(
          serverUrl: serverUrl,
          username: adminUsername ?? adminPanelUsername,
          password: adminPassword ?? adminPanelPassword,
        );

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

        if (createResponse.statusCode == 201) {
          final userData =
              json.decode(createResponse.body) as Map<String, dynamic>;
          return {
            'id': userData['id'] as String,
            'email': userData['email'] as String,
          };
        }

        if (createResponse.statusCode == 429 && attempt < maxAttempts) {
          await Future.delayed(const Duration(seconds: 5));
          continue;
        }

        final body =
            createResponse.body.isEmpty ? '(empty)' : createResponse.body;
        throw Exception(
          'Failed to create user: HTTP ${createResponse.statusCode} $body. '
          'Ensure server has admin user (admin/admin123) and migration 010 is applied.',
        );
      } catch (e) {
        if (attempt == maxAttempts) rethrow;
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    throw StateError('createUser retry exhausted');
  }
  
  /// Create a new wallet via admin API
  static Future<Map<String, String>> createWallet({
    required String name,
    String? description,
    String serverUrl = 'http://localhost:8000',
    String? adminUsername,
    String? adminPassword,
  }) async {
    final token = await _getAdminToken(
      serverUrl: serverUrl,
      username: adminUsername ?? adminPanelUsername,
      password: adminPassword ?? adminPanelPassword,
    );

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
  
  /// Add a user to a wallet via admin API (by username/email; new members get role member).
  static Future<void> addUserToWallet({
    required String walletId,
    required String username,
    String serverUrl = 'http://localhost:8000',
    String? adminUsername,
    String? adminPassword,
  }) async {
    final token = await _getAdminToken(
      serverUrl: serverUrl,
      username: adminUsername ?? adminPanelUsername,
      password: adminPassword ?? adminPanelPassword,
    );

    // Add user to wallet (backend looks up user by email; role is always member, change later)
    final addResponse = await http.post(
      Uri.parse('$serverUrl/api/admin/wallets/$walletId/users'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode({
        'username': username,
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
