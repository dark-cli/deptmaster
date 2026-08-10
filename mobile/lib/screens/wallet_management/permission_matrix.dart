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
/// full permission name, a human label, and a one-line description of what
/// granting the permission actually lets the user do (shown as a hint in
/// the editor dialog and inside the grid cell tooltip).
class MatrixColumn {
  final String letter; // e.g. 'r', 'c', 'w', 'd', 'x', 'a', 'e'
  final String action; // e.g. 'contact:read', 'member_group:members_add'
  final String label; // e.g. 'read', 'create', 'add'
  final String description; // e.g. 'See contacts in this wallet.'

  const MatrixColumn({
    required this.letter,
    required this.action,
    required this.label,
    required this.description,
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
///
/// The two rows are just visual categories (contact-related vs transaction-
/// related actions) — NOT a target axis. Render with `useTextRowLabels: true`
/// so each row shows its full name instead of a matrix-implying letter.
const List<MatrixRowSpec> contactAndTransactionRows = [
  MatrixRowSpec(
    prefix: 'C',
    categoryHeader: 'Contact',
    columns: [
      MatrixColumn(
        letter: 'r',
        action: 'contact:read',
        label: 'read',
        description: 'See contacts belonging to the selected contact group.',
      ),
      MatrixColumn(
        letter: 'c',
        action: 'contact:create',
        label: 'create',
        description: 'Add new contacts into the selected contact group.',
      ),
      MatrixColumn(
        letter: 'w',
        action: 'contact:update',
        label: 'write',
        description: 'Edit a contact\'s name, phone, notes, etc.',
      ),
      MatrixColumn(
        letter: 'd',
        action: 'contact:delete',
        label: 'delete',
        description: 'Permanently remove contacts (also deletes their history).',
      ),
    ],
  ),
  MatrixRowSpec(
    prefix: 'T',
    categoryHeader: 'Transaction',
    columns: [
      MatrixColumn(
        letter: 'r',
        action: 'transaction:read',
        label: 'read',
        description: 'See transactions for these contacts and their balances.',
      ),
      MatrixColumn(
        letter: 'c',
        action: 'transaction:create',
        label: 'create',
        description: 'Add new debts, payments and other transactions.',
      ),
      MatrixColumn(
        letter: 'w',
        action: 'transaction:update',
        label: 'write',
        description: 'Edit existing transactions (amount, date, notes).',
      ),
      MatrixColumn(
        letter: 'd',
        action: 'transaction:delete',
        label: 'delete',
        description: 'Permanently remove transactions from history.',
      ),
      MatrixColumn(
        letter: 'x',
        action: 'transaction:close',
        label: 'close',
        description: 'Mark a transaction as settled / paid off.',
      ),
    ],
  ),
];

/// member_group:* actions for the Member Permissions screen (single row).
const List<MatrixRowSpec> memberGroupRows = [
  MatrixRowSpec(
    prefix: 'M',
    categoryHeader: 'Member group management',
    columns: [
      MatrixColumn(
        letter: 'r',
        action: 'member_group:members_read',
        label: 'read',
        description: 'See who belongs to the target user group.',
      ),
      MatrixColumn(
        letter: 'a',
        action: 'member_group:members_add',
        label: 'add',
        description: 'Add wallet members to the target user group.',
      ),
      MatrixColumn(
        letter: 'x',
        action: 'member_group:members_remove',
        label: 'remove',
        description: 'Remove members from the target user group.',
      ),
      MatrixColumn(
        letter: 'e',
        action: 'member_group:permissions_edit',
        label: 'edit permissions',
        description: 'Change what the target user group is allowed to do.',
      ),
    ],
  ),
];

/// wallet:* actions for the Wallet Permissions screen.
///
/// Layer 1 permissions are a **single vector per user group** — the rows
/// here are just visual categories, NOT a target axis. Render with
/// `useTextRowLabels: true` on [PermissionMatrixGrid] so each row shows its
/// category name (e.g. 'Wallet', 'Members') instead of a matrix-implying
/// letter prefix.
const List<MatrixRowSpec> walletPermissionRows = [
  MatrixRowSpec(
    prefix: 'W',
    categoryHeader: 'Wallet',
    columns: [
      MatrixColumn(
        letter: 'r',
        action: 'wallet:info_read',
        label: 'info read',
        description: 'See the wallet\'s name and settings.',
      ),
      MatrixColumn(
        letter: 'w',
        action: 'wallet:info_update',
        label: 'info update',
        description: 'Rename the wallet and edit its settings.',
      ),
      MatrixColumn(
        letter: '!',
        action: 'wallet:delete',
        label: 'delete wallet',
        description: 'Permanently delete the entire wallet.',
      ),
      MatrixColumn(
        letter: 't',
        action: 'wallet:owner_transfer',
        label: 'transfer ownership',
        description: 'Hand wallet ownership to another user.',
      ),
    ],
  ),
  MatrixRowSpec(
    prefix: 'M',
    categoryHeader: 'Members',
    columns: [
      MatrixColumn(
        letter: 'r',
        action: 'wallet:members_read',
        label: 'read',
        description: 'See who is a member of the wallet.',
      ),
      MatrixColumn(
        letter: 'a',
        action: 'wallet:members_add',
        label: 'add',
        description: 'Invite new users into the wallet.',
      ),
      MatrixColumn(
        letter: 'x',
        action: 'wallet:members_remove',
        label: 'remove',
        description: 'Kick users out of the wallet.',
      ),
    ],
  ),
  MatrixRowSpec(
    prefix: 'G',
    categoryHeader: 'Member Groups',
    columns: [
      MatrixColumn(
        letter: 'c',
        action: 'wallet:groups_create',
        label: 'create',
        description: 'Create new user groups.',
      ),
      MatrixColumn(
        letter: 'u',
        action: 'wallet:groups_update',
        label: 'update',
        description: 'Rename existing user groups.',
      ),
      MatrixColumn(
        letter: 'd',
        action: 'wallet:groups_delete',
        label: 'delete',
        description: 'Delete user groups.',
      ),
    ],
  ),
  MatrixRowSpec(
    prefix: 'C',
    categoryHeader: 'Contact Groups',
    columns: [
      MatrixColumn(
        letter: 'c',
        action: 'wallet:contact_groups_create',
        label: 'create',
        description: 'Create new contact groups.',
      ),
      MatrixColumn(
        letter: 'u',
        action: 'wallet:contact_groups_update',
        label: 'update',
        description: 'Rename existing contact groups.',
      ),
      MatrixColumn(
        letter: 'd',
        action: 'wallet:contact_groups_delete',
        label: 'delete',
        description: 'Delete contact groups.',
      ),
    ],
  ),
  MatrixRowSpec(
    prefix: 'P',
    categoryHeader: 'Permissions',
    columns: [
      MatrixColumn(
        letter: 'e',
        action: 'wallet:permissions_edit',
        label: 'edit',
        description: 'Change wallet-level, member and contact-group permissions.',
      ),
      MatrixColumn(
        letter: 'm',
        action: 'wallet:permissions_matrix_edit',
        label: 'matrix edit',
        description: 'Change the Permission Rules matrix (contact/transaction rules).',
      ),
    ],
  ),
];

/// contact_group:* actions for the Contact Permissions screen (single row).
const List<MatrixRowSpec> contactGroupRows = [
  MatrixRowSpec(
    prefix: 'C',
    categoryHeader: 'Contact group management',
    columns: [
      MatrixColumn(
        letter: 'r',
        action: 'contact_group:contacts_read',
        label: 'read',
        description: 'See which contacts are in the target contact group.',
      ),
      MatrixColumn(
        letter: 'a',
        action: 'contact_group:contacts_add',
        label: 'add',
        description: 'Put existing contacts into the target contact group.',
      ),
      MatrixColumn(
        letter: 'x',
        action: 'contact_group:contacts_remove',
        label: 'remove',
        description: 'Take contacts out of the target contact group.',
      ),
      MatrixColumn(
        letter: 'e',
        action: 'contact_group:permissions_edit',
        label: 'edit permissions',
        description: 'Change who can manage this contact group.',
      ),
    ],
  ),
];

// ─── Widgets ───────────────────────────────────────────────────────────────

/// Compact label showing `[icon] TYPE  · Name`, used as ExpansionTile /
/// ListTile titles so users can tell at a glance whether a group is a user
/// group or a contact group.
class GroupTypeHeader extends StatelessWidget {
  final IconData icon;
  final String type; // e.g. 'User group', 'Contact group'
  final String name;
  final double iconSize;
  final bool bold;

  const GroupTypeHeader({
    super.key,
    required this.icon,
    required this.type,
    required this.name,
    this.iconSize = 18,
    this.bold = true,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(icon, size: iconSize),
        const SizedBox(width: 8),
        Text(
          '$type · ',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: labelColor),
        ),
        Expanded(
          child: Text(
            name,
            style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}


/// Compact matrix display: one Row per [MatrixRowSpec], with a prefix cell
/// and one letter cell per column. Cells are green if action is in [allowed],
/// red if in [denied], gray '-' if neither.
///
/// [showRowPrefix] — pass false when the grid has just one row (or the row
/// prefix is redundant with surrounding context, e.g. Member Permissions
/// where every row is 'M:'). Default true to preserve the Rules layout.
///
/// [useTextRowLabels] — replace the single-letter prefix cell with the row's
/// full [MatrixRowSpec.categoryHeader] text (e.g. 'Wallet', 'Members',
/// 'Groups'). Use for permission sets where the rows are just visual
/// categories rather than a target dimension — this makes clear the row is
/// a *label*, not a target-axis entry that would imply a matrix.
class PermissionMatrixGrid extends StatelessWidget {
  final List<MatrixRowSpec> rows;
  final Set<String> allowed;
  final Set<String> denied;
  final bool showRowPrefix;
  final bool useTextRowLabels;

  const PermissionMatrixGrid({
    super.key,
    required this.rows,
    required this.allowed,
    required this.denied,
    this.showRowPrefix = true,
    this.useTextRowLabels = false,
  });

  @override
  Widget build(BuildContext context) {
    const greenColor = Color(0xFF2E7D32);
    final redColor = Theme.of(context).colorScheme.error;
    final grayColor = Theme.of(context).colorScheme.onSurfaceVariant;

    // Text-label mode: each row starts with a plain-text category label
    // (e.g. 'Wallet', 'Members') instead of a single-letter prefix cell.
    // Makes it obvious the row is a label, not a target-axis entry.
    if (useTextRowLabels) {
      final labelWidth = _textLabelWidth(context);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows.map((row) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: labelWidth,
                  child: Text(
                    row.categoryHeader ?? row.prefix,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                ...row.columns.map((c) => _cell(
                      context,
                      c.letter,
                      c.action,
                      c.label,
                      c.description,
                      greenColor,
                      redColor,
                      grayColor,
                    )),
              ],
            ),
          );
        }).toList(),
      );
    }

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
              if (showRowPrefix)
                _cell(context, row.prefix, '', '', '', greenColor, redColor, grayColor),
              ...row.columns.map((c) => _cell(
                    context,
                    c.letter,
                    c.action,
                    c.label,
                    c.description,
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

  /// Width for the text label column: pick the widest label with a small pad
  /// so all rows line up.
  double _textLabelWidth(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    double widest = 0;
    for (final row in rows) {
      final text = row.categoryHeader ?? row.prefix;
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      if (painter.width > widest) widest = painter.width;
    }
    return widest + 4;
  }

  Widget _cell(
    BuildContext context,
    String letter,
    String permission,
    String label,
    String description,
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

    // Tooltip on hover; on mobile, long-press shows the same tooltip.
    return Container(
      width: 35,
      height: 35,
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 1),
      ),
      child: permission.isEmpty
          ? cell
          : Tooltip(
              message: '$label ($state)\n$description',
              triggerMode: TooltipTriggerMode.longPress,
              waitDuration: const Duration(milliseconds: 300),
              showDuration: const Duration(seconds: 4),
              child: cell,
            ),
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Checkbox(
                              value: active,
                              onChanged: (checked) {
                                _set(col.action, checked == true ? _EditState.allow : null);
                              },
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(col.label),
                                    const SizedBox(height: 2),
                                    Text(
                                      col.description,
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            fontStyle: FontStyle.italic,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
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
        // Clear-all: unchecks every action locally. User still has to Save to
        // persist the reset — makes accidental clears one Cancel away.
        TextButton(
          onPressed: (_allowed.isEmpty && _denied.isEmpty)
              ? null
              : () => setState(() {
                    _allowed.clear();
                    _denied.clear();
                  }),
          child: const Text('Clear all'),
        ),
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
