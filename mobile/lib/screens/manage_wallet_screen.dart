// Wallet management with Android Settings-style navigation
// Sections: People & Access, Groups, Permissions, Wallet Settings

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart';
import '../utils/toast_service.dart';
import '../widgets/gradient_background.dart';
import '../widgets/management_section_card.dart';
import '../providers/wallet_management_provider.dart';
import 'wallet_management/members_screen.dart';
import 'wallet_management/user_groups_screen.dart';
import 'wallet_management/contact_groups_screen.dart';
import 'wallet_management/permission_rules_screen.dart';
import 'wallet_management/wallet_permissions_screen.dart';
import 'wallet_management/member_permissions_screen.dart';
import 'wallet_management/contact_permissions_screen.dart';
import '../widgets/invite_code_dialog.dart';

class ManageWalletScreen extends ConsumerWidget {
  final String walletId;
  final String walletName;

  const ManageWalletScreen({
    super.key,
    required this.walletId,
    required this.walletName,
  });

  void _showRenameWalletDialog(BuildContext context) {
    final nameController = TextEditingController(text: walletName);
    showDialog<bool>(
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
    ToastService.showInfoFromContext(context, 'Rename wallet (coming soon - API not yet available)');
  }

  void _showLeaveWalletDialog(BuildContext context) {
    showDialog<bool>(
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
    ToastService.showInfoFromContext(context, 'Leave wallet (coming soon - API not yet available)');
  }

  void _showDeleteWalletDialog(BuildContext context) {
    showDialog<bool>(
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
    ToastService.showInfoFromContext(context, 'Delete wallet (coming soon - API not yet available)');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userGroupsAsync = ref.watch(userGroupsProvider(walletId));
    final contactGroupsAsync = ref.watch(contactGroupsProvider(walletId));

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text('Manage: $walletName'),
        ),
        body: userGroupsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, st) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(err.toString(), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => refreshWalletManagement(ref, walletId),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
          data: (userGroups) => contactGroupsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, st) => Center(child: Text(err.toString())),
            data: (contactGroups) => RefreshIndicator(
              onRefresh: () async => refreshWalletManagement(ref, walletId),
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
                        subtitle: 'Manage members',
                        leadingIcon: Icons.person,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => MembersScreen(
                                walletId: walletId,
                                users: const [],
                                onReload: () => refreshWalletManagement(ref, walletId),
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
                            builder: (context) => InviteCodeDialog(walletId: walletId),
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
                        subtitle: '${userGroups.length} group${userGroups.length == 1 ? '' : 's'}',
                        leadingIcon: Icons.group,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => UserGroupsScreen(
                                walletId: walletId,
                                userGroups: userGroups.where((g) {
                                  final name = g['name'] as String? ?? '';
                                  return name != '__owners__' && name != 'all_users';
                                }).toList(),
                                users: const [],
                                onReload: () => refreshWalletManagement(ref, walletId),
                              ),
                            ),
                          );
                        },
                      ),
                      ManagementTile(
                        title: 'Contact Groups',
                        subtitle: '${contactGroups.length} group${contactGroups.length == 1 ? '' : 's'}',
                        leadingIcon: Icons.contacts,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ContactGroupsScreen(
                                walletId: walletId,
                                contactGroups: contactGroups,
                                onReload: () => refreshWalletManagement(ref, walletId),
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
                                walletId: walletId,
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
                                walletId: walletId,
                              ),
                            ),
                          );
                        },
                      ),
                      if (contactGroups.isNotEmpty)
                        ManagementTile(
                          title: 'Contact Permissions',
                          subtitle: 'Group-scoped access',
                          leadingIcon: Icons.lock,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ContactPermissionsScreen(
                                  walletId: walletId,
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
                                walletId: walletId,
                              ),
                            ),
                          );
                        },
                      ),
                      ManagementTile(
                        title: 'Rename Wallet',
                        leadingIcon: Icons.edit,
                        onTap: () {
                          _showRenameWalletDialog(context);
                        },
                      ),
                      ManagementTile(
                        title: 'Leave Wallet',
                        leadingIcon: Icons.exit_to_app,
                        onTap: () {
                          _showLeaveWalletDialog(context);
                        },
                      ),
                      ManagementTile(
                        title: 'Delete Wallet',
                        leadingIcon: Icons.delete,
                        onTap: () {
                          _showDeleteWalletDialog(context);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
