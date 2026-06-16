import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';

/// Reactive bus from Rust. Every provider that wants to invalidate on
/// a specific [DataChangeKind] subscribes to this and inspects the
/// event in a `ref.listen` callback.
///
/// The underlying stream is a broadcast cache over the single-listener
/// stream Rust exposes — multiple Riverpod providers can listen
/// independently and each will receive every event.
final dataChangeStreamProvider = StreamProvider<DataChangeEvent>((ref) {
  return Api.dataChangeStream;
});

/// Convenience: invalidate `ref` whenever a [DataChangeKind] matching
/// `kinds` arrives. Optionally scope to a specific wallet — events
/// for other wallets are ignored. Pass `walletId = null` to invalidate
/// on any wallet.
///
/// `DataChangeKind.session` ALWAYS triggers an invalidation, regardless
/// of `kinds` or `walletId`. A session change (login/logout) wipes the
/// local SQLite — any cached provider value is computed from now-deleted
/// data and would leak across user switches.
void invalidateOnDataChange(
  Ref ref, {
  required List<DataChangeKind> kinds,
  String? walletId,
}) {
  ref.listen(dataChangeStreamProvider, (_, asyncEv) {
    final ev = asyncEv.valueOrNull;
    if (ev == null) return;
    if (ev.kind == DataChangeKind.session) {
      ref.invalidateSelf();
      return;
    }
    if (!kinds.contains(ev.kind)) return;
    if (walletId != null && ev.walletId != walletId) return;
    ref.invalidateSelf();
  });
}
