import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api.dart';
import '../../providers/wallet_management_provider.dart';
import '../../utils/toast_service.dart';
import '../../widgets/custom_expansion_tile.dart';
import '../../widgets/gradient_background.dart';
import '../../widgets/gradient_card.dart';

/// Tri-state permission on a single (source, target, action) tuple.
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

  String _formatAction(String action) {
    final part = action.split(':').last;
    return part.replaceAll('_', ' ');
  }

  _PermState _stateOf(
    List<Map<String, dynamic>> entries,
    String sourceGroupId,
    String targetGroupId,
    String action,
  ) {
    for (final e in entries) {
      if (e['source_group_id'] == sourceGroupId &&
          e['target_group_id'] == targetGroupId &&
          e['action'] == action) {
        return (e['is_deny'] as bool? ?? false) ? _PermState.deny : _PermState.allow;
      }
    }
    return _PermState.unset;
  }

  Future<void> _setPermission(
    BuildContext context,
    List<Map<String, dynamic>> allEntries,
    String sourceGroupId,
    String targetGroupId,
    String action,
    _PermState newState,
  ) async {
    // Remove any existing entry for this tuple, then add new one if not unset.
    final updated = allEntries
        .where((e) =>
            !(e['source_group_id'] == sourceGroupId &&
                e['target_group_id'] == targetGroupId &&
                e['action'] == action))
        .toList();
    if (newState != _PermState.unset) {
      updated.add({
        'source_group_id': sourceGroupId,
        'target_group_id': targetGroupId,
        'action': action,
        'is_deny': newState == _PermState.deny,
      });
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
    // All groups can be a target. Exclude the special __owners__ group as source
    // (owners bypass permissions anyway).
    final targetGroups = allGroups.where((g) => g['name'] != '__owners__').toList();
    final sourceGroups = allGroups.where((g) => g['name'] != '__owners__').toList();

    if (targetGroups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Create at least one user group first.',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: targetGroups.map((target) {
        final targetId = target['id'] as String? ?? '';
        final targetName = _formatGroupName(target['name'] as String? ?? '');
        return GradientCard(
          margin: const EdgeInsets.only(bottom: 10),
          variationSeed: targetId.hashCode,
          child: CustomExpansionTile(
            title: Text('Target: $targetName', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Who can manage this group\'s members'),
            children: [
              const Divider(height: 1),
              ...sourceGroups.map((source) {
                final sourceId = source['id'] as String? ?? '';
                final sourceName = _formatGroupName(source['name'] as String? ?? '');
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('From: $sourceName', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      ...memberGroupActions.map((action) {
                        final state = _stateOf(perms, sourceId, targetId, action);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(child: Text(_formatAction(action))),
                              SegmentedButton<_PermState>(
                                style: const ButtonStyle(
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                                showSelectedIcon: false,
                                segments: const [
                                  ButtonSegment(value: _PermState.unset, label: Text('—')),
                                  ButtonSegment(value: _PermState.allow, label: Text('Allow')),
                                  ButtonSegment(value: _PermState.deny, label: Text('Deny')),
                                ],
                                selected: {state},
                                onSelectionChanged: (s) => _setPermission(
                                  context, perms, sourceId, targetId, action, s.first),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      }).toList(),
    );
  }
}
