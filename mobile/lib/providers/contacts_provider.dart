import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/contact.dart';
import '../src/lib.dart' as rust;
import '../api.dart';
import 'data_change_provider.dart';
import 'wallets_provider.dart';

/// Contacts for the currently-selected wallet, sorted by name. Reactive:
/// rebuilds when a [DataChangeKind.contacts] event arrives for that
/// wallet (local CRUD, sync pull, undo). Throws if no wallet is
/// selected (mirrors `currentWalletIdProvider`).
final contactsProvider = FutureProvider<List<Contact>>((ref) async {
  final walletId = await ref.watch(currentWalletIdProvider.future);
  invalidateOnDataChange(
    ref,
    kinds: [DataChangeKind.contacts],
    walletId: walletId,
  );
  final jsonStr = await rust.getContacts();
  final decoded = jsonDecode(jsonStr);
  if (decoded is! List) {
    throw const FormatException('Expected a JSON array from getContacts()');
  }
  return decoded
      .cast<Map<String, dynamic>>()
      .map(Contact.fromJson)
      .toList(growable: false);
});

/// Single contact by id. Throws if the contact doesn't exist or has
/// been deleted. Reactive: rebuilds on [DataChangeKind.contacts].
final contactByIdProvider = FutureProvider.family<Contact, String>((ref, id) async {
  final walletId = await ref.watch(currentWalletIdProvider.future);
  invalidateOnDataChange(
    ref,
    kinds: [DataChangeKind.contacts],
    walletId: walletId,
  );
  final jsonStr = await rust.getContact(id: id);
  return Contact.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
});
