import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/contact.dart';
import '../models/event.dart';
import '../models/transaction.dart';
import '../models/wallet.dart';
import 'api_provider.dart';
import 'data_bus.dart';

final dataBusProvider = ChangeNotifierProvider<DataBus>((ref) => DataBus.instance);

/// Active wallet id (from Rust config).
///
/// Rebuilds when the wallet changes.
final activeWalletIdProvider = FutureProvider<String?>((ref) async {
  ref.watch(dataBusProvider.select((b) => b.revWallet));
  final api = ref.watch(apiProvider);
  return api.getCurrentWalletId();
});

/// Contacts for the currently active wallet.
final contactsProvider = FutureProvider<List<Contact>>((ref) async {
  ref.watch(dataBusProvider.select((b) => b.revContacts ^ b.revTransactions ^ b.revAll ^ b.revWallet));

  final walletId = await ref.watch(activeWalletIdProvider.future);
  if (walletId == null || walletId.isEmpty) return [];

  final api = ref.watch(apiProvider);
  final jsonStr = await api.getContacts();
  final list = jsonDecode(jsonStr) as List<dynamic>? ?? [];
  return list.map((e) => Contact.fromJson(e as Map<String, dynamic>)).toList();
});

/// Transactions for the currently active wallet.
final transactionsProvider = FutureProvider<List<Transaction>>((ref) async {
  ref.watch(dataBusProvider.select((b) => b.revTransactions ^ b.revAll ^ b.revWallet));

  final walletId = await ref.watch(activeWalletIdProvider.future);
  if (walletId == null || walletId.isEmpty) return [];

  final api = ref.watch(apiProvider);
  final jsonStr = await api.getTransactions();
  final list = jsonDecode(jsonStr) as List<dynamic>? ?? [];
  return list.map((e) => Transaction.fromJson(e as Map<String, dynamic>)).toList();
});

/// Wallets list for the current user.
final walletsProvider = FutureProvider<List<Wallet>>((ref) async {
  ref.watch(dataBusProvider.select((b) => b.revWallet ^ b.revAll));
  final api = ref.watch(apiProvider);
  final list = await api.getWallets();
  return list.map((m) => Wallet.fromJson(m)).toList();
});

/// Events for the currently active wallet.
final eventsProvider = FutureProvider<List<Event>>((ref) async {
  ref.watch(dataBusProvider.select((b) => b.revContacts ^ b.revTransactions ^ b.revAll ^ b.revWallet));

  final walletId = await ref.watch(activeWalletIdProvider.future);
  if (walletId == null || walletId.isEmpty) return [];

  final api = ref.watch(apiProvider);
  final jsonStr = await api.getEvents();
  final list = jsonDecode(jsonStr) as List<dynamic>? ?? [];
  return list.map((e) => Event.fromJson(e as Map<String, dynamic>)).toList();
});

