import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api.dart';
import '../../providers/wallet_management_provider.dart';
import '../../utils/toast_service.dart';
import '../../widgets/custom_expansion_tile.dart';
import '../../widgets/gradient_background.dart';
import '../../widgets/gradient_card.dart';
import 'permission_matrix.dart';

/// Member Permissions: matrix of source user_group × target user_group.
/// Each cell shows the compact "M: r a x e" grid; tapping opens the shared
/// PermissionActionsDialog (same UX as Permission Rules).
class MemberPermissionsScreen extends ConsumerWidget {
  final String walletId;

  const MemberPermissionsScreen({
    super.key,
    required this.walletId,
  });

  String _formatGroupName(String name) {
    if (name == '__owners__') return 'Owners (system)';
    if (name == 'all_users') return 'All Users (system)';
    return name;
  }

  /// Get allowed/denied action sets for a (source, target) pair from the flat
  /// [perms] list. Server returns entries with source_group_id, target_group_id,
  /// action, is_deny.
  (Set<String> allowed, Set<String> denied) _stateFor(
    List<Map<String, dynamic>> perms,
    String sourceId,
    String targetId,
  ) {
    final allowed = <String>{};
    final denied = <String>{};
    for (final e in perms) {
      if (e['source_group_id'] == sourceId && e['target_group_id'] == targetId) {
        final action = e['action'] as String? ?? '';
        if (action.isEmpty) continue;
        if (e['is_deny'] == true) {
          denied.add(action);
        } else {
          allowed.add(action);
        }
      }
    }
    return (allowed, denied);
  }

  /// Persist the (source, target) row. Server does full-replacement per
  /// touched target group (both those in `entries` AND those in
  /// `clear_target_group_ids`). We always include our target in
  /// `clear_target_group_ids` — that guarantees stale rows for (source, target)
  /// get wiped even when the user unchecked everything and the payload has
  /// zero entries for that target.
  Future<void> _save(
    BuildContext context,
    List<Map<String, dynamic>> allPerms,
    String sourceId,
    String targetId,
    Set<String> allowed,
    Set<String> denied,
  ) async {
    // Keep existing entries for this target from OTHER sources.
    final entries = <Map<String, dynamic>>[];
    for (final e in allPerms) {
      if (e['target_group_id'] != targetId) continue;
      if (e['source_group_id'] == sourceId) continue; // will be re-added below
      entries.add({
        'source_group_id': e['source_group_id'],
        'target_group_id': e['target_group_id'],
        'action': e['action'],
        'is_deny': e['is_deny'] == true,
      });
    }
    for (final action in allowed) {
      entries.add({
        'source_group_id': sourceId,
        'target_group_id': targetId,
        'action': action,
        'is_deny': false,
      });
    }
    for (final action in denied) {
      entries.add({
        'source_group_id': sourceId,
        'target_group_id': targetId,
        'action': action,
        'is_deny': true,
      });
    }

    final body = {
      'entries': entries,
      // Always mark our target for clearing so DELETE runs even if `entries`
      // has nothing for this target (the "user unset the only row" case).
      'clear_target_group_ids': [targetId],
    };

    try {
      await Api.setMemberPermissions(walletId, body);
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
    List<Map<String, dynamic>> allPerms,
    String sourceId,
    String sourceName,
    String targetId,
    String targetName,
  ) {
    final (allowed, denied) = _stateFor(allPerms, sourceId, targetId);
    showDialog(
      context: context,
      builder: (_) => PermissionActionsDialog(
        title: 'Edit Member Permissions',
        subtitle: '$sourceName → $targetName',
        rows: memberGroupRows,
        initialAllowed: allowed,
        initialDenied: denied,
        onSave: (a, d) => _save(context, allPerms, sourceId, targetId, a, d),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(userGroupsProvider(walletId));
    final permsAsync = ref.watch(memberPermissionsProvider(walletId));

    // Preserve cached data across refetches so expanded cards don't collapse.
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
    if (visible.length < 2) {
      return _scaffold(
        context,
        const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Create at least two user groups to configure who can manage whom.',
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
            _buildSourceCard(context, i, visible, perms),
        ],
      ),
    );
  }

  Widget _scaffold(BuildContext context, Widget body) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Member Permissions')),
        body: body,
      ),
    );
  }

  Widget _buildSourceCard(
    BuildContext context,
    int index,
    List<Map<String, dynamic>> visibleGroups,
    List<Map<String, dynamic>> perms,
  ) {
    final source = visibleGroups[index];
    final sourceId = source['id'] as String? ?? '';
    final sourceName = _formatGroupName(source['name'] as String? ?? '');
    return GradientCard(
      key: ValueKey('member-source-$sourceId'),
      margin: const EdgeInsets.only(bottom: 12),
      variationSeed: sourceId.hashCode,
      child: CustomExpansionTile(
        key: PageStorageKey('member-source-$sourceId'),
        title: GroupTypeHeader(
          icon: Icons.groups,
          type: 'User group',
          name: sourceName,
        ),
        subtitle: const Padding(
          padding: EdgeInsets.only(left: 26),
          child: Text('can manage members of…'),
        ),
        initiallyExpanded: index == 0,
        children: [
          const Divider(height: 1),
          ...visibleGroups.where((t) => t['id'] != sourceId).map((target) {
            final targetId = target['id'] as String? ?? '';
            final targetName = _formatGroupName(target['name'] as String? ?? '');
            final (allowed, denied) = _stateFor(perms, sourceId, targetId);
            return ListTile(
              title: GroupTypeHeader(
                icon: Icons.arrow_forward,
                type: 'User group',
                name: targetName,
                iconSize: 16,
                bold: false,
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(left: 22, top: 4),
                child: PermissionMatrixGrid(
                  rows: memberGroupRows,
                  allowed: allowed,
                  denied: denied,
                  showRowPrefix: false,
                ),
              ),
              trailing: const Icon(Icons.edit, size: 20),
              onTap: () =>
                  _openEditor(context, perms, sourceId, sourceName, targetId, targetName),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
