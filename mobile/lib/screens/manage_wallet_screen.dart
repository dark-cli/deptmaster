// Wallet management with Android Settings-style navigation
// Sections: People & Access, Groups, Permissions, Wallet Settings

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart';
import '../providers/data_change_provider.dart';
import '../utils/toast_service.dart';
import '../widgets/gradient_background.dart';
import '../widgets/management_section_card.dart';
import 'wallet_management/members_screen.dart';
import 'wallet_management/user_groups_screen.dart';
import 'wallet_management/contact_groups_screen.dart';
import 'wallet_management/permission_rules_screen.dart';
import 'wallet_management/wallet_permissions_screen.dart';
import 'wallet_management/member_permissions_screen.dart';
import 'wallet_management/contact_permissions_screen.dart';
import '../widgets/invite_code_dialog.dart';

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

class _ManageWalletScreenState extends ConsumerState<ManageWalletScreen> {
  // Data
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _userGroups = [];
  List<Map<String, dynamic>> _contactGroups = [];
  List<Map<String, dynamic>> _permissionActions = [];
  List<Map<String, dynamic>> _matrix = [];
  List<Map<String, dynamic>> _walletPermissions = [];
  List<Map<String, dynamic>> _memberPermissions = [];
  bool _loading = true;
  String? _loadError;
  StreamSubscription<DataChangeEvent>? _dataChangeSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadAll();
        _listenToDataChanges();
      }
    });
  }

  void _listenToDataChanges() {
    _dataChangeSubscription = Api.dataChangeStream.listen((event) {
      if (mounted && event.walletId == widget.walletId) {
        if ([
          DataChangeKind.walletMembership,
          DataChangeKind.contacts,
          DataChangeKind.permissions,
        ].contains(event.kind)) {
          _loadAll();
        }
      }
    });
  }

  @override
  void dispose() {
    _dataChangeSubscription?.cancel();
    super.dispose();
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

      List<Map<String, dynamic>> walletPerms = [];
      try {
        walletPerms = await Api.getWalletPermissions(widget.walletId);
      } catch (e) {
        debugPrint('[manage-wallet] Failed to load wallet permissions: $e');
      }

      List<Map<String, dynamic>> memberPerms = [];
      try {
        memberPerms = await Api.getMemberPermissions(widget.walletId);
      } catch (e) {
        debugPrint('[manage-wallet] Failed to load member permissions: $e');
      }

      if (mounted) {
        setState(() {
          _users = results[0] as List<Map<String, dynamic>>;
          _userGroups = results[1] as List<Map<String, dynamic>>;
          _contactGroups = results[2] as List<Map<String, dynamic>>;
          _permissionActions = results[3] as List<Map<String, dynamic>>;
          _matrix = results[4] as List<Map<String, dynamic>>;
          _walletPermissions = walletPerms;
          _memberPermissions = memberPerms;
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

  Future<void> _showRenameWalletDialog() async {
    final nameController = TextEditingController(text: widget.walletName);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename wallet'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Wallet name'),
          autofocus: true,
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
    );
    if (ok != true) return;
    ToastService.showInfoFromContext(context, 'Rename wallet (coming soon - API not yet available)');
  }

  Future<void> _showLeaveWalletDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave wallet'),
        content: const Text('You will no longer have access to this wallet. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    ToastService.showInfoFromContext(context, 'Leave wallet (coming soon - API not yet available)');
  }

  Future<void> _showDeleteWalletDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete wallet'),
        content: const Text('This will permanently delete the wallet and all its data. This action cannot be undone.'),
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
    if (confirm != true) return;
    ToastService.showInfoFromContext(context, 'Delete wallet (coming soon - API not yet available)');
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text('Manage: ${widget.walletName}'),
        ),
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
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      children: [
                        // 👥 PEOPLE & ACCESS
                        ManagementSectionCard(
                          title: 'PEOPLE & ACCESS',
                          icon: Icons.people,
                          tiles: [
                            ManagementTile(
                              title: 'Members',
                              subtitle: '${_users.length} member${_users.length == 1 ? '' : 's'}',
                              leadingIcon: Icons.person,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => MembersScreen(
                                      walletId: widget.walletId,
                                      users: _users,
                                      onReload: _loadAll,
                                    ),
                                  ),
                                );
                              },
                            ),
                            ManagementTile(
                              title: 'Invite by Code',
                              subtitle: 'Share 4-digit code',
                              leadingIcon: Icons.share,
                              onTap: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => InviteCodeDialog(walletId: widget.walletId),
                                );
                              },
                            ),
                          ],
                        ),
                        // 📦 GROUPS
                        ManagementSectionCard(
                          title: 'GROUPS',
                          icon: Icons.folder_special,
                          tiles: [
                            ManagementTile(
                              title: 'User Groups',
                              subtitle: '${_userGroups.length} group${_userGroups.length == 1 ? '' : 's'}',
                              leadingIcon: Icons.group,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => UserGroupsScreen(
                                      walletId: widget.walletId,
                                      userGroups: _userGroups.where((g) {
                                        final name = g['name'] as String? ?? '';
                                        return name != '__owners__' && name != 'all_users';
                                      }).toList(),
                                      users: _users,
                                      onReload: _loadAll,
                                    ),
                                  ),
                                );
                              },
                            ),
                            ManagementTile(
                              title: 'Contact Groups',
                              subtitle: '${_contactGroups.length} group${_contactGroups.length == 1 ? '' : 's'}',
                              leadingIcon: Icons.contacts,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ContactGroupsScreen(
                                      walletId: widget.walletId,
                                      contactGroups: _contactGroups,
                                      onReload: _loadAll,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        // 🔒 PERMISSIONS
                        ManagementSectionCard(
                          title: 'PERMISSIONS',
                          icon: Icons.security,
                          tiles: [
                            ManagementTile(
                              title: 'Permission Rules',
                              subtitle: 'Access matrix',
                              leadingIcon: Icons.rule,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => PermissionRulesScreen(
                                      walletId: widget.walletId,
                                    ),
                                  ),
                                );
                              },
                            ),
                            ManagementTile(
                              title: 'Member Permissions',
                              subtitle: 'Delegable permissions',
                              leadingIcon: Icons.manage_accounts,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => MemberPermissionsScreen(
                                      walletId: widget.walletId,
                                    ),
                                  ),
                                );
                              },
                            ),
                            if (_contactGroups.isNotEmpty)
                              ManagementTile(
                                title: 'Contact Permissions',
                                subtitle: 'Group-scoped access',
                                leadingIcon: Icons.lock,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ContactPermissionsScreen(
                                        walletId: widget.walletId,
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                        // ⚙️ WALLET SETTINGS
                        ManagementSectionCard(
                          title: 'WALLET SETTINGS',
                          icon: Icons.settings,
                          tiles: [
                            ManagementTile(
                              title: 'Wallet Permissions',
                              subtitle: 'Who can manage wallet',
                              leadingIcon: Icons.admin_panel_settings,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => WalletPermissionsScreen(
                                      walletId: widget.walletId,
                                    ),
                                  ),
                                );
                              },
                            ),
                            ManagementTile(
                              title: 'Rename Wallet',
                              leadingIcon: Icons.edit,
                              onTap: () {
                                _showRenameWalletDialog();
                              },
                            ),
                            ManagementTile(
                              title: 'Leave Wallet',
                              leadingIcon: Icons.exit_to_app,
                              onTap: () {
                                _showLeaveWalletDialog();
                              },
                            ),
                            ManagementTile(
                              title: 'Delete Wallet',
                              leadingIcon: Icons.delete,
                              onTap: () {
                                _showDeleteWalletDialog();
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
      ),
    );
  }
}
