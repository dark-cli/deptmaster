import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart';
import 'data_change_provider.dart';

/// Actions that can be granted on a target user group (member management).
/// Used by the Member Permissions screen.
const memberGroupActions = <String>[
  'member_group:members_read',
  'member_group:members_add',
  'member_group:members_remove',
  'member_group:permissions_edit',
];

/// Actions that can be granted on a target contact group.
/// Used by the Contact Permissions screen.
const contactGroupActions = <String>[
  'contact_group:contacts_read',
  'contact_group:contacts_add',
  'contact_group:contacts_remove',
  'contact_group:permissions_edit',
];

/// Provides list of wallet members (users) for the given wallet.
final walletUsersProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, walletId) async {
  invalidateOnDataChange(
    ref,
    kinds: [DataChangeKind.permissions, DataChangeKind.walletMembership],
    walletId: walletId,
  );
  try {
    return await Api.getWalletUsers(walletId);
  } catch (e) {
    throw Exception('Failed to load wallet users: $e');
  }
});

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

/// Provides available permission action names for a wallet.
final walletPermissionActionsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, walletId) async {
  invalidateOnDataChange(ref, kinds: [DataChangeKind.permissions], walletId: walletId);
  try {
    return await Api.getWalletPermissionActions(walletId);
  } catch (e) {
    throw Exception('Failed to load permission actions: $e');
  }
});

/// Provides the wallet permission matrix (user_group x contact_group -> allowed/denied actions).
final walletPermissionMatrixProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, walletId) async {
  invalidateOnDataChange(ref, kinds: [DataChangeKind.permissions], walletId: walletId);
  try {
    return await Api.getWalletPermissionMatrix(walletId);
  } catch (e) {
    throw Exception('Failed to load permission matrix: $e');
  }
});

/// Key for group-scoped family providers: (walletId, groupId).
class WalletGroupKey {
  final String walletId;
  final String groupId;
  const WalletGroupKey(this.walletId, this.groupId);

  @override
  bool operator ==(Object other) =>
      other is WalletGroupKey && other.walletId == walletId && other.groupId == groupId;

  @override
  int get hashCode => Object.hash(walletId, groupId);
}

/// Provides members of a single user group.
final userGroupMembersProvider =
    FutureProvider.family<List<Map<String, dynamic>>, WalletGroupKey>((ref, key) async {
  invalidateOnDataChange(ref, kinds: [DataChangeKind.permissions], walletId: key.walletId);
  try {
    return await Api.getWalletUserGroupMembers(key.walletId, key.groupId);
  } catch (e) {
    throw Exception('Failed to load user group members: $e');
  }
});

/// Provides members of a single contact group.
final contactGroupMembersProvider =
    FutureProvider.family<List<Map<String, dynamic>>, WalletGroupKey>((ref, key) async {
  invalidateOnDataChange(ref, kinds: [DataChangeKind.permissions], walletId: key.walletId);
  try {
    return await Api.getWalletContactGroupMembers(key.walletId, key.groupId);
  } catch (e) {
    throw Exception('Failed to load contact group members: $e');
  }
});

/// Provides delegable permissions for a single contact group.
final contactGroupPermissionsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, WalletGroupKey>((ref, key) async {
  invalidateOnDataChange(ref, kinds: [DataChangeKind.permissions], walletId: key.walletId);
  try {
    return await Api.getContactGroupPermissions(key.walletId, key.groupId);
  } catch (e) {
    throw Exception('Failed to load contact group permissions: $e');
  }
});

/// Manual refresh: invalidate all wallet management providers for the given wallet.
/// Call from pull-to-refresh or retry buttons.
void refreshWalletManagement(WidgetRef ref, String walletId) {
  ref.invalidate(walletUsersProvider(walletId));
  ref.invalidate(userGroupsProvider(walletId));
  ref.invalidate(contactGroupsProvider(walletId));
  ref.invalidate(walletPermissionsProvider(walletId));
  ref.invalidate(memberPermissionsProvider(walletId));
  ref.invalidate(walletPermissionActionsProvider(walletId));
  ref.invalidate(walletPermissionMatrixProvider(walletId));
}
