import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api.dart';
import '../../providers/wallet_management_provider.dart';
import '../../utils/toast_service.dart';
import '../../widgets/gradient_card.dart';
import '../../widgets/custom_expansion_tile.dart';
import '../../widgets/gradient_background.dart';

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
                    subtitle: const Text('Delegable permissions'),
                    children: [
                      _ContactGroupPermissionsDetail(
                        walletId: walletId,
                        contactGroupId: groupId,
                        groupName: groupName,
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
  final String groupName;

  const _ContactGroupPermissionsDetail({
    required this.walletId,
    required this.contactGroupId,
    required this.groupName,
  });

  Future<void> _togglePermission(
    BuildContext context,
    List<Map<String, dynamic>> allPermissions,
    Map<String, dynamic> perm,
    String sourceGroup,
    String actionName,
  ) async {
    final isDeny = perm['is_deny'] as bool? ?? false;

    try {
      final newEntries = allPermissions.map((p) {
        if (p['source_group_id'] == sourceGroup && p['action'] == actionName) {
          return {...p, 'is_deny': !isDeny};
        }
        return p;
      }).toList();

      await Api.setContactGroupPermissions(walletId, contactGroupId, newEntries);
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
        child: Center(child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        )),
      ),
      error: (err, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(err.toString()),
      ),
      data: (permissions) {
        if (permissions.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'No delegable permissions for this group',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: permissions.map((perm) {
              final sourceGroup = perm['source_group_id'] as String? ?? '';
              final action = perm['action'] as String? ?? '';
              final isDeny = perm['is_deny'] as bool? ?? false;

              return ListTile(
                dense: true,
                title: Text('$sourceGroup: $action'),
                trailing: Chip(
                  label: Text(isDeny ? 'Deny' : 'Allow'),
                  backgroundColor: isDeny ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary,
                ),
                onTap: () => _togglePermission(context, permissions, perm, sourceGroup, action),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
