import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api.dart';
import '../../utils/toast_service.dart';
import '../../widgets/gradient_card.dart';

class MembersScreen extends ConsumerStatefulWidget {
  final String walletId;
  final List<Map<String, dynamic>> users;
  final VoidCallback onReload;

  const MembersScreen({
    super.key,
    required this.walletId,
    required this.users,
    required this.onReload,
  });

  @override
  ConsumerState<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends ConsumerState<MembersScreen> {
  late List<Map<String, dynamic>> _users;

  @override
  void initState() {
    super.initState();
    _users = List.from(widget.users);
  }

  @override
  void didUpdateWidget(MembersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _users = List.from(widget.users);
  }

  Future<void> _updateRole(Map<String, dynamic> user) async {
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
    if (ok != true || !mounted) return;
    final userId = user['user_id'] as String? ?? '';
    final prev = List<Map<String, dynamic>>.from(_users);
    try {
      await Api.updateWalletUserRole(widget.walletId, userId, newRole);
      widget.onReload();
    } catch (e) {
      if (Api.isPermissionDeniedError(e)) {
        if (mounted) {
          ToastService.showErrorFromContext(context, 'You don\'t have permission. Change was reverted.');
        }
        setState(() => _users = prev);
      } else {
        if (mounted) {
          ToastService.showErrorFromContext(
            context,
            e.toString().replaceFirst('Exception: ', ''),
          );
        }
      }
    }
  }

  Future<void> _removeUser(Map<String, dynamic> user) async {
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
    if (confirm != true || !mounted) return;
    final userId = user['user_id'] as String? ?? '';
    final prev = List<Map<String, dynamic>>.from(_users);
    try {
      await Api.removeWalletUser(widget.walletId, userId);
      widget.onReload();
    } catch (e) {
      if (Api.isPermissionDeniedError(e)) {
        if (mounted) {
          ToastService.showErrorFromContext(context, 'You don\'t have permission. Change was reverted.');
        }
        setState(() => _users = prev);
      } else {
        if (mounted) {
          ToastService.showErrorFromContext(
            context,
            e.toString().replaceFirst('Exception: ', ''),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Members'),
        elevation: 0,
      ),
      body: _users.isEmpty
          ? Center(
              child: Text(
                'No members yet',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              children: [
                ..._users.map((u) {
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
                          if (v == 'change_role') _updateRole(u);
                          if (v == 'remove') _removeUser(u);
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
            ),
    );
  }
}
