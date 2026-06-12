import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/lib.dart' as rust;
import '../api.dart';
import 'data_change_provider.dart';
import 'wallets_provider.dart';

/// One permission check: "can the current user perform `action` on a
/// resource of `resourceType` (optionally a specific instance
/// `resourceId`)?". Wrapped in a class so it's a stable family key.
class PermCheck {
  final String action;
  final String resourceType;
  final String? resourceId;

  const PermCheck({
    required this.action,
    required this.resourceType,
    this.resourceId,
  });

  // Common shorthands for screens.
  const PermCheck.editContact(String id)
      : action = 'contact:write',
        resourceType = 'contact',
        resourceId = id;
  const PermCheck.deleteContact(String id)
      : action = 'contact:delete',
        resourceType = 'contact',
        resourceId = id;
  const PermCheck.createContact()
      : action = 'contact:write',
        resourceType = 'contact',
        resourceId = null;
  const PermCheck.editTransaction(String id)
      : action = 'transaction:write',
        resourceType = 'transaction',
        resourceId = id;
  const PermCheck.deleteTransaction(String id)
      : action = 'transaction:delete',
        resourceType = 'transaction',
        resourceId = id;
  const PermCheck.createTransaction()
      : action = 'transaction:write',
        resourceType = 'transaction',
        resourceId = null;

  @override
  bool operator ==(Object other) =>
      other is PermCheck &&
      action == other.action &&
      resourceType == other.resourceType &&
      resourceId == other.resourceId;

  @override
  int get hashCode => Object.hash(action, resourceType, resourceId);
}

/// `true` if the current user can perform the given action against the
/// given resource. Uses Rust-side `canPerform`, which evaluates the
/// shared permission resolver against the local projection tables —
/// no network roundtrip. Authoritative answer still comes from the
/// server when the user actually attempts the write; this is for UX
/// (greying out buttons, hiding actions the user can't take).
///
/// Reactive on the current wallet (re-checks on wallet switch) and on
/// [DataChangeKind.permissions] events (matrix changes, group
/// memberships, role changes). Defaults to `false` on error to fail
/// closed — a button stays disabled if we can't prove the user can
/// click it.
final canPerformProvider = FutureProvider.family<bool, PermCheck>((ref, check) async {
  await ref.watch(currentWalletIdProvider.future);
  invalidateOnDataChange(
    ref,
    kinds: [DataChangeKind.permissions, DataChangeKind.walletMembership],
  );
  return await rust.canPerform(
    actionName: check.action,
    resourceType: check.resourceType,
    resourceId: check.resourceId,
  );
});
