// ignore_for_file: unused_field, unused_local_variable

import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../api.dart';
import '../utils/text_utils.dart';
import '../utils/theme_colors.dart';
import '../utils/toast_service.dart';
import '../utils/app_colors.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';
import '../models/contact.dart';
import '../providers/settings_provider.dart';
import '../providers/wallet_data_providers.dart';
import 'edit_transaction_screen.dart';
import 'add_transaction_screen.dart';
import '../widgets/sync_status_icon.dart';
import '../utils/bottom_sheet_helper.dart';
import '../widgets/avatar_with_selection.dart';
import '../widgets/diff_animated_list.dart';
import '../widgets/animated_pixelated_text.dart';
import '../widgets/glitch_transition.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  final VoidCallback? onOpenDrawer;
  final VoidCallback? onNavigateToDashboard;
  
  const TransactionsScreen({super.key, this.onOpenDrawer, this.onNavigateToDashboard});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

enum TransactionSortOption {
  mostRecent,
  oldest,
  amountHigh,
  amountLow,
  nameAZ,
  nameZA,
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  bool _loading = false; // Local busy state for UI actions (not initial data load)
  TransactionSortOption _sortOption = TransactionSortOption.mostRecent;
  Set<String> _selectedTransactions = {}; // For multi-select
  bool _selectionMode = false;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  String? _lastMissingContactsHash; // Track missing contacts to avoid repeated warnings
  List<Transaction> _lastValidTransactions = []; // Cache to prevent flash on refresh

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    Api.connectRealtime();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  List<Transaction> _filterAndSortTransactions({
    required List<Transaction> transactions,
    required Map<String, Contact> contactsById,
  }) {
    final query = _searchController.text.toLowerCase().trim();
    var filtered = transactions;

    if (query.isNotEmpty) {
      filtered = filtered.where((transaction) {
        final contact = contactsById[transaction.contactId];
        final contactName = contact?.name ?? 'Unknown';
        final contactUsername = contact?.username ?? '';
        return contactName.toLowerCase().contains(query) ||
            (contactUsername.isNotEmpty && contactUsername.toLowerCase().contains(query)) ||
            (transaction.description?.toLowerCase().contains(query) ?? false) ||
            transaction.amount.toString().contains(query);
      }).toList();
    } else {
      filtered = List<Transaction>.from(filtered);
    }

    switch (_sortOption) {
      case TransactionSortOption.mostRecent:
        filtered.sort((a, b) => b.transactionDate.compareTo(a.transactionDate));
        break;
      case TransactionSortOption.oldest:
        filtered.sort((a, b) => a.transactionDate.compareTo(b.transactionDate));
        break;
      case TransactionSortOption.amountHigh:
        filtered.sort((a, b) => b.amount.compareTo(a.amount));
        break;
      case TransactionSortOption.amountLow:
        filtered.sort((a, b) => a.amount.compareTo(b.amount));
        break;
      case TransactionSortOption.nameAZ:
        filtered.sort((a, b) {
          final nameA = contactsById[a.contactId]?.name ?? 'Unknown';
          final nameB = contactsById[b.contactId]?.name ?? 'Unknown';
          return nameA.compareTo(nameB);
        });
        break;
      case TransactionSortOption.nameZA:
        filtered.sort((a, b) {
          final nameA = contactsById[a.contactId]?.name ?? 'Unknown';
          final nameB = contactsById[b.contactId]?.name ?? 'Unknown';
          return nameB.compareTo(nameA);
        });
        break;
    }

    return filtered;
  }

  Future<void> _refreshData({bool sync = false}) async {
    setState(() => _loading = true);
    try {
      if (sync && !kIsWeb) {
        await Api.manualSync().catchError((_) {});
      }
      ref.invalidate(transactionsProvider);
      ref.invalidate(contactsProvider); // names affect transaction display
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
      child: Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search transactions...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Colors.white70),
                ),
                style: const TextStyle(color: Colors.white),
                onSubmitted: (_) {
                  setState(() {
                    _isSearching = false;
                  });
                },
              )
            : _selectionMode 
                ? Text('${_selectedTransactions.length} selected')
                : const Text('Transactions'),
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
            : _isSearching
                ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () {
                      setState(() {
                        _isSearching = false;
                        _searchController.clear();
                      });
                    },
                  )
                : widget.onOpenDrawer != null
                    ? IconButton(
                        icon: const Icon(Icons.menu),
                        onPressed: widget.onOpenDrawer,
                      )
                    : null,
        actions: [
          if (!_selectionMode && !_isSearching) ...[
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () {
                setState(() {
                  _isSearching = true;
                });
              },
            ),
          ],
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
                            
                            if (mounted) {
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
                            }
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
          PopupMenuButton<TransactionSortOption>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort',
            onSelected: (option) {
              setState(() {
                _sortOption = option;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: TransactionSortOption.mostRecent,
                child: Text('Most Recent'),
              ),
              const PopupMenuItem(
                value: TransactionSortOption.oldest,
                child: Text('Oldest First'),
              ),
              const PopupMenuItem(
                value: TransactionSortOption.amountHigh,
                child: Text('Amount (High to Low)'),
              ),
              const PopupMenuItem(
                value: TransactionSortOption.amountLow,
                child: Text('Amount (Low to High)'),
              ),
              const PopupMenuItem(
                value: TransactionSortOption.nameAZ,
                child: Text('Name (A to Z)'),
              ),
              const PopupMenuItem(
                value: TransactionSortOption.nameZA,
                child: Text('Name (Z to A)'),
              ),
            ],
          ),
          ],
          if (!_selectionMode && !_isSearching)
            const Padding(
              padding: EdgeInsets.only(left: 24.0, right: 20.0),
              child: SyncStatusIcon(),
            ),
        ],
      ),
      body: Builder(
        builder: (context) {
          // if (_loading) {
          //   return const Center(child: CircularProgressIndicator());
          // }
          final transactionsAsync = ref.watch(transactionsProvider);
          final contactsAsync = ref.watch(contactsProvider);

          // Update cache if we have a value
          if (transactionsAsync.hasValue) {
            _lastValidTransactions = transactionsAsync.value!;
          }

          final baseTransactions = transactionsAsync.valueOrNull ?? _lastValidTransactions;

          if (transactionsAsync.hasError && baseTransactions.isEmpty) {
            final e = transactionsAsync.error;
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Error: $e'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => _refreshData(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (transactionsAsync.isLoading && baseTransactions.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          final contacts = contactsAsync.valueOrNull ?? const <Contact>[];
          final contactsById = {for (final c in contacts) c.id: c};
          final contactNameMap = {for (final c in contacts) c.id: c.name};

              final transactions = _filterAndSortTransactions(
                transactions: baseTransactions,
                contactsById: contactsById,
              );

              if (transactions.isEmpty && _searchController.text.isNotEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.search_off, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        'No transactions found for "${_searchController.text}"',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              if (transactions.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        'No transactions yet',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add your first transaction to get started',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

          return Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => _refreshData(sync: true),
                  child: DiffAnimatedList<Transaction>(
                    items: transactions,
                    itemId: (t) => t.id,
                    padding: const EdgeInsets.only(bottom: 32),
                    itemBuilder: (context, transaction, animation) {
                    final isSelected = _selectionMode && _selectedTransactions.contains(transaction.id);
                    final isRemoving = animation.status == AnimationStatus.reverse;
                            // Add: 1) card scrambled + move (expand) 0-300ms, 2) delay 300ms, 3) glitch to real 600-800ms.
                            // Remove: 1) glitch to scrambles 0-300ms, 2) delay 300ms, 3) move (shrink) 600-800ms.
                            final moveAnimation = CurvedAnimation(
                              parent: animation,
                              curve: isRemoving
                                  ? const Interval(0.0, 0.25, curve: Curves.easeIn)  // Remove: shrink in last 300ms (parent 0.25→0)
                                  : const Interval(0.0, 0.375, curve: Curves.easeOut), // Add: expand in first 300ms
                            );
                            final glitchAnimation = CurvedAnimation(
                              parent: animation,
                              curve: isRemoving
                                  ? const Interval(0.625, 1.0, curve: Curves.easeOut) // Remove: glitch to scramble in first 300ms (parent 1→0.625)
                                  : const Interval(0.75, 1.0, curve: Curves.easeOut),   // Add: glitch to real in last 200ms (parent 0.75→1)
                            );

                    final contactId = transaction.contactId;
                    final contactNameFromMap = contactNameMap[contactId];
                    final contactForItem = contactsById[contactId];

                    Widget transactionItem = AnimatedBuilder(
                      animation: animation,
                      builder: (context, _) {
                        // Add: show scramble until glitch phase starts (after move + 300ms delay)
                        final showScrambleForInsert = !isRemoving && animation.value < 0.75;
                        return TransactionListItem(
                          transaction: transaction,
                          contactName: contactNameFromMap,
                          contact: contactForItem,
                          isSelected: _selectionMode ? isSelected : null,
                          isRemoving: isRemoving,
                          glitchAnimation: glitchAnimation,
                          showScrambleForInsert: showScrambleForInsert,
                        );
                      },
                    );


                    // Wrap with Dismissible for swipe actions (only when not in selection mode)
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
                          final contact = contactForItem ??
                              Contact(
                                id: transaction.contactId,
                                name: 'Unknown',
                                createdAt: DateTime.now(),
                                updatedAt: DateTime.now(),
                                balance: 0,
                              );

                          // Create a reverse transaction screen with pre-filled data to close/settle the transaction
                          final reverseDirection = transaction.direction == TransactionDirection.owed
                              ? TransactionDirection.lent
                              : TransactionDirection.owed;
                          final result = await showScreenAsBottomSheet(
                            context: context,
                            screen: AddTransactionScreenWithData(
                              contact: contact,
                              amount: transaction.amount,
                              direction: reverseDirection,
                              description: transaction.description != null ? 'Close: ${transaction.description}' : 'Close transaction',
                            ),
                          );
                          if (result == true && mounted) {
                            ref.invalidate(transactionsProvider);
                            ref.invalidate(contactsProvider);
                          }
                          return false; // Don't dismiss
                        },
                        child: GestureDetector(
                          onTap: () async {
                            final contact = contactForItem ??
                                Contact(
                                  id: transaction.contactId,
                                  name: 'Unknown',
                                  createdAt: DateTime.now(),
                                  updatedAt: DateTime.now(),
                                  balance: 0,
                                );

                            final result = await showScreenAsBottomSheet(
                              context: context,
                              screen: EditTransactionScreen(
                                transaction: transaction,
                                contact: contact,
                              ),
                            );
                            if (result == true && mounted) {
                              ref.invalidate(transactionsProvider);
                              ref.invalidate(contactsProvider);
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
                      return SizeTransition(
                        key: ValueKey(transaction.id),
                        sizeFactor: moveAnimation,
                        child: FadeTransition(opacity: moveAnimation, child: inner),
                      );
                    }

                    final inner = GestureDetector(
                      onTap: () {
                        if (_selectionMode) {
                          setState(() {
                            if (_selectedTransactions.contains(transaction.id)) {
                              _selectedTransactions.remove(transaction.id);
                            } else {
                              _selectedTransactions.add(transaction.id);
                            }
                          });
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
                    return SizeTransition(
                      key: ValueKey(transaction.id),
                      sizeFactor: moveAnimation,
                      child: FadeTransition(opacity: moveAnimation, child: inner),
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
}

class TransactionListItem extends StatelessWidget {
  final Transaction transaction;
  final String? contactName;
  final Contact? contact;
  final bool? isSelected;
  final bool isRemoving;
  final Animation<double>? glitchAnimation;
  final bool showScrambleForInsert;

  const TransactionListItem({
    super.key,
    required this.transaction,
    this.contactName,
    this.contact,
    this.isSelected,
    this.isRemoving = false,
    this.glitchAnimation,
    this.showScrambleForInsert = false,
  });

  String _getContactName() {
    if (contact?.name != null && contact!.name.isNotEmpty) return contact!.name;
    if (contactName != null && contactName!.isNotEmpty && contactName != 'Unknown') return contactName!;
    return 'Unknown Contact';
  }

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
    const double amountSectionWidth = 120.0;
    final contact = this.contact;
    final contactName = _getContactName();
    final amount = transaction.amount;
    final status = _getStatus(transaction.direction);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: null, // Add navigation if needed
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Left side: Avatar with optional selection checkmark
              AvatarWithSelection(
                radius: 24,
                isSelected: isSelected ?? false,
                avatar: CircleAvatar(
                  backgroundColor: color.withOpacity(0.2),
                  radius: 24,
                  child: Icon(
                    Icons.attach_money,
                    color: color,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Name, Username, and Description/Date
              Expanded(
                child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
                    _glitchText(
                      TextUtils.hasArabic(contactName)
                          ? contactName
                          : TextUtils.forceLtr(contactName),
                      const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // Always reserve space for username to maintain consistent card height
                    if (contact?.username != null && contact!.username!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      _glitchText(
                        '@${contact.username}',
                        TextStyle(
                          color: ThemeColors.gray(context, shade: 500),
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ] else ...[
                      // Reserve same space when username is missing (2px spacing + 14px text height)
                      const SizedBox(height: 16),
                    ],
                    if (transaction.description != null || transaction.dueDate != null) ...[
                      const SizedBox(height: 4),
            if (transaction.description != null) 
            _glitchText(
              transaction.description!,
              TextStyle(
                fontSize: 12,
                color: ThemeColors.gray(context, shade: 600),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (transaction.dueDate != null) ...[
                        const SizedBox(height: 2),
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
                  _glitchText(
                    dateFormat.format(transaction.dueDate!),
                    TextStyle(
                      fontSize: 11,
                      color: transaction.dueDate!.isBefore(DateTime.now())
                          ? ThemeColors.error(context)
                          : ThemeColors.warning(context),
                    ),
                  ),
                ],
                        ),
                      ] else if (transaction.description == null) ...[
                        _glitchText(
                          dateFormat.format(transaction.transactionDate),
                          TextStyle(
                            fontSize: 11,
                            color: ThemeColors.gray(context, shade: 500),
                          ),
                        ),
                      ],
                    ] else ...[
                      const SizedBox(height: 2),
                      _glitchText(
                        dateFormat.format(transaction.transactionDate),
                        TextStyle(
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
                    _glitchText(
                      '${_formatAmount(amount)} IQD',
                      TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: color,
                      ),
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    _glitchText(
                      status,
                      TextStyle(
                        fontSize: 11,
                        color: ThemeColors.gray(context, shade: 600),
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}