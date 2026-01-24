import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/text_utils.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/contact.dart';
import '../models/transaction.dart';
import '../services/local_database_service_v2.dart';
import '../services/realtime_service.dart';
import '../providers/settings_provider.dart';
import '../utils/app_colors.dart';
import '../utils/theme_colors.dart';
import '../utils/toast_service.dart';
import 'add_transaction_screen.dart';
import 'edit_transaction_screen.dart';
import 'edit_contact_screen.dart';
import '../widgets/gradient_background.dart';
import '../widgets/gradient_card.dart';
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
  List<Transaction>? _transactions;
  bool _loading = true;
  String? _error;
  Set<String> _selectedTransactions = {}; // For multi-select
  bool _selectionMode = false;

  @override
  void initState() {
    super.initState();
    _loadTransactions();
    
    // Listen for real-time updates
    RealtimeService.addListener(_onRealtimeUpdate);
    
    // Connect WebSocket if not connected
    RealtimeService.connect();
  }

  void _onRealtimeUpdate(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    if (type == 'transaction_created' || type == 'transaction_updated' || type == 'transaction_deleted') {
      // Reload transactions when real-time update received
      _loadTransactions();
    }
  }

  @override
  void dispose() {
    RealtimeService.removeListener(_onRealtimeUpdate);
    super.dispose();
  }

  Future<void> _loadTransactions() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    
    try {
      // Always use local database - never call API from UI
      final allTransactions = await LocalDatabaseServiceV2.getTransactions();
      // Filter transactions for this contact
      final contactTransactions = allTransactions
          .where((t) => t.contactId == widget.contact.id)
          .toList();
      
      if (mounted) {
        setState(() {
          _transactions = contactTransactions;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
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
                            await LocalDatabaseServiceV2.bulkDeleteTransactions(deletedIds);
                            
                            if (!mounted) return;
                            setState(() {
                              _selectedTransactions.clear();
                              _selectionMode = false;
                            });
                            _loadTransactions();
                            if (!mounted) return;
                            
                            // Show undo toast for all deletes (single or bulk)
                            ToastService.showUndoWithErrorHandlingFromContext(
                              context: context,
                              message: '✅ $deletedCount transaction(s) deleted',
                              onUndo: () async {
                                if (deletedIds.length == 1) {
                                  await LocalDatabaseServiceV2.undoTransactionAction(deletedIds.first);
                                } else {
                                  await LocalDatabaseServiceV2.undoBulkTransactionActions(deletedIds);
                                }
                                _loadTransactions();
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
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await showScreenAsBottomSheet(
            context: context,
            screen: AddTransactionScreen(contact: widget.contact),
          );
          if (result == true && mounted) {
            _loadTransactions();
          }
        },
        tooltip: 'Add Transaction',
        child: const Icon(Icons.add),
      ),
      body: Builder(
        builder: (context) {
          if (_loading) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (_error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Error: $_error'),
                  ElevatedButton(
                    onPressed: _loadTransactions,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (_transactions == null || _transactions!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.receipt_long, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    'No transactions with ${widget.contact.name}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tap + to add a transaction',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          // Calculate total balance for this contact
          final totalBalance = _transactions!.fold<int>(
            0,
            (sum, t) => sum + (t.direction == TransactionDirection.lent ? t.amount : -t.amount),
          );

          final transactions = _transactions!..sort((a, b) => b.transactionDate.compareTo(a.transactionDate));

          return Column(
            children: [
              // Balance Summary
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: GradientCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'BALANCE',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Consumer(
                        builder: (context, ref, child) {
                          final flipColors = ref.watch(flipColorsProvider);
                          final isDark = Theme.of(context).brightness == Brightness.dark;
                          // Standardized: Positive balance = Gave (green), Negative balance = Received (red)
                          final balanceColor = totalBalance >= 0
                              ? AppColors.getGiveColor(flipColors, isDark) // Positive = Gave = green
                              : AppColors.getReceivedColor(flipColors, isDark); // Negative = Received = red
                          return Text(
                            _formatBalance(totalBalance),
                            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: balanceColor,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              // Transactions List with pull-to-refresh
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadTransactions,
                  child: ListView.builder(
                    itemCount: transactions.length,
                    cacheExtent: 200, // Cache more items for smoother scrolling
                    itemBuilder: (context, index) {
                      final transaction = transactions[index];
                      final isSelected = _selectionMode && _selectedTransactions.contains(transaction.id);
                      
                      Widget transactionItem = Container(
                        color: isSelected ? Colors.blue.withOpacity(0.1) : null,
                        child: _TransactionListItem(
                          transaction: transaction,
                          isSelected: _selectionMode ? isSelected : null,
                          selectionMode: _selectionMode,
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
                              _loadTransactions();
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
                                // Delete from local database (creates event, rebuilds state)
                                await LocalDatabaseServiceV2.deleteTransaction(transaction.id);
                                
                                if (!mounted) return;
                                _loadTransactions();
                                if (!mounted) return;
                                
                                // Show undo toast
                                ToastService.showUndoWithErrorHandlingFromContext(
                                  context: context,
                                  message: '✅ Transaction deleted!',
                                  onUndo: () async {
                                    await LocalDatabaseServiceV2.undoTransactionAction(transaction.id);
                                    _loadTransactions();
                                  },
                                  successMessage: 'Transaction deletion undone',
                                );
                              } catch (e) {
                                if (!mounted) return;
                                ToastService.showErrorFromContext(context, 'Error deleting: $e');
                              }
                            }
                          },
                        ),
                      );
                      
                      // Wrap with Dismissible for swipe actions (only when not in selection mode)
                      if (!_selectionMode) {
                        return Dismissible(
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
                            // Open reverse transaction to close/settle (swipe right)
                            final reverseDirection = transaction.direction == TransactionDirection.owed
                                ? TransactionDirection.lent
                                : TransactionDirection.owed;
                            final result = await showScreenAsBottomSheet(
                              context: context,
                              screen: AddTransactionScreenWithData(
                                contact: widget.contact,
                                amount: transaction.amount,
                                direction: reverseDirection,
                                description: transaction.description != null
                                    ? 'Close: ${transaction.description}'
                                    : 'Close transaction',
                              ),
                            );
                            if (result == true && mounted) {
                              _loadTransactions();
                            }
                            return false; // Don't dismiss
                          },
                          child: transactionItem,
                        );
                      }
                      
                      return transactionItem;
                    },
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

  const _TransactionListItem({
    required this.transaction,
    this.onEdit,
    this.onDelete,
    this.isSelected,
    this.onSelectionChanged,
    this.selectionMode = false,
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
              // Left side: Avatar (or Checkbox in selection mode)
              isSelected != null && isSelected == true
                  ? Checkbox(
                      value: true,
                      onChanged: (value) => onSelectionChanged?.call(),
                    )
                  : CircleAvatar(
                      backgroundColor: color.withOpacity(0.2),
                      radius: 20,
                      child: Icon(
                        Icons.attach_money,
                        color: color,
                        size: 16,
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
                      Text(
                        transaction.description!,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
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
                            child: Text(
                              dateFormat.format(transaction.dueDate!),
                              style: TextStyle(
                                fontSize: 11,
                                color: transaction.dueDate!.isBefore(DateTime.now())
                                    ? ThemeColors.error(context)
                                    : ThemeColors.warning(context),
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      Text(
                        dateFormat.format(transaction.transactionDate),
                        style: TextStyle(
                          fontSize: 11,
                          color: ThemeColors.gray(context, shade: 500),
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
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
                    Text(
                      '${_formatAmount(amount)} IQD',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: color,
                      ),
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status,
                      style: TextStyle(
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
