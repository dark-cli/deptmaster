import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api.dart';
import '../../providers/wallet_management_provider.dart';
import '../../utils/toast_service.dart';
import '../../widgets/gradient_card.dart';
import '../../widgets/gradient_background.dart';

class MembersScreen extends ConsumerWidget {
  final String walletId;
  final VoidCallback? onReload;

  const MembersScreen({
    super.key,
    required this.walletId,
    this.onReload,
  });

  Future<void> _updateRole(BuildContext context, Map<String, dynamic> user) async {
    final currentRole = user['role'] as String? ?? 'member';
    String newRole = currentRole;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Change role'),
          content: DropdownButtonFormField<String>(
            value: newRole,
            decoration: const InputDecoration(labelText: 'Role'),
            items: const [
              DropdownMenuItem(value: 'member', child: Text('Member')),
              DropdownMenuItem(value: 'admin', child: Text('Admin')),
              DropdownMenuItem(value: 'owner', child: Text('Owner')),
            ],
            onChanged: (v) {
              if (v != null) setDialogState(() => newRole = v);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final userId = user['user_id'] as String? ?? '';
    try {
      await Api.updateWalletUserRole(walletId, userId, newRole);
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

  Future<void> _removeUser(BuildContext context, Map<String, dynamic> user) async {
    final displayName = user['username'] as String? ?? user['user_id'] as String? ?? '';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove user'),
        content: Text('Remove user $displayName from this wallet?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    final userId = user['user_id'] as String? ?? '';
    try {
      await Api.removeWalletUser(walletId, userId);
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
    final usersAsync = ref.watch(walletUsersProvider(walletId));
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Members'),
          elevation: 0,
        ),
        body: usersAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text(err.toString())),
          data: (users) {
            if (users.isEmpty) {
              return Center(
                child: Text(
                  'No members yet',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              children: [
                ...users.map((u) {
                  final role = u['role'] as String? ?? '';
                  final userId = u['user_id'] as String? ?? '';
                  final displayName = u['username'] as String? ?? userId;
                  return GradientCard(
                    margin: const EdgeInsets.only(bottom: 8),
                    variationSeed: userId.hashCode,
                    child: ListTile(
                      title: Text(displayName),
                      subtitle: Text('Role: $role'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'change_role') _updateRole(context, u);
                          if (v == 'remove') _removeUser(context, u);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'change_role', child: Text('Change role')),
                          const PopupMenuItem(value: 'remove', child: Text('Remove')),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            );
          },
        ),
      ),
    );
  }
}
