// Shared widgets for displaying and editing a permission matrix row.
// Extracted from permission_rules_screen.dart so member_permissions_screen
// and contact_permissions_screen can use the exact same UI.
//
// A "matrix cell" is a compact colored-letter grid (e.g. `C: r c w d`)
// showing which of a fixed set of actions are allowed / denied / unset.
// Tapping the cell opens an editor dialog with a Checkbox + Allow/Deny
// SegmentedButton per action, grouped by category.

import 'package:flutter/material.dart';

/// A single action within a matrix row: the short letter to display, the
/// full permission name, and a human label for tooltips.
class MatrixColumn {
  final String letter; // e.g. 'r', 'c', 'w', 'd', 'x', 'a', 'e'
  final String action; // e.g. 'contact:read', 'member_group:members_add'
  final String label; // e.g. 'read', 'create', 'add'

  const MatrixColumn({
    required this.letter,
    required this.action,
    required this.label,
  });
}

/// One row in the grid: a prefix letter (like 'C' or 'T') and the actions
/// that follow it.
class MatrixRowSpec {
  final String prefix; // e.g. 'C', 'T', 'M', 'CG'
  final String? categoryHeader; // section header shown in the dialog
  final List<MatrixColumn> columns;

  const MatrixRowSpec({
    required this.prefix,
    required this.columns,
    this.categoryHeader,
  });
}

// ─── Preset row specs ──────────────────────────────────────────────────────

/// Contact + Transaction actions used by PermissionRulesScreen.
const List<MatrixRowSpec> contactAndTransactionRows = [
  MatrixRowSpec(
    prefix: 'C',
    categoryHeader: 'Contacts',
    columns: [
      MatrixColumn(letter: 'r', action: 'contact:read', label: 'read'),
      MatrixColumn(letter: 'c', action: 'contact:create', label: 'create'),
      MatrixColumn(letter: 'w', action: 'contact:update', label: 'write'),
      MatrixColumn(letter: 'd', action: 'contact:delete', label: 'delete'),
    ],
  ),
  MatrixRowSpec(
    prefix: 'T',
    categoryHeader: 'Transactions',
    columns: [
      MatrixColumn(letter: 'r', action: 'transaction:read', label: 'read'),
      MatrixColumn(letter: 'c', action: 'transaction:create', label: 'create'),
      MatrixColumn(letter: 'w', action: 'transaction:update', label: 'write'),
      MatrixColumn(letter: 'd', action: 'transaction:delete', label: 'delete'),
      MatrixColumn(letter: 'x', action: 'transaction:close', label: 'close'),
    ],
  ),
];

/// member_group:* actions for the Member Permissions screen (single row).
const List<MatrixRowSpec> memberGroupRows = [
  MatrixRowSpec(
    prefix: 'M',
    categoryHeader: 'Member group management',
    columns: [
      MatrixColumn(letter: 'r', action: 'member_group:members_read', label: 'read'),
      MatrixColumn(letter: 'a', action: 'member_group:members_add', label: 'add'),
      MatrixColumn(letter: 'x', action: 'member_group:members_remove', label: 'remove'),
      MatrixColumn(letter: 'e', action: 'member_group:permissions_edit', label: 'edit permissions'),
    ],
  ),
];

/// contact_group:* actions for the Contact Permissions screen (single row).
const List<MatrixRowSpec> contactGroupRows = [
  MatrixRowSpec(
    prefix: 'C',
    categoryHeader: 'Contact group management',
    columns: [
      MatrixColumn(letter: 'r', action: 'contact_group:contacts_read', label: 'read'),
      MatrixColumn(letter: 'a', action: 'contact_group:contacts_add', label: 'add'),
      MatrixColumn(letter: 'x', action: 'contact_group:contacts_remove', label: 'remove'),
      MatrixColumn(letter: 'e', action: 'contact_group:permissions_edit', label: 'edit permissions'),
    ],
  ),
];

// ─── Widgets ───────────────────────────────────────────────────────────────

/// Compact matrix display: one Row per [MatrixRowSpec], with a prefix cell
/// and one letter cell per column. Cells are green if action is in [allowed],
/// red if in [denied], gray '-' if neither.
class PermissionMatrixGrid extends StatelessWidget {
  final List<MatrixRowSpec> rows;
  final Set<String> allowed;
  final Set<String> denied;

  const PermissionMatrixGrid({
    super.key,
    required this.rows,
    required this.allowed,
    required this.denied,
  });

  @override
  Widget build(BuildContext context) {
    const greenColor = Color(0xFF2E7D32);
    final redColor = Theme.of(context).colorScheme.error;
    final grayColor = Theme.of(context).colorScheme.onSurfaceVariant;

    // Pad all rows to the same length for a uniform grid.
    final maxCols = rows.map((r) => r.columns.length).fold<int>(0, (a, b) => a > b ? a : b);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: rows.map((row) {
          final padCells = maxCols - row.columns.length;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _cell(context, row.prefix, '', '', greenColor, redColor, grayColor),
              ...row.columns.map((c) => _cell(
                    context,
                    c.letter,
                    c.action,
                    c.label,
                    greenColor,
                    redColor,
                    grayColor,
                  )),
              // Blank filler cells so shorter rows line up with longer ones.
              for (int i = 0; i < padCells; i++) _blankCell(context),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _cell(
    BuildContext context,
    String letter,
    String permission,
    String label,
    Color allowColor,
    Color denyColor,
    Color unsetColor,
  ) {
    final String display;
    final Color textColor;
    final String state;

    if (permission.isEmpty) {
      display = letter;
      textColor = Theme.of(context).colorScheme.onSurface;
      state = '';
    } else if (denied.contains(permission)) {
      display = letter;
      textColor = denyColor;
      state = 'denied';
    } else if (allowed.contains(permission)) {
      display = letter;
      textColor = allowColor;
      state = 'allowed';
    } else {
      display = '-';
      textColor = unsetColor;
      state = 'unset';
    }

    final cell = SizedBox(
      width: 35,
      height: 35,
      child: Center(
        child: Text(
          display,
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

    return Container(
      width: 35,
      height: 35,
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 1),
      ),
      child: permission.isEmpty
          ? cell
          : Tooltip(message: '$label: $state', child: cell),
    );
  }

  Widget _blankCell(BuildContext context) => Container(
        width: 35,
        height: 35,
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 1),
        ),
      );
}

enum _EditState { allow, deny }

/// Editor dialog: Checkbox + Allow/Deny SegmentedButton for each action.
/// Actions are grouped by [MatrixRowSpec.categoryHeader] and rendered in
/// order. Calls [onSave] with the new (allowed, denied) sets.
class PermissionActionsDialog extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<MatrixRowSpec> rows;
  final Set<String> initialAllowed;
  final Set<String> initialDenied;
  final void Function(Set<String> allowed, Set<String> denied) onSave;

  const PermissionActionsDialog({
    super.key,
    required this.title,
    required this.subtitle,
    required this.rows,
    required this.initialAllowed,
    required this.initialDenied,
    required this.onSave,
  });

  @override
  State<PermissionActionsDialog> createState() => _PermissionActionsDialogState();
}

class _PermissionActionsDialogState extends State<PermissionActionsDialog> {
  late Set<String> _allowed;
  late Set<String> _denied;

  @override
  void initState() {
    super.initState();
    _allowed = Set.from(widget.initialAllowed);
    _denied = Set.from(widget.initialDenied);
  }

  bool _isActive(String action) => _allowed.contains(action) || _denied.contains(action);

  _EditState _allowDeny(String action) =>
      _denied.contains(action) ? _EditState.deny : _EditState.allow;

  void _set(String action, _EditState? state) {
    setState(() {
      _allowed.remove(action);
      _denied.remove(action);
      if (state == _EditState.allow) {
        _allowed.add(action);
      } else if (state == _EditState.deny) {
        _denied.add(action);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final anyActions = widget.rows.any((r) => r.columns.isNotEmpty);

    if (!anyActions) {
      return AlertDialog(
        title: Text(widget.title),
        content: const Text('No permission actions available.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      );
    }

    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: (screenWidth < 400) ? 8.0 : 40.0,
        vertical: 24,
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.title),
          const SizedBox(height: 4),
          Text(
            widget.subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
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
              for (int r = 0; r < widget.rows.length; r++) ...[
                if (r > 0) const Divider(height: 24),
                if (widget.rows[r].categoryHeader != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      widget.rows[r].categoryHeader!,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                ...widget.rows[r].columns.map((col) {
                  final active = _isActive(col.action);
                  final allowDeny = _allowDeny(col.action);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Checkbox(
                              value: active,
                              onChanged: (checked) {
                                _set(col.action, checked == true ? _EditState.allow : null);
                              },
                            ),
                            Expanded(child: Text(col.label)),
                          ],
                        ),
                        if (active) ...[
                          const SizedBox(height: 6),
                          LayoutBuilder(builder: (context, constraints) {
                            final narrow = constraints.maxWidth < 280;
                            return SegmentedButton<_EditState>(
                              style: narrow
                                  ? const ButtonStyle(
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      padding: WidgetStatePropertyAll(
                                          EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
                                    )
                                  : null,
                              showSelectedIcon: false,
                              segments: const [
                                ButtonSegment(
                                    value: _EditState.allow,
                                    icon: Icon(Icons.check, size: 16),
                                    label: Text('Allow')),
                                ButtonSegment(
                                    value: _EditState.deny,
                                    icon: Icon(Icons.block, size: 16),
                                    label: Text('Deny')),
                              ],
                              selected: {allowDeny},
                              onSelectionChanged: (s) => _set(col.action, s.first),
                            );
                          }),
                        ],
                      ],
                    ),
                  );
                }),
              ],
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
            widget.onSave(_allowed, _denied);
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
