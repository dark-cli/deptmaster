import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/text_utils.dart';
import '../utils/theme_colors.dart';
import '../utils/app_colors.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';
import '../models/contact.dart';
import '../services/dummy_data_service.dart';
import '../services/local_database_service.dart';
import '../services/sync_service.dart';
import '../services/realtime_service.dart';
import '../providers/settings_provider.dart';
import 'edit_transaction_screen.dart';
import 'add_transaction_screen.dart';
import '../utils/bottom_sheet_helper.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

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
  List<Transaction>? _transactions;
  List<Transaction>? _filteredTransactions; // Filtered by search
  List<Contact>? _contacts;
  bool _loading = true;
  String? _error;
  TransactionSortOption _sortOption = TransactionSortOption.mostRecent;
  Set<String> _selectedTransactions = {}; // For multi-select
  bool _selectionMode = false;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_onSearchChanged);
    
    // Listen for real-time updates
    RealtimeService.addListener(_onRealtimeUpdate);
    
    // Connect WebSocket if not connected
    RealtimeService.connect();
  }

  void _onRealtimeUpdate(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    if (type == 'transaction_created' || 
        type == 'transaction_updated' || 
        type == 'transaction_deleted') {
      // Reload transactions when real-time update received
      _loadData();
    }
  }

  void _onSearchChanged() {
    _applySearchAndSort();
  }

  void _applySearchAndSort() {
    if (_transactions == null) return;
    
    final query = _searchController.text.toLowerCase().trim();
    List<Transaction> filtered = _transactions!;
    
    // Apply search filter
    if (query.isNotEmpty) {
      filtered = filtered.where((transaction) {
        final contact = _contacts?.firstWhere(
          (c) => c.id == transaction.contactId,
          orElse: () => Contact(
            id: '',
            name: 'Unknown',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            balance: 0,
          ),
        );
        final contactName = contact?.name ?? 'Unknown';
        final contactUsername = contact?.username ?? '';
        return contactName.toLowerCase().contains(query) ||
               (contactUsername.isNotEmpty && contactUsername.toLowerCase().contains(query)) ||
               (transaction.description?.toLowerCase().contains(query) ?? false) ||
               transaction.amount.toString().contains(query);
      }).toList();
    }
    
    // Build contact map for name sorting
    final contactMap = _contacts != null 
        ? Map.fromEntries(_contacts!.map((c) => MapEntry(c.id, c.name)))
        : <String, String>{};
    
    // Apply sort
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
          final nameA = contactMap[a.contactId] ?? 'Unknown';
          final nameB = contactMap[b.contactId] ?? 'Unknown';
          return nameA.compareTo(nameB);
        });
        break;
      case TransactionSortOption.nameZA:
        filtered.sort((a, b) {
          final nameA = contactMap[a.contactId] ?? 'Unknown';
          final nameB = contactMap[b.contactId] ?? 'Unknown';
          return nameB.compareTo(nameA);
        });
        break;
    }
    
    if (mounted) {
      setState(() {
        _filteredTransactions = filtered;
      });
    }
  }

  List<Transaction> _getTransactions() {
    return _filteredTransactions ?? [];
  }

  @override
  void dispose() {
    _searchController.dispose();
    RealtimeService.removeListener(_onRealtimeUpdate);
    super.dispose();
  }

  Future<void> _loadData({bool sync = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    
    try {
      // Local-first: read from local database (instant, snappy)
      List<Transaction> transactions;
      List<Contact> contacts;
      
      // Always use local database - never call API from UI
      transactions = await LocalDatabaseService.getTransactions();
      contacts = await LocalDatabaseService.getContacts();
      print('📊 Got ${transactions.length} transactions and ${contacts.length} contacts from local database');
      
      // If sync requested, do full sync in background
      if (sync && !kIsWeb) {
        SyncService.fullSync(); // Don't await, let it run in background
      }
      
      // Update state
      if (mounted) {
        setState(() {
          _transactions = transactions;
          _filteredTransactions = transactions;
          _contacts = contacts;
          _loading = false;
        });
        _applySearchAndSort();
        print('✅ State updated with ${_transactions?.length ?? 0} transactions');
      }
    } catch (e, stackTrace) {
      print('❌ Error loading transactions: $e');
      print('Stack trace: $stackTrace');
      
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
    return Scaffold(
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
                            
                            // Always delete from local database first
                            await LocalDatabaseService.bulkDeleteTransactions(deletedIds);
                            
                            // Add to pending operations for background sync
                            if (!kIsWeb) {
                              for (final id in deletedIds) {
                                await SyncService.addPendingOperation(
                                  entityId: id,
                                  type: PendingOperationType.delete,
                                  entityType: 'transaction',
                                  data: null,
                                );
                              }
                            }
                            
                            if (mounted) {
                              setState(() {
                                _selectedTransactions.clear();
                                _selectionMode = false;
                              });
                              _loadData();
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('✅ $deletedCount transaction(s) deleted'),
                                ),
                              );
                            }
                          } catch (e) {
                            if (!mounted) return;
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
              _applySearchAndSort();
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
          IconButton(
            icon: Icon(_selectionMode ? Icons.check_box : Icons.check_box_outline_blank),
            onPressed: () {
              setState(() {
                _selectionMode = !_selectionMode;
                if (!_selectionMode) {
                  _selectedTransactions.clear();
                }
              });
            },
            tooltip: 'Select',
          ),
          ],
        ],
      ),
      body: Builder(
        builder: (context) {
          // Show loading state
          if (_loading) {
            return const Center(child: CircularProgressIndicator());
          }
          
          // Show error state
          if (_error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Error: $_error'),
                  ElevatedButton(
                    onPressed: _loadData,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
    
          // Use filtered and sorted transactions
          final transactions = _getTransactions();
          
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

          // Build contact map for display
          final contactMap = _contacts != null 
              ? Map.fromEntries(_contacts!.map((c) => MapEntry(c.id, c.name)))
              : <String, String>{};

          return RefreshIndicator(
            onRefresh: () => _loadData(sync: true),
            child: ListView.builder(
              itemCount: transactions.length,
              cacheExtent: 200, // Cache more items for smoother scrolling
              itemBuilder: (context, index) {
                final transaction = transactions[index];
                final isSelected = _selectionMode && _selectedTransactions.contains(transaction.id);
                
                Widget transactionItem = Container(
                  color: isSelected ? Colors.blue.withOpacity(0.1) : null,
                  child: TransactionListItem(
                    transaction: transaction,
                    contactName: contactMap[transaction.contactId] ?? 'Unknown',
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
                      // Open reverse transaction - opposite direction, same amount, same contact (swipe right)
                      final contact = _contacts?.firstWhere(
                        (c) => c.id == transaction.contactId,
                        orElse: () => Contact(
                          id: transaction.contactId,
                          name: 'Unknown',
                          createdAt: DateTime.now(),
                          updatedAt: DateTime.now(),
                          balance: 0,
                        ),
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
                          description: transaction.description != null
                              ? 'Close: ${transaction.description}'
                              : 'Close transaction',
                        ),
                      );
                      if (result == true && mounted) {
                        _loadData();
                      }
                      return false; // Don't dismiss
                    },
                    child: GestureDetector(
                      onTap: () async {
                        // Open edit transaction screen
                        final contact = _contacts?.firstWhere(
                          (c) => c.id == transaction.contactId,
                          orElse: () => Contact(
                            id: transaction.contactId,
                            name: 'Unknown',
                            createdAt: DateTime.now(),
                            updatedAt: DateTime.now(),
                            balance: 0,
                          ),
                        );
                        final result = await showScreenAsBottomSheet(
                          context: context,
                          screen: EditTransactionScreen(
                            transaction: transaction,
                            contact: contact,
                          ),
                        );
                        if (result == true && mounted) {
                          _loadData();
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
          );
        },
      ),
    );
  }
}

class TransactionListItem extends StatelessWidget {
  final Transaction transaction;
  final String? contactName; // For web, pass contact name directly

  const TransactionListItem({
    super.key,
    required this.transaction,
    this.contactName,
  });

  String _getContactName() {
    if (contactName != null) return contactName!;
    if (kIsWeb) return 'Unknown';
    final contactsBox = Hive.box<Contact>(DummyDataService.contactsBoxName);
    final contact = contactsBox.get(transaction.contactId);
    return contact?.name ?? 'Unknown';
  }

  Contact? _getContact() {
    if (kIsWeb) return null;
    final contactsBox = Hive.box<Contact>(DummyDataService.contactsBoxName);
    return contactsBox.get(transaction.contactId);
  }

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
    
    final contact = _getContact();
    final contactName = _getContactName();
    final amount = transaction.amount;
    final status = _getStatus(transaction.direction, flipColors);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: null, // Add navigation if needed
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Left side: Avatar
              CircleAvatar(
                backgroundColor: color.withOpacity(0.2),
                radius: 24,
                child: Icon(
                  Icons.attach_money,
                  color: color,
                  size: 18,
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
                    Text(
                      TextUtils.forceLtr(contactName), // Force LTR for mixed Arabic/English text
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    // Always reserve space for username to maintain consistent card height
                    if (contact?.username != null && contact!.username!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '@${contact.username}',
                        style: TextStyle(
                          color: ThemeColors.gray(context, shade: 500),
                          fontSize: 12,
                        ),
                      ),
                    ] else ...[
                      // Reserve same space when username is missing (2px spacing + 14px text height)
                      const SizedBox(height: 16),
                    ],
                    if (transaction.description != null || transaction.dueDate != null) ...[
                      const SizedBox(height: 4),
                      if (transaction.description != null)
                        Text(
                          transaction.description!,
                          style: TextStyle(
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
                      ] else if (transaction.description == null) ...[
                        Text(
                          dateFormat.format(transaction.transactionDate),
                          style: TextStyle(
                            fontSize: 11,
                            color: ThemeColors.gray(context, shade: 500),
                          ),
                        ),
                      ],
                    ] else ...[
                      const SizedBox(height: 2),
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
            ],
          ),
        ),
      ),
    );
  }
}
