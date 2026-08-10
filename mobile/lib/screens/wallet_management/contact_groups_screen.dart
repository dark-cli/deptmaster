import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api.dart';
import '../../providers/contacts_provider.dart';
import '../../providers/wallet_management_provider.dart';
import '../../utils/toast_service.dart';
import '../../widgets/gradient_card.dart';
import '../../widgets/custom_expansion_tile.dart';
import '../../widgets/gradient_background.dart';

class ContactGroupsScreen extends ConsumerStatefulWidget {
  final String walletId;

  const ContactGroupsScreen({
    super.key,
    required this.walletId,
  });

  @override
  ConsumerState<ContactGroupsScreen> createState() => _ContactGroupsScreenState();
}

class _ContactGroupsScreenState extends ConsumerState<ContactGroupsScreen> {
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
      await Api.deleteWalletContactGroup(widget.walletId, groupId);
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
    final contactGroupsAsync = ref.watch(contactGroupsProvider(widget.walletId));
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Contact Groups'),
        ),
        floatingActionButton: Padding(
          padding: const EdgeInsets.only(bottom: 24.0),
          child: FloatingActionButton(
            onPressed: _createGroup,
            tooltip: 'Create new group',
            child: const Icon(Icons.add),
          ),
        ),
        body: contactGroupsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text(err.toString())),
          data: (allGroups) {
            final groups = allGroups.where((g) => g['is_hidden'] != true).toList();
            if (groups.isEmpty) {
              return Center(
                child: Text(
                  'No contact groups yet',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              children: [
                ...groups.map((g) {
                  final groupId = g['id'] as String? ?? '';
                  return GradientCard(
                    margin: const EdgeInsets.only(bottom: 8),
                    variationSeed: groupId.hashCode,
                    child: CustomExpansionTile(
                      title: Text(g['name'] as String? ?? ''),
                      subtitle: const Text('Static'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteGroup(g),
                      ),
                      children: [
                        _ContactGroupMembers(
                          walletId: widget.walletId,
                          groupId: groupId,
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
}

class _ContactGroupMembers extends ConsumerWidget {
  final String walletId;
  final String groupId;

  const _ContactGroupMembers({
    required this.walletId,
    required this.groupId,
  });

  Future<void> _removeMember(BuildContext context, String contactId) async {
    try {
      await Api.removeWalletContactGroupMember(walletId, groupId, contactId);
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
    Map<String, Map<String, dynamic>> contactById,
  ) async {
    final memberIds = members.map((m) => m['contact_id'] as String).toSet();
    final availableContacts = contactById.entries
        .where((e) => !memberIds.contains(e.key))
        .map((e) => MapEntry(e.key, e.value))
        .toList();

    if (availableContacts.isEmpty) {
      if (context.mounted) {
        ToastService.showInfoFromContext(context, 'All contacts are already in this group.');
      }
      return;
    }

    String? selectedContactId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add contact'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: availableContacts.length,
            itemBuilder: (context, index) {
              final contactId = availableContacts[index].key;
              final contact = availableContacts[index].value;
              final name = contact['name'] as String? ?? 'Unknown';
              final username = contact['username'] as String?;
              final subtitle = username != null && username.isNotEmpty ? '@$username' : null;

              return RadioListTile<String>(
                value: contactId,
                groupValue: selectedContactId,
                onChanged: (value) {
                  selectedContactId = value;
                  Navigator.pop(ctx, true);
                },
                title: Text(name),
                subtitle: subtitle != null ? Text(subtitle) : null,
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

    if (ok == true && selectedContactId != null && context.mounted) {
      try {
        await Api.addWalletContactGroupMember(walletId, groupId, selectedContactId!);
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
    final membersAsync = ref.watch(contactGroupMembersProvider(WalletGroupKey(walletId, groupId)));
    final contactsAsync = ref.watch(contactsProvider);
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
        final contactById = <String, Map<String, dynamic>>{};
        for (final c in contactsAsync.value ?? const []) {
          contactById[c.id] = {
            'id': c.id,
            'name': c.name,
            'username': c.username,
          };
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
                onTap: () => _showAddMemberDialog(context, members, contactById),
              ),
              ...members.map((m) {
                final contactId = m['contact_id'] as String? ?? '';
                final contact = contactById[contactId];
                final name = contact?['name'] as String? ?? 'Unknown';
                final username = contact?['username'] as String?;
                final subtitle = username != null && username.isNotEmpty ? '@$username' : null;
                return ListTile(
                  dense: true,
                  title: Text(name),
                  subtitle: subtitle != null
                      ? Text(subtitle, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))
                      : null,
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                    onPressed: () => _removeMember(context, contactId),
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
