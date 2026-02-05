import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../multi_app/helpers/test_user_wallet_helpers.dart';

/// Server reset helper using dev-only API endpoint
/// This is much faster than calling manage.sh reset-database-complete
Future<void> resetServer({bool skipServerBuild = false}) async {
  try {
    print('🔄 Resetting server data via API endpoint /api/dev/clear-database...');
    
    final serverUrl = 'http://localhost:8000';
    final url = Uri.parse('$serverUrl/api/dev/clear-database');
    
    // Call the dev-only endpoint
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
    ).timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        throw TimeoutException('Server reset request timed out');
      },
    );
    
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      print('✅ Server data reset complete: ${body['message']}');
    } else if (response.statusCode == 403) {
      // Endpoint not available (production mode)
      print('⚠️ Dev endpoint not available (production mode), falling back to manage.sh...');
      await _resetServerViaManageSh();
    } else {
      // Try fallback to manage.sh if API fails
      print('⚠️ API reset failed (${response.statusCode}), falling back to manage.sh...');
      print('   Response: ${response.body}');
      await _resetServerViaManageSh();
    }
  } catch (e) {
    // If API call fails, fall back to manage.sh
    if (e is TimeoutException || e is SocketException) {
      print('⚠️ API reset failed ($e), falling back to manage.sh...');
      await _resetServerViaManageSh();
    } else {
      print('❌ Error resetting server: $e');
      rethrow;
    }
  }
}

/// Fallback: Reset server using manage.sh (slower but more reliable)
Future<void> _resetServerViaManageSh() async {
  try {
    print('🔄 Resetting server data via manage.sh reset-database-complete...');
    
    final projectRoot = '/home/max/dev/debitum';
    final scriptPath = '$projectRoot/scripts/manage.sh';
    
    final result = await Process.run(
      'bash',
      [scriptPath, 'reset-database-complete'],
      workingDirectory: projectRoot,
      runInShell: true,
    );
    
    if (result.exitCode != 0) {
      throw Exception('Server reset failed (exit code ${result.exitCode}): ${result.stderr}');
    }
    
    print('✅ Server data reset complete (via manage.sh)');
    if (result.stdout.toString().isNotEmpty) {
      print('   ${result.stdout}');
    }
  } catch (e) {
    print('❌ Error resetting server via manage.sh: $e');
    rethrow;
  }
}

/// Wait for server to be ready
Future<void> waitForServerReady({
  String serverUrl = 'http://localhost:8000',
  Duration timeout = const Duration(seconds: 30),
  Duration interval = const Duration(seconds: 1),
}) async {
  print('⏳ Waiting for server to be ready at $serverUrl...');
  
  final startTime = DateTime.now();
  final http = HttpClient();
  
  while (DateTime.now().difference(startTime) < timeout) {
    try {
      final uri = Uri.parse('$serverUrl/health');
      final request = await http.getUrl(uri);
      final response = await request.close();
      
      if (response.statusCode == 200) {
        print('✅ Server is ready');
        http.close();
        return;
      }
    } catch (e) {
      // Server not ready yet, continue waiting
    }
    
    await Future.delayed(interval);
  }
  
  http.close();
  throw TimeoutException(
    'Server did not become ready within ${timeout.inSeconds} seconds',
    timeout,
  );
}

/// Check if server is running
Future<bool> isServerRunning({String serverUrl = 'http://localhost:8000'}) async {
  try {
    final http = HttpClient();
    final uri = Uri.parse('$serverUrl/health');
    final request = await http.getUrl(uri);
    final response = await request.close();
    http.close();
    return response.statusCode == 200;
  } catch (e) {
    return false;
  }
}

/// Cached wallet ID for integration tests (set by ensureTestUserHasWallet)
String? _testWalletId;

/// Get the test wallet ID (call after ensureTestUserHasWallet in setUpAll)
String? getTestWalletId() => _testWalletId;

/// Creates a unique test user and wallet for this test. Call in setUp() so each test
/// has its own isolated wallet. Requires ensureTestUserExists() to have been called
/// in setUpAll (admin user 'max' is used to create users via API).
/// Returns map with: email (use as username for AuthService.login), password, walletId, userId.
Future<Map<String, String>> createUniqueTestUserAndWallet({
  String serverUrl = 'http://localhost:8000',
  String testUserPassword = 'test123456',
}) async {
  final user = await TestUserWalletHelpers.createTestUser(
    password: testUserPassword,
    serverUrl: serverUrl,
  );
  await Future.delayed(const Duration(milliseconds: 800));
  final wallet = await TestUserWalletHelpers.createTestWallet(serverUrl: serverUrl);
  await Future.delayed(const Duration(milliseconds: 800));
  await TestUserWalletHelpers.addUserToWallet(
    walletId: wallet['id']!,
    userId: user['id']!,
    role: 'owner',
    serverUrl: serverUrl,
  );
  return {
    'email': user['email']!,
    'password': testUserPassword,
    'walletId': wallet['id']!,
    'userId': user['id']!,
  };
}

/// Ensure test user has at least one wallet (for multi-wallet integration tests)
/// Call after ensureTestUserExists - uses admin API to create wallet and add user
/// Stores wallet ID in _testWalletId for use with AppInstance.create(walletId: getTestWalletId())
Future<void> ensureTestUserHasWallet({
  String username = 'max',
  String password = '12345678',
}) async {
  try {
    // Login as user to get user_id
    final loginResponse = await http.post(
      Uri.parse('http://localhost:8000/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    ).timeout(const Duration(seconds: 5));

    if (loginResponse.statusCode != 200) return;

    final loginData = jsonDecode(loginResponse.body) as Map<String, dynamic>;
    final userId = loginData['user_id'] as String?;
    if (userId == null) return;

    // Check if user already has wallets first (e.g. from migration 011 default wallet)
    final walletsResponse = await http.get(
      Uri.parse('http://localhost:8000/api/wallets'),
      headers: {'Authorization': 'Bearer ${loginData['token']}'},
    ).timeout(const Duration(seconds: 5));

    if (walletsResponse.statusCode == 200) {
      final walletsData = jsonDecode(walletsResponse.body) as Map<String, dynamic>;
      final wallets = walletsData['wallets'] as List?;
      if (wallets != null && wallets.isNotEmpty) {
        _testWalletId = (wallets.first as Map<String, dynamic>)['id'] as String?;
        print('✅ Test user "$username" already has ${wallets.length} wallet(s)');
        return;
      }
    }

    // No wallets: login as admin to create wallet and add user
    final adminLoginResponse = await http.post(
      Uri.parse('http://localhost:8000/api/auth/admin/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': 'admin', 'password': 'admin123'}),
    ).timeout(const Duration(seconds: 5));

    if (adminLoginResponse.statusCode != 200) return;

    final adminData = jsonDecode(adminLoginResponse.body) as Map<String, dynamic>;
    final token = adminData['token'] as String?;
    if (token == null) return;

    // Create wallet via admin API
    final createWalletResponse = await http.post(
      Uri.parse('http://localhost:8000/api/admin/wallets'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'name': 'Test Wallet',
        'description': 'Default wallet for integration tests',
      }),
    ).timeout(const Duration(seconds: 5));

    if (createWalletResponse.statusCode != 201) return;

    final walletData = jsonDecode(createWalletResponse.body) as Map<String, dynamic>;
    final walletId = walletData['id'] as String?;
    if (walletId == null) return;

    _testWalletId = walletId;

    // Add user to wallet
    final addUserResponse = await http.post(
      Uri.parse('http://localhost:8000/api/admin/wallets/$walletId/users'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'user_id': userId, 'role': 'owner'}),
    ).timeout(const Duration(seconds: 5));

    if (addUserResponse.statusCode == 200 || addUserResponse.statusCode == 201) {
      print('✅ Created wallet for test user "$username"');
    }
  } catch (e) {
    print('⚠️ Could not ensure test user has wallet: $e');
  }
}

/// Create test user if it doesn't exist
/// Uses reset_password binary to create/update user in users_projection table
/// Optimized: Only calls binary if user doesn't exist (saves ~1.2s per call)
Future<void> ensureTestUserExists({
  String username = 'max',
  String password = '12345678',
}) async {
  try {
    // Quick check: Try to login first (fast HTTP call)
    // If login succeeds, user exists with correct password - skip creation
    try {
      final loginUrl = Uri.parse('http://localhost:8000/api/auth/login');
      final loginResponse = await http.post(
        loginUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      ).timeout(const Duration(seconds: 2));
      
      if (loginResponse.statusCode == 200) {
        print('✅ Test user "$username" already exists with correct password (verified via login)');
        return; // User exists, skip creation
      }
    } catch (e) {
      // Login failed, user might not exist - continue to create
    }
    
    print('🔧 Ensuring test user "$username" exists with password "$password"...');
    
    final projectRoot = '/home/max/dev/debitum';
    
    // Use reset_password binary to set/create the user
    // This works with users_projection table (regular users, not admin_users)
    final result = await Process.run(
      'bash',
      [
        '-c',
        'cd $projectRoot/backend/rust-api && cargo run --bin reset_password -- "$username" "$password" 2>&1'
      ],
      workingDirectory: projectRoot,
      runInShell: true,
    );
    
    final output = result.stdout.toString();
    final stderr = result.stderr.toString();
    
    if (result.exitCode == 0 || output.contains('✅')) {
      print('✅ Test user "$username" ensured with password');
      if (output.isNotEmpty && !output.contains('Password updated')) {
        print('   $output');
      }
    } else {
      print('⚠️ Could not ensure test user via reset_password binary: $stderr');
      print('   Exit code: ${result.exitCode}');
      print('   Output: $output');
      // Continue - user might already exist or we'll try SQL fallback
      await _createUserViaSQL(username, password);
    }
  } catch (e) {
    print('⚠️ Could not ensure test user exists: $e');
    // Try SQL fallback
    try {
      await _createUserViaSQL(username, password);
    } catch (e2) {
      print('⚠️ SQL fallback also failed: $e2');
      // Continue - user might already exist
    }
  }
}

/// Create user directly via SQL (fallback method)
/// Note: This requires generating bcrypt hash, which is complex in Dart
/// Prefer using reset_password binary instead
Future<void> _createUserViaSQL(String username, String password) async {
  try {
    print('⚠️ Attempting SQL fallback (generating bcrypt hash via Python)...');
    
    // Generate bcrypt hash using Python
    final hashResult = await Process.run(
      'python3',
      [
        '-c',
        'import bcrypt; import sys; print(bcrypt.hashpw(sys.argv[1].encode(), bcrypt.gensalt(rounds=12)).decode())',
        password,
      ],
      workingDirectory: '/home/max/dev/debitum',
      runInShell: false,
    );
    
    if (hashResult.exitCode != 0) {
      print('⚠️ Could not generate bcrypt hash via Python: ${hashResult.stderr}');
      return;
    }
    
    final passwordHash = hashResult.stdout.toString().trim();
    
    // Now insert/update user in database
    final sqlResult = await Process.run(
      'docker',
      [
        'exec',
        '-i',
        'debt_tracker_postgres',
        'psql',
        '-U', 'debt_tracker',
        '-d', 'debt_tracker',
        '-c',
        '''
        DO \$\$
        BEGIN
          IF EXISTS (SELECT 1 FROM users_projection WHERE email = '$username') THEN
            UPDATE users_projection SET password_hash = '$passwordHash' WHERE email = '$username';
          ELSE
            INSERT INTO users_projection (id, email, password_hash, created_at, last_event_id)
            VALUES (gen_random_uuid(), '$username', '$passwordHash', NOW(), 0);
          END IF;
        END \$\$;
        ''',
      ],
      workingDirectory: '/home/max/dev/debitum',
      runInShell: true,
    );
    
    if (sqlResult.exitCode == 0) {
      print('✅ Test user "$username" created/updated via SQL');
    } else {
      print('⚠️ Could not create user via SQL: ${sqlResult.stderr}');
    }
  } catch (e) {
    print('⚠️ Error creating user via SQL: $e');
  }
}
