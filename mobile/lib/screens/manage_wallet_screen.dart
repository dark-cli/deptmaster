// Manage wallet: members, user groups, contact groups, permission rules.
// On server permission error we undo local state and show toast (no UI disabling for now).

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart';
import '../utils/toast_service.dart';
import '../widgets/gradient_background.dart';

class ManageWalletScreen extends ConsumerStatefulWidget {
  final String walletId;
  final String walletName;

  const ManageWalletScreen({
    super.key,
    required this.walletId,
    required this.walletName,
  });

  @override
  ConsumerState<ManageWalletScreen> createState() => _ManageWalletScreenState();
}

class _ManageWalletScreenState extends ConsumerState<ManageWalletScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Map<int, VoidCallback?> _fabActions = {};
  void _onTabChanged() => setState(() {});
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _userGroups = [];
  List<Map<String, dynamic>> _contactGroups = [];
  List<Map<String, dynamic>> _permissionActions = [];
  List<Map<String, dynamic>> _matrix = [];
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    // Defer load to next frame so the screen and loading indicator show first (avoids UI freeze).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadAll();
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _registerFab(int tabIndex, VoidCallback? action) {
    if (_fabActions[tabIndex] != action) {
      setState(() => _fabActions[tabIndex] = action);
    }
  }

  Widget? _buildFloatingActionButton() {
    final action = _fabActions[_tabController.index];
    if (action == null) return null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: FloatingActionButton(
        onPressed: action,
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        Api.getWalletUsers(widget.walletId),
        Api.getWalletUserGroups(widget.walletId),
        Api.getWalletContactGroups(widget.walletId),
        Api.getWalletPermissionActions(widget.walletId),
        Api.getWalletPermissionMatrix(widget.walletId),
      ]);
      if (mounted) {
        setState(() {
          _users = results[0] as List<Map<String, dynamic>>;
          _userGroups = results[1] as List<Map<String, dynamic>>;
          _contactGroups = results[2] as List<Map<String, dynamic>>;
          _permissionActions = results[3] as List<Map<String, dynamic>>;
          _matrix = results[4] as List<Map<String, dynamic>>;
          _loading = false;
          _loadError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        final errStr = e.toString().replaceFirst('Exception: ', '');
        setState(() {
          _loading = false;
          _loadError = errStr;
        });
        if (Api.isPermissionDeniedError(e)) {
          ToastService.showErrorFromContext(
            context,
            'You don\'t have permission to manage this wallet.',
          );
        } else if (errStr.contains('404')) {
          ToastService.showErrorFromContext(
            context,
            'Wallet or endpoint not found (404). Restart the backend server and try again.',
          );
        }
      }
    }
  }

  void _onPermissionError() {
    ToastService.showErrorFromContext(
      context,
      'You don\'t have permission. Change was reverted.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text('Manage: ${widget.walletName}'),
          bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Members', icon: Icon(Icons.people)),
            Tab(text: 'User groups', icon: Icon(Icons.group)),
            Tab(text: 'Contact groups', icon: Icon(Icons.contacts)),
            Tab(text: 'Rules', icon: Icon(Icons.rule)),
          ],
        ),
      ),
      floatingActionButton: _buildFloatingActionButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_loadError!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _loadAll,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadAll,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _MembersTab(
                        walletId: widget.walletId,
                        users: _users,
                        onReload: _loadAll,
                        onPermissionError: _onPermissionError,
                        onRegisterFab: (action) => _registerFab(0, action),
                      ),
                      _UserGroupsTab(
                        walletId: widget.walletId,
                        userGroups: _userGroups.where((g) => g['is_system'] != true).toList(),
                        users: _users,
                        onReload: _loadAll,
                        onPermissionError: _onPermissionError,
                        onRegisterFab: (action) => _registerFab(1, action),
                      ),
                      _ContactGroupsTab(
                        walletId: widget.walletId,
                        contactGroups: _contactGroups.where((g) => g['is_system'] != true).toList(),
                        onReload: _loadAll,
                        onPermissionError: _onPermissionError,
                        onRegisterFab: (action) => _registerFab(2, action),
                      ),
                      _RulesTab(
                        walletId: widget.walletId,
                        userGroups: _userGroups,
                        contactGroups: _contactGroups,
                        permissionActions: _permissionActions,
                        matrix: _matrix,
                        onReload: _loadAll,
                        onPermissionError: _onPermissionError,
                        onRegisterFab: (action) => _registerFab(3, action),
                      ),
                    ],
                  ),
                ),
      ),
    );
  }
}

/// Invite code dialog: generate 4-digit code; anyone with the code can join the wallet.
class _InviteCodeDialog extends StatefulWidget {
  final String walletId;

  const _InviteCodeDialog({required this.walletId});

  @override
  State<_InviteCodeDialog> createState() => _InviteCodeDialogState();
}

class _InviteCodeDialogState extends State<_InviteCodeDialog> {
  String? _code;
  bool _loading = false;
  String? _error;

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
      _code = null;
    });
    try {
      final code = await Api.createWalletInviteCode(widget.walletId);
      if (mounted) {
        setState(() {
          _code = code;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Invite by code'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Share this 4-digit code. Anyone who enters it will join this wallet as a member.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13),
            )
          else if (_code != null) ...[
            Center(
              child: SelectableText(
                _code!,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  letterSpacing: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  if (_code != null && context.mounted) {
                    Clipboard.setData(ClipboardData(text: _code!));
                    ToastService.showSuccessFromContext(context, 'Code copied');
                  }
                },
                icon: const Icon(Icons.copy, size: 20),
                label: const Text('Copy'),
              ),
            ),
          ] else
            FilledButton.icon(
              onPressed: _generate,
              icon: const Icon(Icons.qr_code, size: 20),
              label: const Text('Generate invite code'),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _MembersTab extends StatefulWidget {
  final String walletId;
  final List<Map<String, dynamic>> users;
  final VoidCallback onReload;
  final VoidCallback onPermissionError;
  final void Function(VoidCallback? action) onRegisterFab;

  const _MembersTab({
    required this.walletId,
    required this.users,
    required this.onReload,
    required this.onPermissionError,
    required this.onRegisterFab,
  });

  @override
  State<_MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<_MembersTab> {
  late List<Map<String, dynamic>> _users;

  @override
  void initState() {
    super.initState();
    _users = List.from(widget.users);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onRegisterFab(_showInviteCode);
    });
  }

  @override
  void didUpdateWidget(_MembersTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _users = List.from(widget.users);
  }

  Future<void> _showInviteCode() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _InviteCodeDialog(walletId: widget.walletId),
    );
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
        widget.onPermissionError();
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
        content: Text(
          'Remove user $displayName from this wallet?',
        ),
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
        widget.onPermissionError();
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      children: [
        ..._users.map((u) {
          final role = u['role'] as String? ?? '';
          final userId = u['user_id'] as String? ?? '';
          final displayName = u['username'] as String? ?? userId;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
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
    );
  }
}

class _UserGroupsTab extends StatefulWidget {
  final String walletId;
  final List<Map<String, dynamic>> userGroups;
  final List<Map<String, dynamic>> users;
  final VoidCallback onReload;
  final VoidCallback onPermissionError;
  final void Function(VoidCallback? action) onRegisterFab;

  const _UserGroupsTab({
    required this.walletId,
    required this.userGroups,
    required this.users,
    required this.onReload,
    required this.onPermissionError,
    required this.onRegisterFab,
  });

  @override
  State<_UserGroupsTab> createState() => _UserGroupsTabState();
}

class _UserGroupsTabState extends State<_UserGroupsTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onRegisterFab(_createGroup);
    });
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
    final prev = List<Map<String, dynamic>>.from(widget.userGroups);
    try {
      await Api.createWalletUserGroup(widget.walletId, name);
      widget.onReload();
    } catch (e) {
      if (Api.isPermissionDeniedError(e)) {
        widget.onPermissionError();
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
        widget.onPermissionError();
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      children: [
        ...widget.userGroups.map((g) {
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ExpansionTile(
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
                  onPermissionError: widget.onPermissionError,
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _UserGroupMembers extends StatefulWidget {
  final String walletId;
  final String groupId;
  final List<Map<String, dynamic>> users;
  final VoidCallback onReload;
  final VoidCallback onPermissionError;

  const _UserGroupMembers({
    required this.walletId,
    required this.groupId,
    required this.users,
    required this.onReload,
    required this.onPermissionError,
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

  Future<void> _addMember() async {
    showDialog(
      context: context,
      builder: (context) => _AddMemberDialog(
        walletId: widget.walletId,
        groupId: widget.groupId,
        onAdd: (username) async {
          Navigator.pop(context);
          try {
            await Api.addWalletUserGroupMember(widget.walletId, widget.groupId, username);
            await _load();
            widget.onReload();
          } catch (e) {
            if (mounted) {
              if (Api.isPermissionDeniedError(e)) {
                widget.onPermissionError();
              } else {
                ToastService.showErrorFromContext(
                  context,
                  e.toString().replaceFirst('Exception: ', ''),
                );
              }
            }
          }
        },
      ),
    );
  }

  Future<void> _removeMember(String userId) async {
    final prev = List<Map<String, dynamic>>.from(_members);
    try {
      await Api.removeWalletUserGroupMember(widget.walletId, widget.groupId, userId);
      await _load();
      widget.onReload();
    } catch (e) {
      if (Api.isPermissionDeniedError(e)) {
        widget.onPermissionError();
        setState(() => _members = prev);
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
            onTap: _addMember,
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

class _ContactGroupsTab extends StatefulWidget {
  final String walletId;
  final List<Map<String, dynamic>> contactGroups;
  final VoidCallback onReload;
  final VoidCallback onPermissionError;
  final void Function(VoidCallback? action) onRegisterFab;

  const _ContactGroupsTab({
    required this.walletId,
    required this.contactGroups,
    required this.onReload,
    required this.onPermissionError,
    required this.onRegisterFab,
  });

  @override
  State<_ContactGroupsTab> createState() => _ContactGroupsTabState();
}

class _ContactGroupsTabState extends State<_ContactGroupsTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onRegisterFab(_createGroup);
    });
  }

  Future<void> _createGroup() async {
    final nameController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New contact group'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'e.g. VIP contacts',
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
      await Api.createWalletContactGroup(widget.walletId, name);
      widget.onReload();
    } catch (e) {
      if (Api.isPermissionDeniedError(e)) {
        widget.onPermissionError();
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
      await Api.deleteWalletContactGroup(widget.walletId, groupId);
      widget.onReload();
    } catch (e) {
      if (Api.isPermissionDeniedError(e)) {
        widget.onPermissionError();
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      children: [
        ...widget.contactGroups.map((g) {
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ExpansionTile(
              title: Text(_formatGroupName(g['name'] as String? ?? '')),
              subtitle: const Text('Static'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deleteGroup(g),
              ),
              children: [
                _ContactGroupMembers(
                  walletId: widget.walletId,
                  groupId: g['id'] as String? ?? '',
                  onReload: widget.onReload,
                  onPermissionError: widget.onPermissionError,
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _ContactGroupMembers extends StatefulWidget {
  final String walletId;
  final String groupId;
  final VoidCallback onReload;
  final VoidCallback onPermissionError;

  const _ContactGroupMembers({
    required this.walletId,
    required this.groupId,
    required this.onReload,
    required this.onPermissionError,
  });

  @override
  State<_ContactGroupMembers> createState() => _ContactGroupMembersState();
}

class _ContactGroupMembersState extends State<_ContactGroupMembers> {
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
      final list = await Api.getWalletContactGroupMembers(widget.walletId, widget.groupId);
      if (mounted) setState(() {
        _members = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addMember() async {
    showDialog(
      context: context,
      builder: (context) => _AddContactDialog(
        walletId: widget.walletId,
        groupId: widget.groupId,
        onAdd: (contactId) async {
          Navigator.pop(context);
          try {
            await Api.addWalletContactGroupMember(widget.walletId, widget.groupId, contactId);
            await _load();
            widget.onReload();
          } catch (e) {
            if (mounted) {
              if (Api.isPermissionDeniedError(e)) {
                widget.onPermissionError();
              } else {
                ToastService.showErrorFromContext(
                  context,
                  e.toString().replaceFirst('Exception: ', ''),
                );
              }
            }
          }
        },
      ),
    );
  }

  Future<void> _removeMember(String contactId) async {
    final prev = List<Map<String, dynamic>>.from(_members);
    try {
      await Api.removeWalletContactGroupMember(widget.walletId, widget.groupId, contactId);
      await _load();
      widget.onReload();
    } catch (e) {
      if (Api.isPermissionDeniedError(e)) {
        widget.onPermissionError();
        setState(() => _members = prev);
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
            title: const Text('Add contact'),
            onTap: _addMember,
          ),
          ..._members.map((m) {
            final contactId = m['contact_id'] as String? ?? '';
            return ListTile(
              dense: true,
              title: Text(contactId),
              trailing: IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                onPressed: () => _removeMember(contactId),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _RulesTab extends StatefulWidget {
  final String walletId;
  final List<Map<String, dynamic>> userGroups;
  final List<Map<String, dynamic>> contactGroups;
  final List<Map<String, dynamic>> permissionActions;
  final List<Map<String, dynamic>> matrix;
  final VoidCallback onReload;
  final VoidCallback onPermissionError;
  final void Function(VoidCallback? action) onRegisterFab;

  const _RulesTab({
    required this.walletId,
    required this.userGroups,
    required this.contactGroups,
    required this.permissionActions,
    required this.matrix,
    required this.onReload,
    required this.onPermissionError,
    required this.onRegisterFab,
  });

  @override
  State<_RulesTab> createState() => _RulesTabState();
}

class _RulesTabState extends State<_RulesTab> {
  late List<Map<String, dynamic>> _matrix;
  final Map<String, Set<String>> _matrixMap = {};
  final Map<String, Set<String>> _matrixMapDenied = {};

  @override
  void initState() {
    super.initState();
    _matrix = List.from(widget.matrix);
    _buildMatrixMap();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onRegisterFab(null);
    });
  }

  @override
  void didUpdateWidget(_RulesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _matrix = List.from(widget.matrix);
    _buildMatrixMap();
  }

  void _buildMatrixMap() {
    _matrixMap.clear();
    _matrixMapDenied.clear();
    for (final e in _matrix) {
      final ug = e['user_group_id'] as String? ?? '';
      final cg = e['contact_group_id'] as String? ?? '';
      final key = '$ug:$cg';
      final allowed = (e['allowed_actions'] as List<dynamic>?)?.cast<String>() ??
          (e['action_names'] as List<dynamic>?)?.cast<String>() ??
          <String>[];
      final denied = (e['denied_actions'] as List<dynamic>?)?.cast<String>() ?? <String>[];
      _matrixMap[key] = Set<String>.from(allowed);
      _matrixMapDenied[key] = Set<String>.from(denied);
    }
  }

  Set<String> _getActions(String userGroupId, String contactGroupId) {
    final key = '$userGroupId:$contactGroupId';
    return _matrixMap[key] ?? {};
  }

  Set<String> _getDenied(String userGroupId, String contactGroupId) {
    final key = '$userGroupId:$contactGroupId';
    return _matrixMapDenied[key] ?? {};
  }

  Future<void> _savePermissions(
    String userGroupId,
    String contactGroupId,
    List<String> allowedActions,
    List<String> deniedActions,
  ) async {
    final key = '$userGroupId:$contactGroupId';
    final prevMap = Map<String, Set<String>>.from(_matrixMap);
    final prevDenied = Map<String, Set<String>>.from(_matrixMapDenied);
    final prevMatrix = List<Map<String, dynamic>>.from(_matrix);

    setState(() {
      _matrixMap[key] = Set<String>.from(allowedActions);
      _matrixMapDenied[key] = Set<String>.from(deniedActions);
    });

    final entry = {
      'user_group_id': userGroupId,
      'contact_group_id': contactGroupId,
      'action_names': allowedActions,
      'allowed_actions': allowedActions,
      'denied_actions': deniedActions,
    };

    try {
      await Api.putWalletPermissionMatrix(widget.walletId, [entry]);
      widget.onReload();
      if (mounted) {
        ToastService.showSuccessFromContext(context, 'Permissions saved');
      }
    } catch (e) {
      if (mounted) {
        if (Api.isPermissionDeniedError(e)) {
          widget.onPermissionError();
        } else {
          ToastService.showErrorFromContext(
            context,
            e.toString().replaceFirst('Exception: ', ''),
          );
        }
        setState(() {
          _matrixMap.clear();
          _matrixMap.addAll(prevMap);
          _matrixMapDenied.clear();
          _matrixMapDenied.addAll(prevDenied);
          _matrix = prevMatrix;
        });
      }
    }
  }

  void _openEditor(String ugId, String ugName, String cgId, String cgName) {
    showDialog(
      context: context,
      builder: (context) => _PermissionsDialog(
        userGroupName: ugName,
        contactGroupName: cgName,
        availableActions: widget.permissionActions,
        initialAllowed: _getActions(ugId, cgId).toList(),
        initialDenied: _getDenied(ugId, cgId).toList(),
        onSave: (allowed, denied) => _savePermissions(ugId, cgId, allowed, denied),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.userGroups.isEmpty || widget.contactGroups.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Create at least one user group and one contact group to set rules.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      children: [
        ...List.generate(widget.userGroups.length, (index) {
          final ug = widget.userGroups[index];
          final ugId = ug['id'] as String? ?? '';
          final rawUgName = ug['name'] as String? ?? '';
          final ugName = _formatGroupName(rawUgName);

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ExpansionTile(
              title: Text(ugName, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('User Group'),
              initiallyExpanded: index == 0,
              children: [
                const Divider(height: 1),
                ...widget.contactGroups.map((cg) {
                  final cgId = cg['id'] as String? ?? '';
                  final rawCgName = cg['name'] as String? ?? '';
                  final cgName = _formatGroupName(rawCgName);
                  final activeActions = _getActions(ugId, cgId);

                  return ListTile(
                    title: Text(cgName),
                    subtitle: activeActions.isEmpty
                        ? const Text('No access', style: TextStyle(color: Colors.grey))
                        : Text(
                            _getDenied(ugId, cgId).isEmpty
                                ? '${activeActions.length} allow'
                                : '${activeActions.length} allow, ${_getDenied(ugId, cgId).length} deny',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                    trailing: const Icon(Icons.edit, size: 20),
                    onTap: () => _openEditor(ugId, ugName, cgId, cgName),
                  );
                }),
                const SizedBox(height: 8),
              ],
            ),
          );
        }),
      ],
    );
  }
}

enum _PermissionState { allow, deny, unset }

class _PermissionsDialog extends StatefulWidget {
  final String userGroupName;
  final String contactGroupName;
  final List<Map<String, dynamic>> availableActions;
  final List<String> initialAllowed;
  final List<String> initialDenied;
  final void Function(List<String> allowed, List<String> denied) onSave;

  const _PermissionsDialog({
    required this.userGroupName,
    required this.contactGroupName,
    required this.availableActions,
    required this.initialAllowed,
    required this.initialDenied,
    required this.onSave,
  });

  @override
  State<_PermissionsDialog> createState() => _PermissionsDialogState();
}

class _PermissionsDialogState extends State<_PermissionsDialog> {
  late Set<String> _allowed;
  late Set<String> _denied;
  late Map<String, List<Map<String, dynamic>>> _groupedActions;

  @override
  void initState() {
    super.initState();
    _allowed = Set.from(widget.initialAllowed);
    _denied = Set.from(widget.initialDenied);
    _groupActions();
  }

  bool _isActive(String name) {
    return _allowed.contains(name) || _denied.contains(name);
  }

  _PermissionState _getAllowDeny(String name) {
    if (_denied.contains(name)) return _PermissionState.deny;
    return _PermissionState.allow;
  }

  /// When clearing a permission, also clear any permissions that depend on it (backend rule:
  /// e.g. contact:delete requires contact:read; transaction:* requires contact:read).
  void _clearDependents(String name) {
    if (name == 'contact:read') {
      _allowed.removeAll(['contact:create', 'contact:update', 'contact:delete', 'contact:close']);
      _denied.removeAll(['contact:create', 'contact:update', 'contact:delete', 'contact:close']);
      _allowed.removeWhere((a) => a.startsWith('transaction:'));
      _denied.removeWhere((a) => a.startsWith('transaction:'));
    } else if (name == 'wallet:read') {
      _allowed.removeAll(['wallet:update', 'wallet:delete', 'wallet:manage_members']);
      _denied.removeAll(['wallet:update', 'wallet:delete', 'wallet:manage_members']);
    }
  }

  void _setState(String name, _PermissionState state) {
    setState(() {
      _allowed.remove(name);
      _denied.remove(name);
      if (state == _PermissionState.allow) {
        _allowed.add(name);
        if (!name.endsWith(':read')) {
          final parts = name.split(':');
          if (parts.length > 1) _allowed.add('${parts[0]}:read');
        }
        if (name.startsWith('transaction:')) _allowed.add('contact:read');
      } else if (state == _PermissionState.deny) {
        _denied.add(name);
      } else {
        // Unset: clear any permissions that depend on this one so the backend accepts the save
        _clearDependents(name);
      }
    });
  }

  void _groupActions() {
    _groupedActions = {};
    for (final action in widget.availableActions) {
      final name = action['name'] as String? ?? '';
      final parts = name.split(':');
      final category = parts.isNotEmpty ? parts[0] : 'other';
      
      if (!_groupedActions.containsKey(category)) {
        _groupedActions[category] = [];
      }
      _groupedActions[category]!.add(action);
    }
  }

  String _formatActionName(String name) {
    const manualNames = {
      'contact:create': 'Add Contact',
      'contact:read': 'View Contacts',
      'contact:update': 'Edit Contact',
      'contact:delete': 'Delete Contact',
      'transaction:create': 'Add Transaction',
      'transaction:read': 'View Transactions',
      'transaction:update': 'Edit Transaction',
      'transaction:delete': 'Delete Transaction',
      'transaction:close': 'Close Debt',
      'events:read': 'View Activity Log',
      'wallet:read': 'View Wallet Details',
      'wallet:update': 'Edit Wallet Details',
      'wallet:delete': 'Delete Wallet',
      'wallet:manage_members': 'Manage Members',
    };
    
    if (manualNames.containsKey(name)) {
      return manualNames[name]!;
    }

    final parts = name.split(':');
    if (parts.length > 1) {
      // Capitalize first letter of action
      final action = parts[1];
      return action[0].toUpperCase() + action.substring(1).replaceAll('_', ' ');
    }
    return name;
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'contact':
        return Icons.contacts_outlined;
      case 'transaction':
        return Icons.receipt_long_outlined;
      case 'wallet':
        return Icons.account_balance_wallet_outlined;
      case 'events':
        return Icons.history;
      default:
        return Icons.settings_outlined;
    }
  }

  IconData _getActionIcon(String name) {
    if (name.contains(':create')) return Icons.add_circle_outline;
    if (name.contains(':read')) return Icons.visibility_outlined;
    if (name.contains(':update')) return Icons.edit_outlined;
    if (name.contains(':delete')) return Icons.delete_outline;
    if (name.contains(':close')) return Icons.check_circle_outlined;
    if (name.contains('manage')) return Icons.manage_accounts_outlined;
    return Icons.circle_outlined;
  }


  @override
  Widget build(BuildContext context) {
    if (widget.availableActions.isEmpty) {
      return AlertDialog(
        title: const Text('Edit Permissions'),
        content: const Text(
          'No permission actions loaded. Pull down to refresh the page.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      );
    }

    final categories = _groupedActions.keys.toList()..sort();

    final screenWidth = MediaQuery.sizeOf(context).width;

    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: (screenWidth < 400) ? 8.0 : 40.0,
        vertical: 24,
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Edit Permissions'),
          const SizedBox(height: 4),
          Text(
            '${widget.userGroupName} → ${widget.contactGroupName}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              final actions = _groupedActions[category]!;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (index > 0) const Divider(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(_getCategoryIcon(category), size: 20, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          category[0].toUpperCase() + category.substring(1),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...actions.map((action) {
                    final name = action['name'] as String? ?? '';
                    final displayName = _formatActionName(name);
                    final active = _isActive(name);
                    final allowDeny = _getAllowDeny(name);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Checkbox(
                                value: active,
                                onChanged: (checked) {
                                  if (checked == true) {
                                    _setState(name, _PermissionState.allow);
                                  } else {
                                    _setState(name, _PermissionState.unset);
                                  }
                                },
                              ),
                              Icon(_getActionIcon(name), size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  displayName,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                          if (active) ...[
                            const SizedBox(height: 6),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final narrow = constraints.maxWidth < 280;
                                return SegmentedButton<_PermissionState>(
                                  style: narrow
                                      ? const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap, padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8, vertical: 6)))
                                      : null,
                                  segments: [
                                    ButtonSegment(value: _PermissionState.allow, icon: const Icon(Icons.check, size: 16), label: narrow ? null : const Text('Allow')),
                                    ButtonSegment(value: _PermissionState.deny, icon: const Icon(Icons.block, size: 16), label: narrow ? null : const Text('Deny')),
                                  ],
                                  selected: {allowDeny},
                                  onSelectionChanged: (s) => _setState(name, s.first),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                ],
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            widget.onSave(_allowed.toList(), _denied.toList());
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// Helper to format group names
String _formatGroupName(String name) {
  if (name == 'all_users') return 'All Members';
  if (name == 'all_contacts') return 'All Contacts';
  return name;
}

// Dialog for adding a member (searchable)
class _AddMemberDialog extends StatefulWidget {
  final String walletId;
  final String groupId;
  final Function(String) onAdd;

  const _AddMemberDialog({
    required this.walletId,
    required this.groupId,
    required this.onAdd,
  });

  @override
  State<_AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<_AddMemberDialog> {
  final _searchController = TextEditingController();
  List<dynamic> _walletUsers = [];
  List<dynamic> _searchResults = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final users = await Api.getWalletUsers(widget.walletId);
      
      if (mounted) {
        setState(() {
          _walletUsers = users;
          _searchResults = users;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _search(String query) {
    final q = query.toLowerCase();
    setState(() {
      _searchResults = _walletUsers.where((u) {
        final username = (u['username'] as String? ?? '').toLowerCase();
        return username.contains(q);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add member to group'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search members',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _search,
            ),
            const SizedBox(height: 16),
            if (_loading)
              const CircularProgressIndicator()
            else if (_error != null)
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final user = _searchResults[index];
                    final username = user['username'] as String? ?? 'Unknown';
                    return ListTile(
                      title: Text(username),
                      onTap: () => widget.onAdd(username),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

// Dialog for adding a contact (searchable)
class _AddContactDialog extends StatefulWidget {
  final String walletId;
  final String groupId;
  final Function(String) onAdd;

  const _AddContactDialog({
    required this.walletId,
    required this.groupId,
    required this.onAdd,
  });

  @override
  State<_AddContactDialog> createState() => _AddContactDialogState();
}

class _AddContactDialogState extends State<_AddContactDialog> {
  final _searchController = TextEditingController();
  List<dynamic> _contacts = [];
  List<dynamic> _searchResults = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    try {
      final jsonStr = await Api.getContacts();
      final List<dynamic> contacts = jsonDecode(jsonStr);
      
      if (mounted) {
        setState(() {
          _contacts = contacts;
          _searchResults = contacts;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _search(String query) {
    final q = query.toLowerCase();
    setState(() {
      _searchResults = _contacts.where((c) {
        final name = (c['name'] as String? ?? '').toLowerCase();
        return name.contains(q);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add contact to group'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search contacts',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _search,
            ),
            const SizedBox(height: 16),
            if (_loading)
              const CircularProgressIndicator()
            else if (_error != null)
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final contact = _searchResults[index];
                    final name = contact['name'] as String? ?? 'Unknown';
                    final id = contact['id'] as String? ?? '';
                    return ListTile(
                      title: Text(name),
                      onTap: () => widget.onAdd(id),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
