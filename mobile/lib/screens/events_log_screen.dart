import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../models/event.dart';
import '../services/event_store_service.dart';
import '../services/local_database_service.dart';
import '../services/projection_service.dart';
import '../utils/app_colors.dart';
import '../utils/theme_colors.dart';

class EventsLogScreen extends ConsumerStatefulWidget {
  const EventsLogScreen({super.key});

  @override
  ConsumerState<EventsLogScreen> createState() => _EventsLogScreenState();
}

class _EventsLogScreenState extends ConsumerState<EventsLogScreen> {
  List<Event> _allEvents = [];
  List<Event> _filteredEvents = [];
  bool _loading = true;
  bool _showFilters = false; // Collapsible filters for mobile
  
  // Filters
  String _searchQuery = '';
  String _eventTypeFilter = 'all';
  String _aggregateTypeFilter = 'all';
  DateTime? _dateFrom;
  DateTime? _dateTo;
  
  // Pagination
  int _currentPage = 0;
  int _pageSize = 50; // Smaller default for mobile
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEvents() async {
    setState(() {
      _loading = true;
    });

    try {
      final events = await EventStoreService.getAllEvents();
      setState(() {
        _allEvents = events;
        _loading = false;
      });
      _applyFilters();
    } catch (e) {
      print('Error loading events: $e');
      setState(() {
        _loading = false;
      });
    }
  }

  void _applyFilters() {
    List<Event> filtered = List.from(_allEvents);

    // Search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((e) {
        final comment = e.eventData['comment']?.toString().toLowerCase() ?? '';
        final name = e.eventData['name']?.toString().toLowerCase() ?? '';
        final description = e.eventData['description']?.toString().toLowerCase() ?? '';
        final eventType = e.eventType.toLowerCase();
        final aggregateType = e.aggregateType.toLowerCase();
        return comment.contains(query) ||
            name.contains(query) ||
            description.contains(query) ||
            eventType.contains(query) ||
            aggregateType.contains(query);
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
  }

  void _clearFilters() {
    setState(() {
      _searchQuery = '';
      _eventTypeFilter = 'all';
      _aggregateTypeFilter = 'all';
      _dateFrom = null;
      _dateTo = null;
      _currentPage = 0;
    });
    _searchController.clear();
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

    return Scaffold(
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
          // Search Bar (always visible)
          Container(
            padding: const EdgeInsets.all(12),
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
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search events...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                          _applyFilters();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
              padding: const EdgeInsets.all(12),
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
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All')),
                        DropdownMenuItem(value: 'CREATED', child: Text('Created')),
                        DropdownMenuItem(value: 'UPDATED', child: Text('Updated')),
                        DropdownMenuItem(value: 'DELETED', child: Text('Deleted')),
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
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
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
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          suffixIcon: const Icon(Icons.calendar_today),
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
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          suffixIcon: const Icon(Icons.calendar_today),
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
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'all', child: Text('All')),
                              DropdownMenuItem(value: 'CREATED', child: Text('Created')),
                              DropdownMenuItem(value: 'UPDATED', child: Text('Updated')),
                              DropdownMenuItem(value: 'DELETED', child: Text('Deleted')),
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
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
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
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                suffixIcon: const Icon(Icons.calendar_today),
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
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                suffixIcon: const Icon(Icons.calendar_today),
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
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _clearFilters,
                        icon: const Icon(Icons.clear),
                        label: const Text('Clear Filters'),
                      ),
                    ),
                  ] else ...[
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: _applyFilters,
                          icon: const Icon(Icons.filter_list),
                          label: const Text('Apply'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _clearFilters,
                          icon: const Icon(Icons.clear),
                          label: const Text('Clear'),
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
                          ? () {
                              setState(() {
                                _currentPage--;
                              });
                            }
                          : null,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _currentPage < _totalPages - 1
                          ? () {
                              setState(() {
                                _currentPage++;
                              });
                            }
                          : null,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
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
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.event_note,
                              size: 64,
                              color: ThemeColors.gray(context),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No events found',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _paginatedEvents.length,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemBuilder: (context, index) {
                          final event = _paginatedEvents[index];
                          return _EventCard(
                            event: event,
                            dateFormat: dateFormat,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _EventCard extends StatefulWidget {
  final Event event;
  final DateFormat dateFormat;

  const _EventCard({
    required this.event,
    required this.dateFormat,
  });

  @override
  State<_EventCard> createState() => _EventCardState();
}

class _EventCardState extends State<_EventCard> {
  String? _contactName;
  int? _totalDebt;
  bool _loadingTotalDebt = false;

  @override
  void initState() {
    super.initState();
    _loadContactInfo();
    _loadTotalDebt();
  }

  Future<void> _loadContactInfo() async {
    final eventData = widget.event.eventData;
    final contactId = eventData['contact_id'] as String?;
    
    if (contactId != null) {
      // For transactions, look up contact name
      try {
        final contact = await LocalDatabaseService.getContact(contactId);
        if (contact != null && mounted) {
          setState(() {
            _contactName = contact.name;
          });
        }
      } catch (e) {
        print('Error loading contact: $e');
      }
    } else if (widget.event.aggregateType == 'contact') {
      // For contact events, use name from event data
      final name = eventData['name'] as String?;
      if (name != null && mounted) {
        setState(() {
          _contactName = name;
        });
      }
    }
  }

  Future<void> _loadTotalDebt() async {
    // First check if total_debt is already in event data (from server)
    final eventData = widget.event.eventData;
    final totalDebtFromEvent = eventData['total_debt'];
    
    if (totalDebtFromEvent != null) {
      // Use total_debt from event data (calculated on server after the action)
      if (mounted) {
        setState(() {
          _totalDebt = (totalDebtFromEvent as num?)?.toInt();
          _loadingTotalDebt = false;
        });
      }
      return;
    }
    
    // Fallback: Calculate total debt at the time of this event (for local events)
    setState(() {
      _loadingTotalDebt = true;
    });
    
    try {
      // Calculate total debt at the time of this event (includes this event)
      final totalDebt = await ProjectionService.calculateTotalDebtAtTime(widget.event.timestamp);
      if (mounted) {
        setState(() {
          _totalDebt = totalDebt;
          _loadingTotalDebt = false;
        });
      }
    } catch (e) {
      print('Error calculating total debt: $e');
      if (mounted) {
        setState(() {
          _loadingTotalDebt = false;
        });
      }
    }
  }

  Color _getEventColor(String eventType, bool isDark) {
    switch (eventType) {
      case 'CREATED':
        return isDark ? AppColors.darkSuccess : AppColors.lightSuccess;
      case 'UPDATED':
        return isDark ? AppColors.darkWarning : AppColors.lightWarning;
      case 'DELETED':
        return isDark ? AppColors.darkError : AppColors.lightError;
      default:
        return isDark ? AppColors.darkGray : AppColors.lightGray;
    }
  }

  String _formatEventType(String eventType) {
    return eventType
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final event = widget.event;
    final eventData = event.eventData;
    final comment = eventData['comment'] as String? ?? 'No comment';
    final amount = eventData['amount'];
    final direction = eventData['direction'] as String?;
    final currency = eventData['currency'] as String? ?? 'IQD';
    final username = eventData['username'] as String?;
    
    // Determine contact name
    String? contactName = _contactName;
    if (contactName == null && event.aggregateType == 'contact') {
      contactName = eventData['name'] as String?;
    }
    
    // Build summary based on event type
    String summary = '';
    if (event.aggregateType == 'transaction') {
      if (amount != null && direction != null) {
        final amountFormatted = NumberFormat('#,###').format(amount);
        final directionText = direction == 'lent' ? 'Lent' : 'Owed';
        summary = '$directionText $amountFormatted $currency';
      }
    } else if (event.aggregateType == 'contact') {
      final name = eventData['name'] as String? ?? 'Unknown';
      final user = username ?? 'N/A';
      summary = '$name (User: $user)';
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _getEventColor(event.eventType, isDark).withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              event.eventType[0],
              style: TextStyle(
                color: _getEventColor(event.eventType, isDark),
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _formatEventType(event.eventType),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkSurfaceVariant
                        : AppColors.lightSurfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    event.aggregateType.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              widget.dateFormat.format(event.timestamp),
              style: TextStyle(
                fontSize: 11,
                color: ThemeColors.gray(context),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Contact name
              if (contactName != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.person,
                        size: 12,
                        color: ThemeColors.gray(context),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          contactName,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: ThemeColors.gray(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              // Summary
              if (summary.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    summary,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              // Total Debt stamp
              if (_totalDebt != null || _loadingTotalDebt)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkPrimary.withOpacity(0.2)
                        : AppColors.lightPrimary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isDark
                          ? AppColors.darkPrimary
                          : AppColors.lightPrimary,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.account_balance_wallet,
                        size: 12,
                        color: isDark
                            ? AppColors.darkPrimary
                            : AppColors.lightPrimary,
                      ),
                      const SizedBox(width: 4),
                      _loadingTotalDebt
                          ? SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  isDark
                                      ? AppColors.darkPrimary
                                      : AppColors.lightPrimary,
                                ),
                              ),
                            )
                          : Text(
                              'Total Debt: ${NumberFormat('#,###').format(_totalDebt ?? 0)} IQD',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? AppColors.darkPrimary
                                    : AppColors.lightPrimary,
                              ),
                            ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              // Sync status
              Row(
                children: [
                  Icon(
                    event.synced ? Icons.cloud_done : Icons.cloud_off,
                    size: 14,
                    color: event.synced
                        ? AppColors.darkSuccess
                        : AppColors.darkWarning,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    event.synced ? 'Synced' : 'Pending',
                    style: TextStyle(
                      fontSize: 11,
                      color: ThemeColors.gray(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Comment (highlighted)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkPrimary.withOpacity(0.2)
                        : AppColors.lightPrimary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark
                          ? AppColors.darkPrimary
                          : AppColors.lightPrimary,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.comment,
                        size: 18,
                        color: isDark
                            ? AppColors.darkPrimary
                            : AppColors.lightPrimary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          comment,
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Summary Info
                if (contactName != null)
                  _InfoRow(label: 'Contact', value: contactName),
                if (summary.isNotEmpty)
                  _InfoRow(label: 'Summary', value: summary),
                if (amount != null && event.aggregateType == 'transaction')
                  _InfoRow(
                    label: 'Amount',
                    value: '${NumberFormat('#,###').format(amount)} $currency',
                  ),
                if (direction != null && event.aggregateType == 'transaction')
                  _InfoRow(
                    label: 'Direction',
                    value: direction == 'lent' ? 'Lent' : 'Owed',
                  ),
                if (username != null && event.aggregateType == 'contact')
                  _InfoRow(label: 'Username', value: username),
                const SizedBox(height: 12),
                // Full Data
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('View Full Data', style: TextStyle(fontSize: 13)),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkSurfaceVariant
                            : AppColors.lightSurfaceVariant,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        const JsonEncoder.withIndent('  ').convert(event.eventData),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
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
