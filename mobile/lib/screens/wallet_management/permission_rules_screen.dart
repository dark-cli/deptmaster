import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api.dart';
import '../../providers/wallet_management_provider.dart';
import '../../utils/toast_service.dart';
import '../../widgets/custom_expansion_tile.dart';
import '../../widgets/gradient_background.dart';
import '../../widgets/gradient_card.dart';
import 'permission_matrix.dart';

class PermissionRulesScreen extends ConsumerWidget {
  final String walletId;

  const PermissionRulesScreen({
    super.key,
    required this.walletId,
  });

  String _formatGroupName(String name) {
    if (name == '__owners__') return 'Owners (system)';
    if (name == 'all_users') return 'All Users (system)';
    if (name == 'all_contacts') return 'All Contacts (default)';
    return name;
  }

  Set<String> _actionsOf(
    List<Map<String, dynamic>> matrix,
    String userGroupId,
    String contactGroupId,
    String key,
  ) {
    for (final e in matrix) {
      if (e['user_group_id'] == userGroupId && e['contact_group_id'] == contactGroupId) {
        final list = (e[key] as List<dynamic>?)?.cast<String>() ?? <String>[];
        return Set<String>.from(list);
      }
    }
    return {};
  }

  Future<void> _save(
    BuildContext context,
    String ugId,
    String cgId,
    Set<String> allowed,
    Set<String> denied,
  ) async {
    final entry = {
      'user_group_id': ugId,
      'contact_group_id': cgId,
      'action_names': allowed.toList(),
      'allowed_actions': allowed.toList(),
      'denied_actions': denied.toList(),
    };
    try {
      await Api.putWalletPermissionMatrix(walletId, [entry]);
      if (context.mounted) {
        ToastService.showSuccessFromContext(context, 'Permissions saved');
      }
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

  void _openEditor(
    BuildContext context,
    String ugId,
    String ugName,
    String cgId,
    String cgName,
    Set<String> allowed,
    Set<String> denied,
  ) {
    showDialog(
      context: context,
      builder: (_) => PermissionActionsDialog(
        title: 'Edit Permissions',
        subtitle: '$ugName → $cgName',
        rows: contactAndTransactionRows,
        initialAllowed: allowed,
        initialDenied: denied,
        onSave: (a, d) => _save(context, ugId, cgId, a, d),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userGroupsAsync = ref.watch(userGroupsProvider(walletId));
    final contactGroupsAsync = ref.watch(contactGroupsProvider(walletId));
    final matrixAsync = ref.watch(walletPermissionMatrixProvider(walletId));

    // Keep showing the last-known data during refetch so open cards don't collapse.
    final userGroups = userGroupsAsync.valueOrNull;
    final contactGroups = contactGroupsAsync.valueOrNull;
    final matrix = matrixAsync.valueOrNull;

    if (userGroups == null || contactGroups == null || matrix == null) {
      if (userGroupsAsync.hasError || contactGroupsAsync.hasError || matrixAsync.hasError) {
        final err = userGroupsAsync.error ?? contactGroupsAsync.error ?? matrixAsync.error;
        return _scaffold(context, Center(child: Text(err.toString())));
      }
      return _scaffold(context, const Center(child: CircularProgressIndicator()));
    }

    final visibleUserGroups = userGroups.where((g) => g['is_hidden'] != true).toList();
    if (visibleUserGroups.isEmpty || contactGroups.isEmpty) {
      return _scaffold(
        context,
        const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Create at least one user group and one contact group to set rules.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return _scaffold(
      context,
      ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        children: [
          for (int index = 0; index < visibleUserGroups.length; index++)
            _buildUserGroupCard(
              context,
              index,
              visibleUserGroups[index],
              contactGroups,
              matrix,
            ),
        ],
      ),
    );
  }

  Widget _scaffold(BuildContext context, Widget body) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Permission Rules')),
        body: body,
      ),
    );
  }

  Widget _buildUserGroupCard(
    BuildContext context,
    int index,
    Map<String, dynamic> ug,
    List<Map<String, dynamic>> contactGroups,
    List<Map<String, dynamic>> matrix,
  ) {
    final ugId = ug['id'] as String? ?? '';
    final ugName = _formatGroupName(ug['name'] as String? ?? '');
    return GradientCard(
      key: ValueKey('user-group-$ugId'),
      margin: const EdgeInsets.only(bottom: 12),
      variationSeed: ugId.hashCode,
      child: CustomExpansionTile(
        key: PageStorageKey('rules-ug-$ugId'),
        title: Text(ugName, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('User Group'),
        initiallyExpanded: index == 0,
        children: [
          const Divider(height: 1),
          ...contactGroups.map((cg) {
            final cgId = cg['id'] as String? ?? '';
            final cgName = _formatGroupName(cg['name'] as String? ?? '');
            final allowed = _actionsOf(matrix, ugId, cgId, 'allowed_actions');
            final denied = _actionsOf(matrix, ugId, cgId, 'denied_actions');
            return ListTile(
              title: Text(cgName),
              subtitle: PermissionMatrixGrid(
                rows: contactAndTransactionRows,
                allowed: allowed,
                denied: denied,
                useTextRowLabels: true,
              ),
              trailing: const Icon(Icons.edit, size: 20),
              onTap: () => _openEditor(context, ugId, ugName, cgId, cgName, allowed, denied),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
