import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api.dart';
import '../../providers/wallet_management_provider.dart';
import '../../utils/toast_service.dart';
import '../../widgets/gradient_background.dart';

class MemberPermissionsScreen extends ConsumerWidget {
  final String walletId;

  const MemberPermissionsScreen({
    super.key,
    required this.walletId,
  });

  Future<void> _togglePermission(
    BuildContext context,
    WidgetRef ref,
    List<Map<String, dynamic>> allPermissions,
    Map<String, dynamic> perm,
    String sourceGroup,
    String targetGroup,
    String actionName,
  ) async {
    final isDeny = perm['is_deny'] as bool? ?? false;

    try {
      final newEntries = allPermissions.map((p) {
        if (p['source_group_id'] == sourceGroup && p['target_group_id'] == targetGroup && p['action'] == actionName) {
          return {...p, 'is_deny': !isDeny};
        }
        return p;
      }).toList();

      await Api.setMemberPermissions(walletId, newEntries);
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
    final permissionsAsync = ref.watch(memberPermissionsProvider(walletId));
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Member Permissions')),
        body: permissionsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text(err.toString())),
          data: (permissions) {
            if (permissions.isEmpty) {
              return Center(
                child: Text(
                  'No member permissions configured',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: permissions.map((perm) {
                final sourceGroup = perm['source_group_id'] as String? ?? '';
                final targetGroup = perm['target_group_id'] as String? ?? '';
                final action = perm['action'] as String? ?? '';
                final isDeny = perm['is_deny'] as bool? ?? false;

                return ListTile(
                  title: Text('$sourceGroup → $targetGroup'),
                  subtitle: Text(action, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  trailing: Chip(
                    label: Text(isDeny ? 'Deny' : 'Allow'),
                    backgroundColor: isDeny ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary,
                  ),
                  onTap: () => _togglePermission(context, ref, permissions, perm, sourceGroup, targetGroup, action),
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }
}
