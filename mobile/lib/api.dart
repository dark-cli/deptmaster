// Single API to Rust. UI calls only this. No other service layers.
// Initialize: Api.init() then Api.initStorage(documentsPath).

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:local_auth/local_auth.dart';

import 'src/frb_generated.dart';
import 'src/lib.dart' as rust;

class Api {
  static bool _initialized = false;
  static bool _hasSyncError = false;
  static WebSocketChannel? _wsChannel;
  static StreamSubscription? _wsSubscription;
  static bool _wsConnected = false;
  static bool _wsConnecting = false;
  static final List<void Function(Map<String, dynamic>)> _realtimeListeners = [];
  static final List<void Function()> _dataChangedListeners = [];
  static void Function(String)? _realtimeErrorCallback;

  static const _keyBackendIp = 'backend_ip';
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

  static void Function()? onLogout;

  /// Last init error (e.g. native library not found). Cleared on success.
  static String? initError;

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
        await rust.setBackendConfig(baseUrl: baseUrl, wsUrl: wsUrl);
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
    if (!_initialized) await init();
    try {
      await rust.initStorage(storagePath: path);
    } catch (e) {
      debugPrint('Api.initStorage: $e');
    }
  }

  // ---------- Backend config (prefs + Rust) ----------
  static String get defaultBackendIp => 'localhost';
  static int get defaultBackendPort => 8000;

  static Future<String> getBackendIp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyBackendIp) ?? defaultBackendIp;
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
    final ip = await getBackendIp();
    final port = await getBackendPort();
    final https = await getUseHttps();
    return '${https ? 'https' : 'http'}://$ip:$port';
  }

  static Future<String> getWebSocketUrl() async {
    final ip = await getBackendIp();
    final port = await getBackendPort();
    final https = await getUseHttps();
    return '${https ? 'wss' : 'ws'}://$ip:$port/ws';
  }

  static Future<void> setBackendConfig(String ip, int port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBackendIp, ip);
    await prefs.setInt(_keyBackendPort, port);
    await prefs.setBool(_keyBackendConfigured, true);
    final baseUrl = await getBaseUrl();
    final wsUrl = await getWebSocketUrl();
    if (!kIsWeb && _initialized) {
      try {
        await rust.setBackendConfig(baseUrl: baseUrl, wsUrl: wsUrl);
      } catch (_) {}
    }
  }

  // ---------- Auth (Rust) ----------
  static Future<void> login(String username, String password) async {
    if (!_initialized && !(await init())) {
      throw StateError(initError ?? 'Rust library not loaded. Did you forget to call init?');
    }
    if (kIsWeb) throw UnsupportedError('Login not supported on web');
    await rust.login(username: username, password: password);
  }

  static Future<void> logout() async {
    if (!kIsWeb) {
      try {
        await rust.logout();
      } catch (_) {}
    }
    await _wsDisconnect();
    onLogout?.call();
  }

  static Future<bool> isLoggedIn() async {
    if (!_initialized) await init();
    if (kIsWeb) return false;
    try {
      return await rust.isLoggedIn();
    } catch (_) {
      return false;
    }
  }

  static Future<String?> getUserId() async {
    if (!_initialized) await init();
    if (kIsWeb) return null;
    try {
      return await rust.getUserId();
    } catch (_) {
      return null;
    }
  }

  static Future<String?> getToken() async {
    if (!_initialized) await init();
    if (kIsWeb) return null;
    try {
      return await rust.getToken();
    } catch (_) {
      return null;
    }
  }

  /// True if JWT is expired or invalid. Used to avoid WebSocket 401 spam.
  static bool _isTokenExpired(String? token) {
    if (token == null || token.isEmpty) return true;
    final parts = token.split('.');
    if (parts.length != 3) return true;
    try {
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final map = json.decode(payload) as Map<String, dynamic>;
      final exp = map['exp'];
      if (exp == null) return true;
      final expSec = exp is int ? exp : (exp as num).toInt();
      return DateTime.now().millisecondsSinceEpoch ~/ 1000 >= expSec;
    } catch (_) {
      return true;
    }
  }

  static Future<bool> validateAuth() async {
    if (kIsWeb) return false;
    try {
      await rust.manualSync();
      _hasSyncError = false;
      return true;
    } catch (e) {
      final s = e.toString().toLowerCase();
      if (s.contains('401') || s.contains('authentication') || s.contains('expired')) {
        try {
          await rust.logout();
        } catch (_) {}
        onLogout?.call();
        return false;
      }
      rethrow;
    }
  }

  // ---------- Wallet (Rust) ----------
  static Future<String?> getCurrentWalletId() async {
    if (!_initialized) await init();
    if (kIsWeb) return null;
    try {
      return await rust.getCurrentWalletId();
    } catch (_) {
      return null;
    }
  }

  static Future<void> setCurrentWalletId(String walletId) async {
    if (kIsWeb) return;
    try {
      await rust.setCurrentWalletId(walletId: walletId);
    } catch (e) {
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getWallets() async {
    if (!_initialized) await init();
    if (kIsWeb) return [];
    try {
      final json = await rust.getWallets();
      final list = jsonDecode(json) as List<dynamic>?;
      return list?.map((e) => e as Map<String, dynamic>).toList() ?? [];
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, dynamic>?> createWallet(String name, String description) async {
    if (kIsWeb) return null;
    try {
      final json = await rust.createWallet(name: name, description: description);
      return jsonDecode(json) as Map<String, dynamic>?;
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> ensureCurrentWallet() async {
    if (kIsWeb) return;
    await rust.ensureCurrentWallet();
  }

  static Future<Map<String, dynamic>?> getWallet(String id) async {
    final list = await getWallets();
    try {
      return list.firstWhere((w) => w['id'] == id);
    } catch (_) {
      return null;
    }
  }

  // ---------- Data (Rust) ----------
  static Future<String> getContacts() async {
    if (!_initialized) await init();
    if (kIsWeb) return '[]';
    try {
      return await rust.getContacts();
    } catch (_) {
      return '[]';
    }
  }

  static Future<String> getTransactions() async {
    if (!_initialized) await init();
    if (kIsWeb) return '[]';
    try {
      return await rust.getTransactions();
    } catch (_) {
      return '[]';
    }
  }

  static Future<String?> getContact(String id) async {
    if (!_initialized) await init();
    if (kIsWeb) return null;
    try {
      return await rust.getContact(id: id);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> getTransaction(String id) async {
    if (!_initialized) await init();
    if (kIsWeb) return null;
    try {
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
  }) async {
    if (kIsWeb) throw UnsupportedError('Not on web');
    final result = await rust.createContact(
      name: name,
      username: username,
      phone: phone,
      email: email,
      notes: notes,
    );
    _notifyDataChanged();
    return result;
  }

  static Future<void> updateContact({
    required String id,
    required String name,
    String? username,
    String? phone,
    String? email,
    String? notes,
  }) async {
    if (kIsWeb) return;
    await rust.updateContact(
      id: id,
      name: name,
      username: username,
      phone: phone,
      email: email,
      notes: notes,
    );
    _notifyDataChanged();
  }

  static Future<void> deleteContact(String contactId) async {
    if (kIsWeb) return;
    await rust.deleteContact(contactId: contactId);
    _notifyDataChanged();
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
    _notifyDataChanged();
    return result;
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
    _notifyDataChanged();
  }

  static Future<void> deleteTransaction(String transactionId) async {
    if (kIsWeb) return;
    await rust.deleteTransaction(transactionId: transactionId);
    _notifyDataChanged();
  }

  static Future<void> undoContactAction(String contactId) async {
    if (kIsWeb) return;
    await rust.undoContactAction(contactId: contactId);
    _notifyDataChanged();
  }

  static Future<void> undoTransactionAction(String transactionId) async {
    if (kIsWeb) return;
    await rust.undoTransactionAction(transactionId: transactionId);
    _notifyDataChanged();
  }

  static Future<void> bulkDeleteContacts(List<String> ids) async {
    if (kIsWeb) return;
    await rust.bulkDeleteContacts(contactIds: ids);
    _notifyDataChanged();
  }

  static Future<void> bulkDeleteTransactions(List<String> ids) async {
    if (kIsWeb) return;
    await rust.bulkDeleteTransactions(transactionIds: ids);
    _notifyDataChanged();
  }

  static Future<String> getEvents() async {
    if (!_initialized) await init();
    if (kIsWeb) return '[]';
    try {
      final currentWalletId = await getCurrentWalletId();
      if (currentWalletId == null || currentWalletId.isEmpty) {
        debugPrint('Api.getEvents: no current wallet set – cannot load events');
        return '[]';
      }
      final json = await rust.getEvents();
      final list = jsonDecode(json) as List<dynamic>? ?? [];
      if (list.isEmpty) {
        debugPrint('Api.getEvents: 0 events for current wallet $currentWalletId');
      }
      return json;
    } catch (e) {
      debugPrint('Api.getEvents failed: $e');
      return '[]';
    }
  }

  // ---------- Data changed (notify UI to refresh) ----------
  static void addDataChangedListener(void Function() listener) {
    _dataChangedListeners.add(listener);
  }

  static void removeDataChangedListener(void Function() listener) {
    _dataChangedListeners.remove(listener);
  }

  static void _notifyDataChanged() {
    for (final fn in List<void Function()>.from(_dataChangedListeners)) {
      try {
        fn();
      } catch (_) {}
    }
  }

  // ---------- Sync (Rust) ----------
  static Future<void> manualSync() async {
    if (kIsWeb) return;
    try {
      await rust.manualSync();
      _hasSyncError = false;
      _notifyDataChanged();
    } catch (e) {
      _hasSyncError = true;
      debugPrint('Api.manualSync failed: $e');
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

  static Future<String> getSyncStatusForUI() async {
    return _hasSyncError ? 'Error' : 'Synced';
  }

  // ---------- WebSocket ----------
  static bool get isRealtimeConnected => _wsConnected;

  static void setRealtimeErrorCallback(void Function(String)? cb) {
    _realtimeErrorCallback = cb;
  }

  static void addRealtimeListener(void Function(Map<String, dynamic>) listener) {
    _realtimeListeners.add(listener);
  }

  static void removeRealtimeListener(void Function(Map<String, dynamic>) listener) {
    _realtimeListeners.remove(listener);
  }

  static Future<void> connectRealtime() async {
    if (_wsConnected && _wsChannel != null) return;
    if (_wsConnecting) return;
    final token = await getToken();
    if (token == null || token.isEmpty) return;
    if (_isTokenExpired(token)) return;

    _wsConnecting = true;
    try {
      final wsUrl = await getWebSocketUrl();
      final uri = Uri.parse(wsUrl).replace(queryParameters: {'token': token});
      final channel = WebSocketChannel.connect(uri);

      _wsSubscription = channel.stream.listen(
        (message) {
          if (!_wsConnected) {
            _wsConnecting = false;
            _wsConnected = true;
            _wsChannel = channel;
            manualSync().catchError((_) {});
          }
          try {
            final data = json.decode(message as String) as Map<String, dynamic>;
            for (final fn in _realtimeListeners) fn(data);
            manualSync().catchError((_) {});
          } catch (_) {}
        },
        onError: (_) {
          _wsConnected = false;
          _wsChannel = null;
          _wsSubscription = null;
          _reconnectWs();
        },
        onDone: () {
          _wsConnected = false;
          _wsConnecting = false;
          _wsChannel = null;
          _wsSubscription = null;
          _reconnectWs();
        },
        cancelOnError: false,
      );
      _wsChannel = channel;
    } catch (_) {
      _wsConnecting = false;
      _reconnectWs();
    }
  }

  static void _reconnectWs() {
    getToken().then((token) {
      if (token == null || token.isEmpty) return;
      if (_isTokenExpired(token)) return;
      Future.delayed(const Duration(seconds: 5), () {
        if (!_wsConnected) connectRealtime().catchError((_) => _reconnectWs());
      });
    });
  }

  static Future<void> _wsDisconnect() async {
    try {
      await _wsSubscription?.cancel();
    } catch (_) {}
    try {
      await _wsChannel?.sink.close();
    } catch (_) {}
    _wsChannel = null;
    _wsSubscription = null;
    _wsConnected = false;
  }

  static Future<void> disconnectRealtime() async {
    await _wsDisconnect();
  }

  static Future<void> syncWhenOnline() async {
    if (!_wsConnected) return;
    try {
      await manualSync();
    } catch (_) {}
  }

  // ---------- Settings (prefs only) ----------
  static Future<bool> getDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyDarkMode) ?? true;
  }

  static Future<void> setDarkMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDarkMode, enabled);
  }

  static Future<String> getDefaultDirection() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDefaultDirection) ?? 'received';
  }

  static Future<void> setDefaultDirection(String direction) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDefaultDirection, direction);
  }

  static Future<bool> getFlipColors() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyFlipColors) ?? false;
  }

  static Future<void> setFlipColors(bool flip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyFlipColors, flip);
  }

  static Future<bool> getDueDateEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyDueDateEnabled) ?? true;
  }

  static Future<void> setDueDateEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDueDateEnabled, enabled);
  }

  static Future<int> getDefaultDueDateDays() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyDefaultDueDateDays) ?? 14;
  }

  static Future<void> setDefaultDueDateDays(int days) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyDefaultDueDateDays, days);
  }

  static Future<bool> getDefaultDueDateSwitch() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyDefaultDueDateSwitch) ?? true;
  }

  static Future<void> setDefaultDueDateSwitch(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDefaultDueDateSwitch, enabled);
  }

  static Future<bool> getShowDashboardChart() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyShowDashboardChart) ?? true;
  }

  static Future<void> setShowDashboardChart(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowDashboardChart, enabled);
  }

  static Future<String> getDashboardDefaultPeriod() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDashboardDefaultPeriod) ?? 'month';
  }

  static Future<void> setDashboardDefaultPeriod(String period) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDashboardDefaultPeriod, period);
  }

  static Future<String> getGraphDefaultPeriod() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyGraphDefaultPeriod) ?? 'month';
  }

  static Future<void> setGraphDefaultPeriod(String period) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGraphDefaultPeriod, period);
  }

  static Future<bool> getInvertYAxis() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyInvertYAxis) ?? false;
  }

  static Future<void> setInvertYAxis(bool invert) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyInvertYAxis, invert);
  }

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
