import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api.dart';
import '../../utils/toast_service.dart';

class MemberPermissionsScreen extends ConsumerStatefulWidget {
  final String walletId;

  const MemberPermissionsScreen({
    super.key,
    required this.walletId,
  });

  @override
  ConsumerState<MemberPermissionsScreen> createState() => _MemberPermissionsScreenState();
}

class _MemberPermissionsScreenState extends ConsumerState<MemberPermissionsScreen> {
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
      final perms = await Api.getMemberPermissions(widget.walletId);
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

  Future<void> _togglePermission(Map<String, dynamic> perm, String sourceGroup, String targetGroup, String actionName) async {
    final isDeny = perm['is_deny'] as bool? ?? false;

    try {
      final newEntries = _permissions.map((p) {
        if (p['source_group_id'] == sourceGroup && p['target_group_id'] == targetGroup && p['action'] == actionName) {
          return {...p, 'is_deny': !isDeny};
        }
        return p;
      }).toList();

      await Api.setMemberPermissions(widget.walletId, newEntries);
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
      return Scaffold(
        appBar: AppBar(title: const Text('Member Permissions')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Member Permissions')),
      body: _permissions.isEmpty
          ? Center(
              child: Text(
                'No member permissions configured',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: _permissions.map((perm) {
                final sourceGroup = perm['source_group_id'] as String? ?? '';
                final targetGroup = perm['target_group_id'] as String? ?? '';
                final action = perm['action'] as String? ?? '';
                final isDeny = perm['is_deny'] as bool? ?? false;

                return ListTile(
                  title: Text('$sourceGroup → $targetGroup'),
                  subtitle: Text(action, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  trailing: Chip(
                    label: Text(isDeny ? 'Deny' : 'Allow'),
                    backgroundColor: isDeny ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary,
                  ),
                  onTap: () => _togglePermission(perm, sourceGroup, targetGroup, action),
                );
              }).toList(),
            ),
    );
  }
}
