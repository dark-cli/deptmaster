import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api.dart';
import '../../providers/wallet_management_provider.dart';
import '../../utils/toast_service.dart';
import '../../widgets/gradient_card.dart';
import '../../widgets/custom_expansion_tile.dart';
import '../../widgets/gradient_background.dart';

class UserGroupsScreen extends ConsumerStatefulWidget {
  final String walletId;

  const UserGroupsScreen({
    super.key,
    required this.walletId,
  });

  @override
  ConsumerState<UserGroupsScreen> createState() => _UserGroupsScreenState();
}

class _UserGroupsScreenState extends ConsumerState<UserGroupsScreen> {
  Future<void> _createGroup() async {
    final nameController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New user group'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'e.g. Editors',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (nameController.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final name = nameController.text.trim();
    try {
      await Api.createWalletUserGroup(widget.walletId, name);
    } catch (e) {
      if (Api.isPermissionDeniedError(e)) {
        if (mounted) {
          ToastService.showErrorFromContext(context, 'You don\'t have permission.');
        }
      } else if (mounted) {
        ToastService.showErrorFromContext(
          context,
          e.toString().replaceFirst('Exception: ', ''),
        );
      }
    }
  }

  Future<void> _deleteGroup(Map<String, dynamic> group) async {
    final isSystem = group['is_system'] == true;
    if (isSystem) {
      ToastService.showErrorFromContext(context, 'System groups cannot be deleted.');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete group'),
        content: Text('Delete "${group['name']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final groupId = group['id'] as String? ?? '';
    try {
      await Api.deleteWalletUserGroup(widget.walletId, groupId);
    } catch (e) {
      if (Api.isPermissionDeniedError(e)) {
        if (mounted) {
          ToastService.showErrorFromContext(context, 'You don\'t have permission.');
        }
      } else if (mounted) {
        ToastService.showErrorFromContext(
          context,
          e.toString().replaceFirst('Exception: ', ''),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userGroupsAsync = ref.watch(userGroupsProvider(widget.walletId));
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('User Groups'),
        ),
        floatingActionButton: Padding(
          padding: const EdgeInsets.only(bottom: 24.0),
          child: FloatingActionButton(
            onPressed: _createGroup,
            tooltip: 'Create new group',
            child: const Icon(Icons.add),
          ),
        ),
        body: userGroupsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text(err.toString())),
          data: (allGroups) {
            final userGroups = allGroups
                .where((g) => g['name'] != '__owners__' && g['name'] != 'all_users')
                .toList();
            if (userGroups.isEmpty) {
              return Center(
                child: Text(
                  'No user groups yet',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              children: [
                ...userGroups.map((g) {
                  final groupId = g['id'] as String? ?? '';
                  return GradientCard(
                    margin: const EdgeInsets.only(bottom: 8),
                    variationSeed: groupId.hashCode,
                    child: CustomExpansionTile(
                      title: Text(_formatGroupName(g['name'] as String? ?? '')),
                      subtitle: const Text('Static'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteGroup(g),
                      ),
                      children: [
                        _UserGroupMembers(
                          walletId: widget.walletId,
                          groupId: g['id'] as String? ?? '',
                        ),
                      ],
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

  String _formatGroupName(String name) {
    if (name == '__owners__') return 'Owners (system)';
    if (name == 'all_users') return 'All Users (system)';
    return name;
  }
}

class _UserGroupMembers extends ConsumerWidget {
  final String walletId;
  final String groupId;

  const _UserGroupMembers({
    required this.walletId,
    required this.groupId,
  });

  Future<void> _removeMember(BuildContext context, String userId) async {
    try {
      await Api.removeWalletUserGroupMember(walletId, groupId, userId);
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

  Future<void> _showAddMemberDialog(
    BuildContext context,
    List<Map<String, dynamic>> members,
    List<Map<String, dynamic>> walletUsers,
  ) async {
    final memberIds = members.map((m) => m['user_id'] as String).toSet();
    final availableUsers = walletUsers
        .where((u) => !memberIds.contains(u['user_id'] ?? u['id']))
        .toList();

    if (availableUsers.isEmpty) {
      if (context.mounted) {
        ToastService.showInfoFromContext(context, 'All users are already in this group.');
      }
      return;
    }

    String? selectedUserId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add member'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: availableUsers.length,
            itemBuilder: (context, index) {
              final user = availableUsers[index];
              final userId = (user['user_id'] ?? user['id']) as String? ?? '';
              final username = user['username'] as String? ?? 'Unknown';
              final email = user['email'] as String?;

              return RadioListTile<String>(
                value: userId,
                groupValue: selectedUserId,
                onChanged: (value) {
                  selectedUserId = value;
                  Navigator.pop(ctx, true);
                },
                title: Text(username),
                subtitle: email != null ? Text(email) : null,
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (ok == true && selectedUserId != null && context.mounted) {
      try {
        await Api.addWalletUserGroupMember(walletId, groupId, selectedUserId!);
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
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(userGroupMembersProvider(WalletGroupKey(walletId, groupId)));
    final walletUsersAsync = ref.watch(walletUsersProvider(walletId));
    return membersAsync.when(
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
      data: (members) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                dense: true,
                leading: const Icon(Icons.add, size: 20),
                title: const Text('Add member'),
                onTap: () => _showAddMemberDialog(context, members, walletUsersAsync.value ?? const []),
              ),
              ...members.map((m) {
                final userId = m['user_id'] as String? ?? '';
                final displayName = m['username'] as String? ?? userId;
                return ListTile(
                  dense: true,
                  title: Text(displayName),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                    onPressed: () => _removeMember(context, userId),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}
