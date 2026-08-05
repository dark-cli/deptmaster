import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api.dart';
import '../../utils/toast_service.dart';
import '../../widgets/gradient_card.dart';
import '../../widgets/custom_expansion_tile.dart';

class ContactPermissionsScreen extends ConsumerStatefulWidget {
  final String walletId;

  const ContactPermissionsScreen({
    super.key,
    required this.walletId,
  });

  @override
  ConsumerState<ContactPermissionsScreen> createState() => _ContactPermissionsScreenState();
}

class _ContactPermissionsScreenState extends ConsumerState<ContactPermissionsScreen> {
  List<Map<String, dynamic>> _contactGroups = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final groups = await Api.getWalletContactGroups(widget.walletId);
      if (mounted) {
        setState(() {
          _contactGroups = groups.where((g) => g['name'] != 'all_contacts').toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
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
      return Scaffold(
        appBar: AppBar(title: const Text('Contact Permissions')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_contactGroups.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Contact Permissions')),
        body: Center(
          child: Text(
            'No contact groups available',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Contact Permissions')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: _contactGroups.map((group) {
          final groupId = group['id'] as String? ?? '';
          final groupName = group['name'] as String? ?? '';

          return GradientCard(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            variationSeed: groupId.hashCode,
            child: CustomExpansionTile(
              title: Text(groupName),
              subtitle: const Text('Delegable permissions'),
              children: [
                _ContactGroupPermissionsDetail(
                  walletId: widget.walletId,
                  contactGroupId: groupId,
                  groupName: groupName,
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ContactGroupPermissionsDetail extends StatefulWidget {
  final String walletId;
  final String contactGroupId;
  final String groupName;

  const _ContactGroupPermissionsDetail({
    required this.walletId,
    required this.contactGroupId,
    required this.groupName,
  });

  @override
  State<_ContactGroupPermissionsDetail> createState() => _ContactGroupPermissionsDetailState();
}

class _ContactGroupPermissionsDetailState extends State<_ContactGroupPermissionsDetail> {
  List<Map<String, dynamic>> _permissions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final perms = await Api.getContactGroupPermissions(widget.walletId, widget.contactGroupId);
      if (mounted) {
        setState(() {
          _permissions = perms;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ToastService.showErrorFromContext(
          context,
          e.toString().replaceFirst('Exception: ', ''),
        );
      }
    }
  }

  Future<void> _togglePermission(Map<String, dynamic> perm, String sourceGroup, String actionName) async {
    final isDeny = perm['is_deny'] as bool? ?? false;

    try {
      final newEntries = _permissions.map((p) {
        if (p['source_group_id'] == sourceGroup && p['action'] == actionName) {
          return {...p, 'is_deny': !isDeny};
        }
        return p;
      }).toList();

      await Api.setContactGroupPermissions(widget.walletId, widget.contactGroupId, newEntries);
      await _load();
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

    if (_permissions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No delegable permissions for this group',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _permissions.map((perm) {
          final sourceGroup = perm['source_group_id'] as String? ?? '';
          final action = perm['action'] as String? ?? '';
          final isDeny = perm['is_deny'] as bool? ?? false;

          return ListTile(
            dense: true,
            title: Text('$sourceGroup: $action'),
            trailing: Chip(
              label: Text(isDeny ? 'Deny' : 'Allow'),
              backgroundColor: isDeny ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary,
            ),
            onTap: () => _togglePermission(perm, sourceGroup, action),
          );
        }).toList(),
      ),
    );
  }
}
