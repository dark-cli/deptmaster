import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/transaction.dart';
import '../src/lib.dart' as rust;
import '../api.dart';
import 'data_change_provider.dart';
import 'wallets_provider.dart';

/// All transactions for the currently-selected wallet. Reactive:
/// rebuilds on [DataChangeKind.transactions] events for this wallet.
/// Throws if no wallet is selected.
final transactionsProvider = FutureProvider<List<Transaction>>((ref) async {
  final walletId = await ref.watch(currentWalletIdProvider.future);
  invalidateOnDataChange(
    ref,
    kinds: [DataChangeKind.transactions],
    walletId: walletId,
  );
  final jsonStr = await rust.getTransactions();
  final decoded = jsonDecode(jsonStr);
  if (decoded is! List) {
    throw const FormatException('Expected a JSON array from getTransactions()');
  }
  return decoded
      .cast<Map<String, dynamic>>()
      .map(Transaction.fromJson)
      .toList(growable: false);
});

/// Single transaction by id. Throws if the transaction doesn't exist
/// or has been deleted. Reactive on [DataChangeKind.transactions].
final transactionByIdProvider =
    FutureProvider.family<Transaction, String>((ref, id) async {
  final walletId = await ref.watch(currentWalletIdProvider.future);
  invalidateOnDataChange(
    ref,
    kinds: [DataChangeKind.transactions],
    walletId: walletId,
  );
  final jsonStr = await rust.getTransaction(id: id);
  return Transaction.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
});

/// Transactions filtered to a single contact. Computed on top of
/// [transactionsProvider] so it shares its cache and reactivity —
/// changing a transaction invalidates the master list, which fans out
/// here automatically.
final transactionsForContactProvider =
    FutureProvider.family<List<Transaction>, String>((ref, contactId) async {
  final all = await ref.watch(transactionsProvider.future);
  return all.where((t) => t.contactId == contactId).toList(growable: false);
});
