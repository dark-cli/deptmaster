import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api.dart';
import '../../providers/wallet_management_provider.dart';
import '../../utils/toast_service.dart';
import '../../widgets/custom_expansion_tile.dart';
import '../../widgets/gradient_background.dart';
import '../../widgets/gradient_card.dart';
import 'permission_matrix.dart';

/// Contact Permissions: matrix of source user_group × target contact_group.
/// Vector direction is user_group → contact_group ("this user group can do
/// these actions on this contact group"). Outer expansion is user_group,
/// inner rows are contact_groups.
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

  String _formatContactGroupName(String name) {
    if (name == 'all_contacts') return 'All Contacts (default)';
    return name;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userGroupsAsync = ref.watch(userGroupsProvider(walletId));
    final contactGroupsAsync = ref.watch(contactGroupsProvider(walletId));

    // Preserve cached data so open cards don't collapse when we refetch.
    final userGroups = userGroupsAsync.valueOrNull;
    final contactGroups = contactGroupsAsync.valueOrNull;
    if (userGroups == null || contactGroups == null) {
      if (userGroupsAsync.hasError || contactGroupsAsync.hasError) {
        return _scaffold(context,
            Center(child: Text((userGroupsAsync.error ?? contactGroupsAsync.error).toString())));
      }
      return _scaffold(context, const Center(child: CircularProgressIndicator()));
    }

    final visibleUsers = userGroups.where((g) => g['is_hidden'] != true).toList();
    if (visibleUsers.isEmpty) {
      return _scaffold(
        context,
        const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Create at least one user group first.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    if (contactGroups.isEmpty) {
      return _scaffold(
        context,
        const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('No contact groups available.', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return _scaffold(
      context,
      ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        children: [
          for (int i = 0; i < visibleUsers.length; i++)
            _buildSourceCard(context, ref, i, visibleUsers, contactGroups),
        ],
      ),
    );
  }

  Widget _scaffold(BuildContext context, Widget body) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Contact Permissions')),
        body: body,
      ),
    );
  }

  Widget _buildSourceCard(
    BuildContext context,
    WidgetRef ref,
    int index,
    List<Map<String, dynamic>> userGroups,
    List<Map<String, dynamic>> contactGroups,
  ) {
    final source = userGroups[index];
    final sourceId = source['id'] as String? ?? '';
    final sourceName = _formatUserGroupName(source['name'] as String? ?? '');
    return GradientCard(
      key: ValueKey('contact-source-$sourceId'),
      margin: const EdgeInsets.only(bottom: 12),
      variationSeed: sourceId.hashCode,
      child: CustomExpansionTile(
        key: PageStorageKey('contact-source-$sourceId'),
        title: Text('From: $sourceName', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('What this group can do on each contact group'),
        initiallyExpanded: index == 0,
        children: [
          const Divider(height: 1),
          ...contactGroups.map((target) {
            final targetId = target['id'] as String? ?? '';
            final targetName = _formatContactGroupName(target['name'] as String? ?? '');
            return _ContactGroupRow(
              walletId: walletId,
              sourceGroupId: sourceId,
              sourceGroupName: sourceName,
              contactGroupId: targetId,
              contactGroupName: targetName,
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// One (source user_group, target contact_group) row. Watches the
/// per-contact-group permission list so it updates in real-time.
class _ContactGroupRow extends ConsumerWidget {
  final String walletId;
  final String sourceGroupId;
  final String sourceGroupName;
  final String contactGroupId;
  final String contactGroupName;

  const _ContactGroupRow({
    required this.walletId,
    required this.sourceGroupId,
    required this.sourceGroupName,
    required this.contactGroupId,
    required this.contactGroupName,
  });

  (Set<String> allowed, Set<String> denied) _stateFor(List<Map<String, dynamic>> perms) {
    final allowed = <String>{};
    final denied = <String>{};
    for (final e in perms) {
      // Server returns `member_group_id`; also tolerate `source_group_id`.
      final mg = e['member_group_id'] as String? ?? e['source_group_id'] as String? ?? '';
      if (mg != sourceGroupId) continue;
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

  /// Build the payload the server expects: nested by member_group_id, listing
  /// every action's tri-state. Server does full-replacement per contact_group,
  /// so we must include ALL sources currently set + our updated source.
  List<Map<String, dynamic>> _buildPayload(
    List<Map<String, dynamic>> allPerms,
    Set<String> newAllowed,
    Set<String> newDenied,
  ) {
    // Aggregate current state (memberGroupId -> action -> allow/deny),
    // excluding entries for this source (they'll be replaced).
    final byGroup = <String, Map<String, bool>>{}; // isDeny
    for (final e in allPerms) {
      final mg = e['member_group_id'] as String? ?? e['source_group_id'] as String? ?? '';
      if (mg.isEmpty || mg == sourceGroupId) continue;
      final action = e['action'] as String? ?? '';
      if (action.isEmpty) continue;
      byGroup.putIfAbsent(mg, () => {})[action] = e['is_deny'] == true;
    }
    // Add our source's new state.
    if (newAllowed.isNotEmpty || newDenied.isNotEmpty) {
      final map = <String, bool>{};
      for (final a in newAllowed) {
        map[a] = false;
      }
      for (final a in newDenied) {
        map[a] = true;
      }
      byGroup[sourceGroupId] = map;
    }

    final entries = <Map<String, dynamic>>[];
    byGroup.forEach((mg, actions) {
      final permissions = <Map<String, dynamic>>[];
      for (final entry in contactGroupRows.expand((r) => r.columns)) {
        final action = entry.action;
        final isDeny = actions[action];
        permissions.add({
          'action': action,
          'state': isDeny == null ? 'unset' : (isDeny ? 'deny' : 'allow'),
        });
      }
      entries.add({
        'member_group_id': mg,
        'permissions': permissions,
      });
    });
    return entries;
  }

  Future<void> _save(
    BuildContext context,
    List<Map<String, dynamic>> allPerms,
    Set<String> allowed,
    Set<String> denied,
  ) async {
    final payload = _buildPayload(allPerms, allowed, denied);
    try {
      await Api.setContactGroupPermissions(walletId, contactGroupId, payload);
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
  ) {
    final (allowed, denied) = _stateFor(allPerms);
    showDialog(
      context: context,
      builder: (_) => PermissionActionsDialog(
        title: 'Edit Contact Permissions',
        subtitle: '$sourceGroupName → $contactGroupName',
        rows: contactGroupRows,
        initialAllowed: allowed,
        initialDenied: denied,
        onSave: (a, d) => _save(context, allPerms, a, d),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permsAsync = ref.watch(
      contactGroupPermissionsProvider(WalletGroupKey(walletId, contactGroupId)),
    );
    final perms = permsAsync.valueOrNull ?? const [];
    final (allowed, denied) = _stateFor(perms);
    return ListTile(
      title: Text('On: $contactGroupName'),
      subtitle: PermissionMatrixGrid(
        rows: contactGroupRows,
        allowed: allowed,
        denied: denied,
      ),
      trailing: const Icon(Icons.edit, size: 20),
      onTap: () => _openEditor(context, perms),
    );
  }
}
