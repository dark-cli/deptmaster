// ignore_for_file: unused_import, unused_local_variable

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../api.dart';
import '../utils/text_utils.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/contact.dart';
import '../models/transaction.dart';
import '../providers/settings_provider.dart';
import '../providers/wallet_data_providers.dart';
import '../utils/app_colors.dart';
import '../utils/theme_colors.dart';
import '../utils/toast_service.dart';
import 'add_transaction_screen.dart';
import 'edit_transaction_screen.dart';
import 'edit_contact_screen.dart';
import '../widgets/gradient_background.dart';
import '../widgets/gradient_card.dart';
import '../widgets/avatar_with_selection.dart';
import '../widgets/diff_animated_list.dart';
import '../widgets/empty_state.dart';
import '../widgets/animated_pixelated_text.dart';
import '../widgets/glitch_transition.dart';
import '../utils/bottom_sheet_helper.dart';

class ContactTransactionsScreen extends ConsumerStatefulWidget {
  final Contact contact;

  const ContactTransactionsScreen({
    super.key,
    required this.contact,
  });

  @override
  ConsumerState<ContactTransactionsScreen> createState() => _ContactTransactionsScreenState();
}

class _ContactTransactionsScreenState extends ConsumerState<ContactTransactionsScreen> {
  bool _loading = false; // local busy state for UI actions (delete/bulk delete)
  Set<String> _selectedTransactions = {}; // For multi-select
  bool _selectionMode = false;
  List<Transaction> _lastValidTransactions = []; // Cache to prevent flash on refresh

  @override
  void initState() {
    super.initState();
    Api.connectRealtime();
  }

  Future<void> _refresh({bool sync = false}) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      if (sync && !kIsWeb) {
        await Api.manualSync().catchError((_) {});
      }
      ref.invalidate(transactionsProvider);
      ref.invalidate(contactsProvider);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_selectionMode, // Block pop when in selection mode (swipe gesture blocked, but back button works)
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        // If pop was blocked (didPop = false) and we're in selection mode, cancel selection
        if (!didPop && _selectionMode) {
          setState(() {
            _selectionMode = false;
            _selectedTransactions.clear();
          });
        }
        // If didPop is true, normal navigation happened (not in selection mode)
      },
      child: GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
        title: _selectionMode 
            ? Text('${_selectedTransactions.length} selected')
            : Text(
                widget.contact.username != null && widget.contact.username!.isNotEmpty
                    ? '${TextUtils.forceLtr(widget.contact.name)} @${widget.contact.username}'
                    : TextUtils.forceLtr(widget.contact.name),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _selectionMode = false;
                    _selectedTransactions.clear();
                  });
                },
              )
            : null,
        actions: [
          if (_selectionMode) ...[
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _selectedTransactions.isEmpty
                  ? null
                  : () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete Transactions'),
                            content: Text(
                              'Are you sure you want to delete ${_selectedTransactions.length} transaction(s)? This action cannot be undone.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(true),
                                style: TextButton.styleFrom(foregroundColor: Colors.red),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true && mounted) {
                          setState(() {
                            _loading = true;
                          });

                          try {
                            final deletedCount = _selectedTransactions.length;
                            final deletedIds = _selectedTransactions.toList();
                            
                            // Delete from local database (creates events, rebuilds state)
                            await Api.bulkDeleteTransactions(deletedIds);
                            
                            if (!mounted) return;
                            setState(() {
                              _selectedTransactions.clear();
                              _selectionMode = false;
                              _loading = false;
                            });
                            ref.invalidate(transactionsProvider);
                            ref.invalidate(contactsProvider);
                            if (!mounted) return;
                            
                            // Show undo toast for all deletes (single or bulk)
                            ToastService.showUndoWithErrorHandlingFromContext(
                              context: context,
                              message: '✅ $deletedCount transaction(s) deleted',
                              onUndo: () async {
                                for (final id in deletedIds) {
                                  await Api.undoTransactionAction(id);
                                }
                                ref.invalidate(transactionsProvider);
                                ref.invalidate(contactsProvider);
                              },
                              successMessage: '${deletedIds.length} transaction(s) deletion undone',
                            );
                          } catch (e) {
                            if (!mounted) return;
                            ToastService.showErrorFromContext(context, 'Error deleting transactions: $e');
                            setState(() {
                              _loading = false;
                            });
                          }
                        }
                    },
                  ),
          ] else ...[
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              final result = await showScreenAsBottomSheet(
                context: context,
                screen: EditContactScreen(contact: widget.contact),
              );
              if (result == true) {
                if (!mounted) return;
                // Reload contact data
                Navigator.of(context).pop(true);
              }
            },
            tooltip: 'Edit Contact',
          ),
          // Selection button removed - use long press on transaction items instead
          ],
        ],
      ),
      floatingActionButton: Tooltip(
        message: 'Add Transaction',
        child: FloatingActionButton(
          onPressed: () async {
            final result = await showScreenAsBottomSheet(
              context: context,
              screen: AddTransactionScreen(contact: widget.contact),
            );
            if (result == true && mounted) {
              ref.invalidate(transactionsProvider);
              ref.invalidate(contactsProvider);
            }
          },
          child: const Icon(Icons.add),
        ),
      ),
      body: Builder(
        builder: (context) {
          // if (_loading) {
          //   return const Center(child: CircularProgressIndicator());
          // }

          final txAsync = ref.watch(transactionsProvider);
          // Update cache if we have a value
          if (txAsync.hasValue) {
            _lastValidTransactions = txAsync.value!;
          }
          final baseTx = txAsync.valueOrNull ?? _lastValidTransactions;

          if (txAsync.hasError && baseTx.isEmpty) {
            final e = txAsync.error;
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Error: $e'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => _refresh(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final transactions = baseTx.where((t) => t.contactId == widget.contact.id).toList()
            ..sort((a, b) {
              final c = b.createdAt.compareTo(a.createdAt);
              if (c != 0) return c;
              return b.id.compareTo(a.id);
            });

          final emptyState = EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No transactions with ${widget.contact.name}',
            subtitle: 'Tap + to add a transaction',
          );

          // Calculate total balance for this contact
          final totalBalance = transactions.fold<int>(
            0,
            (sum, t) => sum + (t.direction == TransactionDirection.lent ? t.amount : -t.amount),
          );

          return Column(
            children: [
              // Balance Summary (same style as dashboard Total balance, full width like transaction cards)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: Consumer(
                    builder: (context, ref, child) {
                      final flipColors = ref.watch(flipColorsProvider);
                      final isDark = Theme.of(context).brightness == Brightness.dark;
                      // Standardized: Positive balance = Gave (green), Negative balance = Received (red)
                      final balanceColor = totalBalance >= 0
                          ? AppColors.getGiveColor(flipColors, isDark)
                          : AppColors.getReceivedColor(flipColors, isDark);
                      return GradientCard(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'BALANCE',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                            const SizedBox(height: 8),
                            AnimatedPixelatedText(
                              _formatBalance(totalBalance),
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: balanceColor,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              // Transactions List with pull-to-refresh
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    await Api.refreshConnectionAndSync();
                    await _refresh(sync: true);
                  },
                  child: Column(
                    children: [
                      Expanded(
                        child: Stack(
                          children: [
                            DiffAnimatedList<Transaction>(
                              items: transactions,
                              itemId: (t) => t.id,
                              padding: const EdgeInsets.only(bottom: 24),
                              itemBuilder: (context, transaction, animation) {
                            final isSelected = _selectionMode && _selectedTransactions.contains(transaction.id);
                            final isRemoving = animation.status == AnimationStatus.reverse;
                            // Add: 1) card scrambled + move (expand) 0-300ms, 2) delay 300ms, 3) glitch to real 600-800ms.
                            // Remove: 1) glitch to scrambles 0-300ms, 2) delay 300ms, 3) move (shrink) 600-800ms.
                            final moveAnimation = CurvedAnimation(
                              parent: animation,
                              curve: isRemoving
                                  ? const Interval(0.0, 0.25, curve: Curves.easeIn)  // Remove: shrink in last 300ms
                                  : const Interval(0.0, 0.375, curve: Curves.easeOut), // Add: expand in first 300ms
                            );
                            final glitchAnimation = CurvedAnimation(
                              parent: animation,
                              curve: isRemoving
                                  ? const Interval(0.625, 1.0, curve: Curves.easeOut) // Remove: glitch to scramble first 300ms
                                  : const Interval(0.75, 1.0, curve: Curves.easeOut),   // Add: glitch to real last 200ms
                            );

                            Widget transactionItem = AnimatedBuilder(
                              animation: animation,
                              builder: (context, _) {
                                final showScrambleForInsert = !isRemoving && animation.value < 0.75;
                                return _TransactionListItem(
                              transaction: transaction,
                              isSelected: _selectionMode ? isSelected : null,
                              selectionMode: _selectionMode,
                              isRemoving: isRemoving,
                              glitchAnimation: glitchAnimation,
                              onSelectionChanged: _selectionMode
                                  ? () {
                                      setState(() {
                                        if (_selectedTransactions.contains(transaction.id)) {
                                          _selectedTransactions.remove(transaction.id);
                                        } else {
                                          _selectedTransactions.add(transaction.id);
                                        }
                                      });
                                    }
                                  : () {
                                      // Long press starts selection mode
                                      setState(() {
                                        _selectionMode = true;
                                        _selectedTransactions.add(transaction.id);
                                      });
                                    },
                              onEdit: () async {
                                  final result = await showScreenAsBottomSheet(
                                    context: context,
                                    screen: EditTransactionScreen(
                                      transaction: transaction,
                                      contact: widget.contact,
                                    ),
                                  );
                                  if (result == true && mounted) {
                                    ref.invalidate(transactionsProvider);
                                    ref.invalidate(contactsProvider);
                                  }
                                },
                                onDelete: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Delete Transaction'),
                                      content: const Text('Are you sure you want to delete this transaction?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.of(context).pop(false),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.of(context).pop(true),
                                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                                          child: const Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (confirm == true && mounted) {
                                    try {
                                      await Api.deleteTransaction(transaction.id);

                                      if (!mounted) return;
                                      ref.invalidate(transactionsProvider);
                                      ref.invalidate(contactsProvider);

                                      ToastService.showUndoWithErrorHandlingFromContext(
                                        context: context,
                                        message: '✅ Transaction deleted!',
                                        onUndo: () async {
                                          await Api.undoTransactionAction(transaction.id);
                                          ref.invalidate(transactionsProvider);
                                          ref.invalidate(contactsProvider);
                                        },
                                        successMessage: 'Transaction deletion undone',
                                      );
                                    } catch (e) {
                                      if (!mounted) return;
                                      ToastService.showErrorFromContext(context, 'Error deleting: $e');
                                    }
                                  }
                                },
                                showScrambleForInsert: showScrambleForInsert,
                              );
                              },
                            );

                            if (!_selectionMode) {
                              final inner = Dismissible(
                                key: Key(transaction.id),
                                direction: DismissDirection.startToEnd, // Only swipe right (LTR)
                                dismissThresholds: const {
                                  DismissDirection.startToEnd: 0.7, // Require 70% swipe for close
                                },
                                movementDuration: const Duration(milliseconds: 300), // Slower animation
                                background: Container(
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.only(left: 20),
                                  color: Colors.green,
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    children: [
                                      Icon(Icons.check_circle, color: Colors.white),
                                      SizedBox(width: 8),
                                      Text(
                                        'Close',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                confirmDismiss: (direction) async {
                                  final reverseDirection = transaction.direction == TransactionDirection.owed
                                      ? TransactionDirection.lent
                                      : TransactionDirection.owed;
                                  final result = await showScreenAsBottomSheet(
                                    context: context,
                                    screen: AddTransactionScreenWithData(
                                      contact: widget.contact,
                                      amount: transaction.amount,
                                      direction: reverseDirection,
                                      description: transaction.description != null ? 'Close: ${transaction.description}' : 'Close transaction',
                                    ),
                                  );
                                  if (result == true && mounted) {
                                    ref.invalidate(transactionsProvider);
                                    ref.invalidate(contactsProvider);
                                  }
                                  return false;
                                },
                                child: transactionItem,
                              );
                              return SizeTransition(
                                key: ValueKey(transaction.id),
                                sizeFactor: moveAnimation,
                                child: FadeTransition(opacity: moveAnimation, child: inner),
                              );
                            }

                            return SizeTransition(
                              key: ValueKey(transaction.id),
                              sizeFactor: moveAnimation,
                              child: FadeTransition(opacity: moveAnimation, child: transactionItem),
                            );
                              },
                            ),
                            if (transactions.isEmpty)
                              Positioned.fill(
                                child: IgnorePointer(
                                  ignoring: true,
                                  child: emptyState,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
      ),
      ),
    );
  }

  String _formatBalance(int balance) {
    // Balance is stored as whole units (IQD), not cents
    if (balance == 0) return '0 IQD';
    final absBalance = balance.abs();
    final formatted = absBalance.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return balance < 0 ? '-$formatted IQD' : '$formatted IQD';
  }
}

class _TransactionListItem extends StatelessWidget {
  final Transaction transaction;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool? isSelected;
  final VoidCallback? onSelectionChanged;
  final bool selectionMode; // Track if we're in selection mode
  final Animation<double>? glitchAnimation;
  final bool isRemoving;
  final bool showScrambleForInsert;

  const _TransactionListItem({
    required this.transaction,
    this.onEdit,
    this.onDelete,
    this.isSelected,
    this.onSelectionChanged,
    this.selectionMode = false,
    this.glitchAnimation,
    this.isRemoving = false,
    this.showScrambleForInsert = false,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final flipColors = ref.watch(flipColorsProvider);
        final dateFormat = DateFormat('MMM d, y');
        final isReceived = transaction.direction == TransactionDirection.owed; // owed = Received (negative, red)
        final isGave = transaction.direction == TransactionDirection.lent; // lent = Gave (positive, green)
        final isDark = Theme.of(context).brightness == Brightness.dark;
        // Standardized: Received (owed) = red (negative), Gave (lent) = green (positive) (respects flipColors)
        final color = isReceived 
            ? AppColors.getReceivedColor(flipColors, isDark) // Received = red (negative)
            : AppColors.getGiveColor(flipColors, isDark); // Gave = green (positive)
        
        return _buildTransactionItem(context, dateFormat, color);
      },
    );
  }

  String _formatAmount(int amount) {
    // Amount is stored as whole units (IQD), format with commas
    return amount.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }

  String _getStatus(TransactionDirection direction) {
    // Standardized: owed = Received (negative), lent = Gave (positive)
    if (direction == TransactionDirection.owed) {
      return 'RECEIVED'; // Received = negative
    } else {
      return 'GAVE'; // Gave = positive
    }
  }

  Widget _glitchText(
    String text,
    TextStyle style, {
    TextAlign? textAlign,
    TextOverflow? overflow,
    int? maxLines,
  }) {
    final shouldScramble = (isRemoving || showScrambleForInsert) && text.trim().isNotEmpty;
    final hasArabic = TextUtils.hasArabic(text);
    final base = AnimatedPixelatedText(
      text,
      style: style,
      textAlign: textAlign,
      textDirection: hasArabic ? ui.TextDirection.rtl : ui.TextDirection.ltr,
      overflow: overflow,
      maxLines: maxLines,
      forceScramble: shouldScramble,
    );
    final animation = glitchAnimation;
    if (animation == null) return base;
    return GlitchTransition(
      animation: animation,
      child: base,
      showScramble: true,
      maxX: 10,
      maxY: 5,
      flickerChance: 0.35,
    );
  }

  Widget _buildTransactionItem(BuildContext context, DateFormat dateFormat, Color color) {
    final amount = transaction.amount;
    final status = _getStatus(transaction.direction);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: selectionMode ? onSelectionChanged : onEdit,
        onLongPress: onSelectionChanged != null ? () {
          // Long press starts selection mode
          onSelectionChanged?.call();
        } : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              // Left side: Avatar with optional selection checkmark (same as transaction card)
              AvatarWithSelection(
                radius: 20,
                isSelected: isSelected == true,
                avatar: CircleAvatar(
                  backgroundColor: color.withOpacity(0.2),
                  radius: 20,
                  child: Icon(
                    Icons.attach_money,
                    color: color,
                    size: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Description and Date
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (transaction.description != null && transaction.description!.isNotEmpty) ...[
                      _glitchText(
                        transaction.description!,
                        const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 16),
                    ] else ...[
                      // Reserve space for consistent card height when no description
                      const SizedBox(height: 16),
                    ],
                    if (transaction.dueDate != null) ...[
                      Row(
                        children: [
                          Icon(
                            Icons.event,
                            size: 12,
                            color: transaction.dueDate!.isBefore(DateTime.now())
                                ? ThemeColors.error(context)
                                : ThemeColors.warning(context),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: _glitchText(
                              dateFormat.format(transaction.dueDate!),
                              TextStyle(
                                fontSize: 11,
                                color: transaction.dueDate!.isBefore(DateTime.now())
                                    ? ThemeColors.error(context)
                                    : ThemeColors.warning(context),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      _glitchText(
                        dateFormat.format(transaction.transactionDate),
                        TextStyle(
                          fontSize: 11,
                          color: ThemeColors.gray(context, shade: 500),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Right side: Amount and Status (flexible width)
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _glitchText(
                      '${_formatAmount(amount)} IQD',
                      TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: color,
                      ),
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 2),
                    _glitchText(
                      status,
                      TextStyle(
                        fontSize: 10,
                        color: ThemeColors.gray(context, shade: 600),
                      ),
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              // Popup menu button
              if (onEdit != null || onDelete != null) ...[
                const SizedBox(width: 4),
                PopupMenuButton(
                  icon: const Icon(Icons.more_vert, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  itemBuilder: (context) => [
                    if (onEdit != null)
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 20),
                            SizedBox(width: 8),
                            Text('Edit'),
                          ],
                        ),
                      ),
                    if (onDelete != null)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 20, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                  ],
                  onSelected: (value) {
                    if (value == 'edit' && onEdit != null) {
                      onEdit!();
                    } else if (value == 'delete' && onDelete != null) {
                      onDelete!();
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}