import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api.dart';
import '../../utils/toast_service.dart';
import '../../widgets/gradient_card.dart';
import '../../widgets/custom_expansion_tile.dart';

class PermissionRulesScreen extends ConsumerStatefulWidget {
  final String walletId;

  const PermissionRulesScreen({
    super.key,
    required this.walletId,
  });

  @override
  ConsumerState<PermissionRulesScreen> createState() => _PermissionRulesScreenState();
}

class _PermissionRulesScreenState extends ConsumerState<PermissionRulesScreen> {
  List<Map<String, dynamic>> _userGroups = [];
  List<Map<String, dynamic>> _contactGroups = [];
  List<Map<String, dynamic>> _permissionActions = [];
  List<Map<String, dynamic>> _matrix = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        Api.getWalletUserGroups(widget.walletId),
        Api.getWalletContactGroups(widget.walletId),
        Api.getWalletPermissionActions(widget.walletId),
        Api.getWalletPermissionMatrix(widget.walletId),
      ]);

      if (mounted) {
        setState(() {
          _userGroups = results[0] as List<Map<String, dynamic>>;
          _contactGroups = results[1] as List<Map<String, dynamic>>;
          _permissionActions = results[2] as List<Map<String, dynamic>>;
          _matrix = results[3] as List<Map<String, dynamic>>;
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

  Future<void> _savePermissions(
    String userGroupId,
    String contactGroupId,
    List<String> allowedActions,
    List<String> deniedActions,
  ) async {
    final entry = {
      'user_group_id': userGroupId,
      'contact_group_id': contactGroupId,
      'action_names': allowedActions,
      'allowed_actions': allowedActions,
      'denied_actions': deniedActions,
    };

    try {
      await Api.putWalletPermissionMatrix(widget.walletId, [entry]);
      await _load();
      if (mounted) {
        ToastService.showSuccessFromContext(context, 'Permissions saved');
      }
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

  Set<String> _getActions(String userGroupId, String contactGroupId) {
    for (final e in _matrix) {
      if (e['user_group_id'] == userGroupId && e['contact_group_id'] == contactGroupId) {
        final allowed = (e['allowed_actions'] as List<dynamic>?)?.cast<String>() ?? <String>[];
        return Set<String>.from(allowed);
      }
    }
    return {};
  }

  Set<String> _getDenied(String userGroupId, String contactGroupId) {
    for (final e in _matrix) {
      if (e['user_group_id'] == userGroupId && e['contact_group_id'] == contactGroupId) {
        final denied = (e['denied_actions'] as List<dynamic>?)?.cast<String>() ?? <String>[];
        return Set<String>.from(denied);
      }
    }
    return {};
  }

  void _openEditor(String ugId, String ugName, String cgId, String cgName) {
    showDialog(
      context: context,
      builder: (context) => _PermissionsDialog(
        userGroupName: ugName,
        contactGroupName: cgName,
        availableActions: _permissionActions,
        initialAllowed: _getActions(ugId, cgId).toList(),
        initialDenied: _getDenied(ugId, cgId).toList(),
        onSave: (allowed, denied) => _savePermissions(ugId, cgId, allowed, denied),
      ),
    );
  }

  String _formatGroupName(String name) {
    if (name == '__owners__') return 'Owners (system)';
    if (name == 'all_users') return 'All Users (system)';
    if (name == 'all_contacts') return 'All Contacts (default)';
    return name;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Permission Rules')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_userGroups.isEmpty || _contactGroups.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Permission Rules')),
        body: const Center(
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

    return Scaffold(
      appBar: AppBar(title: const Text('Permission Rules')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        children: [
          ...List.generate(_userGroups.length, (index) {
            final ug = _userGroups[index];
            final ugId = ug['id'] as String? ?? '';
            final rawUgName = ug['name'] as String? ?? '';
            final ugName = _formatGroupName(rawUgName);

            return GradientCard(
              margin: const EdgeInsets.only(bottom: 12),
              variationSeed: ugId.hashCode,
              child: CustomExpansionTile(
                title: Text(ugName, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('User Group'),
                initiallyExpanded: index == 0,
                children: [
                  const Divider(height: 1),
                  ..._contactGroups.map((cg) {
                    final cgId = cg['id'] as String? ?? '';
                    final rawCgName = cg['name'] as String? ?? '';
                    final cgName = _formatGroupName(rawCgName);
                    final activeActions = _getActions(ugId, cgId);
                    final deniedActions = _getDenied(ugId, cgId);

                    return ListTile(
                      title: Text(cgName),
                      subtitle: _PermissionGridDisplay(
                        allowed: activeActions,
                        denied: deniedActions,
                      ),
                      trailing: const Icon(Icons.edit, size: 20),
                      onTap: () => _openEditor(ugId, ugName, cgId, cgName),
                    );
                  }).toList(),
                  const SizedBox(height: 8),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

enum _PermissionState { allow, deny, unset }

/// Display permissions as colored letters using rwx-inspired format
/// C: r:a c:- w:a d:-, T: r:a c:- w:- d:- x:-
/// Green=allow, Red=deny, Gray=unset
class _PermissionGridDisplay extends StatelessWidget {
  final Set<String> allowed;
  final Set<String> denied;

  const _PermissionGridDisplay({
    required this.allowed,
    required this.denied,
  });

  @override
  Widget build(BuildContext context) {
    const greenColor = Color(0xFF2E7D32);
    final redColor = Theme.of(context).colorScheme.error;
    final grayColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Contact row
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildGridCell(context, 'C', '', '', greenColor, redColor, grayColor, true),
              _buildGridCell(context, 'r', 'contact:read', 'read', greenColor, redColor, grayColor, false),
              _buildGridCell(context, 'c', 'contact:create', 'create', greenColor, redColor, grayColor, false),
              _buildGridCell(context, 'w', 'contact:update', 'write', greenColor, redColor, grayColor, false),
              _buildGridCell(context, 'd', 'contact:delete', 'delete', greenColor, redColor, grayColor, false),
              SizedBox(
                width: 35,
                height: 35,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 1),
                  ),
                ),
              ),
            ],
          ),
          // Transaction row
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildGridCell(context, 'T', '', '', greenColor, redColor, grayColor, true),
              _buildGridCell(context, 'r', 'transaction:read', 'read', greenColor, redColor, grayColor, false),
              _buildGridCell(context, 'c', 'transaction:create', 'create', greenColor, redColor, grayColor, false),
              _buildGridCell(context, 'w', 'transaction:update', 'write', greenColor, redColor, grayColor, false),
              _buildGridCell(context, 'd', 'transaction:delete', 'delete', greenColor, redColor, grayColor, false),
              _buildGridCell(context, 'x', 'transaction:close', 'close', greenColor, redColor, grayColor, false),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGridCell(
    BuildContext context,
    String letter,
    String permission,
    String label,
    Color allowColor,
    Color denyColor,
    Color unsetColor,
    bool isFirstColumn,
  ) {
    late final String displayLetter;
    late final Color textColor;
    late final String state;

    // For C and T labels (permission is empty)
    if (permission.isEmpty) {
      displayLetter = letter;
      textColor = Theme.of(context).colorScheme.onSurface;
      state = '';
    } else if (denied.contains(permission)) {
      displayLetter = letter;
      textColor = denyColor;
      state = 'denied';
    } else if (allowed.contains(permission)) {
      displayLetter = letter;
      textColor = allowColor;
      state = 'allowed';
    } else {
      displayLetter = '-';
      textColor = unsetColor;
      state = 'unset';
    }

    final cell = SizedBox(
      width: 35,
      height: 35,
      child: Center(
        child: Text(
          displayLetter,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: textColor,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );

    // Add border and optional tooltip
    return Container(
      width: 35,
      height: 35,
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      child: permission.isEmpty
          ? cell
          : Tooltip(
              message: '$label: $state',
              child: cell,
            ),
    );
  }
}

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

  void _setState(String name, _PermissionState state) {
    setState(() {
      _allowed.remove(name);
      _denied.remove(name);
      if (state == _PermissionState.allow) {
        _allowed.add(name);
      } else if (state == _PermissionState.deny) {
        _denied.add(name);
      }
    });
  }

  void _groupActions() {
    _groupedActions = {};
    final contactTransactionActions = widget.availableActions.where((a) {
      final name = a['name'] as String? ?? '';
      return name.startsWith('contact:') || name.startsWith('transaction:');
    }).toList();

    for (final action in contactTransactionActions) {
      final name = action['name'] as String? ?? '';
      final parts = name.split(':');
      final category = parts.isNotEmpty ? parts[0] : 'other';

      if (!_groupedActions.containsKey(category)) {
        _groupedActions[category] = [];
      }
      _groupedActions[category]!.add(action);
    }

    for (final category in _groupedActions.keys) {
      _groupedActions[category]!.sort((a, b) {
        final aName = a['name'] as String? ?? '';
        final bName = b['name'] as String? ?? '';
        return _getPermissionSortOrder(aName).compareTo(_getPermissionSortOrder(bName));
      });
    }
  }

  int _getPermissionSortOrder(String actionName) {
    if (actionName.contains(':read')) return 0;
    if (actionName.contains(':create')) return 1;
    if (actionName.contains(':update')) return 2;
    if (actionName.contains(':delete')) return 3;
    if (actionName.contains(':close')) return 4;
    return 99;
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
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'rwx format: r=read, c=create, w=write, d=delete, x=close',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              ListView.builder(
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
                        child: Text(
                          category == 'contact' ? 'Contacts' : 'Transactions',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      ...actions.map((action) {
                        final name = action['name'] as String? ?? '';
                        final isActive = _isActive(name);
                        final state = _getAllowDeny(name);

                        return ListTile(
                          dense: true,
                          title: Text(name.split(':').last),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  Icons.check_circle,
                                  color: state == _PermissionState.allow ? const Color(0xFF2E7D32) : Colors.grey,
                                  size: 24,
                                ),
                                onPressed: () => _setState(name, _PermissionState.allow),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.cancel,
                                  color: state == _PermissionState.deny ? Theme.of(context).colorScheme.error : Colors.grey,
                                  size: 24,
                                ),
                                onPressed: () => _setState(name, _PermissionState.deny),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.remove_circle_outline,
                                  color: !isActive ? Colors.grey : Colors.grey,
                                  size: 24,
                                ),
                                onPressed: () => _setState(name, _PermissionState.unset),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  );
                },
              ),
            ],
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
