import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/wallet.dart';
import 'api_service.dart';

/// Service for managing wallets and current wallet context
class WalletService {
  static const String _currentWalletKey = 'current_wallet_id';
  static const String _walletsBoxName = 'wallets';
  
  static String? _currentWalletId;
  static List<Wallet>? _cachedWallets;

  /// Initialize wallet service
  static Future<void> initialize() async {
    try {
      // Open wallets box
      await Hive.openBox<Wallet>(_walletsBoxName);
      
      // Load current wallet from preferences
      final prefs = await SharedPreferences.getInstance();
      _currentWalletId = prefs.getString(_currentWalletKey);
      
      print('✅ WalletService initialized. Current wallet: $_currentWalletId');
    } catch (e) {
      print('⚠️ Error initializing WalletService: $e');
    }
  }

  /// Get current wallet ID
  static String? getCurrentWalletId() {
    return _currentWalletId;
  }

  /// Set current wallet ID
  static Future<void> setCurrentWalletId(String walletId) async {
    _currentWalletId = walletId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentWalletKey, walletId);
    print('✅ Current wallet set to: $walletId');
  }

  /// Clear current wallet (logout scenario)
  static Future<void> clearCurrentWallet() async {
    _currentWalletId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_currentWalletKey);
    _cachedWallets = null;
    print('✅ Current wallet cleared');
  }

  /// Get user's wallets from server. Throws on network/API failure so UI can show retry.
  static Future<List<Wallet>> getUserWallets() async {
    try {
      final wallets = await ApiService.getWallets();
      await _cacheWallets(wallets);
      _cachedWallets = wallets;
      return wallets;
    } catch (e) {
      print('⚠️ Error fetching wallets: $e');
      // Return cached wallets if we have them (e.g. offline), but still rethrow
      // so the UI can show "load failed, retry" when cache is empty
      final cached = await _getCachedWallets();
      if (cached.isNotEmpty) {
        return cached;
      }
      rethrow;
    }
  }

  /// Get cached wallets from local storage
  static Future<List<Wallet>> _getCachedWallets() async {
    try {
      final walletsBox = Hive.box<Wallet>(_walletsBoxName);
      return walletsBox.values.toList();
    } catch (e) {
      print('⚠️ Error reading cached wallets: $e');
      return [];
    }
  }

  /// Cache wallets to local storage
  static Future<void> _cacheWallets(List<Wallet> wallets) async {
    try {
      final walletsBox = Hive.box<Wallet>(_walletsBoxName);
      await walletsBox.clear();
      for (final wallet in wallets) {
        await walletsBox.put(wallet.id, wallet);
      }
    } catch (e) {
      print('⚠️ Error caching wallets: $e');
    }
  }

  /// Get wallet by ID
  static Future<Wallet?> getWallet(String walletId) async {
    try {
      // Try cache first
      final walletsBox = Hive.box<Wallet>(_walletsBoxName);
      final cached = walletsBox.get(walletId);
      if (cached != null) {
        return cached;
      }
      
      // If not in cache, fetch from server
      final wallets = await getUserWallets();
      try {
        return wallets.firstWhere((w) => w.id == walletId);
      } catch (e) {
        return null;
      }
    } catch (e) {
      print('⚠️ Error getting wallet: $e');
      return null;
    }
  }

  /// Ensure current wallet is set (use first wallet if none set)
  static Future<String?> ensureCurrentWallet() async {
    if (_currentWalletId != null) {
      return _currentWalletId;
    }

    // Try to get wallets and use the first one
    final wallets = await getUserWallets();
    if (wallets.isNotEmpty) {
      await setCurrentWalletId(wallets.first.id);
      return wallets.first.id;
    }

    return null;
  }
}
