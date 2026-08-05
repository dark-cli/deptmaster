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

    if (permission.isEmpty) {
      displayLetter = letter;
      textColor = Colors.black87;
    } else {
      if (allowed.contains(permission)) {
        displayLetter = letter;
        textColor = allowColor;
      } else if (denied.contains(permission)) {
        displayLetter = letter;
        textColor = denyColor;
      } else {
        displayLetter = '-';
        textColor = unsetColor;
      }
    }

    return SizedBox(
      width: 35,
      height: 35,
      child: Container(
        decoration: BoxDecoration(
          color: isFirstColumn ? Theme.of(context).colorScheme.surface : null,
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 1),
        ),
        child: Center(
          child: Tooltip(
            message: label.isEmpty ? letter : label,
            child: Text(
              displayLetter,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: textColor,
                fontSize: 13,
              ),
            ),
          ),
        ),
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
  final Function(List<String>, List<String>) onSave;

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
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _allowed = Set<String>.from(widget.initialAllowed);
    _denied = Set<String>.from(widget.initialDenied);
  }

  void _toggle(String action) {
    setState(() {
      if (_allowed.contains(action)) {
        _allowed.remove(action);
      } else if (_denied.contains(action)) {
        _denied.remove(action);
      } else {
        _allowed.add(action);
      }
    });
  }

  void _setAllow(String action) {
    setState(() {
      _allowed.add(action);
      _denied.remove(action);
    });
  }

  void _setDeny(String action) {
    setState(() {
      _denied.add(action);
      _allowed.remove(action);
    });
  }

  void _unset(String action) {
    setState(() {
      _allowed.remove(action);
      _denied.remove(action);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.userGroupName} → ${widget.contactGroupName}'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: widget.availableActions.map((action) {
            final actionName = action['name'] as String? ?? '';
            final isAllowed = _allowed.contains(actionName);
            final isDenied = _denied.contains(actionName);

            return ListTile(
              dense: true,
              title: Text(actionName),
              trailing: PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'allow') {
                    _setAllow(actionName);
                  } else if (value == 'deny') {
                    _setDeny(actionName);
                  } else if (value == 'unset') {
                    _unset(actionName);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'allow',
                    child: Text('Allow', style: TextStyle(color: const Color(0xFF2E7D32))),
                  ),
                  PopupMenuItem(
                    value: 'deny',
                    child: Text('Deny', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                  PopupMenuItem(
                    value: 'unset',
                    child: const Text('Unset'),
                  ),
                ],
                child: Chip(
                  label: Text(isAllowed ? 'Allow' : (isDenied ? 'Deny' : 'Unset')),
                  backgroundColor: isAllowed
                      ? const Color(0xFF2E7D32)
                      : (isDenied ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.surfaceVariant),
                  labelStyle: TextStyle(
                    color: isAllowed || isDenied ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving
              ? null
              : () async {
                  setState(() => _saving = true);
                  widget.onSave(_allowed.toList(), _denied.toList());
                  if (mounted) Navigator.pop(context);
                },
          child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
        ),
      ],
    );
  }
}
