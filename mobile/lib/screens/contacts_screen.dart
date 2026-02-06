// ignore_for_file: unused_import, unused_field

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart';
import '../models/contact.dart';
import '../models/transaction.dart';
import '../widgets/contact_list_item.dart';
import '../widgets/diff_animated_list.dart';
import '../widgets/flash_on_change.dart';
import '../widgets/sync_status_icon.dart';
import 'add_contact_screen.dart';
import 'contact_transactions_screen.dart';
import 'add_transaction_screen.dart';
import '../utils/bottom_sheet_helper.dart';
import '../providers/settings_provider.dart';
import '../providers/wallet_data_providers.dart';
import '../utils/app_colors.dart';
import '../utils/toast_service.dart';

class ContactsScreen extends ConsumerStatefulWidget {
  final VoidCallback? onOpenDrawer;
  final VoidCallback? onNavigateToDashboard;
  
  const ContactsScreen({super.key, this.onOpenDrawer, this.onNavigateToDashboard});

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
  bool _loading = false; // Local busy state for UI actions (not initial data load)
  ContactSortOption _sortOption = ContactSortOption.alphabetical;
  Set<String> _selectedContacts = {}; // For multi-select
  bool _selectionMode = false;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  Color? _defaultDirectionColor; // Color for default direction (for swipe background)
  List<Contact> _lastValidContacts = []; // Cache to prevent flash on refresh

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _searchController.addListener(_onSearchChanged);
    Api.connectRealtime();
  }


  Future<void> _loadSettings() async {
    final defaultDir = await Api.getDefaultDirection();
    _updateSwipeColor(defaultDir);
  }

  void _updateSwipeColor(String defaultDir) {
    // Watch flipColors provider so it updates when settings change
    final flipColors = ref.read(flipColorsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (mounted) {
      setState(() {
        // Set color based on default direction: received = red, give = green (respects flipColors)
        _defaultDirectionColor = defaultDir == 'received'
            ? AppColors.getReceivedColor(flipColors, isDark)
            : AppColors.getGiveColor(flipColors, isDark);
      });
    }
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

  List<Contact> _filterAndSortContacts(List<Contact> contacts) {
    final query = _searchController.text.toLowerCase().trim();
    var filtered = contacts;

    if (query.isNotEmpty) {
      filtered = filtered.where((contact) {
        return contact.name.toLowerCase().contains(query) ||
            (contact.username?.toLowerCase().contains(query) ?? false) ||
            (contact.phone?.toLowerCase().contains(query) ?? false) ||
            (contact.email?.toLowerCase().contains(query) ?? false) ||
            (contact.notes?.toLowerCase().contains(query) ?? false);
      }).toList();
    } else {
      // Avoid copying when no filtering is required.
      filtered = List<Contact>.from(filtered);
    }

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
    return filtered;
  }

  Future<void> _refreshContacts({bool sync = false}) async {
    setState(() => _loading = true);
    try {
      if (sync && !kIsWeb) {
        await Api.manualSync().catchError((_) {});
      }
      // Providers will refetch from Rust. This keeps refresh work scoped to mounted screens.
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
            _selectedContacts.clear();
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
                          await Api.bulkDeleteContacts(deletedIds);
                          
                          // Check mounted before any UI operations
                          if (!mounted) return;
                          
                          setState(() {
                            _selectedContacts.clear();
                            _selectionMode = false;
                            _loading = false;
                          });
                          
                          // ContactsProvider will refresh via DataBus; ensure UI picks it up.
                          ref.invalidate(contactsProvider);
                          
                          // Show undo toast for all deletes (single or bulk) - always show, even in offline mode
                          // Use a small delay to ensure context is stable
                          await Future.delayed(const Duration(milliseconds: 100));
                          
                          // Check mounted again before showing toast
                          if (!mounted) {
                            // Use global toast service if context is deactivated
                            ToastService.showUndoWithErrorHandling(
                              message: '✅ $deletedCount contact(s) deleted',
                              onUndo: () async {
                                try {
                                  for (final id in deletedIds) {
                                    await Api.undoContactAction(id);
                                  }
                                } catch (e) {
                                  // Error handled by ToastService
                                }
                              },
                              successMessage: '${deletedIds.length} contact(s) deletion undone',
                            );
                            return;
                          }
                          
                          ToastService.showUndoWithErrorHandlingFromContext(
                            context: context,
                            message: '✅ $deletedCount contact(s) deleted',
                            onUndo: () async {
                              if (!mounted) return;
                              try {
                                for (final id in deletedIds) {
                                  await Api.undoContactAction(id);
                                }
                                if (mounted) ref.invalidate(contactsProvider);
                              } catch (e) {
                                // Error handled by ToastService
                              }
                            },
                            successMessage: '${deletedIds.length} contact(s) deletion undone',
                          );
                        } catch (e) {
                          // Check mounted before showing error
                          if (!mounted) return;
                          
                          // Use global toast service if context is deactivated
                          ToastService.showErrorFromContext(context, 'Error deleting contacts: $e');
                          
                          if (mounted) {
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
          ],
          if (!_selectionMode && !_isSearching)
            const Padding(
              padding: EdgeInsets.only(left: 24.0, right: 20.0),
              child: SyncStatusIcon(),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refreshContacts(sync: true),
        child: Builder(
          builder: (context) {
            // if (_loading) {
            //   return const Center(child: CircularProgressIndicator());
            // }

            final contactsAsync = ref.watch(contactsProvider);
            
            // Update cache if we have a value
            if (contactsAsync.hasValue) {
              _lastValidContacts = contactsAsync.value!;
            }
            
            final baseContacts = contactsAsync.valueOrNull ?? _lastValidContacts;

            if (contactsAsync.hasError && baseContacts.isEmpty) {
              final e = contactsAsync.error;
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Error: $e', style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => _refreshContacts(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }

            if (contactsAsync.isLoading && baseContacts.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            final contacts = _filterAndSortContacts(baseContacts);

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

            return Column(
              children: [
                if (contactsAsync.isLoading) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: DiffAnimatedList<Contact>(
                    items: contacts,
                    itemId: (c) => c.id,
                    padding: const EdgeInsets.only(bottom: 32),
                    itemBuilder: (context, contact, animation) {
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
                            : () {
                                // Long press starts selection mode
                                setState(() {
                                  _selectionMode = true;
                                  _selectedContacts.add(contact.id);
                                });
                              },
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
                      
                      // Wrap with FlashOnChange if not in selection mode
                      if (!_selectionMode) {
                        contactItem = FlashOnChange(
                          signature: '${contact.id}|${contact.name}|${contact.username}|${contact.balance}|${contact.updatedAt.millisecondsSinceEpoch}',
                          child: contactItem,
                        );
                      }

                      // Wrap with Dismissible for swipe actions (only when not in selection mode)
                      Widget currentItem;
                      if (!_selectionMode) {
                        currentItem = Dismissible(
                          key: Key(contact.id),
                          direction: DismissDirection.startToEnd, // Only swipe right (LTR)
                          dismissThresholds: const {
                            DismissDirection.startToEnd: 0.7, // Require 70% swipe for add transaction
                          },
                          movementDuration: const Duration(milliseconds: 300), // Slower animation
                          background: Consumer(
                            builder: (context, ref, child) {
                              final flipColors = ref.watch(flipColorsProvider);
                              final isDark = Theme.of(context).brightness == Brightness.dark;
                              return FutureBuilder<String>(
                                future: Api.getDefaultDirection(),
                                builder: (context, snapshot) {
                                  final defaultDir = snapshot.data ?? 'received';
                                  // Set color based on default direction: received = red, give = green (respects flipColors)
                                  final swipeColor = defaultDir == 'received'
                                      ? AppColors.getReceivedColor(flipColors, isDark)
                                      : AppColors.getGiveColor(flipColors, isDark);
                                  // Capitalize first letter: "received" -> "Received", "give" -> "Gave"
                                  final directionText = defaultDir == 'received' 
                                      ? 'Received' 
                                      : 'Gave';
                                  return Container(
                                    alignment: Alignment.centerLeft,
                                    padding: const EdgeInsets.only(left: 20),
                                    color: swipeColor,
                                    child: Text(
                                      directionText,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                          confirmDismiss: (direction) async {
                            // Open new transaction screen with this contact (swipe right) using default direction
                            final defaultDir = await Api.getDefaultDirection();
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
                              ref.invalidate(contactsProvider);
                            }
                            return false; // Don't dismiss the contact item
                          },
                          child: contactItem,
                        );
                      } else {
                         // In selection mode, we just return the item (it has its own tap handlers)
                         currentItem = contactItem;
                      }

                      return SizeTransition(
                        key: ValueKey(contact.id),
                        sizeFactor: animation,
                        child: FadeTransition(opacity: animation, child: currentItem),
                      );
                    },
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
}