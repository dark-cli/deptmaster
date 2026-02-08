// Manage wallet: members, user groups, contact groups, permission rules.
// On server permission error we undo local state and show toast (no UI disabling for now).

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
              title: Text(g['name'] as String? ?? ''),
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
    final userIdController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add member'),
        content: TextField(
          controller: userIdController,
          decoration: const InputDecoration(
            labelText: 'Username',
            hintText: 'Enter username',
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
              if (userIdController.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final userId = userIdController.text.trim();
    final prev = List<Map<String, dynamic>>.from(_members);
    try {
      await Api.addWalletUserGroupMember(widget.walletId, widget.groupId, userId);
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
            title: const Text('Add member (enter username)'),
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
              title: Text(g['name'] as String? ?? ''),
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
    final contactIdController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add contact'),
        content: TextField(
          controller: contactIdController,
          decoration: const InputDecoration(
            labelText: 'Contact ID (UUID)',
            hintText: 'Paste contact UUID',
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
              if (contactIdController.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final contactId = contactIdController.text.trim();
    final prev = List<Map<String, dynamic>>.from(_members);
    try {
      await Api.addWalletContactGroupMember(widget.walletId, widget.groupId, contactId);
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
            title: const Text('Add contact (paste contact ID)'),
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
    for (final e in _matrix) {
      final ug = e['user_group_id'] as String? ?? '';
      final cg = e['contact_group_id'] as String? ?? '';
      final key = '$ug:$cg';
      final names = (e['action_names'] as List<dynamic>?)?.cast<String>() ?? <String>[];
      _matrixMap[key] = Set<String>.from(names);
    }
  }

  bool _hasAction(String userGroupId, String contactGroupId, String actionName) {
    final key = '$userGroupId:$contactGroupId';
    return _matrixMap[key]?.contains(actionName) ?? false;
  }

  Future<void> _toggleAction(String userGroupId, String contactGroupId, String actionName, bool value) async {
    final key = '$userGroupId:$contactGroupId';
    final current = Set<String>.from(_matrixMap[key] ?? {});
    if (value) {
      current.add(actionName);
    } else {
      current.remove(actionName);
    }
    final entries = _matrix.map((e) {
      final ug = e['user_group_id'] as String? ?? '';
      final cg = e['contact_group_id'] as String? ?? '';
      if (ug == userGroupId && cg == contactGroupId) {
        return {'user_group_id': ug, 'contact_group_id': cg, 'action_names': current.toList()};
      }
      return {'user_group_id': ug, 'contact_group_id': cg, 'action_names': (e['action_names'] as List<dynamic>?)?.cast<String>() ?? []};
    }).toList();
    final hasEntry = entries.any((e) => e['user_group_id'] == userGroupId && e['contact_group_id'] == contactGroupId);
    if (!hasEntry) {
      entries.add({'user_group_id': userGroupId, 'contact_group_id': contactGroupId, 'action_names': current.toList()});
    }
    final prev = List<Map<String, dynamic>>.from(_matrix);
    final prevMap = Map<String, Set<String>>.from(_matrixMap);
    _matrixMap[key] = current;
    setState(() {});
    try {
      await Api.putWalletPermissionMatrix(widget.walletId, entries);
      widget.onReload();
    } catch (e) {
      if (Api.isPermissionDeniedError(e)) {
        widget.onPermissionError();
        _matrixMap.clear();
        for (final k in prevMap.keys) {
          _matrixMap[k] = Set<String>.from(prevMap[k]!);
        }
        setState(() => _matrix = prev);
      } else if (mounted) {
        ToastService.showErrorFromContext(
          context,
          e.toString().replaceFirst('Exception: ', ''),
        );
        _matrixMap.clear();
        for (final k in prevMap.keys) {
          _matrixMap[k] = Set<String>.from(prevMap[k]!);
        }
        setState(() => _matrix = prev);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = widget.permissionActions;
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 24),
        child: DataTable(
          columns: [
            const DataColumn(label: Text('User group \\ Contact group')),
            ...widget.contactGroups.map((cg) => DataColumn(
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  cg['name'] as String? ?? '',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )),
          ],
          rows: widget.userGroups.map((ug) {
            final ugId = ug['id'] as String? ?? '';
            final ugName = ug['name'] as String? ?? '';
            return DataRow(
              cells: [
                DataCell(ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(ugName, overflow: TextOverflow.ellipsis),
                )),
                ...widget.contactGroups.map((cg) {
                  final cgId = cg['id'] as String? ?? '';
                  return DataCell(
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final a in actions)
                          Builder(
                            builder: (ctx) {
                              final name = a['name'] as String? ?? '';
                              final checked = _hasAction(ugId, cgId, name);
                              return FilterChip(
                                label: Text(name, style: const TextStyle(fontSize: 10)),
                                selected: checked,
                                onSelected: (v) => _toggleAction(ugId, cgId, name, v ?? false),
                              );
                            },
                          ),
                      ],
                    ),
                  );
                }),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}
