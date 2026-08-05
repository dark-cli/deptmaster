import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api.dart';
import '../../providers/wallet_management_provider.dart';
import '../../utils/toast_service.dart';
import '../../widgets/gradient_background.dart';

class WalletPermissionsScreen extends ConsumerWidget {
  final String walletId;

  const WalletPermissionsScreen({
    super.key,
    required this.walletId,
  });

  Future<void> _togglePermission(
    BuildContext context,
    WidgetRef ref,
    List<Map<String, dynamic>> allPermissions,
    Map<String, dynamic> perm,
    String actionName,
  ) async {
    final sourceGroupId = perm['source_group_id'] as String? ?? '';
    final isDeny = perm['is_deny'] as bool? ?? false;

    try {
      final newEntries = allPermissions.map((p) {
        if (p['source_group_id'] == sourceGroupId && p['action'] == actionName) {
          return {...p, 'is_deny': !isDeny};
        }
        return p;
      }).toList();

      await Api.setWalletPermissions(walletId, newEntries);
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
    final permissionsAsync = ref.watch(walletPermissionsProvider(walletId));
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Wallet Permissions')),
        body: permissionsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text(err.toString())),
          data: (permissions) {
            if (permissions.isEmpty) {
              return Center(
                child: Text(
                  'No wallet permissions configured',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: permissions.map((perm) {
                final sourceGroupId = perm['source_group_id'] as String? ?? '';
                final action = perm['action'] as String? ?? '';
                final isDeny = perm['is_deny'] as bool? ?? false;

                return ListTile(
                  title: Text(action),
                  subtitle: Text(sourceGroupId, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  trailing: Chip(
                    label: Text(isDeny ? 'Deny' : 'Allow'),
                    backgroundColor: isDeny ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary,
                  ),
                  onTap: () => _togglePermission(context, ref, permissions, perm, action),
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }
}
