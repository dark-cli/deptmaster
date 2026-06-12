import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/event.dart';
import '../src/lib.dart' as rust;
import '../api.dart';
import 'data_change_provider.dart';
import 'wallets_provider.dart';

/// All events for the currently-selected wallet, used by the events
/// log screen. Reactive: rebuilds on contacts / transactions /
/// permissions events for the current wallet (any of those produce
/// new entries in the log).
final eventsProvider = FutureProvider<List<Event>>((ref) async {
  final walletId = await ref.watch(currentWalletIdProvider.future);
  invalidateOnDataChange(
    ref,
    kinds: [
      DataChangeKind.contacts,
      DataChangeKind.transactions,
      DataChangeKind.permissions,
    ],
    walletId: walletId,
  );
  final jsonStr = await rust.getEvents();
  final decoded = jsonDecode(jsonStr);
  if (decoded is! List) {
    throw const FormatException('Expected a JSON array from getEvents()');
  }
  return decoded
      .cast<Map<String, dynamic>>()
      .map(Event.fromJson)
      .toList(growable: false);
});
