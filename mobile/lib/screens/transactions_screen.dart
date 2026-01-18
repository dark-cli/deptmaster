import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';
import '../models/contact.dart';
import '../services/dummy_data_service.dart';
import '../services/api_service.dart';
import '../services/realtime_service.dart';
import '../services/settings_service.dart';
import '../providers/settings_provider.dart';
import 'edit_transaction_screen.dart';
import 'add_transaction_screen.dart';

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
        return contactName.toLowerCase().contains(query) ||
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

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    
    try {
      print('🔄 Loading transactions from API...');
      final transactions = await ApiService.getTransactions();
      print('📊 Got ${transactions.length} transactions from API');
      final contacts = await ApiService.getContacts();
      print('👥 Got ${contacts.length} contacts from API');
      
      // Update state (works for both web and desktop)
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
      
      // Store in Hive for offline capability (mobile/desktop)
      if (!kIsWeb) {
        try {
          final transactionsBox = Hive.box<Transaction>(DummyDataService.transactionsBoxName);
          await transactionsBox.clear();
          for (var transaction in transactions) {
            await transactionsBox.put(transaction.id, transaction);
          }
          print('✅ Stored ${transactions.length} transactions in Hive');
        } catch (e) {
          // Hive might not be initialized or enum adapter issue - that's okay
          print('⚠️ Could not store in Hive: $e');
        }
      }
    } catch (e, stackTrace) {
      print('❌ Error loading transactions: $e');
      print('Stack trace: $stackTrace');
      
      // If online fails, try to load from Hive (offline)
      if (!kIsWeb) {
        try {
          final transactionsBox = Hive.box<Transaction>(DummyDataService.transactionsBoxName);
          final contactsBox = Hive.box<Contact>(DummyDataService.contactsBoxName);
          final transactions = transactionsBox.values.cast<Transaction>().toList();
          final contacts = contactsBox.values.cast<Contact>().toList();
          if (mounted) {
            setState(() {
              _transactions = transactions;
              _filteredTransactions = transactions;
              _contacts = contacts;
              _loading = false;
              _error = 'Offline - showing cached data';
            });
            _applySearchAndSort();
          }
          return;
        } catch (_) {
          // Hive also failed
        }
      }
      
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
                            await ApiService.bulkDeleteTransactions(_selectedTransactions.toList());
                            if (mounted) {
                              setState(() {
                                _selectedTransactions.clear();
                                _selectionMode = false;
                              });
                              _loadData();
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
            onRefresh: _loadData,
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
                              _loadData();
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
                        // Open reverse transaction - opposite direction, same amount, same contact (swipe right to left)
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
                        final result = await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => AddTransactionScreenWithData(
                              contact: contact,
                              amount: transaction.amount,
                              direction: reverseDirection,
                              description: transaction.description != null
                                  ? 'Close: ${transaction.description}'
                                  : 'Close transaction',
                            ),
                          ),
                        );
                        if (result == true && mounted) {
                          _loadData();
                        }
                        return false; // Don't dismiss
                      }
                      return false;
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
                        final result = await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => EditTransactionScreen(
                              transaction: transaction,
                              contact: contact,
                            ),
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

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final flipColors = ref.watch(flipColorsProvider);
        final dateFormat = DateFormat('MMM d, y');
        final isOwed = transaction.direction == TransactionDirection.owed;
        final color = flipColors
            ? (isOwed ? Colors.green : Colors.red)
            : (isOwed ? Colors.red : Colors.green);
        
        return _buildTransactionItem(context, dateFormat, color);
      },
    );
  }

  Widget _buildTransactionItem(BuildContext context, DateFormat dateFormat, Color color) {

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.2),
          child: Icon(
            Icons.attach_money,
            color: color,
          ),
        ),
        title: Directionality(
          textDirection: TextDirection.ltr, // Force LTR for mixed Arabic/English text
          child: Text(_getContactName()),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (transaction.description != null) 
              Text(transaction.description!),
            Text(
              dateFormat.format(transaction.transactionDate),
              style: TextStyle(color: Colors.grey[600]),
            ),
            if (transaction.dueDate != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.event, size: 14, color: Colors.orange),
                  const SizedBox(width: 4),
                  Text(
                    'Due: ${dateFormat.format(transaction.dueDate!)}',
                    style: TextStyle(
                      color: transaction.dueDate!.isBefore(DateTime.now())
                          ? Colors.red
                          : Colors.orange,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        trailing: Text(
          transaction.getFormattedAmount(2),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ),
    );
  }
}
