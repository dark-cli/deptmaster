import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/contact.dart';
import '../models/transaction.dart';
import '../services/dummy_data_service.dart';
import '../services/local_database_service_v2.dart';
import '../services/sync_service_v2.dart';
import '../services/settings_service.dart';
import '../widgets/contact_list_item.dart';
import 'add_contact_screen.dart';
import 'contact_transactions_screen.dart';
import 'add_transaction_screen.dart';
import '../services/realtime_service.dart';
import '../utils/bottom_sheet_helper.dart';
import '../providers/settings_provider.dart';
import '../utils/app_colors.dart';

class ContactsScreen extends ConsumerStatefulWidget {
  final VoidCallback? onOpenDrawer;
  
  const ContactsScreen({super.key, this.onOpenDrawer});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

enum ContactSortOption {
  alphabetical,
  alphabeticalZA,
  balanceHigh,
  balanceLow,
  mostRecent,
  oldest,
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  List<Contact>? _contacts;
  List<Contact>? _filteredContacts; // Filtered by search
  bool _loading = true;
  String? _error;
  ContactSortOption _sortOption = ContactSortOption.alphabetical;
  Set<String> _selectedContacts = {}; // For multi-select
  bool _selectionMode = false;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  Color? _defaultDirectionColor; // Color for default direction (for swipe background)

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _loadSettings();
    _searchController.addListener(_onSearchChanged);
    
    // Listen for real-time updates
    RealtimeService.addListener(_onRealtimeUpdate);
    
    // Connect WebSocket if not connected
    RealtimeService.connect();
    
    // Listen to local Hive box changes for offline updates
    _setupLocalListeners();
  }

  void _setupLocalListeners() {
    if (kIsWeb) return;
    
    // Listen to local Hive box changes for offline updates
    final contactsBox = Hive.box<Contact>(DummyDataService.contactsBoxName);
    final transactionsBox = Hive.box<Transaction>(DummyDataService.transactionsBoxName);
    
    contactsBox.listenable().addListener(_onLocalDataChanged);
    transactionsBox.listenable().addListener(_onLocalDataChanged);
  }

  void _onLocalDataChanged() {
    // Reload contacts when local database changes (works offline)
    // Transactions affect contact balances, so reload when either changes
    if (mounted) {
      _loadContacts();
    }
  }

  Future<void> _loadSettings() async {
    // Load default direction to set swipe background color
    final defaultDir = await SettingsService.getDefaultDirection();
    final flipColors = ref.read(flipColorsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (mounted) {
      setState(() {
        // Set color based on default direction: received = red, give = green
        _defaultDirectionColor = defaultDir == 'received'
            ? AppColors.getReceivedColor(flipColors, isDark)
            : AppColors.getGiveColor(flipColors, isDark);
      });
    }
  }

  void _onRealtimeUpdate(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    // Reload contacts for any change - contacts, transactions (affect balance), etc.
    if (type == 'contact_created' || 
        type == 'contact_updated' || 
        type == 'transaction_created' || 
        type == 'transaction_updated' || 
        type == 'transaction_deleted') {
      // Reload contacts when real-time update received (transactions affect balance)
      _loadContacts();
    }
  }

  void _onSearchChanged() {
    _applySearchAndSort();
  }

  void _applySearchAndSort() {
    if (_contacts == null) return;
    
    final query = _searchController.text.toLowerCase().trim();
    List<Contact> filtered = _contacts!;
    
    // Apply search filter
    if (query.isNotEmpty) {
      filtered = filtered.where((contact) {
        return contact.name.toLowerCase().contains(query) ||
               (contact.username?.toLowerCase().contains(query) ?? false) ||
               (contact.phone?.toLowerCase().contains(query) ?? false) ||
               (contact.email?.toLowerCase().contains(query) ?? false) ||
               (contact.notes?.toLowerCase().contains(query) ?? false);
      }).toList();
    }
    
    // Apply sort
    switch (_sortOption) {
      case ContactSortOption.alphabetical:
        filtered.sort((a, b) => a.name.compareTo(b.name));
        break;
      case ContactSortOption.alphabeticalZA:
        filtered.sort((a, b) => b.name.compareTo(a.name));
        break;
      case ContactSortOption.balanceHigh:
        filtered.sort((a, b) => b.balance.compareTo(a.balance));
        break;
      case ContactSortOption.balanceLow:
        filtered.sort((a, b) => a.balance.compareTo(b.balance));
        break;
      case ContactSortOption.mostRecent:
        filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        break;
      case ContactSortOption.oldest:
        filtered.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
        break;
    }
    
    if (mounted) {
      setState(() {
        _filteredContacts = filtered;
      });
    }
  }

  List<Contact> _getContacts() {
    return _filteredContacts ?? [];
  }

  @override
  void dispose() {
    _searchController.dispose();
    if (!kIsWeb) {
      final contactsBox = Hive.box<Contact>(DummyDataService.contactsBoxName);
      final transactionsBox = Hive.box<Transaction>(DummyDataService.transactionsBoxName);
      contactsBox.listenable().removeListener(_onLocalDataChanged);
      transactionsBox.listenable().removeListener(_onLocalDataChanged);
    }
    RealtimeService.removeListener(_onRealtimeUpdate);
    super.dispose();
  }

  Future<void> _loadContacts({bool sync = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    
    try {
      // Local-first: read from local database (instant, snappy)
      List<Contact> contacts;
      
      // Always use local database - never call API from UI
      contacts = await LocalDatabaseServiceV2.getContacts();
      
      // If sync requested, do full sync in background
      if (sync && !kIsWeb) {
        SyncServiceV2.manualSync(); // Don't await, let it run in background
      }
      
      // Update state
      if (mounted) {
        setState(() {
          _contacts = contacts;
          _filteredContacts = contacts;
          _loading = false;
        });
        _applySearchAndSort();
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
    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search contacts...',
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
                ? Text('${_selectedContacts.length} selected')
                : const Text('Contacts'),
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _selectionMode = false;
                    _selectedContacts.clear();
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
              onPressed: _selectedContacts.isEmpty
                  ? null
                  : () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Delete Contacts'),
                          content: Text(
                            'Are you sure you want to delete ${_selectedContacts.length} contact(s)? This action cannot be undone.',
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
                          final deletedCount = _selectedContacts.length;
                          final deletedIds = _selectedContacts.toList();
                          
                          // Always delete from local database first
                          await LocalDatabaseServiceV2.bulkDeleteContacts(deletedIds);
                          
                          if (mounted) {
                            setState(() {
                              _selectedContacts.clear();
                              _selectionMode = false;
                            });
                            _loadContacts();
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('✅ $deletedCount contact(s) deleted'),
                              ),
                            );
                          }
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error deleting contacts: $e'),
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
          PopupMenuButton<ContactSortOption>(
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
                value: ContactSortOption.alphabetical,
                child: Text('Name (A to Z)'),
              ),
              const PopupMenuItem(
                value: ContactSortOption.alphabeticalZA,
                child: Text('Name (Z to A)'),
              ),
              const PopupMenuItem(
                value: ContactSortOption.balanceHigh,
                child: Text('Balance (High to Low)'),
              ),
              const PopupMenuItem(
                value: ContactSortOption.balanceLow,
                child: Text('Balance (Low to High)'),
              ),
              const PopupMenuItem(
                value: ContactSortOption.mostRecent,
                child: Text('Most Recent'),
              ),
              const PopupMenuItem(
                value: ContactSortOption.oldest,
                child: Text('Oldest First'),
              ),
            ],
          ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () async {
                final result = await showScreenAsBottomSheet(
                  context: context,
                  screen: const AddContactScreen(),
                );
                // Refresh if contact was created
                if (result == true && mounted) {
                  _loadContacts();
                }
              },
              tooltip: 'Add Contact',
            ),
            // Selection button removed - use long press on contact items instead
          ],
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadContacts(sync: true),
        child: Builder(
          builder: (context) {
            if (_loading) {
              return const Center(child: CircularProgressIndicator());
            }
            
            if (_error != null) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Error: $_error', style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadContacts,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }

            final contacts = _getContacts();

            if (contacts.isEmpty && _searchController.text.isNotEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.search_off, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(
                      'No contacts found for "${_searchController.text}"',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              );
            }
            

          return ListView.builder(
            itemCount: contacts.length,
            cacheExtent: 200, // Cache more items for smoother scrolling
            itemBuilder: (context, index) {
              final contact = contacts[index];
              final isSelected = _selectionMode && _selectedContacts.contains(contact.id);
              
              Widget contactItem = ContactListItem(
                        contact: contact,
                        isSelected: _selectionMode ? isSelected : null,
                        onSelectionChanged: _selectionMode
                            ? () {
                                setState(() {
                                  if (_selectedContacts.contains(contact.id)) {
                                    _selectedContacts.remove(contact.id);
                                  } else {
                                    _selectedContacts.add(contact.id);
                                  }
                                });
                              }
                            : null,
                        onTap: _selectionMode
                            ? () {
                                setState(() {
                                  if (_selectedContacts.contains(contact.id)) {
                                    _selectedContacts.remove(contact.id);
                                  } else {
                                    _selectedContacts.add(contact.id);
                                  }
                                });
                              }
                            : () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => ContactTransactionsScreen(
                                      contact: contact,
                                    ),
                                  ),
                                );
                              },
                      );
                      
                      // Wrap with Dismissible for swipe actions (only when not in selection mode)
                      if (!_selectionMode) {
                        return Dismissible(
                          key: Key(contact.id),
                          direction: DismissDirection.startToEnd, // Only swipe right (LTR)
                          dismissThresholds: const {
                            DismissDirection.startToEnd: 0.7, // Require 70% swipe for add transaction
                          },
                          movementDuration: const Duration(milliseconds: 300), // Slower animation
                          background: Container(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.only(left: 20),
                            color: _defaultDirectionColor ?? Colors.green, // Use default direction color
                            child: const Icon(Icons.add, color: Colors.white),
                          ),
                          confirmDismiss: (direction) async {
                            // Open new transaction screen with this contact (swipe right) using default direction
                            final defaultDir = await SettingsService.getDefaultDirection();
                            final defaultDirection = defaultDir == 'received' 
                                ? TransactionDirection.owed 
                                : TransactionDirection.lent;
                            final result = await showScreenAsBottomSheet(
                              context: context,
                              screen: AddTransactionScreenWithData(
                                contact: contact,
                                direction: defaultDirection,
                              ),
                            );
                            if (result == true && mounted) {
                              _loadContacts();
                            }
                            return false; // Don't dismiss
                          },
                          child: contactItem,
                        );
              }
              
              return contactItem;
            },
          );
          },
        ),
      ),
    );
  }
}