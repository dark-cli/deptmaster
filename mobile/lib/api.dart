// Single API to Rust. UI calls only this. No other service layers.
// Initialize: Api.init() then Api.initStorage(documentsPath).
//
// INVARIANT: All business logic, behavior, and bug fixes live in Rust — never in Dart.
// This file is a thin FFI wrapper. Do not add logic here.
//
// Connection state (online/offline) is determined entirely in Flutter by the WebSocket:
// - Connected => online. Not connected => offline.
// - When offline, we retry connecting every [Api.reconnectInterval].
// - State is exposed via [Api.connectionState] like any other app data.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint, ValueNotifier;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';

import 'src/frb_generated.dart';
import 'src/lib.dart' as rust;
import 'src/data_bus.dart' as rust_bus;
import 'src/ws.dart' as rust_ws;
import 'utils/toast_service.dart';

// Re-export so the new Riverpod providers can `import 'package:.../api.dart'`
// and use these types without also reaching into src/data_bus.dart.
export 'src/data_bus.dart' show DataChangeEvent, DataChangeKind;

/// Connection state provided by the API (Flutter WebSocket only; Rust is not involved).
/// Use [Api.connectionState] to read; listen to [Api.connectionStateRevision] to react to changes.
class ConnectionState {
  const ConnectionState({
    required this.isOnline,
    required this.hasSyncError,
    required this.hasAuthIssue,
  });

  final bool isOnline;
  final bool hasSyncError;
  final bool hasAuthIssue;

  /// 'Offline' when not connected, 'Error' when connected but sync failed, 'Synced' when connected and no error.
  String get status =>
      !isOnline
          ? 'Offline'
          : (hasAuthIssue ? 'Auth required' : (hasSyncError ? 'Error' : 'Synced'));
}

class Api {
  static bool _initialized = false;
  static bool _hasSyncError = false;
  static bool _hasAuthIssue = false;
  static String? _cachedWalletId;
  // Optimistic "we asked Rust to connect" flag. The Rust ws worker
  // owns the real socket + reconnect logic; this only powers the
  // sync-status icon in the UI.
  static bool _wsConnected = false;
  // Legacy hook still used by other code paths; the realtime error
  // callback path is dead now that Rust owns the connection.
  static void Function(String)? _realtimeErrorCallback;

  /// When offline, we try to reconnect the WebSocket every this interval.
  static const Duration reconnectInterval = Duration(seconds: 5);

  /// Connection check + sync. Call this on pull-to-refresh or when tapping the sync icon.
  /// Ensures WebSocket is connected then runs sync; updates connection state and notifies data.
  /// connectRealtime and manualSync run independently — a failure in one does NOT skip the
  /// other (used to silently swallow connect errors and never sync).
  static Future<void> refreshConnectionAndSync() async {
    if (kIsWeb) return;
    try {
      await connectRealtime();
    } catch (e) {
      debugPrint('[sync-icon] connectRealtime failed: $e');
    }
    try {
      await manualSync();
    } catch (e) {
      debugPrint('[sync-icon] manualSync failed: $e');
      rethrow; // surfacing this lets the icon's tap handler show a snackbar
    }
  }

  /// Notifier for connection/sync state changes. Incremented when [connectionState] changes.
  /// Widgets (e.g. [SyncStatusIcon]) should listen and rebuild so the UI updates immediately.
  static final ValueNotifier<int> connectionStateRevision = ValueNotifier(0);

  /// Broadcast Stream of [ConnectionState] changes. Backs the new
  /// Riverpod-based providers; existing widgets that watch
  /// [connectionStateRevision] keep working unchanged.
  static final StreamController<ConnectionState> _connectionStateController =
      StreamController<ConnectionState>.broadcast();
  static Stream<ConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  static void _notifyConnectionStateChanged() {
    connectionStateRevision.value = connectionStateRevision.value + 1;
    _connectionStateController.add(connectionState);
  }

  /// Broadcast Stream of data-change events from Rust. Riverpod
  /// providers subscribe to this and invalidate themselves when a
  /// relevant [DataChangeKind] arrives. The underlying Rust stream
  /// is single-listener (the sink is replaced on each subscribe), so
  /// we wrap in a broadcast stream and cache it — call this getter
  /// freely from anywhere.
  static Stream<rust_bus.DataChangeEvent>? _dataChangeStreamCached;
  static Stream<rust_bus.DataChangeEvent> get dataChangeStream {
    return _dataChangeStreamCached ??=
        rust_bus.dataChangeStream().asBroadcastStream();
  }

  /// Connection state from the Flutter WebSocket only (Rust does not provide this).
  /// If we are connected => online; if not => offline. In offline mode we keep trying to reconnect every [reconnectInterval].
  static ConnectionState get connectionState => ConnectionState(
        isOnline: _wsConnected,
        hasSyncError: _hasSyncError,
        hasAuthIssue: _hasAuthIssue,
      );

  static bool get hasWalletSelected =>
      _cachedWalletId != null && _cachedWalletId!.isNotEmpty;

  static const _keyBackendHost = 'backend_host';
  static const _keyBackendPort = 'backend_port';
  static const _keyBackendUseHttps = 'backend_use_https';
  static const _keyBackendConfigured = 'backend_configured';
  static const _keyDarkMode = 'dark_mode';
  static const _keyDefaultDirection = 'default_direction';
  static const _keyFlipColors = 'flip_colors';
  static const _keyDueDateEnabled = 'due_date_enabled';
  static const _keyDefaultDueDateDays = 'default_due_date_days';
  static const _keyDefaultDueDateSwitch = 'default_due_date_switch';
  static const _keyShowDashboardChart = 'show_dashboard_chart';
  static const _keyDashboardDefaultPeriod = 'dashboard_default_period';
  static const _keyGraphDefaultPeriod = 'graph_default_period';
  static const _keyInvertYAxis = 'invert_y_axis';

  /// Server-sent code for insufficient wallet permission. Only show "permission denied" toast when this is in the error (never for network errors).
  static const _permissionDeniedCode = 'DEBITUM_INSUFFICIENT_WALLET_PERMISSION';
  static const _authDeclinedCode = 'DEBITUM_AUTH_DECLINED';

  static void Function()? onLogout;
  /// Optional hook to attempt re-auth (e.g. refresh/login) when server says unauthorized.
  /// Return true if re-auth succeeded and the caller should retry later.
  static Future<bool> Function()? onReauth;

  static bool _isAuthDeclinedError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains(_authDeclinedCode.toLowerCase()) || s.contains('401 unauthorized');
  }

  static Future<void> _handleAuthDeclined() async {
    if (onReauth != null) {
      try {
        final ok = await onReauth!();
        if (ok) {
          _hasAuthIssue = false;
          _notifyConnectionStateChanged();
          return;
        }
      } catch (_) {}
    }
    _hasAuthIssue = true;
    _notifyConnectionStateChanged();
  }

  /// Last init error (e.g. native library not found). Cleared on success.
  static String? initError;

  /// Cached storage path so we can re-call initStorage on the thread that runs auth (Rust storage is thread-local).
  static String? _storagePath;

  // ---------- Init ----------
  /// Returns true if Rust bridge is ready, false if load failed (e.g. .so not found on Android).
  static Future<bool> init() async {
    if (_initialized) return true;
    if (kIsWeb) return true;
    initError = null;
    try {
      await RustLib.init();
      _initialized = true;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_keyBackendConfigured) == true) {
        final baseUrl = await getBaseUrl();
        final wsUrl = await getWebSocketUrl();
        await RustLib.instance.api.crateConfigSetBackendConfig(baseUrl: baseUrl, wsUrl: wsUrl);
      }
      return true;
    } catch (e) {
      debugPrint('Api.init: $e');
      initError = e.toString();
      return false;
    }
  }

  static Future<void> initStorage(String path) async {
    if (kIsWeb) return;
    _storagePath = path;
    if (!_initialized) await init();
    try {
      await RustLib.instance.api.crateConfigInitStorage(storagePath: path);
      await _migratePreferencesToRust();
      try {
        final id = await rust.getCurrentWalletId();
        _cachedWalletId = (id == null || id.isEmpty) ? null : id;
        _notifyConnectionStateChanged();
      } catch (_) {}
    } catch (e) {
      debugPrint('Api.initStorage: $e');
    }
  }

  /// One-time: copy UI preferences from SharedPreferences to Rust, then remove from prefs.
  static Future<void> _migratePreferencesToRust() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = [
        _keyDarkMode,
        _keyDefaultDirection,
        _keyFlipColors,
        _keyDueDateEnabled,
        _keyDefaultDueDateDays,
        _keyDefaultDueDateSwitch,
        _keyShowDashboardChart,
        _keyDashboardDefaultPeriod,
        _keyGraphDefaultPeriod,
        _keyInvertYAxis,
      ];
      for (final key in keys) {
        final v = prefs.get(key);
        if (v == null) continue;
        if (v is bool) {
          await rust.setPreference(key: key, value: v ? 'true' : 'false');
        } else if (v is int) {
          await rust.setPreference(key: key, value: v.toString());
        } else if (v is String) {
          await rust.setPreference(key: key, value: v);
        }
        await prefs.remove(key);
      }
    } catch (_) {}
  }

  // ---------- Backend config (prefs + Rust) ----------
  static String get defaultBackendHost => '10.95.12.46';
  static int get defaultBackendPort => 8000;

  static Future<String> getBackendHost() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyBackendHost) ?? defaultBackendHost;
  }

  static Future<int> getBackendPort() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyBackendPort) ?? defaultBackendPort;
  }

  static Future<bool> getUseHttps() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyBackendUseHttps) ?? false;
  }

  static Future<void> setUseHttps(bool use) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBackendUseHttps, use);
  }

  static Future<bool> isBackendConfigured() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyBackendConfigured) ?? false;
  }

  static Future<String> getBaseUrl() async {
    final host = await getBackendHost();
    final port = await getBackendPort();
    final https = await getUseHttps();
    return '${https ? 'https' : 'http'}://$host:$port';
  }

  static Future<String> getWebSocketUrl() async {
    final host = await getBackendHost();
    final port = await getBackendPort();
    final https = await getUseHttps();
    return '${https ? 'wss' : 'ws'}://$host:$port/ws';
  }

  static Future<void> setBackendConfig(String host, int port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBackendHost, host);
    await prefs.setInt(_keyBackendPort, port);
    await prefs.setBool(_keyBackendConfigured, true);
    final baseUrl = await getBaseUrl();
    final wsUrl = await getWebSocketUrl();
    if (!kIsWeb && _initialized) {
      try {
        await RustLib.instance.api.crateConfigSetBackendConfig(baseUrl: baseUrl, wsUrl: wsUrl);
      } catch (e) {
        debugPrint('Api.setBackendConfig: Rust setBackendConfig failed: $e');
        rethrow;
      }
    }
  }

  /// Ensures backend config is set in Rust (storage is process-wide and inited once at startup).
  static Future<void> _ensureRustReady() async {
    if (kIsWeb || !_initialized) return;
    try {
      if (await isBackendConfigured()) {
        final baseUrl = await getBaseUrl();
        final wsUrl = await getWebSocketUrl();
        await RustLib.instance.api.crateConfigSetBackendConfig(baseUrl: baseUrl, wsUrl: wsUrl);
      }
    } catch (e) {
      debugPrint('Api._ensureRustReady: $e');
    }
  }

  // ---------- Auth (Rust) ----------
  static Future<void> login(String username, String password) async {
    if (!_initialized && !(await init())) {
      throw StateError(initError ?? 'Rust library not loaded. Did you forget to call init?');
    }
    if (kIsWeb) throw UnsupportedError('Login not supported on web');
    await _ensureRustReady();
    await rust.login(username: username, password: password);
    _hasAuthIssue = false;
    _notifyConnectionStateChanged();
  }

  static Future<void> register(String username, String password) async {
    if (!_initialized && !(await init())) {
      throw StateError(initError ?? 'Rust library not loaded. Did you forget to call init?');
    }
    if (kIsWeb) throw UnsupportedError('Sign up not supported on web');
    await _ensureRustReady();
    await rust.register(username: username, password: password);
    _hasAuthIssue = false;
    _notifyConnectionStateChanged();
  }

  static Future<void> logout() async {
    if (!kIsWeb) {
      try {
        await _ensureRustReady();
        await rust.logout();
      } catch (_) {}
    }
    await _wsDisconnect();
    _cachedWalletId = null;
    _hasSyncError = false;
    _hasAuthIssue = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {}
    _notifyConnectionStateChanged();
    onLogout?.call();
  }

  static Future<bool> isLoggedIn() async {
    if (!_initialized) await init();
    if (kIsWeb) return false;
    try {
      await _ensureRustReady();
      return await rust.isLoggedIn();
    } catch (_) {
      return false;
    }
  }

  static Future<String?> getUserId() async {
    if (!_initialized) await init();
    if (kIsWeb) return null;
    try {
      await _ensureRustReady();
      return await rust.getUserId();
    } catch (_) {
      return null;
    }
  }

  static Future<String?> getToken() async {
    if (!_initialized) await init();
    if (kIsWeb) return null;
    try {
      await _ensureRustReady();
      return await rust.getToken();
    } catch (_) {
      return null;
    }
  }

  /// Username from JWT (Rust decodes token; single source of truth).
  static Future<String?> getUsername() async {
    if (kIsWeb) return null;
    try {
      await _ensureRustReady();
      return await rust.getUsername();
    } catch (_) {
      return null;
    }
  }

  /// True if JWT is expired or invalid (Rust decodes token). Used to avoid WebSocket 401 spam.
  static Future<bool> isTokenExpired() async {
    if (kIsWeb) return true;
    try {
      await _ensureRustReady();
      return await rust.isTokenExpired();
    } catch (_) {
      return true;
    }
  }

  /// Call when coming online or to revalidate. Rust does sync and, if server sends DEBITUM_AUTH_DECLINED, Rust logs out and cleans up; Dart only reacts by calling onLogout for UI.
  static Future<bool> validateAuth() async {
    if (kIsWeb) return false;
    try {
      await _ensureRustReady();
      await RustLib.instance.api.crateIntegrationSyncControlManualSync();
      _hasSyncError = false;
      _hasAuthIssue = false;
      _notifyConnectionStateChanged();
      return true;
    } catch (e) {
      final s = e.toString();
      if (s.contains(_authDeclinedCode)) {
        await _handleAuthDeclined();
        return false;
      }
      _hasSyncError = true;
      _notifyConnectionStateChanged();
      // Network/offline errors should not block startup or force logout.
      return true;
    }
  }

  // ---------- Wallet (Rust) ----------
  static Future<String?> getCurrentWalletId() async {
    if (!_initialized) await init();
    if (kIsWeb) return null;
    try {
      await _ensureRustReady();
      final id = await rust.getCurrentWalletId();
      _cachedWalletId = (id == null || id.isEmpty) ? null : id;
      return _cachedWalletId;
    } catch (_) {
      return null;
    }
  }

  static Future<void> setCurrentWalletId(String walletId) async {
    if (kIsWeb) return;
    try {
      await _ensureRustReady();
      await rust.setCurrentWalletId(walletId: walletId);
      _cachedWalletId = walletId;
      // Stage 2 realtime: reconnect websocket to subscribe to the active wallet only.
      await _wsDisconnect();
      connectRealtime().catchError((_) {});
    } catch (e) {
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getWallets() async {
    if (!_initialized) await init();
    if (kIsWeb) return [];
    try {
      await _ensureRustReady();
      final json = await rust.getWallets();
      final list = jsonDecode(json) as List<dynamic>?;
      if (_hasAuthIssue) {
        _hasAuthIssue = false;
        _notifyConnectionStateChanged();
      }
      return list?.map((e) => e as Map<String, dynamic>).toList() ?? [];
    } catch (e) {
      if (_isAuthDeclinedError(e)) {
        await _handleAuthDeclined();
      }
      return [];
    }
  }

  static Future<Map<String, dynamic>?> createWallet(String name, String description) async {
    if (kIsWeb) return null;
    try {
      await _ensureRustReady();
      final json = await rust.createWallet(name: name, description: description);
      return jsonDecode(json) as Map<String, dynamic>?;
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> ensureCurrentWallet() async {
    if (kIsWeb) return;
    await _ensureRustReady();
    await rust.ensureCurrentWallet();
    // Force cache update and notification to ensure UI stays in sync
    try {
      final id = await rust.getCurrentWalletId();
      if (id != null && id.isNotEmpty) {
        if (_cachedWalletId != id) {
          _cachedWalletId = id;
          
          // Ensure realtime is connected for this wallet
          await _wsDisconnect();
          connectRealtime().catchError((_) {});
        }
      }
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> getWallet(String id) async {
    final list = await getWallets();
    try {
      return list.firstWhere((w) => w['id'] == id);
    } catch (_) {
      return null;
    }
  }

  // ---------- Wallet management (manage wallet screen) ----------
  static Future<List<Map<String, dynamic>>> getWalletUsers(String walletId) async {
    if (kIsWeb) return [];
    await _ensureRustReady();
    final json = await rust.listWalletUsers(walletId: walletId);
    final data = jsonDecode(json) as Map<String, dynamic>?;
    final list = data?['users'] as List<dynamic>?;
    return list?.map((e) => e as Map<String, dynamic>).toList() ?? [];
  }

  /// Search users by email (for add-member typeahead). Returns JSON array of { id, email }.
  static Future<List<Map<String, dynamic>>> searchWalletUsers(
      String walletId, String query) async {
    if (kIsWeb) return [];
    await _ensureRustReady();
    final json = await rust.searchWalletUsers(
        walletId: walletId, query: query.trim());
    final list = jsonDecode(json) as List<dynamic>?;
    return list
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        [];
  }

  static Future<void> addUserToWallet(String walletId, String username) async {
    if (kIsWeb) return;
    await _ensureRustReady();
    await rust.addUserToWallet(walletId: walletId, username: username);
  }

  /// Create or replace 4-digit invite code for the wallet. Returns the code.
  static Future<String> createWalletInviteCode(String walletId) async {
    if (kIsWeb) throw UnsupportedError('Invite codes not supported on web');
    await _ensureRustReady();
    return rust.createWalletInviteCode(walletId: walletId);
  }

  /// Join a wallet by invite code. Returns the joined wallet_id.
  static Future<String> joinWalletByCode(String code) async {
    if (kIsWeb) throw UnsupportedError('Join by code not supported on web');
    await _ensureRustReady();
    return rust.joinWalletByCode(code: code);
  }

  static Future<void> updateWalletUserRole(String walletId, String userId, String role) async {
    if (kIsWeb) return;
    await _ensureRustReady();
    await rust.updateWalletUserRole(walletId: walletId, userId: userId, role: role);
  }

  static Future<void> removeWalletUser(String walletId, String userId) async {
    if (kIsWeb) return;
    await _ensureRustReady();
    await rust.removeWalletUser(walletId: walletId, userId: userId);
  }

  static Future<List<Map<String, dynamic>>> getWalletUserGroups(String walletId) async {
    if (kIsWeb) return [];
    await _ensureRustReady();
    final json = await rust.listWalletUserGroups(walletId: walletId);
    final list = jsonDecode(json) as List<dynamic>?;
    return list?.map((e) => e as Map<String, dynamic>).toList() ?? [];
  }

  static Future<Map<String, dynamic>> createWalletUserGroup(String walletId, String name) async {
    await _ensureRustReady();
    final json = await rust.createWalletUserGroup(walletId: walletId, name: name);
    return jsonDecode(json) as Map<String, dynamic>;
  }

  static Future<void> updateWalletUserGroup(String walletId, String groupId, String name) async {
    await _ensureRustReady();
    await rust.updateWalletUserGroup(walletId: walletId, groupId: groupId, name: name);
  }

  static Future<void> deleteWalletUserGroup(String walletId, String groupId) async {
    await _ensureRustReady();
    await rust.deleteWalletUserGroup(walletId: walletId, groupId: groupId);
  }

  static Future<List<Map<String, dynamic>>> getWalletUserGroupMembers(String walletId, String groupId) async {
    if (kIsWeb) return [];
    await _ensureRustReady();
    final json = await rust.listWalletUserGroupMembers(walletId: walletId, groupId: groupId);
    final list = jsonDecode(json) as List<dynamic>?;
    return list?.map((e) => e as Map<String, dynamic>).toList() ?? [];
  }

  static Future<void> addWalletUserGroupMember(String walletId, String groupId, String userId) async {
    if (kIsWeb) return;
    await _ensureRustReady();
    await rust.addWalletUserGroupMember(walletId: walletId, groupId: groupId, userId: userId);
  }

  static Future<void> removeWalletUserGroupMember(String walletId, String groupId, String userId) async {
    if (kIsWeb) return;
    await _ensureRustReady();
    await rust.removeWalletUserGroupMember(walletId: walletId, groupId: groupId, userId: userId);
  }

  static Future<List<Map<String, dynamic>>> getWalletContactGroups(String walletId) async {
    if (kIsWeb) return [];
    await _ensureRustReady();
    final json = await rust.listWalletContactGroups(walletId: walletId);
    final list = jsonDecode(json) as List<dynamic>?;
    return list?.map((e) => e as Map<String, dynamic>).toList() ?? [];
  }

  static Future<Map<String, dynamic>> createWalletContactGroup(String walletId, String name) async {
    await _ensureRustReady();
    final json = await rust.createWalletContactGroup(walletId: walletId, name: name);
    return jsonDecode(json) as Map<String, dynamic>;
  }

  static Future<void> updateWalletContactGroup(String walletId, String groupId, String name) async {
    await _ensureRustReady();
    await rust.updateWalletContactGroup(walletId: walletId, groupId: groupId, name: name);
  }

  static Future<void> deleteWalletContactGroup(String walletId, String groupId) async {
    await _ensureRustReady();
    await rust.deleteWalletContactGroup(walletId: walletId, groupId: groupId);
  }

  static Future<List<Map<String, dynamic>>> getWalletContactGroupMembers(String walletId, String groupId) async {
    if (kIsWeb) return [];
    await _ensureRustReady();
    final json = await rust.listWalletContactGroupMembers(walletId: walletId, groupId: groupId);
    final list = jsonDecode(json) as List<dynamic>?;
    return list?.map((e) => e as Map<String, dynamic>).toList() ?? [];
  }

  static Future<void> addWalletContactGroupMember(String walletId, String groupId, String contactId) async {
    if (kIsWeb) return;
    await _ensureRustReady();
    await rust.addWalletContactGroupMember(walletId: walletId, groupId: groupId, contactId: contactId);
  }

  static Future<void> removeWalletContactGroupMember(String walletId, String groupId, String contactId) async {
    if (kIsWeb) return;
    await _ensureRustReady();
    await rust.removeWalletContactGroupMember(walletId: walletId, groupId: groupId, contactId: contactId);
  }

  /// Returns IDs of contact groups that contain this contact. Sourced from Rust (list groups + list members).
  static Future<List<String>> getContactGroupIdsForContact(String walletId, String contactId) async {
    if (kIsWeb) return [];
    await _ensureRustReady();
    final groups = await getWalletContactGroups(walletId);
    final result = <String>[];
    for (final g in groups) {
      final groupId = g['id'] as String?;
      if (groupId == null) continue;
      final members = await getWalletContactGroupMembers(walletId, groupId);
      final inGroup = members.any((m) => m['contact_id'] == contactId);
      if (inGroup) result.add(groupId);
    }
    return result;
  }

  static Future<List<Map<String, dynamic>>> getWalletPermissionActions(String walletId) async {
    if (kIsWeb) return [];
    await _ensureRustReady();
    final json = await rust.listWalletPermissionActions(walletId: walletId);
    final list = jsonDecode(json) as List<dynamic>?;
    return list?.map((e) => e as Map<String, dynamic>).toList() ?? [];
  }

  /// Returns JSON string {"actions": ["contact:read", ...]} for the current user in this wallet.
  static Future<String> getMyPermissions(String walletId) async {
    if (kIsWeb) return '{}';
    await _ensureRustReady();
    return rust.getMyPermissions(walletId: walletId);
  }

  static Future<List<Map<String, dynamic>>> getWalletPermissionMatrix(String walletId) async {
    if (kIsWeb) return [];
    await _ensureRustReady();
    final json = await rust.getWalletPermissionMatrix(walletId: walletId);
    final list = jsonDecode(json) as List<dynamic>?;
    return list?.map((e) => e as Map<String, dynamic>).toList() ?? [];
  }

  static Future<void> putWalletPermissionMatrix(String walletId, List<Map<String, dynamic>> entries) async {
    if (kIsWeb) return;
    await _ensureRustReady();
    final entriesJson = jsonEncode(entries);
    await rust.putWalletPermissionMatrix(walletId: walletId, entriesJson: entriesJson);
  }

  /// Get wallet-level permissions: (user_group, action, is_deny) matrix
  /// Returns empty list if endpoint not available (graceful degradation for older backends)
  static Future<List<Map<String, dynamic>>> getWalletPermissions(String walletId) async {
    if (kIsWeb) return [];
    try {
      await _ensureRustReady();
      final json = await rust.getWalletPermissions(walletId: walletId);
      final list = jsonDecode(json) as List<dynamic>?;
      return list?.map((e) => e as Map<String, dynamic>).toList() ?? [];
    } catch (e) {
      // Graceful degradation: if endpoint doesn't exist, just return empty list
      // This allows the UI to work even if backend doesn't support wallet permissions
      debugPrint('[wallet-permissions] getWalletPermissions failed: $e');
      return [];
    }
  }

  /// Set wallet-level permissions: grant/revoke actions for user groups
  static Future<void> setWalletPermissions(String walletId, List<Map<String, dynamic>> entries) async {
    if (kIsWeb) return;
    try {
      await _ensureRustReady();
      final entriesJson = jsonEncode(entries);
      await rust.setWalletPermissions(walletId: walletId, entriesJson: entriesJson);
    } catch (e) {
      // If backend doesn't support wallet permissions, silently fail
      debugPrint('[wallet-permissions] setWalletPermissions failed: $e');
      throw Exception('Failed to set wallet permissions. Ensure backend supports wallet-level permissions.');
    }
  }

  /// Get member-level permissions: (source_group, target_group, action, is_deny) matrix
  /// Returns empty list if endpoint not available (graceful degradation for older backends)
  static Future<List<Map<String, dynamic>>> getMemberPermissions(String walletId) async {
    if (kIsWeb) return [];
    try {
      await _ensureRustReady();
      final json = await rust.getMemberPermissions(walletId: walletId);
      final list = jsonDecode(json) as List<dynamic>?;
      return list?.map((e) => e as Map<String, dynamic>).toList() ?? [];
    } catch (e) {
      // Graceful degradation: if endpoint doesn't exist, just return empty list
      debugPrint('[member-permissions] getMemberPermissions failed: $e');
      return [];
    }
  }

  /// Set member-level permissions: grant/revoke actions for source→target group pairs
  static Future<void> setMemberPermissions(String walletId, List<Map<String, dynamic>> entries) async {
    if (kIsWeb) return;
    try {
      await _ensureRustReady();
      final entriesJson = jsonEncode(entries);
      await rust.setMemberPermissions(walletId: walletId, entriesJson: entriesJson);
    } catch (e) {
      debugPrint('[member-permissions] setMemberPermissions failed: $e');
      throw Exception('Failed to set member permissions. Ensure backend supports member-level permissions.');
    }
  }

  static bool isPermissionDeniedError(dynamic e) {
    final s = e.toString().toLowerCase();
    return s.contains(_permissionDeniedCode);
  }

  // ---------- Data (Rust) ----------
  static Future<String> getContacts() async {
    if (!_initialized) await init();
    if (kIsWeb) return '[]';
    try {
      await _ensureRustReady();
      return await rust.getContacts();
    } catch (_) {
      return '[]';
    }
  }

  static Future<String> getTransactions() async {
    if (!_initialized) await init();
    if (kIsWeb) return '[]';
    try {
      await _ensureRustReady();
      return await rust.getTransactions();
    } catch (_) {
      return '[]';
    }
  }

  static Future<String?> getContact(String id) async {
    if (!_initialized) await init();
    if (kIsWeb) return null;
    try {
      await _ensureRustReady();
      return await rust.getContact(id: id);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> getTransaction(String id) async {
    if (!_initialized) await init();
    if (kIsWeb) return null;
    try {
      await _ensureRustReady();
      return await rust.getTransaction(id: id);
    } catch (_) {
      return null;
    }
  }

  static Future<String> createContact({
    required String name,
    String? username,
    String? phone,
    String? email,
    String? notes,
    List<String>? groupIds,
  }) async {
    if (kIsWeb) throw UnsupportedError('Not on web');
    try {
      await _ensureRustReady();
      final result = await rust.createContact(
        name: name,
        username: username,
        phone: phone,
        email: email,
        notes: notes,
        groupIds: groupIds,
      );
      return result;
    } catch (e) {
      final s = e.toString().toLowerCase();
      if (s.contains(_permissionDeniedCode)) {
        ToastService.showError('You don’t have permission to make changes in this wallet. Your pending local change was discarded.');
      }
      rethrow;
    }
  }

  static Future<void> updateContact({
    required String id,
    required String name,
    String? username,
    String? phone,
    String? email,
    String? notes,
    List<String>? groupIds,
  }) async {
    if (kIsWeb) return;
    try {
      await _ensureRustReady();
      await rust.updateContact(
        id: id,
        name: name,
        username: username,
        phone: phone,
        email: email,
        notes: notes,
        groupIds: groupIds,
      );
    } catch (e) {
      final s = e.toString().toLowerCase();
      if (s.contains(_permissionDeniedCode)) {
        ToastService.showError('You don’t have permission to make changes in this wallet. Your pending local change was discarded.');
      }
      rethrow;
    }
  }

  static Future<void> deleteContact(String contactId) async {
    if (kIsWeb) return;
    try {
      await _ensureRustReady();
      await rust.deleteContact(contactId: contactId);
    } catch (e) {
      final s = e.toString().toLowerCase();
      if (s.contains(_permissionDeniedCode)) {
        ToastService.showError('You don’t have permission to make changes in this wallet. Your pending local change was discarded.');
      }
      rethrow;
    }
  }

  static Future<String> createTransaction({
    required String contactId,
    required String type,
    required String direction,
    required int amount,
    required String currency,
    String? description,
    required String transactionDate,
    String? dueDate,
  }) async {
    if (kIsWeb) throw UnsupportedError('Not on web');
    try {
      await _ensureRustReady();
      final result = await rust.createTransaction(
        contactId: contactId,
        type: type,
        direction: direction,
        amount: amount,
        currency: currency,
        description: description,
        transactionDate: transactionDate,
        dueDate: dueDate,
      );
      return result;
    } catch (e) {
      final s = e.toString().toLowerCase();
      if (s.contains(_permissionDeniedCode)) {
        ToastService.showError('You don’t have permission to make changes in this wallet. Your pending local change was discarded.');
      }
      rethrow;
    }
  }

  static Future<void> updateTransaction({
    required String id,
    required String contactId,
    required String type,
    required String direction,
    required int amount,
    required String currency,
    String? description,
    required String transactionDate,
    String? dueDate,
  }) async {
    if (kIsWeb) return;
    try {
      await _ensureRustReady();
      await rust.updateTransaction(
        id: id,
        contactId: contactId,
        type: type,
        direction: direction,
        amount: amount,
        currency: currency,
        description: description,
        transactionDate: transactionDate,
        dueDate: dueDate,
      );
    } catch (e) {
      final s = e.toString().toLowerCase();
      if (s.contains(_permissionDeniedCode)) {
        ToastService.showError('You don’t have permission to make changes in this wallet. Your pending local change was discarded.');
      }
      rethrow;
    }
  }

  static Future<void> deleteTransaction(String transactionId) async {
    if (kIsWeb) return;
    try {
      await _ensureRustReady();
      await rust.deleteTransaction(transactionId: transactionId);
    } catch (e) {
      final s = e.toString().toLowerCase();
      if (s.contains(_permissionDeniedCode)) {
        ToastService.showError('You don’t have permission to make changes in this wallet. Your pending local change was discarded.');
      }
      rethrow;
    }
  }

  static Future<void> undoContactAction(String contactId) async {
    if (kIsWeb) return;
    try {
      await _ensureRustReady();
      await rust.undoContactAction(contactId: contactId);
    } catch (e) {
      final s = e.toString().toLowerCase();
      if (s.contains(_permissionDeniedCode)) {
        ToastService.showError('You don’t have permission to make changes in this wallet. Your pending local change was discarded.');
      }
      rethrow;
    }
  }

  static Future<void> undoTransactionAction(String transactionId) async {
    if (kIsWeb) return;
    try {
      await _ensureRustReady();
      await rust.undoTransactionAction(transactionId: transactionId);
    } catch (e) {
      final s = e.toString().toLowerCase();
      if (s.contains(_permissionDeniedCode)) {
        ToastService.showError('You don’t have permission to make changes in this wallet. Your pending local change was discarded.');
      }
      rethrow;
    }
  }

  static Future<void> bulkDeleteContacts(List<String> ids) async {
    if (kIsWeb) return;
    try {
      await _ensureRustReady();
      await rust.bulkDeleteContacts(contactIds: ids);
    } catch (e) {
      final s = e.toString().toLowerCase();
      if (s.contains(_permissionDeniedCode)) {
        ToastService.showError('You don’t have permission to make changes in this wallet. Pending local changes were discarded.');
      }
      rethrow;
    }
  }

  static Future<void> bulkDeleteTransactions(List<String> ids) async {
    if (kIsWeb) return;
    try {
      await _ensureRustReady();
      await rust.bulkDeleteTransactions(transactionIds: ids);
    } catch (e) {
      final s = e.toString().toLowerCase();
      if (s.contains(_permissionDeniedCode)) {
        ToastService.showError('You don’t have permission to make changes in this wallet. Pending local changes were discarded.');
      }
      rethrow;
    }
  }

  static Future<String> getEvents() async {
    if (!_initialized) await init();
    if (kIsWeb) return '[]';
    try {
      final currentWalletId = await getCurrentWalletId();
      if (currentWalletId == null || currentWalletId.isEmpty) {
        return '[]';
      }
      await _ensureRustReady();
      final json = await rust.getEvents();
      final list = jsonDecode(json) as List<dynamic>? ?? [];
      if (_hasAuthIssue) {
        _hasAuthIssue = false;
        _notifyConnectionStateChanged();
      }
      return json;
    } catch (e) {
      if (_isAuthDeclinedError(e)) {
        await _handleAuthDeclined();
        return '[]';
      }
      debugPrint('Api.getEvents failed: $e');
      return '[]';
    }
  }

  // ---------- Sync (Rust) ----------
  static Future<void> manualSync() async {
    if (kIsWeb) return;
    try {
      await _ensureRustReady();
      await RustLib.instance.api.crateIntegrationSyncControlManualSync();
      _hasSyncError = false;
      _hasAuthIssue = false;
      _notifyConnectionStateChanged();
    } catch (e) {
      _hasSyncError = true;
      _notifyConnectionStateChanged();
      debugPrint('Api.manualSync failed: $e');
      final s = e.toString().toLowerCase();
      if (s.contains(_permissionDeniedCode.toLowerCase())) {
        ToastService.showError('You don’t have permission to make changes in this wallet. Pending local changes were discarded.');
      }
      if (_isAuthDeclinedError(e)) {
        await _handleAuthDeclined();
        return;
      }
      await drainRustLogsToConsole();
      rethrow;
    }
    await drainRustLogsToConsole();
  }

  /// Drain buffered Rust log lines and print them to the Flutter console (debugPrint).
  static Future<void> drainRustLogsToConsole() async {
    if (kIsWeb) return;
    try {
      final lines = await rust.drainRustLogs();
      for (final line in lines) {
        debugPrint(line);
      }
    } catch (_) {}
  }

  static bool get hasSyncError => _hasSyncError;

  static Future<String> getSyncStatusForUI() async =>
      connectionState.status;

  /// Synchronous status for UI: Offline, Error, or Synced. Prefer [connectionState] for full state.
  static String get syncStatusForUI => connectionState.status;

  // ---------- WebSocket (Flutter only; online = connected, offline = not connected; reconnect every [reconnectInterval]) ----------
  static bool get isRealtimeConnected => _wsConnected;

  static void setRealtimeErrorCallback(void Function(String)? cb) {
    _realtimeErrorCallback = cb;
  }

  // ---------- Realtime ----------
  //
  // The WebSocket connection + reconnection + events_synced handler all
  // live in Rust now (crates/client/src/ws.rs). Dart's job here is
  // exactly two FFI calls. Per the dart-is-ui-only rule, Dart must not
  // open sockets, parse server messages, or run reconnect timers.
  //
  // `_wsConnected` is kept as an optimistic UI flag — true after we
  // ask Rust to connect, false after we ask Rust to disconnect. The
  // Rust worker handles all the real connection state. A future change
  // can have Rust push real connection state back through a stream.
  static Future<void> connectRealtime() async {
    try {
      await rust_ws.connectRealtime();
      _wsConnected = true;
      _notifyConnectionStateChanged();
    } catch (_) {
      _wsConnected = false;
      _notifyConnectionStateChanged();
      rethrow;
    }
  }

  static Future<void> disconnectRealtime() async {
    try {
      await rust_ws.disconnectRealtime();
    } finally {
      _wsConnected = false;
      _notifyConnectionStateChanged();
    }
  }

  // Internal helper used by setCurrentWalletId to force a reconnect on
  // wallet switch — the Rust worker captures the wallet_id at connect
  // time so a wallet change means disconnect + reconnect.
  static Future<void> _wsDisconnect() async {
    await disconnectRealtime();
  }

  // ---------- Settings (Rust-stored preferences; Dart only reads/writes via FFI) ----------
  static Future<bool> _getPrefBool(String key, bool defaultValue) async {
    if (kIsWeb) return defaultValue;
    try {
      await _ensureRustReady();
      final v = await rust.getPreference(key: key);
      if (v == null || v.isEmpty) return defaultValue;
      return v == 'true';
    } catch (_) {
      return defaultValue;
    }
  }

  static Future<void> _setPrefBool(String key, bool value) async {
    if (kIsWeb) return;
    try {
      await _ensureRustReady();
      await rust.setPreference(key: key, value: value ? 'true' : 'false');
    } catch (_) {}
  }

  static Future<String> _getPrefString(String key, String defaultValue) async {
    if (kIsWeb) return defaultValue;
    try {
      await _ensureRustReady();
      final v = await rust.getPreference(key: key);
      return (v != null && v.isNotEmpty) ? v : defaultValue;
    } catch (_) {
      return defaultValue;
    }
  }

  static Future<void> _setPrefString(String key, String value) async {
    if (kIsWeb) return;
    try {
      await _ensureRustReady();
      await rust.setPreference(key: key, value: value);
    } catch (_) {}
  }

  static Future<int> _getPrefInt(String key, int defaultValue) async {
    if (kIsWeb) return defaultValue;
    try {
      await _ensureRustReady();
      final v = await rust.getPreference(key: key);
      if (v == null || v.isEmpty) return defaultValue;
      return int.tryParse(v) ?? defaultValue;
    } catch (_) {
      return defaultValue;
    }
  }

  static Future<void> _setPrefInt(String key, int value) async {
    if (kIsWeb) return;
    try {
      await _ensureRustReady();
      await rust.setPreference(key: key, value: value.toString());
    } catch (_) {}
  }

  static Future<bool> getDarkMode() async =>
      _getPrefBool(_keyDarkMode, true);
  static Future<void> setDarkMode(bool enabled) async =>
      _setPrefBool(_keyDarkMode, enabled);

  static Future<String> getDefaultDirection() async =>
      _getPrefString(_keyDefaultDirection, 'received');
  static Future<void> setDefaultDirection(String direction) async =>
      _setPrefString(_keyDefaultDirection, direction);

  static Future<bool> getFlipColors() async =>
      _getPrefBool(_keyFlipColors, false);
  static Future<void> setFlipColors(bool flip) async =>
      _setPrefBool(_keyFlipColors, flip);

  static Future<bool> getDueDateEnabled() async =>
      _getPrefBool(_keyDueDateEnabled, true);
  static Future<void> setDueDateEnabled(bool enabled) async =>
      _setPrefBool(_keyDueDateEnabled, enabled);

  static Future<int> getDefaultDueDateDays() async =>
      _getPrefInt(_keyDefaultDueDateDays, 14);
  static Future<void> setDefaultDueDateDays(int days) async =>
      _setPrefInt(_keyDefaultDueDateDays, days);

  static Future<bool> getDefaultDueDateSwitch() async =>
      _getPrefBool(_keyDefaultDueDateSwitch, true);
  static Future<void> setDefaultDueDateSwitch(bool enabled) async =>
      _setPrefBool(_keyDefaultDueDateSwitch, enabled);

  static Future<bool> getShowDashboardChart() async =>
      _getPrefBool(_keyShowDashboardChart, true);
  static Future<void> setShowDashboardChart(bool enabled) async =>
      _setPrefBool(_keyShowDashboardChart, enabled);

  static Future<String> getDashboardDefaultPeriod() async =>
      _getPrefString(_keyDashboardDefaultPeriod, 'month');
  static Future<void> setDashboardDefaultPeriod(String period) async =>
      _setPrefString(_keyDashboardDefaultPeriod, period);

  static Future<String> getGraphDefaultPeriod() async =>
      _getPrefString(_keyGraphDefaultPeriod, 'month');
  static Future<void> setGraphDefaultPeriod(String period) async =>
      _setPrefString(_keyGraphDefaultPeriod, period);

  static Future<bool> getInvertYAxis() async =>
      _getPrefBool(_keyInvertYAxis, false);
  static Future<void> setInvertYAxis(bool invert) async =>
      _setPrefBool(_keyInvertYAxis, invert);

  static Future<void> loadSettingsFromBackend() async {}

  // ---------- Biometric ----------
  static final LocalAuthentication _localAuth = LocalAuthentication();

  static Future<bool> isBiometricAvailable() async {
    if (kIsWeb) return false;
    try {
      final ok = await _localAuth.canCheckBiometrics;
      final supported = await _localAuth.isDeviceSupported();
      return ok && supported;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticateWithBiometrics() async {
    if (kIsWeb) return false;
    try {
      final ok = await _localAuth.canCheckBiometrics;
      final supported = await _localAuth.isDeviceSupported();
      if (!ok || !supported) return false;
      return await _localAuth.authenticate(
        localizedReason: 'Authenticate to access the app',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
    } catch (_) {
      return false;
    }
  }
}
