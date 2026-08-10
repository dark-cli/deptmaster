import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api.dart';
import '../../providers/wallet_management_provider.dart';
import '../../utils/toast_service.dart';
import '../../widgets/custom_expansion_tile.dart';
import '../../widgets/gradient_background.dart';
import '../../widgets/gradient_card.dart';
import 'permission_matrix.dart';

/// Wallet-level (Layer 1) permissions: what each user group can do to the
/// wallet itself — read info, edit info, manage members, create/delete
/// groups, edit permissions, delete the wallet, etc.
///
/// Layer 1 has no target dimension: each user group carries a single
/// vector of wallet:* actions (allow / deny / unset per action). Unlike
/// Layer 2, 2.5 or 3 (which are per-target matrices), the display here
/// flattens all wallet actions into one wrapped strip of colored letters.
class WalletPermissionsScreen extends ConsumerWidget {
  final String walletId;

  const WalletPermissionsScreen({
    super.key,
    required this.walletId,
  });

  String _formatGroupName(String name) {
    if (name == '__owners__') return 'Owners (system)';
    if (name == 'all_users') return 'All Users (system)';
    return name;
  }

  (Set<String> allowed, Set<String> denied) _stateFor(
    List<Map<String, dynamic>> perms,
    String userGroupId,
  ) {
    final allowed = <String>{};
    final denied = <String>{};
    for (final e in perms) {
      if (e['user_group_id'] != userGroupId) continue;
      final action = e['action'] as String? ?? '';
      if (action.isEmpty) continue;
      if (e['is_deny'] == true) {
        denied.add(action);
      } else {
        allowed.add(action);
      }
    }
    return (allowed, denied);
  }

  /// Full-replacement per user_group_id: send the whole `permissions` list
  /// (every action with allow/deny/unset). Server DELETEs the group's rows
  /// and re-inserts only allow/deny entries — unset actions disappear.
  Future<void> _save(
    BuildContext context,
    String userGroupId,
    Set<String> allowed,
    Set<String> denied,
  ) async {
    // Enumerate every action in our matrix spec so unset actions become explicit.
    final permissions = <Map<String, dynamic>>[];
    for (final row in walletPermissionRows) {
      for (final col in row.columns) {
        final String state;
        if (allowed.contains(col.action)) {
          state = 'allow';
        } else if (denied.contains(col.action)) {
          state = 'deny';
        } else {
          state = 'unset';
        }
        permissions.add({'action': col.action, 'state': state});
      }
    }

    final entries = [
      {
        'user_group_id': userGroupId,
        'permissions': permissions,
      }
    ];

    try {
      await Api.setWalletPermissions(walletId, entries);
      if (context.mounted) {
        ToastService.showSuccessFromContext(context, 'Permissions saved');
      }
    } catch (e) {
      if (Api.isPermissionDeniedError(e)) {
        if (context.mounted) {
          ToastService.showErrorFromContext(context, 'You don\'t have permission.');
        }
      } else if (context.mounted) {
        ToastService.showErrorFromContext(
          context,
          e.toString().replaceFirst('Exception: ', ''),
        );
      }
    }
  }

  void _openEditor(
    BuildContext context,
    String userGroupId,
    String userGroupName,
    Set<String> allowed,
    Set<String> denied,
  ) {
    showDialog(
      context: context,
      builder: (_) => PermissionActionsDialog(
        title: 'Edit Wallet Permissions',
        subtitle: userGroupName,
        rows: walletPermissionRows,
        initialAllowed: allowed,
        initialDenied: denied,
        onSave: (a, d) => _save(context, userGroupId, a, d),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(userGroupsProvider(walletId));
    final permsAsync = ref.watch(walletPermissionsProvider(walletId));

    // Preserve cached data during refetches so expanded cards don't collapse.
    final groups = groupsAsync.valueOrNull;
    final perms = permsAsync.valueOrNull;
    if (groups == null || perms == null) {
      if (groupsAsync.hasError || permsAsync.hasError) {
        return _scaffold(context,
            Center(child: Text((groupsAsync.error ?? permsAsync.error).toString())));
      }
      return _scaffold(context, const Center(child: CircularProgressIndicator()));
    }

    final visible = groups.where((g) => g['is_hidden'] != true).toList();
    if (visible.isEmpty) {
      return _scaffold(
        context,
        const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Create at least one user group to configure wallet permissions.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return _scaffold(
      context,
      ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        children: [
          for (int i = 0; i < visible.length; i++)
            _buildUserGroupCard(context, i, visible[i], perms),
        ],
      ),
    );
  }

  Widget _scaffold(BuildContext context, Widget body) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Wallet Permissions')),
        body: body,
      ),
    );
  }

  Widget _buildUserGroupCard(
    BuildContext context,
    int index,
    Map<String, dynamic> group,
    List<Map<String, dynamic>> perms,
  ) {
    final groupId = group['id'] as String? ?? '';
    final groupName = _formatGroupName(group['name'] as String? ?? '');
    final (allowed, denied) = _stateFor(perms, groupId);
    return GradientCard(
      key: ValueKey('wallet-perm-group-$groupId'),
      margin: const EdgeInsets.only(bottom: 12),
      variationSeed: groupId.hashCode,
      child: CustomExpansionTile(
        key: PageStorageKey('wallet-perm-group-$groupId'),
        title: GroupTypeHeader(
          icon: Icons.groups,
          type: 'User group',
          name: groupName,
        ),
        subtitle: const Padding(
          padding: EdgeInsets.only(left: 26),
          child: Text('wallet-level actions (vector)'),
        ),
        initiallyExpanded: index == 0,
        children: [
          const Divider(height: 1),
          ListTile(
            title: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 6),
              child: PermissionMatrixGrid(
                rows: walletPermissionRows,
                allowed: allowed,
                denied: denied,
              ),
            ),
            trailing: const Icon(Icons.edit, size: 20),
            onTap: () => _openEditor(context, groupId, groupName, allowed, denied),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
