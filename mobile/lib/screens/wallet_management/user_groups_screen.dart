import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api.dart';
import '../../utils/toast_service.dart';
import '../../widgets/gradient_card.dart';
import '../../widgets/custom_expansion_tile.dart';

class UserGroupsScreen extends ConsumerStatefulWidget {
  final String walletId;
  final List<Map<String, dynamic>> userGroups;
  final List<Map<String, dynamic>> users;
  final VoidCallback onReload;

  const UserGroupsScreen({
    super.key,
    required this.walletId,
    required this.userGroups,
    required this.users,
    required this.onReload,
  });

  @override
  ConsumerState<UserGroupsScreen> createState() => _UserGroupsScreenState();
}

class _UserGroupsScreenState extends ConsumerState<UserGroupsScreen> {
  late List<Map<String, dynamic>> _userGroups;

  @override
  void initState() {
    super.initState();
    _userGroups = List.from(widget.userGroups);
  }

  @override
  void didUpdateWidget(UserGroupsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _userGroups = List.from(widget.userGroups);
  }

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
      widget.onReload();
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
      widget.onReload();
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Groups'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _createGroup,
            tooltip: 'Create new group',
          ),
        ],
      ),
      body: _userGroups.isEmpty
          ? Center(
              child: Text(
                'No user groups yet',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              children: [
                ..._userGroups.map((g) {
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
                          users: widget.users,
                          onReload: widget.onReload,
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
    );
  }

  String _formatGroupName(String name) {
    if (name == '__owners__') return 'Owners (system)';
    if (name == 'all_users') return 'All Users (system)';
    return name;
  }
}

class _UserGroupMembers extends StatefulWidget {
  final String walletId;
  final String groupId;
  final List<Map<String, dynamic>> users;
  final VoidCallback onReload;

  const _UserGroupMembers({
    required this.walletId,
    required this.groupId,
    required this.users,
    required this.onReload,
  });

  @override
  State<_UserGroupMembers> createState() => _UserGroupMembersState();
}

class _UserGroupMembersState extends State<_UserGroupMembers> {
  List<Map<String, dynamic>> _members = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await Api.getWalletUserGroupMembers(widget.walletId, widget.groupId);
      if (mounted) setState(() {
        _members = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeMember(String userId) async {
    try {
      await Api.removeWalletUserGroupMember(widget.walletId, widget.groupId, userId);
      await _load();
      widget.onReload();
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

  Future<void> _showAddMemberDialog() async {
    final memberIds = _members.map((m) => m['user_id'] as String).toSet();
    final availableUsers = widget.users
        .where((u) => !memberIds.contains(u['id']))
        .toList();

    if (availableUsers.isEmpty) {
      if (mounted) {
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
              final userId = user['id'] as String? ?? '';
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

    if (ok == true && selectedUserId != null && mounted) {
      try {
        await Api.addWalletUserGroupMember(widget.walletId, widget.groupId, selectedUserId!);
        await _load();
        widget.onReload();
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
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        )),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            dense: true,
            leading: const Icon(Icons.add, size: 20),
            title: const Text('Add member'),
            onTap: _showAddMemberDialog,
          ),
          ..._members.map((m) {
            final userId = m['user_id'] as String? ?? '';
            final displayName = m['username'] as String? ?? userId;
            return ListTile(
              dense: true,
              title: Text(displayName),
              trailing: IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                onPressed: () => _removeMember(userId),
              ),
            );
          }),
        ],
      ),
    );
  }
}
