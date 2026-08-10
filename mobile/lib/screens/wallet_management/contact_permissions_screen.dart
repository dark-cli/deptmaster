import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api.dart';
import '../../providers/wallet_management_provider.dart';
import '../../utils/toast_service.dart';
import '../../widgets/custom_expansion_tile.dart';
import '../../widgets/gradient_background.dart';
import '../../widgets/gradient_card.dart';

/// Tri-state permission on a single (source, action) tuple within a contact group.
enum _PermState { unset, allow, deny }

class ContactPermissionsScreen extends ConsumerWidget {
  final String walletId;

  const ContactPermissionsScreen({
    super.key,
    required this.walletId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(contactGroupsProvider(walletId));
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Contact Permissions')),
        body: groupsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text(err.toString())),
          data: (allGroups) {
            final contactGroups = allGroups.where((g) => g['name'] != 'all_contacts').toList();
            if (contactGroups.isEmpty) {
              return Center(
                child: Text(
                  'No contact groups available',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: contactGroups.map((group) {
                final groupId = group['id'] as String? ?? '';
                final groupName = group['name'] as String? ?? '';

                return GradientCard(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  variationSeed: groupId.hashCode,
                  child: CustomExpansionTile(
                    title: Text(groupName),
                    subtitle: const Text('Who can manage this contact group'),
                    children: [
                      _ContactGroupPermissionsDetail(
                        walletId: walletId,
                        contactGroupId: groupId,
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }
}

class _ContactGroupPermissionsDetail extends ConsumerWidget {
  final String walletId;
  final String contactGroupId;

  const _ContactGroupPermissionsDetail({
    required this.walletId,
    required this.contactGroupId,
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
    String action,
  ) {
    for (final e in entries) {
      if (e['source_group_id'] == sourceGroupId && e['action'] == action) {
        return (e['is_deny'] as bool? ?? false) ? _PermState.deny : _PermState.allow;
      }
    }
    return _PermState.unset;
  }

  Future<void> _setPermission(
    BuildContext context,
    List<Map<String, dynamic>> allEntries,
    String sourceGroupId,
    String action,
    _PermState newState,
  ) async {
    final updated = allEntries
        .where((e) => !(e['source_group_id'] == sourceGroupId && e['action'] == action))
        .toList();
    if (newState != _PermState.unset) {
      updated.add({
        'source_group_id': sourceGroupId,
        'action': action,
        'is_deny': newState == _PermState.deny,
      });
    }

    try {
      await Api.setContactGroupPermissions(walletId, contactGroupId, updated);
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
    final groupsAsync = ref.watch(userGroupsProvider(walletId));

    if (permsAsync.isLoading || groupsAsync.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        )),
      );
    }
    if (permsAsync.hasError || groupsAsync.hasError) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text((permsAsync.error ?? groupsAsync.error).toString()),
      );
    }

    final perms = permsAsync.value!;
    final sourceGroups = groupsAsync.value!
        .where((g) => g['name'] != '__owners__')
        .toList();

    if (sourceGroups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Create a user group first, then set permissions here.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: sourceGroups.map((source) {
          final sourceId = source['id'] as String? ?? '';
          final sourceName = _formatGroupName(source['name'] as String? ?? '');
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('From: $sourceName', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                ...contactGroupActions.map((action) {
                  final state = _stateOf(perms, sourceId, action);
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
                          onSelectionChanged: (s) => _setPermission(context, perms, sourceId, action, s.first),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
