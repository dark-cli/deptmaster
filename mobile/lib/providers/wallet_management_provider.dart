import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart';
import 'data_change_provider.dart';

/// Provides list of user groups for the current wallet.
final userGroupsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, walletId) async {
  invalidateOnDataChange(ref, kinds: [DataChangeKind.permissions], walletId: walletId);
  try {
    final json = await Api.getWalletUserGroups(walletId);
    return json.cast<Map<String, dynamic>>();
  } catch (e) {
    throw Exception('Failed to load user groups: $e');
  }
});

/// Provides list of contact groups for the current wallet.
final contactGroupsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, walletId) async {
  invalidateOnDataChange(ref, kinds: [DataChangeKind.permissions], walletId: walletId);
  try {
    final json = await Api.getWalletContactGroups(walletId);
    return json.cast<Map<String, dynamic>>();
  } catch (e) {
    throw Exception('Failed to load contact groups: $e');
  }
});

/// Provides wallet-level permissions.
final walletPermissionsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, walletId) async {
  invalidateOnDataChange(ref, kinds: [DataChangeKind.permissions], walletId: walletId);
  try {
    final json = await Api.getWalletPermissions(walletId);
    return json.cast<Map<String, dynamic>>();
  } catch (e) {
    throw Exception('Failed to load wallet permissions: $e');
  }
});

/// Provides member-scoped permissions.
final memberPermissionsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, walletId) async {
  invalidateOnDataChange(ref, kinds: [DataChangeKind.permissions], walletId: walletId);
  try {
    final json = await Api.getMemberPermissions(walletId);
    return json.cast<Map<String, dynamic>>();
  } catch (e) {
    throw Exception('Failed to load member permissions: $e');
  }
});

/// Manual refresh: invalidate all wallet management providers for the given wallet.
/// Call from pull-to-refresh or retry buttons.
void refreshWalletManagement(WidgetRef ref, String walletId) {
  ref.invalidate(userGroupsProvider(walletId));
  ref.invalidate(contactGroupsProvider(walletId));
  ref.invalidate(walletPermissionsProvider(walletId));
  ref.invalidate(memberPermissionsProvider(walletId));
}
