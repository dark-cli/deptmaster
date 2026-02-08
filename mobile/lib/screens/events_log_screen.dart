// ignore_for_file: unused_element

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import '../models/contact.dart';
import '../models/event.dart';
import '../models/wallet.dart';
import '../providers/wallet_data_providers.dart';
import '../utils/app_colors.dart';
import '../utils/theme_colors.dart';
import '../utils/event_formatter.dart';
import '../utils/state_builder.dart';
import '../widgets/empty_state.dart';
import '../widgets/gradient_background.dart';

class EventsLogScreen extends ConsumerStatefulWidget {
  final DateTime? initialDateFrom;
  final DateTime? initialDateTo;
  
  const EventsLogScreen({
    super.key,
    this.initialDateFrom,
    this.initialDateTo,
  });

  @override
  ConsumerState<EventsLogScreen> createState() => _EventsLogScreenState();
}

class _EventsLogScreenState extends ConsumerState<EventsLogScreen> {
  List<Event> _allEvents = [];
  List<Event> _filteredEvents = [];
  bool _loading = true;
  bool _showFilters = false; // Collapsible filters for mobile
  bool _isReloading = false; // Guard to prevent infinite loops
  
  // Wallet selection (events are scoped to selected wallet)
  List<Wallet> _wallets = [];
  String? _selectedWalletId;
  bool _walletsLoading = true;
  
  // Filters
  String _searchQuery = '';
  String _eventTypeFilter = 'all';
  String _aggregateTypeFilter = 'all';
  DateTime? _dateFrom;
  DateTime? _dateTo;

  @override
  void initState() {
    super.initState();
    _dateFrom = widget.initialDateFrom;
    _dateTo = widget.initialDateTo;
    _loadWalletsThenEvents();
    Api.connectRealtime();

    // Keep the existing filtering/pagination logic, but source events reactively.
    _eventsSub = ref.listenManual<AsyncValue<List<Event>>>(eventsProvider, (previous, next) async {
      if (!mounted) return;

      // Keep showing existing list while loading.
      if (next.isLoading && (next.valueOrNull == null || next.valueOrNull!.isEmpty)) {
        if (_allEvents.isEmpty) {
          setState(() => _loading = true);
        }
        return;
      }

      final events = next.valueOrNull;
      if (events == null) return;

      // Sort newest first for consistent ordering
      final sorted = List<Event>.from(events)..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // Build caches
      await _preloadUndoneEvents(sorted);
      // Contact caches can be built from provider data (fast), plus fallback to CREATED events.
      final contacts = ref.read(contactsProvider).valueOrNull ?? const <Contact>[];
      _contactNameCache = {for (final c in contacts) c.id: c.name};
      _contactUsernameCache = {
        for (final c in contacts)
          if (c.username != null && c.username!.isNotEmpty) c.id: c.username!,
      };
      for (final event in sorted) {
        if (event.aggregateType == 'contact' &&
            (event.eventType == 'CREATED' || event.eventType.contains('CREATE'))) {
          final name = event.eventData['name']?.toString();
          final username = event.eventData['username']?.toString();
          if (name != null && name.isNotEmpty) {
            _contactNameCache[event.aggregateId] = name;
          }
          if (username != null && username.isNotEmpty) {
            _contactUsernameCache[event.aggregateId] = username;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _allEvents = sorted;
        _loading = false;
      });
      _applyFilters();
    }, fireImmediately: true);
  }

  Future<void> _loadWalletsThenEvents() async {
    setState(() {
      _walletsLoading = true;
    });
    try {
      final list = await Api.getWallets();
      final wallets = list.map((m) => Wallet.fromJson(m)).toList();
      final currentId = await Api.getCurrentWalletId();
      final validId = currentId != null && wallets.any((w) => w.id == currentId);
      final newSelected = wallets.isNotEmpty ? (validId ? currentId : wallets.first.id) : null;
      if (!validId && newSelected != null) {
        await Api.setCurrentWalletId(newSelected);
      }
      if (mounted) {
        setState(() {
          _wallets = wallets;
          _walletsLoading = false;
          _selectedWalletId = newSelected;
        });
        await _loadEvents();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _walletsLoading = false;
        });
        await _loadEvents();
      }
    }
  }
  
  // Pagination
  int _currentPage = 0;
  int _pageSize = 50; // Smaller default for mobile
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  // Caches for event formatting
  Map<String, String> _contactNameCache = {};
  Map<String, String> _contactUsernameCache = {}; // Cache for contact usernames
  Map<String, Event> _undoneEventsCache = {};
  ProviderSubscription<AsyncValue<List<Event>>>? _eventsSub;


  @override
  void dispose() {
    _eventsSub?.close();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _onWalletSelected(String? walletId) async {
    if (walletId == null || walletId == _selectedWalletId) return;
    setState(() {
      _selectedWalletId = walletId;
    });
    await Api.setCurrentWalletId(walletId);
    if (mounted) await _loadEvents();
    if (!kIsWeb) {
      Api.manualSync().catchError((_) {});
    }
  }

  Future<void> _loadEvents() async {
    if (!mounted) return;
    setState(() => _loading = true);
    // Trigger reactive reload.
    ref.invalidate(eventsProvider);
  }
  
  Future<void> _preloadContactNames(List<Event> events) async {
    if (!mounted) return;
    
    _contactNameCache.clear();
    _contactUsernameCache.clear();
    
    // Collect all contact IDs
    final contactIds = <String>{};
    for (final event in events) {
      if (!mounted) return;
      if (event.aggregateType == 'contact') {
        contactIds.add(event.aggregateId);
      } else if (event.aggregateType == 'transaction') {
        final contactId = event.eventData['contact_id']?.toString();
        if (contactId != null) {
          contactIds.add(contactId);
        }
      }
    }
    
    for (final contactId in contactIds) {
      if (!mounted) return;
      try {
        final jsonStr = await Api.getContact(contactId);
        if (jsonStr != null && mounted) {
          final contact = Contact.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
          _contactNameCache[contactId] = contact.name;
          if (contact.username != null && contact.username!.isNotEmpty) {
            _contactUsernameCache[contactId] = contact.username!;
          }
        }
      } catch (e) {
        // Contact might not exist, continue
        // Don't show error - this is expected for deleted contacts
      }
    }
    
    if (!mounted) return;
    
    // Also cache names and usernames from CREATED events
    for (final event in events) {
      if (!mounted) return;
      if (event.aggregateType == 'contact' && 
          (event.eventType == 'CREATED' || event.eventType.contains('CREATE'))) {
        final name = event.eventData['name']?.toString();
        final username = event.eventData['username']?.toString();
        if (name != null) {
          _contactNameCache[event.aggregateId] = name;
        }
        if (username != null && username.isNotEmpty) {
          _contactUsernameCache[event.aggregateId] = username;
        }
      }
    }
  }
  
  Future<void> _preloadUndoneEvents(List<Event> events) async {
    if (!mounted) return;
    
    _undoneEventsCache.clear();
    
    // Collect all undone event IDs
    final undoneEventIds = <String>{};
    for (final event in events) {
      if (!mounted) return;
      if (event.eventType.toUpperCase() == 'UNDO') {
        final undoneEventId = event.eventData['undone_event_id'] as String?;
        if (undoneEventId != null) {
          undoneEventIds.add(undoneEventId);
        }
      }
    }
    
    if (!mounted) return;
    
    // Find undone events in the current batch
    for (final event in events) {
      if (!mounted) return;
      if (undoneEventIds.contains(event.id)) {
        _undoneEventsCache[event.id] = event;
      }
    }
  }

  void _applyFilters() {
    List<Event> filtered = List.from(_allEvents);

    // Search filter - search only in contact name and username (same as contact list page)
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase().trim();
      filtered = filtered.where((e) {
        final eventData = e.eventData;
        
        // Get contact name
        String? contactName;
        if (e.aggregateType == 'contact') {
          contactName = eventData['name']?.toString().toLowerCase();
          if (contactName == null) {
            contactName = _contactNameCache[e.aggregateId]?.toLowerCase();
          }
          if (contactName == null) {
            final deletedContact = eventData['deleted_contact'];
            if (deletedContact != null && deletedContact is Map) {
              contactName = deletedContact['name']?.toString().toLowerCase();
            }
          }
        } else if (e.aggregateType == 'transaction') {
          final contactId = eventData['contact_id']?.toString();
          if (contactId != null) {
            contactName = _contactNameCache[contactId]?.toLowerCase();
          }
          if (contactName == null) {
            final deletedTransaction = eventData['deleted_transaction'];
            if (deletedTransaction != null && deletedTransaction is Map) {
              final deletedContactId = deletedTransaction['contact_id']?.toString();
              if (deletedContactId != null) {
                contactName = _contactNameCache[deletedContactId]?.toLowerCase();
              }
            }
          }
        }
        
        // Get username
        String? username;
        if (e.aggregateType == 'contact') {
          username = _contactUsernameCache[e.aggregateId]?.toLowerCase();
          if (username == null) {
            username = eventData['username']?.toString().toLowerCase();
          }
          if (username == null) {
            final deletedContact = eventData['deleted_contact'];
            if (deletedContact != null && deletedContact is Map) {
              username = deletedContact['username']?.toString().toLowerCase();
            }
          }
        } else if (e.aggregateType == 'transaction') {
          final contactId = eventData['contact_id']?.toString();
          if (contactId != null) {
            username = _contactUsernameCache[contactId]?.toLowerCase();
            if (username == null) {
              final contactEvent = _allEvents.firstWhere(
                (evt) => evt.aggregateType == 'contact' &&
                         evt.aggregateId == contactId &&
                         (evt.eventType == 'CREATED' || evt.eventType.contains('CREATE')),
                orElse: () => e,
              );
              if (contactEvent != e) {
                username = contactEvent.eventData['username']?.toString().toLowerCase();
              }
            }
          }
          if (username == null) {
            final deletedTransaction = eventData['deleted_transaction'];
            if (deletedTransaction != null && deletedTransaction is Map) {
              final deletedContactId = deletedTransaction['contact_id']?.toString();
              if (deletedContactId != null) {
                username = _contactUsernameCache[deletedContactId]?.toLowerCase();
              }
            }
          }
        }
        
        // Get comment
        final comment = eventData['comment']?.toString().toLowerCase() ?? '';
        
        // Search in contact name, username, and comment
        return (contactName != null && contactName.contains(query)) ||
               (username != null && username.contains(query)) ||
               comment.contains(query);
      }).toList();
    }

    // Event type filter
    if (_eventTypeFilter != 'all') {
      filtered = filtered.where((e) => e.eventType == _eventTypeFilter).toList();
    }

    // Aggregate type filter
    if (_aggregateTypeFilter != 'all') {
      filtered = filtered.where((e) => e.aggregateType == _aggregateTypeFilter).toList();
    }

    // Date filters
    if (_dateFrom != null) {
      filtered = filtered.where((e) => e.timestamp.isAfter(_dateFrom!) || 
          e.timestamp.isAtSameMomentAs(_dateFrom!)).toList();
    }
    if (_dateTo != null) {
      final dateToEnd = DateTime(_dateTo!.year, _dateTo!.month, _dateTo!.day, 23, 59, 59);
      filtered = filtered.where((e) => e.timestamp.isBefore(dateToEnd) || 
          e.timestamp.isAtSameMomentAs(dateToEnd)).toList();
    }

    // Sort by timestamp (newest first)
    filtered.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    setState(() {
      _filteredEvents = filtered;
      _currentPage = 0; // Reset to first page when filters change
    });
    
    // Scroll to top when filters change
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }
  
  void _goToPage(int page) {
    if (page >= 0 && page < _totalPages) {
      setState(() {
        _currentPage = page;
      });
      // Scroll to top when page changes
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _eventTypeFilter = 'all';
      _aggregateTypeFilter = 'all';
      _dateFrom = null;
      _dateTo = null;
      _currentPage = 0;
    });
    _applyFilters();
  }

  List<Event> get _paginatedEvents {
    final start = _currentPage * _pageSize;
    final end = (start + _pageSize).clamp(0, _filteredEvents.length);
    return _filteredEvents.sublist(start.clamp(0, _filteredEvents.length), end);
  }

  int get _totalPages => (_filteredEvents.length / _pageSize).ceil();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateFormat = DateFormat('M/d/yyyy, h:mm:ss a');
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Events Log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {
              setState(() {
                _showFilters = !_showFilters;
              });
            },
            tooltip: 'Toggle Filters',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadEvents,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Wallet selector
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.account_balance_wallet, size: 20, color: ThemeColors.gray(context)),
                const SizedBox(width: 8),
                Text(
                  'Wallet:',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: ThemeColors.gray(context),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _walletsLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : _wallets.isEmpty
                          ? Text(
                              'No wallets',
                              style: TextStyle(
                                color: ThemeColors.gray(context),
                                fontStyle: FontStyle.italic,
                              ),
                            )
                          : DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedWalletId,
                                isExpanded: true,
                                items: _wallets.map((w) {
                                  return DropdownMenuItem<String>(
                                    value: w.id,
                                    child: Text(
                                      w.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList(),
                                onChanged: _onWalletSelected,
                              ),
                            ),
                ),
              ],
            ),
          ),
          // Search Bar (always visible)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: TextField(
              controller: _searchController,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                hintText: 'Search all event fields...',
                hintStyle: TextStyle(
                  color: ThemeColors.gray(context),
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: ThemeColors.gray(context),
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.clear,
                          color: ThemeColors.gray(context),
                        ),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                          _applyFilters();
                        },
                      )
                    : null,
                filled: true,
                fillColor: isDark
                    ? AppColors.darkSurfaceVariant
                    : AppColors.lightSurfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Theme.of(context).dividerColor,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Theme.of(context).dividerColor,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                    width: 2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
                _applyFilters();
              },
            ),
          ),
          
          // Collapsible Filter Section
          if (_showFilters)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Filters - Stack vertically on mobile
                  if (isMobile) ...[
                    // Event Type
                    DropdownButtonFormField<String>(
                      value: _eventTypeFilter,
                      decoration: InputDecoration(
                        labelText: 'Event Type',
                        filled: true,
                        fillColor: isDark
                            ? AppColors.darkSurfaceVariant
                            : AppColors.lightSurfaceVariant,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All')),
                        DropdownMenuItem(value: 'CREATED', child: Text('Created')),
                        DropdownMenuItem(value: 'UPDATED', child: Text('Updated')),
                        DropdownMenuItem(value: 'DELETED', child: Text('Deleted')),
                        DropdownMenuItem(value: 'UNDO', child: Text('Undo')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _eventTypeFilter = value ?? 'all';
                        });
                        _applyFilters();
                      },
                    ),
                    const SizedBox(height: 12),
                    // Aggregate Type
                    DropdownButtonFormField<String>(
                      value: _aggregateTypeFilter,
                      decoration: InputDecoration(
                        labelText: 'Type',
                        filled: true,
                        fillColor: isDark
                            ? AppColors.darkSurfaceVariant
                            : AppColors.lightSurfaceVariant,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All')),
                        DropdownMenuItem(value: 'contact', child: Text('Contact')),
                        DropdownMenuItem(value: 'transaction', child: Text('Transaction')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _aggregateTypeFilter = value ?? 'all';
                        });
                        _applyFilters();
                      },
                    ),
                    const SizedBox(height: 12),
                    // Date From
                    InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _dateFrom ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (date != null) {
                          setState(() {
                            _dateFrom = date;
                          });
                          _applyFilters();
                        }
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Date From',
                          filled: true,
                          fillColor: isDark
                              ? AppColors.darkSurfaceVariant
                              : AppColors.lightSurfaceVariant,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                              width: 2,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          suffixIcon: Icon(
                            Icons.calendar_today,
                            color: ThemeColors.gray(context),
                          ),
                        ),
                        child: Text(
                          _dateFrom != null
                              ? DateFormat('yyyy-MM-dd').format(_dateFrom!)
                              : 'Select date',
                          style: TextStyle(
                            color: _dateFrom != null
                                ? null
                                : ThemeColors.gray(context),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Date To
                    InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _dateTo ?? DateTime.now(),
                          firstDate: _dateFrom ?? DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (date != null) {
                          setState(() {
                            _dateTo = date;
                          });
                          _applyFilters();
                        }
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Date To',
                          filled: true,
                          fillColor: isDark
                              ? AppColors.darkSurfaceVariant
                              : AppColors.lightSurfaceVariant,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                              width: 2,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          suffixIcon: Icon(
                            Icons.calendar_today,
                            color: ThemeColors.gray(context),
                          ),
                        ),
                        child: Text(
                          _dateTo != null
                              ? DateFormat('yyyy-MM-dd').format(_dateTo!)
                              : 'Select date',
                          style: TextStyle(
                            color: _dateTo != null
                                ? null
                                : ThemeColors.gray(context),
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    // Desktop: Horizontal layout
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: 150,
                          child: DropdownButtonFormField<String>(
                            value: _eventTypeFilter,
                            decoration: InputDecoration(
                              labelText: 'Event Type',
                              filled: true,
                              fillColor: isDark
                                  ? AppColors.darkSurfaceVariant
                                  : AppColors.lightSurfaceVariant,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Theme.of(context).dividerColor,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Theme.of(context).dividerColor,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                                  width: 2,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'all', child: Text('All')),
                              DropdownMenuItem(value: 'CREATED', child: Text('Created')),
                              DropdownMenuItem(value: 'UPDATED', child: Text('Updated')),
                              DropdownMenuItem(value: 'DELETED', child: Text('Deleted')),
                              DropdownMenuItem(value: 'UNDO', child: Text('Undo')),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _eventTypeFilter = value ?? 'all';
                              });
                              _applyFilters();
                            },
                          ),
                        ),
                        SizedBox(
                          width: 150,
                          child: DropdownButtonFormField<String>(
                            value: _aggregateTypeFilter,
                            decoration: InputDecoration(
                              labelText: 'Type',
                              filled: true,
                              fillColor: isDark
                                  ? AppColors.darkSurfaceVariant
                                  : AppColors.lightSurfaceVariant,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Theme.of(context).dividerColor,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Theme.of(context).dividerColor,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                                  width: 2,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'all', child: Text('All')),
                              DropdownMenuItem(value: 'contact', child: Text('Contact')),
                              DropdownMenuItem(value: 'transaction', child: Text('Transaction')),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _aggregateTypeFilter = value ?? 'all';
                              });
                              _applyFilters();
                            },
                          ),
                        ),
                        SizedBox(
                          width: 150,
                          child: InkWell(
                            onTap: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: _dateFrom ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now(),
                              );
                              if (date != null) {
                                setState(() {
                                  _dateFrom = date;
                                });
                                _applyFilters();
                              }
                            },
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: 'Date From',
                                filled: true,
                                fillColor: isDark
                                    ? AppColors.darkSurfaceVariant
                                    : AppColors.lightSurfaceVariant,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: Theme.of(context).dividerColor,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: Theme.of(context).dividerColor,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                                    width: 2,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                suffixIcon: Icon(
                                  Icons.calendar_today,
                                  color: ThemeColors.gray(context),
                                ),
                              ),
                              child: Text(
                                _dateFrom != null
                                    ? DateFormat('yyyy-MM-dd').format(_dateFrom!)
                                    : 'Select date',
                                style: TextStyle(
                                  color: _dateFrom != null
                                      ? null
                                      : ThemeColors.gray(context),
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 150,
                          child: InkWell(
                            onTap: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: _dateTo ?? DateTime.now(),
                                firstDate: _dateFrom ?? DateTime(2020),
                                lastDate: DateTime.now(),
                              );
                              if (date != null) {
                                setState(() {
                                  _dateTo = date;
                                });
                                _applyFilters();
                              }
                            },
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: 'Date To',
                                filled: true,
                                fillColor: isDark
                                    ? AppColors.darkSurfaceVariant
                                    : AppColors.lightSurfaceVariant,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: Theme.of(context).dividerColor,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: Theme.of(context).dividerColor,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                                    width: 2,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                suffixIcon: Icon(
                                  Icons.calendar_today,
                                  color: ThemeColors.gray(context),
                                ),
                              ),
                              child: Text(
                                _dateTo != null
                                    ? DateFormat('yyyy-MM-dd').format(_dateTo!)
                                    : 'Select date',
                                style: TextStyle(
                                  color: _dateTo != null
                                      ? null
                                      : ThemeColors.gray(context),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  // Action Buttons - Stack on mobile
                  if (isMobile) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _applyFilters,
                        icon: const Icon(Icons.filter_list),
                        label: const Text('Apply Filters'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                          foregroundColor: isDark ? AppColors.darkOnPrimary : AppColors.lightOnPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _clearFilters,
                        icon: const Icon(Icons.clear),
                        label: const Text('Clear Filters'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                          side: BorderSide(
                            color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: _applyFilters,
                          icon: const Icon(Icons.filter_list),
                          label: const Text('Apply'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                            foregroundColor: isDark ? AppColors.darkOnPrimary : AppColors.lightOnPrimary,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _clearFilters,
                          icon: const Icon(Icons.clear),
                          label: const Text('Clear'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                            side: BorderSide(
                              color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          
          // Info Bar with count and page size
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkSurfaceVariant
                  : AppColors.lightSurfaceVariant,
              border: Border(
                bottom: BorderSide(
                  color: isDark ? AppColors.darkGray : AppColors.lightGray,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_filteredEvents.length} event(s)',
                    style: TextStyle(
                      color: ThemeColors.gray(context),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (!isMobile) ...[
                  const Text('Page Size: '),
                  SizedBox(
                    width: 70,
                    child: DropdownButton<int>(
                      value: _pageSize,
                      isDense: true,
                      items: const [
                        DropdownMenuItem(value: 25, child: Text('25')),
                        DropdownMenuItem(value: 50, child: Text('50')),
                        DropdownMenuItem(value: 100, child: Text('100')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _pageSize = value ?? 50;
                          _currentPage = 0;
                        });
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          // Pagination
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkSurfaceVariant
                  : AppColors.lightSurfaceVariant,
              border: Border(
                bottom: BorderSide(
                  color: isDark ? AppColors.darkGray : AppColors.lightGray,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Page ${_currentPage + 1} of ${_totalPages == 0 ? 1 : _totalPages}',
                    style: TextStyle(
                      color: ThemeColors.gray(context),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _currentPage > 0
                          ? () => _goToPage(_currentPage - 1)
                          : null,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: _currentPage > 0
                          ? (isDark ? AppColors.darkPrimary : AppColors.lightPrimary)
                          : ThemeColors.gray(context),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _currentPage < _totalPages - 1
                          ? () => _goToPage(_currentPage + 1)
                          : null,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: _currentPage < _totalPages - 1
                          ? (isDark ? AppColors.darkPrimary : AppColors.lightPrimary)
                          : ThemeColors.gray(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Events List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _paginatedEvents.isEmpty
                    ? const EmptyState(
                        icon: Icons.event_note_outlined,
                        title: 'No events found',
                        subtitle: 'Events will appear here as you add and edit transactions.',
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: _paginatedEvents.length,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemBuilder: (context, index) {
                          final event = _paginatedEvents[index];
                          return EventTableRow(
                            key: ValueKey('${event.id}_${_contactNameCache.length}_${_undoneEventsCache.length}'),
                            event: event,
                            dateFormat: dateFormat,
                            allEvents: _allEvents,
                            contactNameCache: _contactNameCache,
                            undoneEventsCache: _undoneEventsCache,
                            isMobile: isMobile,
                          );
                        },
                      ),
          ),
        ],
      ),
      ),
    );
  }
}

class EventTableRow extends StatefulWidget {
  final Event event;
  final DateFormat dateFormat;
  final List<Event> allEvents;
  final Map<String, String> contactNameCache;
  final Map<String, Event> undoneEventsCache;
  final bool isMobile;

  const EventTableRow({
    super.key,
    required this.event,
    required this.dateFormat,
    required this.allEvents,
    required this.contactNameCache,
    required this.undoneEventsCache,
    required this.isMobile,
  });

  @override
  State<EventTableRow> createState() => _EventTableRowState();
}

class _EventTableRowState extends State<EventTableRow> {
  String? _contactName;
  String? _contactUsername;
  AmountDisplay? _amount;
  int? _totalDebt;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(EventTableRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload data if event changed or caches were updated
    if (oldWidget.event.id != widget.event.id ||
        oldWidget.contactNameCache.length != widget.contactNameCache.length ||
        oldWidget.undoneEventsCache.length != widget.undoneEventsCache.length) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    final eventData = widget.event.eventData;
    
    // Load contact name using standardized formatter
    final contactName = await EventFormatter.getContactName(
      widget.event,
      widget.contactNameCache,
      widget.undoneEventsCache,
      widget.allEvents,
    );
    
    // Load contact username using standardized formatter
    final contactUsername = await EventFormatter.getContactUsername(
      widget.event,
      widget.contactNameCache,
      widget.undoneEventsCache,
      widget.allEvents,
    );
    
    // Load amount
    final amount = await EventFormatter.getAmount(
      widget.event,
      widget.undoneEventsCache,
      widget.allEvents,
    );
    
    // Load total debt
    final totalDebtFromEvent = eventData['total_debt'];
    int? totalDebt;
    if (totalDebtFromEvent != null) {
      totalDebt = (totalDebtFromEvent as num?)?.toInt();
    } else {
      try {
        totalDebt = StateBuilder.calculateTotalDebtFromEvents(widget.allEvents, widget.event.timestamp);
      } catch (e) {
        print('Error calculating total debt: $e');
        totalDebt = 0;
      }
    }
    
        if (mounted) {
          setState(() {
        _contactName = contactName;
        _contactUsername = contactUsername;
        _amount = amount;
        _totalDebt = totalDebt;
        _loading = false;
          });
    }
  }

  Color _getEventBadgeColor(String eventType, bool isDark) {
    final eventTypeUpper = eventType.toUpperCase();
    if (eventTypeUpper.contains('CREATED') || eventTypeUpper.contains('CREATE')) {
        return isDark ? AppColors.darkSuccess : AppColors.lightSuccess;
    } else if (eventTypeUpper.contains('UPDATED') || eventTypeUpper.contains('UPDATE') || 
               eventTypeUpper == 'UNDO') {
        return isDark ? AppColors.darkWarning : AppColors.lightWarning;
    } else if (eventTypeUpper.contains('DELETED') || eventTypeUpper.contains('DELETE')) {
      return isDark ? AppColors.darkWarning : AppColors.lightWarning; // Same as UPDATE
    }
        return isDark ? AppColors.darkGray : AppColors.lightGray;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    if (widget.isMobile) {
      // Mobile: Card-like row with all columns stacked
    return Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: InkWell(
          onTap: () {
            // Show event details modal
            _showEventDetails(context);
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                // When, Sync Status, and Event Type
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.dateFormat.format(widget.event.timestamp),
                        style: TextStyle(
                          fontSize: 11,
                          color: ThemeColors.gray(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Sync Status Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: widget.event.synced
                            ? (isDark 
                                ? AppColors.darkSuccess.withOpacity(0.2)
                                : AppColors.lightSuccess.withOpacity(0.2))
                            : (isDark
                                ? AppColors.darkWarning.withOpacity(0.2)
                                : AppColors.lightWarning.withOpacity(0.2)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.event.synced ? Icons.cloud_done : Icons.cloud_upload,
                            size: 12,
                            color: widget.event.synced
                                ? (isDark ? AppColors.darkSuccess : AppColors.lightSuccess)
                                : (isDark ? AppColors.darkWarning : AppColors.lightWarning),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            widget.event.synced ? 'Synced' : 'Pending',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: widget.event.synced
                                  ? (isDark ? AppColors.darkSuccess : AppColors.lightSuccess)
                                  : (isDark ? AppColors.darkWarning : AppColors.lightWarning),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
                        color: _getEventBadgeColor(widget.event.eventType, isDark).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
          ),
            child: Text(
                        EventFormatter.formatEventType(widget.event, widget.undoneEventsCache),
              style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _getEventBadgeColor(widget.event.eventType, isDark),
              ),
            ),
          ),
                  ],
                ),
                const SizedBox(height: 8),
                // Contact Name with Username tag
                if (_contactName != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
                        Text(
                          'Name:',
                          style: TextStyle(
                            fontSize: 11,
                            color: ThemeColors.gray(context),
                            fontWeight: FontWeight.w500,
                  ),
                ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Row(
                            children: [
                              if (_contactUsername != null)
                Container(
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark
                                        ? AppColors.darkPrimary.withOpacity(0.3) // Light purple with opacity for dark mode
                                        : const Color(0xFFE8E0EC), // Light purple background for light mode
                                    borderRadius: BorderRadius.circular(4),
                                    border: isDark
                                        ? Border.all(
                                            color: AppColors.darkPrimary.withOpacity(0.5),
                                            width: 1,
                                          )
                                        : null,
                  ),
                  child: Text(
                                    '@$_contactUsername',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      color: isDark
                                          ? AppColors.darkPrimary // Light purple text for dark mode
                                          : AppColors.lightPrimary, // Dark purple text for light mode
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: Text(
                                  _contactName!,
                    style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
                        ),
                      ],
                    ),
                  ),
                // Amount
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
            Text(
                        'Transaction Amount:',
              style: TextStyle(
                          fontSize: 11,
                color: ThemeColors.gray(context),
                          fontWeight: FontWeight.w500,
            ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _amount != null
                            ? Text(
                                '${_amount!.sign} ${NumberFormat('#,###').format(_amount!.amount)} IQD',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _amount!.isPositive 
                                      ? AppColors.darkSuccess 
                                      : AppColors.darkError,
                                ),
                              )
                            : (!_loading
                                ? const Text(
                                    '-',
                                    style: TextStyle(fontSize: 13),
                                  )
                                : const SizedBox.shrink()),
                      ),
                    ],
                  ),
                ),
                // Total Debt
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'New Total Balance:',
                        style: TextStyle(
                          fontSize: 11,
                        color: ThemeColors.gray(context),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _totalDebt != null
                            ? Text(
                                '${NumberFormat('#,###').format(_totalDebt)} IQD',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                                ),
                              )
                            : (!_loading
                                ? const Text(
                                    'N/A',
                                    style: TextStyle(fontSize: 13),
                                  )
                                : const SizedBox.shrink()),
                      ),
                    ],
                  ),
                ),
                // Comment
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Comment:',
                      style: TextStyle(
                        fontSize: 11,
                        color: ThemeColors.gray(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                        widget.event.eventData['comment'] as String? ?? '-',
                          style: TextStyle(
                            fontSize: 12,
                            color: ThemeColors.gray(context),
                          ),
                        maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      // Desktop: Table-like card row
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: InkWell(
          onTap: () => _showEventDetails(context),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Stack(
              children: [
                Row(
                  children: [
                // When
                SizedBox(
                  width: 150,
                  child: Text(
                    widget.dateFormat.format(widget.event.timestamp),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                // Sync Status and Event Type
                SizedBox(
                  width: 200,
                  child: Row(
                    children: [
                      // Sync Status Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                          color: widget.event.synced
                              ? (isDark 
                                  ? AppColors.darkSuccess.withOpacity(0.2)
                                  : AppColors.lightSuccess.withOpacity(0.2))
                              : (isDark
                                  ? AppColors.darkWarning.withOpacity(0.2)
                                  : AppColors.lightWarning.withOpacity(0.2)),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.event.synced ? Icons.cloud_done : Icons.cloud_upload,
                              size: 12,
                              color: widget.event.synced
                                  ? (isDark ? AppColors.darkSuccess : AppColors.lightSuccess)
                                  : (isDark ? AppColors.darkWarning : AppColors.lightWarning),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              widget.event.synced ? 'Synced' : 'Pending',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: widget.event.synced
                                    ? (isDark ? AppColors.darkSuccess : AppColors.lightSuccess)
                                    : (isDark ? AppColors.darkWarning : AppColors.lightWarning),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getEventBadgeColor(widget.event.eventType, isDark).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            EventFormatter.formatEventType(widget.event, widget.undoneEventsCache),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _getEventBadgeColor(widget.event.eventType, isDark),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Contact Name with Username tag
                Expanded(
                  flex: 2,
                  child: _loading 
                      ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                      : Row(
                          children: [
                            if (_contactUsername != null)
              Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark
                                      ? AppColors.darkPrimary.withOpacity(0.3) // Light purple with opacity for dark mode
                                      : const Color(0xFFE8E0EC), // Light purple background for light mode
                  borderRadius: BorderRadius.circular(4),
                                  border: isDark
                                      ? Border.all(
                                          color: AppColors.darkPrimary.withOpacity(0.5),
                    width: 1,
                                        )
                                      : null,
                ),
                                child: Text(
                                  '@$_contactUsername',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                      color: isDark
                                        ? AppColors.darkPrimary // Light purple text for dark mode
                                        : AppColors.lightPrimary, // Dark purple text for light mode
                                  ),
                                ),
                              ),
                            Expanded(
                              child: Text(
                                _contactName ?? 'N/A',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                ),
                // Amount
                SizedBox(
                  width: 120,
                  child: _loading
                      ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                      : _amount != null
                          ? Text(
                              '${_amount!.sign} ${NumberFormat('#,###').format(_amount!.amount)} IQD',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _amount!.isPositive 
                                    ? AppColors.darkSuccess 
                                    : AppColors.darkError,
                              ),
                            )
                          : const Text('-', style: TextStyle(fontSize: 12)),
                ),
                // Debt
                SizedBox(
                  width: 120,
                  child: _loading
                      ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                      : _totalDebt != null
                          ? Text(
                              '${NumberFormat('#,###').format(_totalDebt)} IQD',
                            style: TextStyle(
                                fontSize: 12,
                              fontWeight: FontWeight.w600,
                                color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                              ),
                            )
                          : const Text('N/A', style: TextStyle(fontSize: 12)),
                ),
                // Comment
                Expanded(
                  flex: 2,
                  child: Text(
                    widget.event.eventData['comment'] as String? ?? '-',
                    style: const TextStyle(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Details
                SizedBox(
                  width: 60,
                  child: IconButton(
                    icon: const Icon(Icons.visibility, size: 18),
                    onPressed: () => _showEventDetails(context),
                    tooltip: 'View Details',
                            ),
                          ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  void _showEventDetails(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _EventDetailsDialog(
        event: widget.event,
        dateFormat: widget.dateFormat,
        contactName: _contactName,
        contactUsername: _contactUsername,
        amount: _amount,
        totalDebt: _totalDebt,
        undoneEventsCache: widget.undoneEventsCache,
      ),
    );
  }
}

// Old _EventCard class removed - replaced with _EventTableRow

class _EventDetailsDialog extends StatefulWidget {
  final Event event;
  final DateFormat dateFormat;
  final String? contactName;
  final String? contactUsername;
  final AmountDisplay? amount;
  final int? totalDebt;
  final Map<String, Event>? undoneEventsCache;

  const _EventDetailsDialog({
    required this.event,
    required this.dateFormat,
    this.contactName,
    this.contactUsername,
    this.amount,
    this.totalDebt,
    this.undoneEventsCache,
  });

  @override
  State<_EventDetailsDialog> createState() => _EventDetailsDialogState();
}

class _EventDetailsDialogState extends State<_EventDetailsDialog> {
  bool _showJson = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final eventData = widget.event.eventData;
    
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
                children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
                  ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                  Text(
                          EventFormatter.formatEventType(widget.event, widget.undoneEventsCache),
                    style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.dateFormat.format(widget.event.timestamp),
                          style: TextStyle(
                            fontSize: 12,
                      color: ThemeColors.gray(context),
                    ),
                  ),
                ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close',
              ),
            ],
          ),
        ),
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                    // Contact Information
                    if (widget.contactName != null)
                      _DetailSection(
                        title: 'Contact',
                        child: Row(
                          children: [
                            if (widget.contactUsername != null)
                Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark
                                      ? AppColors.darkPrimary.withOpacity(0.3)
                                      : const Color(0xFFE8E0EC),
                                  borderRadius: BorderRadius.circular(4),
                                  border: isDark
                                      ? Border.all(
                                          color: AppColors.darkPrimary.withOpacity(0.5),
                                          width: 1,
                                        )
                                      : null,
                  ),
                                child: Text(
                                  '@${widget.contactUsername}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                      ),
                                ),
                              ),
                      Expanded(
                        child: Text(
                                widget.contactName!,
                          style: const TextStyle(
                                  fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                    
                    // Transaction Amount
                    if (widget.amount != null)
                      _DetailSection(
                        title: 'Transaction Amount',
                        child: Text(
                          '${widget.amount!.sign} ${NumberFormat('#,###').format(widget.amount!.amount)} IQD',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: widget.amount!.isPositive 
                                ? AppColors.darkSuccess 
                                : AppColors.darkError,
                  ),
                        ),
                      ),
                    
                    // Total Balance
                    if (widget.totalDebt != null)
                      _DetailSection(
                        title: 'New Total Balance',
                        child: Text(
                          '${NumberFormat('#,###').format(widget.totalDebt)} IQD',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                          ),
                        ),
                      ),
                    
                    // Event Details
                    _DetailSection(
                      title: 'Event Details',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                          _DetailRow(label: 'Event Type', value: widget.event.eventType),
                          _DetailRow(label: 'Aggregate Type', value: widget.event.aggregateType),
                          _DetailRow(label: 'Event ID', value: widget.event.id),
                          if (widget.event.aggregateId.isNotEmpty)
                            _DetailRow(label: 'Aggregate ID', value: widget.event.aggregateId),
                        ],
                      ),
                    ),
                    
                    // Comment
                    if (eventData['comment'] != null && (eventData['comment'] as String).isNotEmpty)
                      _DetailSection(
                        title: 'Comment',
                        child: Text(
                          eventData['comment'] as String,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    
                    const SizedBox(height: 16),
                    
                    // JSON Toggle
                    InkWell(
                      onTap: () {
                        setState(() {
                          _showJson = !_showJson;
                        });
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDark ? AppColors.darkGray : AppColors.lightGray,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _showJson ? Icons.expand_less : Icons.expand_more,
                              size: 20,
                              color: ThemeColors.gray(context),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Full Event Data (JSON)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: ThemeColors.gray(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    // JSON Content (collapsible)
                    if (_showJson)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                            const JsonEncoder.withIndent('  ').convert(widget.event.eventData),
                            style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                              color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                            ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _DetailSection({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: ThemeColors.gray(context),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 12,
                color: ThemeColors.gray(context),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: ThemeColors.gray(context),
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}