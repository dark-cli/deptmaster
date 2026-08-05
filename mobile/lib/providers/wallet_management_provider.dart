import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart';

/// Trigger to refresh wallet management data when needed.
/// Invalidate this provider to force all wallet data to refetch.
final walletManagementRefreshTrigger = StateProvider<int>((ref) => 0);

/// Provides list of user groups for the current wallet.
final userGroupsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, walletId) async {
  // Watch the refresh trigger to refetch when invalidated
  ref.watch(walletManagementRefreshTrigger);

  try {
    final json = await Api.getWalletUserGroups(walletId);
    return json.cast<Map<String, dynamic>>();
  } catch (e) {
    throw Exception('Failed to load user groups: $e');
  }
});

/// Provides list of contact groups for the current wallet.
final contactGroupsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, walletId) async {
  ref.watch(walletManagementRefreshTrigger);

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
