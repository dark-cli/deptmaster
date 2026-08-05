import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart';

/// Trigger to refresh wallet management data when needed.
/// Invalidate this provider to force all wallet data to refetch.
final walletManagementRefreshTrigger = StateProvider<int>((ref) => 0);

/// Listen to data change stream and increment refresh trigger when permissions change.
final _dataChangeSetupProvider = FutureProvider.family<void, String>((ref, walletId) async {
  // This provider sets up the listener and returns a future that never completes,
  // ensuring the listener stays active for the lifetime of this provider instance.
  final completer = Completer<void>();

  final subscription = Api.dataChangeStream
      .where((event) {
        return event.kind == DataChangeKind.permissions &&
            (event.walletId == null || event.walletId == walletId);
      })
      .listen((_) {
        debugPrint('[wallet_management] got permissions event, incrementing trigger for wallet=$walletId');
        ref.read(walletManagementRefreshTrigger.notifier).state += 1;
      });

  // Keep the listener alive
  ref.onDispose(() => subscription.cancel());

  return completer.future;
});

/// Provides list of user groups for the current wallet.
final userGroupsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, walletId) async {
  debugPrint('[userGroupsProvider] fetching for wallet=$walletId');
  // Watch the refresh trigger to refetch when invalidated
  final trigger = ref.watch(walletManagementRefreshTrigger);
  debugPrint('[userGroupsProvider] trigger=$trigger, refetching...');
  // Set up the data change listener
  ref.watch(_dataChangeSetupProvider(walletId));

  try {
    final json = await Api.getWalletUserGroups(walletId);
    debugPrint('[userGroupsProvider] fetched ${json.length} groups');
    return json.cast<Map<String, dynamic>>();
  } catch (e) {
    debugPrint('[userGroupsProvider] error: $e');
    throw Exception('Failed to load user groups: $e');
  }
});

/// Provides list of contact groups for the current wallet.
final contactGroupsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, walletId) async {
  ref.watch(walletManagementRefreshTrigger);
  ref.watch(_dataChangeSetupProvider(walletId));

  try {
    final json = await Api.getWalletContactGroups(walletId);
    return json.cast<Map<String, dynamic>>();
  } catch (e) {
    throw Exception('Failed to load contact groups: $e');
  }
});

/// Provides wallet-level permissions.
final walletPermissionsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, walletId) async {
  ref.watch(walletManagementRefreshTrigger);
  ref.watch(_dataChangeSetupProvider(walletId));

  try {
    final json = await Api.getWalletPermissions(walletId);
    return json.cast<Map<String, dynamic>>();
  } catch (e) {
    throw Exception('Failed to load wallet permissions: $e');
  }
});

/// Provides member-scoped permissions.
final memberPermissionsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, walletId) async {
  ref.watch(walletManagementRefreshTrigger);
  ref.watch(_dataChangeSetupProvider(walletId));

  try {
    final json = await Api.getMemberPermissions(walletId);
    return json.cast<Map<String, dynamic>>();
  } catch (e) {
    throw Exception('Failed to load member permissions: $e');
  }
});

/// Refresh wallet management data (groups, permissions).
/// Call this after creating/deleting groups or changing permissions.
void refreshWalletManagement(WidgetRef ref) {
  ref.read(walletManagementRefreshTrigger.notifier).state += 1;
}
