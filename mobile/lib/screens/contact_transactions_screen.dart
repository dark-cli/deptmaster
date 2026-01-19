import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../utils/text_utils.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/contact.dart';
import '../models/transaction.dart';
import '../services/api_service.dart';
import '../services/realtime_service.dart';
import '../services/settings_service.dart';
import '../providers/settings_provider.dart';
import '../utils/app_colors.dart';
import '../utils/theme_colors.dart';
import 'add_transaction_screen.dart';
import 'edit_transaction_screen.dart';
import 'edit_contact_screen.dart';
import '../widgets/gradient_background.dart';
import '../widgets/gradient_card.dart';

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
      final allTransactions = await ApiService.getTransactions();
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
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
        title: _selectionMode 
            ? Text('${_selectedTransactions.length} selected')
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    TextUtils.forceLtr(widget.contact.name), // Force LTR for mixed Arabic/English text
                  ),
                  if (widget.contact.username != null && widget.contact.username!.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      '@${widget.contact.username}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
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
                            await ApiService.bulkDeleteTransactions(_selectedTransactions.toList());
                            if (mounted) {
                              setState(() {
                                _selectedTransactions.clear();
                                _selectionMode = false;
                              });
                              _loadTransactions();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('✅ ${_selectedTransactions.length} transaction(s) deleted'),
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error deleting transactions: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              setState(() {
                                _loading = false;
                              });
                            }
                          }
                        }
                    },
            ),
          ] else ...[
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              final result = await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => EditContactScreen(contact: widget.contact),
                ),
              );
              if (result == true && mounted) {
                // Reload contact data
                Navigator.of(context).pop(true);
              }
            },
            tooltip: 'Edit Contact',
          ),
          IconButton(
            icon: const Icon(Icons.check_box_outline_blank),
            onPressed: () {
              setState(() {
                _selectionMode = true;
              });
            },
            tooltip: 'Select',
          ),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => AddTransactionScreen(contact: widget.contact),
            ),
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
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
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
                          final balanceColor = totalBalance < 0
                              ? AppColors.getReceivedColor(flipColors, isDark)
                              : AppColors.getGiveColor(flipColors, isDark);
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
                              : null,
                          onEdit: () async {
                            final result = await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => EditTransactionScreen(
                                  transaction: transaction,
                                  contact: widget.contact,
                                ),
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
                                await ApiService.deleteTransaction(transaction.id);
                                if (mounted) {
                                  _loadTransactions();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('✅ Transaction deleted!')),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error deleting: $e')),
                                  );
                                }
                              }
                            }
                          },
                        ),
                      );
                      
                      // Wrap with Dismissible for swipe actions (only when not in selection mode)
                      if (!_selectionMode) {
                        return Dismissible(
                          key: Key(transaction.id),
                          direction: DismissDirection.horizontal,
                          background: Container(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.only(left: 20),
                            color: Colors.red,
                            child: const Icon(Icons.delete, color: Colors.white),
                          ),
                          secondaryBackground: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            color: Colors.green,
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  'Close',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Icon(Icons.check_circle, color: Colors.white),
                              ],
                            ),
                          ),
                          confirmDismiss: (direction) async {
                            if (direction == DismissDirection.startToEnd) {
                              // Delete (swipe left to right)
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
                                  await ApiService.deleteTransaction(transaction.id);
                                  if (mounted) {
                                    _loadTransactions();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('✅ Transaction deleted')),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                                    );
                                  }
                                }
                              }
                              return confirm ?? false;
                            } else if (direction == DismissDirection.endToStart) {
                              // Open reverse transaction to close/settle (swipe right to left)
                              final reverseDirection = transaction.direction == TransactionDirection.owed
                                  ? TransactionDirection.lent
                                  : TransactionDirection.owed;
                              final result = await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => AddTransactionScreenWithData(
                                    contact: widget.contact,
                                    amount: transaction.amount,
                                    direction: reverseDirection,
                                    description: transaction.description != null
                                        ? 'Close: ${transaction.description}'
                                        : 'Close transaction',
                                  ),
                                ),
                              );
                              if (result == true && mounted) {
                                _loadTransactions();
                              }
                              return false; // Don't dismiss
                            }
                            return false;
                          },
                          child: GestureDetector(
                            onTap: () async {
                              // Open edit transaction screen
                              final result = await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => EditTransactionScreen(
                                    transaction: transaction,
                                    contact: widget.contact,
                                  ),
                                ),
                              );
                              if (result == true && mounted) {
                                _loadTransactions();
                              }
                            },
                            onLongPress: () {
                              setState(() {
                                _selectionMode = true;
                                if (_selectedTransactions.contains(transaction.id)) {
                                  _selectedTransactions.remove(transaction.id);
                                } else {
                                  _selectedTransactions.add(transaction.id);
                                }
                              });
                            },
                            child: transactionItem,
                          ),
                        );
                      }
                      
                      return GestureDetector(
                        onTap: () async {
                          // Open edit transaction screen
                          final result = await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => EditTransactionScreen(
                                transaction: transaction,
                                contact: widget.contact,
                              ),
                            ),
                          );
                          if (result == true && mounted) {
                            _loadTransactions();
                          }
                        },
                        onLongPress: () {
                          setState(() {
                            _selectionMode = true;
                            if (_selectedTransactions.contains(transaction.id)) {
                              _selectedTransactions.remove(transaction.id);
                            } else {
                              _selectedTransactions.add(transaction.id);
                            }
                          });
                        },
                        child: transactionItem,
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
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

  const _TransactionListItem({
    required this.transaction,
    this.onEdit,
    this.onDelete,
    this.isSelected,
    this.onSelectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final flipColors = ref.watch(flipColorsProvider);
        final dateFormat = DateFormat('MMM d, y');
        final isOwed = transaction.direction == TransactionDirection.owed;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final color = flipColors
            ? (isOwed 
                ? AppColors.getReceivedColor(flipColors, isDark)
                : AppColors.getGiveColor(flipColors, isDark))
            : (isOwed 
                ? AppColors.getGiveColor(flipColors, isDark)
                : AppColors.getReceivedColor(flipColors, isDark));
        
        return _buildTransactionItem(context, dateFormat, color, flipColors);
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

  String _getStatus(TransactionDirection direction, bool flipColors) {
    // For transactions: "owed" = you owe them (GIVE), "lent" = they owe you (RECEIVED)
    if (direction == TransactionDirection.owed) {
      return flipColors ? 'YOU LENT' : 'YOU OWE';
    } else {
      return flipColors ? 'YOU OWE' : 'YOU LENT';
    }
  }

  Widget _buildTransactionItem(BuildContext context, DateFormat dateFormat, Color color, bool flipColors) {
    // Pre-allocate width for amount section to ensure names align
    const double amountSectionWidth = 120.0;
    
    final amount = transaction.amount;
    final status = _getStatus(transaction.direction, flipColors);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: onSelectionChanged != null
            ? onSelectionChanged
            : onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                      radius: 24,
                      child: Icon(
                        Icons.attach_money,
                        color: color,
                        size: 18,
                      ),
                    ),
              const SizedBox(width: 16),
              // Description and Date
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      transaction.description ?? 'Transaction',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    // Reserve space for consistent card height (same as username space in transactions screen)
                    const SizedBox(height: 16),
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
                          Text(
                            dateFormat.format(transaction.dueDate!),
                            style: TextStyle(
                              fontSize: 11,
                              color: transaction.dueDate!.isBefore(DateTime.now())
                                  ? ThemeColors.error(context)
                                  : ThemeColors.warning(context),
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
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Right side: Amount and Status (fixed width)
              SizedBox(
                width: amountSectionWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_formatAmount(amount)} IQD',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: color,
                      ),
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status,
                      style: TextStyle(
                        fontSize: 11,
                        color: ThemeColors.gray(context, shade: 600),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              // Popup menu button
              if (onEdit != null || onDelete != null) ...[
                const SizedBox(width: 8),
                PopupMenuButton(
                  icon: const Icon(Icons.more_vert),
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
