import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/contact.dart';
import '../services/dummy_data_service.dart';
import '../services/api_service.dart';
import 'dart:async';
import '../widgets/contact_list_item.dart';
import 'add_contact_screen.dart';
import 'edit_contact_screen.dart';
import 'contact_transactions_screen.dart';
import 'add_transaction_screen.dart';
import '../services/realtime_service.dart';
import '../services/settings_service.dart';
import '../providers/settings_provider.dart';
import '../utils/app_colors.dart';
import '../utils/theme_colors.dart';

class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

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
  }

  Future<void> _loadSettings() async {
    // Settings are now managed by providers, no need to load here
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

  @override
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
    RealtimeService.removeListener(_onRealtimeUpdate);
    super.dispose();
  }

  Future<void> _loadContacts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    
    try {
      // Try to load from API (online)
      final contacts = await ApiService.getContacts();
      
      // Update state (works for both web and desktop)
          if (mounted) {
            setState(() {
              _contacts = contacts;
              _filteredContacts = contacts;
              _loading = false;
            });
            _applySearchAndSort();
          }
      
      // Store in Hive for offline capability (mobile/desktop)
      if (!kIsWeb) {
        try {
          final contactsBox = Hive.box<Contact>(DummyDataService.contactsBoxName);
          await contactsBox.clear();
          for (var contact in contacts) {
            await contactsBox.put(contact.id, contact);
          }
        } catch (e) {
          // Hive might not be initialized, that's okay
          print('⚠️ Could not store in Hive: $e');
        }
      }
    } catch (e) {
      // If online fails, try to load from Hive (offline)
      if (!kIsWeb) {
        try {
          final contactsBox = Hive.box<Contact>(DummyDataService.contactsBoxName);
          final contacts = contactsBox.values.cast<Contact>().toList();
          if (mounted) {
            setState(() {
              _contacts = contacts;
              _loading = false;
              _error = 'Offline - showing cached data';
            });
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

  int _calculateTotalBalance() {
    // Use state directly (works for both web and desktop)
    if (_contacts != null && _contacts!.isNotEmpty) {
      return _contacts!.fold<int>(0, (sum, contact) => sum + contact.balance);
    }
    return 0;
  }

  
  String _formatBalance(int balance) {
    // Balance is stored as whole units (IQD), not cents
    if (balance == 0) return '0 IQD';
    // Format with commas for thousands
    final absBalance = balance.abs();
    final formatted = absBalance.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return balance < 0 ? '-$formatted IQD' : '$formatted IQD';
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
                          await ApiService.bulkDeleteContacts(_selectedContacts.toList());
                          if (mounted) {
                            setState(() {
                              _selectedContacts.clear();
                              _selectionMode = false;
                            });
                            _loadContacts();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('✅ ${_selectedContacts.length} contact(s) deleted'),
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
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
                final result = await Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const AddContactScreen()),
                );
                // Refresh if contact was created
                if (result == true && mounted) {
                  _loadContacts();
                }
              },
              tooltip: 'Add Contact',
            ),
            IconButton(
              icon: Icon(_selectionMode ? Icons.check_box : Icons.check_box_outline_blank),
              onPressed: () {
                setState(() {
                  _selectionMode = !_selectionMode;
                  if (!_selectionMode) {
                    _selectedContacts.clear();
                  }
                });
              },
              tooltip: 'Select',
            ),
          ],
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadContacts,
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
            final totalBalance = _calculateTotalBalance();

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
                            color: Colors.green,
                            child: const Icon(Icons.add, color: Colors.white),
                          ),
                          confirmDismiss: (direction) async {
                            // Open new transaction screen with this contact (swipe right)
                            final result = await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => AddTransactionScreen(contact: contact),
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
