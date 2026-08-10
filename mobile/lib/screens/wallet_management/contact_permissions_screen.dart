import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api.dart';
import '../../providers/wallet_management_provider.dart';
import '../../utils/toast_service.dart';
import '../../widgets/custom_expansion_tile.dart';
import '../../widgets/gradient_background.dart';
import '../../widgets/gradient_card.dart';

enum _PermState { unset, allow, deny }

class ContactPermissionsScreen extends ConsumerWidget {
  final String walletId;

  const ContactPermissionsScreen({
    super.key,
    required this.walletId,
  });

  String _formatUserGroupName(String name) {
    if (name == '__owners__') return 'Owners (system)';
    if (name == 'all_users') return 'All Users (system)';
    return name;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userGroupsAsync = ref.watch(userGroupsProvider(walletId));
    final contactGroupsAsync = ref.watch(contactGroupsProvider(walletId));

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Contact Permissions')),
        body: (userGroupsAsync.isLoading || contactGroupsAsync.isLoading)
            ? const Center(child: CircularProgressIndicator())
            : (userGroupsAsync.hasError || contactGroupsAsync.hasError)
                ? Center(child: Text((userGroupsAsync.error ?? contactGroupsAsync.error).toString()))
                : _buildBody(context, userGroupsAsync.value!, contactGroupsAsync.value!),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<Map<String, dynamic>> allUserGroups,
    List<Map<String, dynamic>> allContactGroups,
  ) {
    final sourceGroups = allUserGroups.where((g) => g['name'] != '__owners__').toList();
    final targetGroups = allContactGroups; // include 'all_contacts' — it's a real bucket

    if (sourceGroups.isEmpty) {
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
    if (targetGroups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No contact groups available.',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: sourceGroups.map((source) {
        final sourceId = source['id'] as String? ?? '';
        final sourceName = _formatUserGroupName(source['name'] as String? ?? '');
        return GradientCard(
          margin: const EdgeInsets.only(bottom: 10),
          variationSeed: sourceId.hashCode,
          child: CustomExpansionTile(
            title: Text('From: $sourceName', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('What this group can do on each contact group'),
            children: [
              const Divider(height: 1),
              ...targetGroups.map((target) {
                final targetId = target['id'] as String? ?? '';
                final targetName = target['name'] as String? ?? '';
                return _SourceTargetEditor(
                  walletId: walletId,
                  sourceGroupId: sourceId,
                  contactGroupId: targetId,
                  contactGroupName: targetName,
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

/// One row for a single (source user_group, target contact_group) pair.
/// Watches this contact_group's permission list, filters to just this source,
/// and renders the checkbox + Allow/Deny SegmentedButton per action.
class _SourceTargetEditor extends ConsumerWidget {
  final String walletId;
  final String sourceGroupId;
  final String contactGroupId;
  final String contactGroupName;

  const _SourceTargetEditor({
    required this.walletId,
    required this.sourceGroupId,
    required this.contactGroupId,
    required this.contactGroupName,
  });

  String _shortAction(String action) => action.split(':').last.replaceAll('_', ' ');

  _PermState _stateOf(List<Map<String, dynamic>> perms, String action) {
    for (final e in perms) {
      // Server returns `member_group_id` (NOT `source_group_id`)
      final mg = e['member_group_id'] as String? ?? e['source_group_id'] as String? ?? '';
      if (mg == sourceGroupId && e['action'] == action) {
        return (e['is_deny'] as bool? ?? false) ? _PermState.deny : _PermState.allow;
      }
    }
    return _PermState.unset;
  }

  /// Build the full nested payload for the PUT: group ALL currently-set
  /// permissions (across all source groups) by member_group_id, then override
  /// the one cell that changed.
  List<Map<String, dynamic>> _buildPayload(
    List<Map<String, dynamic>> allPerms,
    String changedAction,
    _PermState newState,
  ) {
    // Aggregate current state: memberGroupId -> action -> state
    final byGroup = <String, Map<String, _PermState>>{};
    for (final e in allPerms) {
      final mg = e['member_group_id'] as String? ?? e['source_group_id'] as String? ?? '';
      final action = e['action'] as String? ?? '';
      if (mg.isEmpty || action.isEmpty) continue;
      final state = (e['is_deny'] as bool? ?? false) ? _PermState.deny : _PermState.allow;
      byGroup.putIfAbsent(mg, () => {})[action] = state;
    }
    // Apply the change
    byGroup.putIfAbsent(sourceGroupId, () => {})[changedAction] = newState;

    // Convert to server's expected shape: [{member_group_id, permissions: [{action, state}]}]
    final entries = <Map<String, dynamic>>[];
    byGroup.forEach((memberGroupId, actions) {
      // Include an entry for every action — server treats missing as unchanged; safer to be explicit.
      // Server does full replacement per contact_group, so we send everything.
      final permissions = <Map<String, dynamic>>[];
      for (final action in contactGroupActions) {
        final s = actions[action] ?? _PermState.unset;
        permissions.add({
          'action': action,
          'state': switch (s) {
            _PermState.allow => 'allow',
            _PermState.deny => 'deny',
            _PermState.unset => 'unset',
          },
        });
      }
      entries.add({
        'member_group_id': memberGroupId,
        'permissions': permissions,
      });
    });
    return entries;
  }

  Future<void> _apply(BuildContext context, List<Map<String, dynamic>> allPerms, String action, _PermState newState) async {
    final payload = _buildPayload(allPerms, action, newState);
    try {
      await Api.setContactGroupPermissions(walletId, contactGroupId, payload);
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
    final permsAsync = ref.watch(
      contactGroupPermissionsProvider(WalletGroupKey(walletId, contactGroupId)),
    );
    return permsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      ),
      error: (err, _) => Padding(padding: const EdgeInsets.all(16), child: Text(err.toString())),
      data: (perms) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('On: $contactGroupName', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              ...contactGroupActions.map((action) {
                final state = _stateOf(perms, action);
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
                              _apply(context, perms, action, checked == true ? _PermState.allow : _PermState.unset);
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
                            onSelectionChanged: (s) => _apply(context, perms, action, s.first),
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
      },
    );
  }
}
