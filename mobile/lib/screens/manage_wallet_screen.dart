// Wallet management with Android Settings-style navigation
// Sections: People & Access, Groups, Permissions, Wallet Settings

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart';
import '../providers/wallets_provider.dart';
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

  Future<void> _showRenameWalletDialog(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController(text: walletName);
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
    if (ok != true || !context.mounted) return;
    final newName = nameController.text.trim();
    if (newName.isEmpty || newName == walletName) return;
    try {
      await Api.updateWallet(walletId, name: newName);
      ref.invalidate(walletsProvider);
      if (context.mounted) {
        ToastService.showSuccessFromContext(context, 'Wallet renamed');
        // Pop back to the wallet list so the new name is picked up on the AppBar too.
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) {
        if (Api.isPermissionDeniedError(e)) {
          ToastService.showErrorFromContext(context, 'You don\'t have permission to rename this wallet.');
        } else {
          ToastService.showErrorFromContext(context, e.toString().replaceFirst('Exception: ', ''));
        }
      }
    }
  }

  Future<void> _showLeaveWalletDialog(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave wallet'),
        content: const Text('You will no longer have access to this wallet.'),
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
    if (confirm != true || !context.mounted) return;
    try {
      // Server-side: removes the user from the wallet.
      // Client-side: wipes local cache + clears current_wallet_id if this
      // was the selected wallet, so the picker doesn't try to load stale
      // data on the next open.
      await Api.leaveWallet(walletId);
      ref.invalidate(walletsProvider);
      if (context.mounted) {
        ToastService.showSuccessFromContext(context, 'Left wallet');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) {
        ToastService.showErrorFromContext(context, e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  Future<void> _showDeleteWalletDialog(BuildContext context, WidgetRef ref) async {
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
    if (confirm != true || !context.mounted) return;
    try {
      await Api.deleteWallet(walletId);
      ref.invalidate(walletsProvider);
      if (context.mounted) {
        ToastService.showSuccessFromContext(context, 'Wallet deleted');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) {
        if (Api.isPermissionDeniedError(e)) {
          ToastService.showErrorFromContext(context, 'Only the wallet owner can delete this wallet.');
        } else {
          ToastService.showErrorFromContext(context, e.toString().replaceFirst('Exception: ', ''));
        }
      }
    }
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
            data: (contactGroups) {
              // Server marks system groups (owners, all_users, all_contacts) with
              // is_hidden. Use it for both the visible list and the counts here.
              final visibleUserGroupCount =
                  userGroups.where((g) => g['is_hidden'] != true).length;
              final visibleContactGroupCount =
                  contactGroups.where((g) => g['is_hidden'] != true).length;
              return RefreshIndicator(
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
                        subtitle: '$visibleUserGroupCount group${visibleUserGroupCount == 1 ? '' : 's'}',
                        leadingIcon: Icons.group,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => UserGroupsScreen(
                                walletId: walletId,
                              ),
                            ),
                          );
                        },
                      ),
                      ManagementTile(
                        title: 'Contact Groups',
                        subtitle: '$visibleContactGroupCount group${visibleContactGroupCount == 1 ? '' : 's'}',
                        leadingIcon: Icons.contacts,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ContactGroupsScreen(
                                walletId: walletId,
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
                        onTap: () => _showRenameWalletDialog(context, ref),
                      ),
                      ManagementTile(
                        title: 'Leave Wallet',
                        leadingIcon: Icons.exit_to_app,
                        onTap: () => _showLeaveWalletDialog(context, ref),
                      ),
                      ManagementTile(
                        title: 'Delete Wallet',
                        leadingIcon: Icons.delete,
                        onTap: () => _showDeleteWalletDialog(context, ref),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
            },
          ),
        ),
      ),
    );
  }
}
