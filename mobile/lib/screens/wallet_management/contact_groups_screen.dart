import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api.dart';
import '../../utils/toast_service.dart';
import '../../widgets/gradient_card.dart';
import '../../widgets/custom_expansion_tile.dart';

class ContactGroupsScreen extends ConsumerStatefulWidget {
  final String walletId;
  final List<Map<String, dynamic>> contactGroups;
  final VoidCallback onReload;

  const ContactGroupsScreen({
    super.key,
    required this.walletId,
    required this.contactGroups,
    required this.onReload,
  });

  @override
  ConsumerState<ContactGroupsScreen> createState() => _ContactGroupsScreenState();
}

class _ContactGroupsScreenState extends ConsumerState<ContactGroupsScreen> {
  late List<Map<String, dynamic>> _contactGroups;

  @override
  void initState() {
    super.initState();
    _contactGroups = List.from(widget.contactGroups);
  }

  @override
  void didUpdateWidget(ContactGroupsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _contactGroups = List.from(widget.contactGroups);
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
    final groups = _contactGroups.where((g) => g['name'] != 'all_contacts').toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contact Groups'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _createGroup,
            tooltip: 'Create new group',
          ),
        ],
      ),
      body: groups.isEmpty
          ? Center(
              child: Text(
                'No contact groups yet',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            )
          : ListView(
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
}

class _ContactGroupMembers extends StatefulWidget {
  final String walletId;
  final String groupId;
  final VoidCallback onReload;

  const _ContactGroupMembers({
    required this.walletId,
    required this.groupId,
    required this.onReload,
  });

  @override
  State<_ContactGroupMembers> createState() => _ContactGroupMembersState();
}

class _ContactGroupMembersState extends State<_ContactGroupMembers> {
  List<Map<String, dynamic>> _members = [];
  Map<String, Map<String, dynamic>> _contactById = {};
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
      final jsonStr = await Api.getContacts();
      final List<dynamic> contacts = jsonDecode(jsonStr);
      final Map<String, Map<String, dynamic>> byId = {};
      for (final c in contacts) {
        final map = c as Map<String, dynamic>;
        final id = map['id'] as String?;
        if (id != null) byId[id] = map;
      }
      if (mounted) setState(() {
        _members = list;
        _contactById = byId;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeMember(String contactId) async {
    try {
      await Api.removeWalletContactGroupMember(widget.walletId, widget.groupId, contactId);
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
    final memberIds = _members.map((m) => m['contact_id'] as String).toSet();
    final availableContacts = _contactById.entries
        .where((e) => !memberIds.contains(e.key))
        .map((e) => MapEntry(e.key, e.value))
        .toList();

    if (availableContacts.isEmpty) {
      if (mounted) {
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

    if (ok == true && selectedContactId != null && mounted) {
      try {
        await Api.addWalletContactGroupMember(widget.walletId, widget.groupId, selectedContactId!);
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
            title: const Text('Add contact'),
            onTap: _showAddMemberDialog,
          ),
          ..._members.map((m) {
            final contactId = m['contact_id'] as String? ?? '';
            final contact = _contactById[contactId];
            final name = contact?['name'] as String? ?? 'Unknown';
            final username = contact?['username'] as String?;
            final subtitle = username != null && username.isNotEmpty ? '@$username' : null;
            return ListTile(
              dense: true,
              title: Text(name),
              subtitle: subtitle != null ? Text(subtitle, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)) : null,
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
