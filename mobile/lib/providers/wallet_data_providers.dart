import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../models/contact.dart';
import '../models/transaction.dart';
import 'data_bus.dart';

final dataBusProvider = ChangeNotifierProvider<DataBus>((ref) => DataBus.instance);

/// Active wallet id (from Rust config).
///
/// Rebuilds when the wallet changes.
final activeWalletIdProvider = FutureProvider<String?>((ref) async {
  // Only re-run when wallet revision changes.
  ref.watch(dataBusProvider.select((b) => b.revWallet));
  return Api.getCurrentWalletId();
});

/// Contacts for the currently active wallet.
final contactsProvider = FutureProvider<List<Contact>>((ref) async {
  // Refresh only when contacts/all changes or wallet changes.
  // Contacts balances depend on transactions too, so include transaction revision.
  ref.watch(dataBusProvider.select((b) => b.revContacts ^ b.revTransactions ^ b.revAll ^ b.revWallet));

  final walletId = await ref.watch(activeWalletIdProvider.future);
  if (walletId == null || walletId.isEmpty) return [];

  final jsonStr = await Api.getContacts();
  final list = jsonDecode(jsonStr) as List<dynamic>? ?? [];
  return list.map((e) => Contact.fromJson(e as Map<String, dynamic>)).toList();
});

/// Transactions for the currently active wallet.
final transactionsProvider = FutureProvider<List<Transaction>>((ref) async {
  // Refresh only when transactions/all changes or wallet changes.
  ref.watch(dataBusProvider.select((b) => b.revTransactions ^ b.revAll ^ b.revWallet));

  final walletId = await ref.watch(activeWalletIdProvider.future);
  if (walletId == null || walletId.isEmpty) return [];

  final jsonStr = await Api.getTransactions();
  final list = jsonDecode(jsonStr) as List<dynamic>? ?? [];
  return list.map((e) => Transaction.fromJson(e as Map<String, dynamic>)).toList();
});

