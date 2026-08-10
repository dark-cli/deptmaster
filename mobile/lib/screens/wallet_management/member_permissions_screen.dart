import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api.dart';
import '../../providers/wallet_management_provider.dart';
import '../../utils/toast_service.dart';
import '../../widgets/custom_expansion_tile.dart';
import '../../widgets/gradient_background.dart';
import '../../widgets/gradient_card.dart';

enum _PermState { unset, allow, deny }

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(userGroupsProvider(walletId));
    final permsAsync = ref.watch(memberPermissionsProvider(walletId));

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Member Permissions')),
        body: (groupsAsync.isLoading || permsAsync.isLoading)
            ? const Center(child: CircularProgressIndicator())
            : (groupsAsync.hasError || permsAsync.hasError)
                ? Center(child: Text((groupsAsync.error ?? permsAsync.error).toString()))
                : _buildBody(context, groupsAsync.value!, permsAsync.value!),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<Map<String, dynamic>> allGroups,
    List<Map<String, dynamic>> perms,
  ) {
    final userGroups = allGroups.where((g) => g['name'] != '__owners__').toList();

    if (userGroups.length < 2) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Create at least two user groups to configure who can manage whom.',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: userGroups.map((source) {
        final sourceId = source['id'] as String? ?? '';
        final sourceName = _formatGroupName(source['name'] as String? ?? '');
        return GradientCard(
          margin: const EdgeInsets.only(bottom: 10),
          variationSeed: sourceId.hashCode,
          child: CustomExpansionTile(
            title: Text('From: $sourceName', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('What this group can do to other groups\' members'),
            children: [
              const Divider(height: 1),
              ...userGroups.where((t) => t['id'] != sourceId).map((target) {
                final targetId = target['id'] as String? ?? '';
                final targetName = _formatGroupName(target['name'] as String? ?? '');
                return _SourceTargetEditor(
                  walletId: walletId,
                  sourceGroupId: sourceId,
                  targetGroupId: targetId,
                  targetGroupName: targetName,
                  allPerms: perms,
                );
              }),
              const SizedBox(height: 4),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// One row per (source, target) pair with checkbox + Allow/Deny SegmentedButton
/// for each action. Uses same design as PermissionRulesScreen's dialog.
class _SourceTargetEditor extends StatelessWidget {
  final String walletId;
  final String sourceGroupId;
  final String targetGroupId;
  final String targetGroupName;
  final List<Map<String, dynamic>> allPerms;

  const _SourceTargetEditor({
    required this.walletId,
    required this.sourceGroupId,
    required this.targetGroupId,
    required this.targetGroupName,
    required this.allPerms,
  });

  String _shortAction(String action) => action.split(':').last.replaceAll('_', ' ');

  _PermState _stateOf(String action) {
    for (final e in allPerms) {
      if (e['source_group_id'] == sourceGroupId &&
          e['target_group_id'] == targetGroupId &&
          e['action'] == action) {
        return (e['is_deny'] as bool? ?? false) ? _PermState.deny : _PermState.allow;
      }
    }
    return _PermState.unset;
  }

  /// Send the full state for this target group (all sources × actions),
  /// with the requested change applied. Server does full replacement per target.
  Future<void> _apply(BuildContext context, String changedAction, _PermState newState) async {
    // Aggregate current state for THIS target across all sources.
    // Keep only entries whose target matches ours; others go untouched by the server.
    final updated = <Map<String, dynamic>>[];
    // Add all existing rows for this target, excluding the one being changed.
    for (final e in allPerms) {
      if (e['target_group_id'] != targetGroupId) continue;
      final isChanged = e['source_group_id'] == sourceGroupId && e['action'] == changedAction;
      if (isChanged) continue;
      updated.add({
        'source_group_id': e['source_group_id'],
        'target_group_id': e['target_group_id'],
        'action': e['action'],
        'is_deny': e['is_deny'] as bool? ?? false,
      });
    }
    // Add the changed row unless it's being unset.
    if (newState != _PermState.unset) {
      updated.add({
        'source_group_id': sourceGroupId,
        'target_group_id': targetGroupId,
        'action': changedAction,
        'is_deny': newState == _PermState.deny,
      });
    } else if (updated.isEmpty) {
      // Server does full-replacement per touched target. If we send zero entries,
      // no target is "touched" and nothing is cleared. Send a placeholder entry
      // that will be a no-op after replace: we need at least one entry with our
      // target_group_id so the server clears it. Use a dummy? No — instead, we
      // simply pick any source_group and re-add all its (existing minus removed)
      // rows. Since we filtered above, if nothing exists we can't unset the last one
      // without a dedicated DELETE endpoint. Workaround: send a temp row we
      // immediately re-remove is not possible in one round-trip. So: for the
      // "last-row-unset" case, we must send at least one dummy — but we don't have
      // a valid one. Skip: server sees empty payload → no-op → row remains → BUG.
      // Fix: server needs to also DELETE for empty target lists. For now, add
      // an is_deny=false + is_deny=true toggle trick is dirty. Simpler: return
      // early if no other rows exist and warn user. This edge case is rare.
      if (context.mounted) {
        ToastService.showInfoFromContext(context, 'Cannot unset the last permission for this target group yet.');
      }
      return;
    }

    try {
      await Api.setMemberPermissions(walletId, updated);
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('On: $targetGroupName', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          ...memberGroupActions.map((action) {
            final state = _stateOf(action);
            final active = state != _PermState.unset;
            final allowDeny = state == _PermState.deny ? _PermState.deny : _PermState.allow;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Checkbox(
                        value: active,
                        onChanged: (checked) {
                          _apply(context, action, checked == true ? _PermState.allow : _PermState.unset);
                        },
                      ),
                      Expanded(child: Text(_shortAction(action))),
                    ],
                  ),
                  if (active) ...[
                    const SizedBox(height: 4),
                    LayoutBuilder(builder: (context, constraints) {
                      final narrow = constraints.maxWidth < 280;
                      return SegmentedButton<_PermState>(
                        style: narrow
                            ? const ButtonStyle(
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
                              )
                            : null,
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: _PermState.allow, icon: Icon(Icons.check, size: 16), label: Text('Allow')),
                          ButtonSegment(value: _PermState.deny, icon: Icon(Icons.block, size: 16), label: Text('Deny')),
                        ],
                        selected: {allowDeny},
                        onSelectionChanged: (s) => _apply(context, action, s.first),
                      );
                    }),
                    const SizedBox(height: 4),
                  ],
                ],
              ),
            );
          }),
          const Divider(height: 16),
        ],
      ),
    );
  }
}
