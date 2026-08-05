import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart';

/// Trigger to refresh wallet management data when needed.
/// Invalidate this provider to force all wallet data to refetch.
final walletManagementRefreshTrigger = StateProvider<int>((ref) => 0);

/// Provides list of user groups for the current wallet.
final userGroupsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  // Watch the refresh trigger to refetch when invalidated
  ref.watch(walletManagementRefreshTrigger);

  final walletId = ref.watch(currentWalletIdProvider);
  if (walletId == null) return [];

  try {
    final json = await Api.getWalletUserGroups(walletId);
    return json.cast<Map<String, dynamic>>();
  } catch (e) {
    throw Exception('Failed to load user groups: $e');
  }
});

/// Provides list of contact groups for the current wallet.
final contactGroupsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(walletManagementRefreshTrigger);

  final walletId = ref.watch(currentWalletIdProvider);
  if (walletId == null) return [];

  try {
    final json = await Api.getWalletContactGroups(walletId);
    return json.cast<Map<String, dynamic>>();
  } catch (e) {
    throw Exception('Failed to load contact groups: $e');
  }
});

/// Provides wallet-level permissions.
final walletPermissionsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(walletManagementRefreshTrigger);

  final walletId = ref.watch(currentWalletIdProvider);
  if (walletId == null) return [];

  try {
    final json = await Api.getWalletPermissions(walletId);
    return json.cast<Map<String, dynamic>>();
  } catch (e) {
    throw Exception('Failed to load wallet permissions: $e');
  }
});

/// Provides member-scoped permissions.
final memberPermissionsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(walletManagementRefreshTrigger);

  final walletId = ref.watch(currentWalletIdProvider);
  if (walletId == null) return [];

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

/// Provider for current wallet ID (assumes it exists from somewhere).
final currentWalletIdProvider = FutureProvider<String?>((ref) async {
  try {
    return await Api.getCurrentWalletId();
  } catch (_) {
    return null;
  }
});
