import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/wallet.dart';
import '../src/lib.dart' as rust;
import '../api.dart';
import 'data_change_provider.dart';

/// List of wallets the current user is a member of. Reactive: rebuilds
/// when the Rust client emits a [DataChangeKind.wallets] or
/// [DataChangeKind.walletMembership] event.
final walletsProvider = FutureProvider<List<Wallet>>((ref) async {
  invalidateOnDataChange(
    ref,
    kinds: [DataChangeKind.wallets, DataChangeKind.walletMembership],
  );
  final jsonStr = await rust.getWallets();
  final decoded = jsonDecode(jsonStr);
  if (decoded is! List) {
    throw const FormatException('Expected a JSON array from getWallets()');
  }
  return decoded
      .cast<Map<String, dynamic>>()
      .map(Wallet.fromJson)
      .toList(growable: false);
});

/// UUID of the wallet the user has selected. Throws if no wallet is
/// selected — screens should treat that as "show wallet picker".
/// Reactive: rebuilds when [DataChangeKind.wallets] arrives (covers
/// wallet creation / deletion / switching).
final currentWalletIdProvider = FutureProvider<String>((ref) async {
  invalidateOnDataChange(ref, kinds: [DataChangeKind.wallets]);
  return await rust.getCurrentWalletId();
});

/// Same as [currentWalletIdProvider] but returns `null` instead of
/// throwing when no wallet is selected. Kept for screens that already
/// handle the "no wallet yet" case via null-check; new code should
/// prefer [currentWalletIdProvider] and let the AsyncValue.error path
/// route to the wallet picker.
final activeWalletIdProvider = FutureProvider<String?>((ref) async {
  try {
    return await ref.watch(currentWalletIdProvider.future);
  } catch (_) {
    return null;
  }
});

/// Convenience: the [Wallet] object for the currently-selected wallet,
/// looked up from the list. Throws if no wallet is selected or if the
/// selected id no longer matches any wallet in the list.
final currentWalletProvider = FutureProvider<Wallet>((ref) async {
  final id = await ref.watch(currentWalletIdProvider.future);
  final wallets = await ref.watch(walletsProvider.future);
  return wallets.firstWhere(
    (w) => w.id == id,
    orElse: () => throw StateError('Current wallet $id not in wallet list'),
  );
});
