import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';
import '../models/event.dart';
import '../services/event_store_service.dart';
import '../services/local_database_service_v2.dart';
import '../services/settings_service.dart';
import '../providers/settings_provider.dart';
import '../utils/app_colors.dart';
import '../utils/theme_colors.dart';
import '../utils/event_formatter.dart';
import 'events_log_screen.dart';

// Data model for Syncfusion charts
class ChartData {
  final DateTime date;
  final double debt; // Debt value after inversion/clamping (for display)
  final double originalDebt; // Original debt value before inversion (for coloring)
  final bool hasTransactions;
  final List<Event> events;
  final DateTime intervalStart;
  final DateTime intervalEnd;
  final String? dominantDirection; // 'lent' or 'owed' - dominant direction in this point's events

  ChartData({
    required this.date,
    required this.debt,
    required this.originalDebt,
    required this.hasTransactions,
    this.events = const [],
    required this.intervalStart,
    required this.intervalEnd,
    this.dominantDirection,
  });
}

/// Detailed debt chart page with interactive chart and event list
class DebtChartDetailScreen extends ConsumerStatefulWidget {
  final DateTime? initialDateFrom;
  final DateTime? initialDateTo;
  
  const DebtChartDetailScreen({
    super.key,
    this.initialDateFrom,
    this.initialDateTo,
  });

  @override
  ConsumerState<DebtChartDetailScreen> createState() => _DebtChartDetailScreenState();
}

class _DebtChartDetailScreenState extends ConsumerState<DebtChartDetailScreen> {
  List<Event>? _allEvents;
  List<Event>? _filteredEvents;
  bool _loading = true;
  String _chartPeriod = 'month'; // 'day', 'week', 'month', 'year'
  DateTime? _selectedDateFrom;
  DateTime? _selectedDateTo;
  Map<String, String> _contactNameCache = {}; // Cache for contact names
  Map<String, Event> _undoneEventsCache = {}; // Cache for undone events
  bool _isDisposed = false; // Flag to prevent operations after disposal
  
  // Filters (same as events log but without search)
  String _eventTypeFilter = 'all';
  String _aggregateTypeFilter = 'all';
  bool _showFilters = false;
  
  // Tooltip navigation state for swipe gestures
  int? _selectedTooltipIndex; // Currently selected point index for tooltip
  final GlobalKey _chartKey = GlobalKey(); // Key to access chart widget
  late TooltipBehavior _tooltipBehavior; // Tooltip behavior controller
  
  // Chart display settings - fixed to smooth lines
  static const bool _useCurvedLines = true; // Always use smooth curved lines (natural spline)
  static const bool _showTooltips = true; // Always show tooltips

  @override
  void initState() {
    super.initState();
    _selectedDateFrom = widget.initialDateFrom;
    _selectedDateTo = widget.initialDateTo;
    _tooltipBehavior = TooltipBehavior(enable: false); // Initialize, will be configured in build
    _loadDefaultPeriod();
    _loadChartData();
  }

  Future<void> _loadDefaultPeriod() async {
    final defaultPeriod = await SettingsService.getGraphDefaultPeriod();
    if (mounted) {
      setState(() {
        _chartPeriod = defaultPeriod;
      });
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    // Hide tooltip before disposal to prevent chart updates
    try {
      _tooltipBehavior.hide();
    } catch (e) {
      // Ignore errors during disposal
    }
    super.dispose();
  }

  Future<void> _loadChartData() async {
    if (_isDisposed || !mounted) return;
    
    setState(() {
      _loading = true;
    });

    try {
      final events = await EventStoreService.getAllEvents();
      
      if (_isDisposed || !mounted) return;
      
      // Filter events that have total_debt in eventData
      final eventsWithDebt = events.where((e) {
        final totalDebt = e.eventData['total_debt'];
        return totalDebt != null && totalDebt is num;
      }).toList();
      
      // Sort by timestamp (oldest first for chart)
      eventsWithDebt.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      
      // Pre-load contact names for tooltip
      await _preloadContactNames(eventsWithDebt);
      
      if (_isDisposed || !mounted) return;
      
      // Pre-load undone events cache
      await _preloadUndoneEvents(eventsWithDebt);
      
      if (_isDisposed || !mounted) return;
      
      setState(() {
        _allEvents = eventsWithDebt;
        _filteredEvents = eventsWithDebt;
        _loading = false;
      });
      
      _applyDateFilters();
    } catch (e) {
      print('Error loading chart data: $e');
      if (!_isDisposed && mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _applyDateFilters() {
    if (_allEvents == null || _isDisposed || !mounted) return;
    
    List<Event> filtered = List.from(_allEvents!);
    
    // Apply date filters
    if (_selectedDateFrom != null) {
      filtered = filtered.where((e) => 
        e.timestamp.isAfter(_selectedDateFrom!.subtract(const Duration(seconds: 1))) ||
        e.timestamp.isAtSameMomentAs(_selectedDateFrom!)
      ).toList();
    }
    
    if (_selectedDateTo != null) {
      final dateToEnd = DateTime(
        _selectedDateTo!.year,
        _selectedDateTo!.month,
        _selectedDateTo!.day,
        23,
        59,
        59,
      );
      filtered = filtered.where((e) => 
        e.timestamp.isBefore(dateToEnd) ||
        e.timestamp.isAtSameMomentAs(dateToEnd)
      ).toList();
    }
    
    // Apply event type filter
    if (_eventTypeFilter != 'all') {
      filtered = filtered.where((e) => 
        e.eventType.toUpperCase() == _eventTypeFilter.toUpperCase()
      ).toList();
    }
    
    // Apply aggregate type filter
    if (_aggregateTypeFilter != 'all') {
      filtered = filtered.where((e) => 
        e.aggregateType.toLowerCase() == _aggregateTypeFilter.toLowerCase()
      ).toList();
    }
    
    // Sort by timestamp (newest first)
    filtered.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    if (!_isDisposed && mounted) {
      setState(() {
        _filteredEvents = filtered;
      });
    }
  }
  
  Future<void> _preloadUndoneEvents(List<Event> events) async {
    _undoneEventsCache.clear();
    for (final event in events) {
      if (event.eventType == 'UNDO') {
        final undoneEventId = event.eventData['undone_event_id'] as String?;
        if (undoneEventId != null) {
          final undoneEvent = events.firstWhere(
            (e) => e.id == undoneEventId,
            orElse: () => event,
          );
          if (undoneEvent != event) {
            _undoneEventsCache[undoneEventId] = undoneEvent;
          }
        }
      }
    }
  }

  Future<void> _preloadContactNames(List<Event> events) async {
    final contactIds = <String>{};
    for (final event in events) {
      final contactId = event.eventData['contact_id'] as String?;
      if (contactId != null) {
        contactIds.add(contactId);
      }
    }
    
    for (final contactId in contactIds) {
      try {
        final contact = await LocalDatabaseServiceV2.getContact(contactId);
        if (contact != null) {
          _contactNameCache[contactId] = contact.name;
        }
      } catch (e) {
        // Contact might not exist, continue
      }
    }
  }

  void _onChartPointTapped(DateTime intervalStart, DateTime intervalEnd) {
    setState(() {
      // Align to day boundaries for proper filtering
      // Start of day (00:00:00) for dateFrom
      _selectedDateFrom = _alignToDayStart(intervalStart);
      // End of day (23:59:59) for dateTo - align to day start then add time
      final endDayStart = _alignToDayStart(intervalEnd);
      _selectedDateTo = DateTime(
        endDayStart.year,
        endDayStart.month,
        endDayStart.day,
        23,
        59,
        59,
      );
    });
    _applyDateFilters();
  }

  void _resetFilters() {
    setState(() {
      _selectedDateFrom = null;
      _selectedDateTo = null;
      _eventTypeFilter = 'all';
      _aggregateTypeFilter = 'all';
      _selectedTooltipIndex = null; // Clear selected point
    });
    _applyDateFilters();
  }

  // Helper functions to align dates to calendar boundaries
  DateTime _alignToDayStart(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }
  
  DateTime _alignToWeekStart(DateTime date) {
    final dayOfWeek = date.weekday; // 1=Monday, 7=Sunday
    final daysToSubtract = dayOfWeek == 7 ? 0 : dayOfWeek;
    final sunday = date.subtract(Duration(days: daysToSubtract));
    return DateTime(sunday.year, sunday.month, sunday.day);
  }
  
  DateTime _alignToMonthStart(DateTime date) {
    return DateTime(date.year, date.month, 1);
  }
  
  DateTime _alignToYearStart(DateTime date) {
    return DateTime(date.year, 1, 1);
  }

  List<ChartDataPoint> _buildChartData() {
    if (_allEvents == null || _allEvents!.isEmpty) return [];
    
    final now = DateTime.now();
    DateTime periodStart;
    int intervalMs;
    
    switch (_chartPeriod) {
      case 'week':
        // Last 7 days, but align to week boundaries (Sunday to Sunday)
        periodStart = _alignToWeekStart(now.subtract(const Duration(days: 7)));
        intervalMs = 24 * 60 * 60 * 1000; // 1 day intervals
        break;
      case 'month':
        // Last 30 days, but align to month boundaries
        final monthStart = _alignToMonthStart(now.subtract(const Duration(days: 30)));
        periodStart = monthStart.isBefore(_alignToMonthStart(now)) 
            ? monthStart 
            : _alignToMonthStart(now);
        intervalMs = 24 * 60 * 60 * 1000; // 1 day intervals
        break;
      case 'year':
        // Last 365 days, but align to year boundaries
        final yearStart = _alignToYearStart(now.subtract(const Duration(days: 365)));
        periodStart = yearStart.isBefore(_alignToYearStart(now)) 
            ? yearStart 
            : _alignToYearStart(now);
        intervalMs = 7 * 24 * 60 * 60 * 1000; // 1 week intervals
        break;
      default:
        periodStart = _alignToMonthStart(now.subtract(const Duration(days: 30)));
        intervalMs = 24 * 60 * 60 * 1000;
    }
    
    final eventsInPeriod = _allEvents!.where((e) => 
      e.timestamp.isAfter(periodStart) || e.timestamp.isAtSameMomentAs(periodStart)
    ).toList();
    
    if (eventsInPeriod.isEmpty) return [];
    
    // Find the actual first event date in the period (or use periodStart if no events)
    DateTime actualStartDate = periodStart;
    if (eventsInPeriod.isNotEmpty) {
      final firstEventDate = eventsInPeriod.map((e) => e.timestamp).reduce((a, b) => a.isBefore(b) ? a : b);
      // Start from the first event date, but align to interval boundary
      // For year view, align to month start; for month view, align to week start; etc.
      if (_chartPeriod == 'year') {
        // Align to month start
        actualStartDate = DateTime(firstEventDate.year, firstEventDate.month, 1);
      } else if (_chartPeriod == 'month') {
        // Align to week start (Sunday)
        final weekday = firstEventDate.weekday;
        actualStartDate = firstEventDate.subtract(Duration(days: weekday == 7 ? 0 : weekday));
      } else {
        // For week/day, use the first event date as-is
        actualStartDate = firstEventDate;
      }
      // Don't go before periodStart
      if (actualStartDate.isBefore(periodStart)) {
        actualStartDate = periodStart;
      }
      print('📊 Detail: First event date: $firstEventDate, aligned start: $actualStartDate');
    }
    
    final minDate = actualStartDate.millisecondsSinceEpoch;
    final maxDate = now.millisecondsSinceEpoch;
    final numIntervals = ((maxDate - minDate) / intervalMs).ceil();
    
    final chartData = <ChartDataPoint>[];
    
    for (int i = 0; i <= numIntervals; i++) {
      // Calculate interval boundaries aligned to calendar units
      DateTime intervalStartDate;
      DateTime intervalEndDate;
      
      if ((_chartPeriod == 'week' || _chartPeriod == 'month') && intervalMs == 24 * 60 * 60 * 1000) {
        // For day intervals in week/month views, align to day boundaries (00:00:00 to 23:59:59.999)
        final baseDate = DateTime.fromMillisecondsSinceEpoch(minDate.toInt());
        intervalStartDate = _alignToDayStart(baseDate.add(Duration(days: i)));
        intervalEndDate = intervalStartDate.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
      } else if (_chartPeriod == 'year' && intervalMs == 7 * 24 * 60 * 60 * 1000) {
        // For week intervals in year view, align to week boundaries (Sunday to Saturday)
        final baseDate = DateTime.fromMillisecondsSinceEpoch(minDate.toInt());
        intervalStartDate = _alignToWeekStart(baseDate.add(Duration(days: i * 7)));
        intervalEndDate = intervalStartDate.add(const Duration(days: 7)).subtract(const Duration(milliseconds: 1));
      } else {
        // For other cases, use millisecond-based calculation
        final intervalStart = minDate + (i * intervalMs);
        final intervalEnd = (intervalStart + intervalMs).clamp(minDate, maxDate);
        intervalStartDate = DateTime.fromMillisecondsSinceEpoch(intervalStart.toInt());
        intervalEndDate = DateTime.fromMillisecondsSinceEpoch(intervalEnd.toInt());
      }
      
      final intervalStart = intervalStartDate.millisecondsSinceEpoch;
      final intervalEnd = intervalEndDate.millisecondsSinceEpoch;
      final intervalCenter = (intervalStart + intervalEnd) / 2;
      
      // Find events in this interval - use proper boundaries (inclusive end for day boundaries)
      final eventsInInterval = eventsInPeriod.where((e) {
        final eventTime = e.timestamp.millisecondsSinceEpoch;
        // Include events that fall within the interval (inclusive start and end for day boundaries)
        return eventTime >= intervalStart && eventTime <= intervalEnd;
      }).toList();
      
      double avgDebt;
      bool hasTransactions = false;
      
      if (eventsInInterval.isNotEmpty) {
        final sum = eventsInInterval.map((e) => 
          (e.eventData['total_debt'] as num).toDouble()
        ).reduce((a, b) => a + b);
        avgDebt = sum / eventsInInterval.length;
        hasTransactions = true;
      } else {
        // Find closest event before this interval
        final beforeEvents = eventsInPeriod.where((e) => 
          e.timestamp.millisecondsSinceEpoch < intervalStart
        ).toList();
        if (beforeEvents.isNotEmpty) {
          final closestBefore = beforeEvents.last;
          avgDebt = (closestBefore.eventData['total_debt'] as num).toDouble();
        } else if (eventsInPeriod.isNotEmpty) {
          avgDebt = (eventsInPeriod.first.eventData['total_debt'] as num).toDouble();
        } else {
          continue; // Skip this interval if no data
        }
      }
      
      chartData.add(ChartDataPoint(
        x: intervalCenter,
        y: avgDebt,
        intervalStart: intervalStartDate,
        intervalEnd: intervalEndDate,
        hasTransactions: hasTransactions,
        events: eventsInInterval, // Store events for tooltip
      ));
    }
    
    return chartData;
  }

  @override
  Widget build(BuildContext context) {
    if (_isDisposed || !mounted) {
      return const SizedBox.shrink();
    }
    
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.darkPrimary : AppColors.lightPrimary;
    final chartData = _buildChartData();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debt Over Time'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Period selector buttons - compact
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildPeriodButton('week', 'W'),
                        const SizedBox(width: 4),
                        _buildPeriodButton('month', 'M'),
                        const SizedBox(width: 4),
                        _buildPeriodButton('year', 'Y'),
                      ],
                    ),
                  ),
                  
                  // Chart
                  if (chartData.isNotEmpty) ...[
                    Container(
                      height: 400,
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                        ),
                      ),
                      child: (_isDisposed || !mounted)
                          ? const SizedBox.shrink()
                          : Builder(
                              builder: (context) {
                                // Check again inside builder
                                if (_isDisposed || !mounted) {
                                  return const SizedBox.shrink();
                                }
                                
                                // Calculate bounds
                                final allX = chartData.map((d) => d.x).toList();
                                final allY = chartData.map((d) => d.y).toList();
                                if (allX.isEmpty || allY.isEmpty) {
                                  return const Center(child: Text('No data'));
                                }
                          
                          final rawMinX = allX.reduce((a, b) => a < b ? a : b);
                          final rawMaxX = allX.reduce((a, b) => a > b ? a : b);
                          final rawMinY = allY.reduce((a, b) => a < b ? a : b);
                          final rawMaxY = allY.reduce((a, b) => a > b ? a : b);
                          
                          final xRange = rawMaxX - rawMinX;
                          final xPadding = xRange > 0 ? xRange * 0.02 : 86400000;
                          final minX = rawMinX - xPadding;
                          final maxX = rawMaxX + xPadding;
                          
                          final yRange = rawMaxY - rawMinY;
                          final yPaddingBottom = yRange > 0 
                              ? (yRange * 0.4).clamp(5000, 200000) 
                              : (rawMinY.abs() * 0.35).clamp(5000, 200000);
                          final yPaddingTop = yRange > 0 ? yRange * 0.4 : (rawMaxY.abs() * 0.35).clamp(1000, 100000);
                          
                          final invertY = ref.watch(invertYAxisProvider);
                          final finalMinY = invertY ? -(rawMaxY + yPaddingTop) : rawMinY - yPaddingBottom;
                          final finalMaxY = invertY ? -(rawMinY - yPaddingBottom) : rawMaxY + yPaddingTop;
                          
                          // Convert to Syncfusion format - include ALL points for correct line progression
                          // Points without transactions will have hidden markers but still contribute to the line
                          // Sort by date to ensure proper line connection
                          final sortedChartData = List<ChartDataPoint>.from(chartData)
                            ..sort((a, b) => a.x.compareTo(b.x));
                          
                          final chartDataList = sortedChartData
                              .map((point) {
                                // When inverted, multiply by -1; otherwise use original value
                                final yValue = invertY ? -point.y : point.y;
                                final margin = (finalMaxY - finalMinY) * 0.02;
                                final clampedY = yValue.clamp(finalMinY + margin, finalMaxY - margin);
                                
                                // Determine dominant direction from events
                                String? dominantDirection;
                                if (point.events.isNotEmpty) {
                                  int lentCount = 0;
                                  int owedCount = 0;
                                  for (final event in point.events) {
                                    final direction = event.eventData['direction'] as String?;
                                    if (direction == 'lent') {
                                      lentCount++;
                                    } else if (direction == 'owed') {
                                      owedCount++;
                                    }
                                  }
                                  if (lentCount > owedCount) {
                                    dominantDirection = 'lent';
                                  } else if (owedCount > lentCount) {
                                    dominantDirection = 'owed';
                                  } else if (point.events.isNotEmpty) {
                                    // If equal, use the most recent event's direction
                                    final lastEvent = point.events.last;
                                    dominantDirection = lastEvent.eventData['direction'] as String?;
                                  }
                                }
                                
                                return ChartData(
                                  date: DateTime.fromMillisecondsSinceEpoch(point.x.toInt()),
                                  debt: clampedY,
                                  originalDebt: point.y, // Store original debt before inversion
                                  hasTransactions: point.hasTransactions,
                                  events: point.events,
                                  intervalStart: point.intervalStart,
                                  intervalEnd: point.intervalEnd,
                                  dominantDirection: dominantDirection,
                                );
                              })
                              .toList();
                          
                          // Create list of indices for visible points only (for navigation)
                          final visiblePointIndices = <int>[];
                          for (int i = 0; i < chartDataList.length; i++) {
                            if (chartDataList[i].hasTransactions) {
                              visiblePointIndices.add(i);
                            }
                          }
                          
                          // Use accent color for all points
                          final primaryColor = Theme.of(context).colorScheme.primary;
                          
                          // Update tooltip behavior with current configuration
                          _tooltipBehavior = TooltipBehavior(
                            enable: _showTooltips,
                            activationMode: ActivationMode.none, // We'll control it programmatically
                            color: Theme.of(context).colorScheme.surface,
                            textStyle: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 9,
                            ),
                            borderWidth: 1,
                            borderColor: primaryColor,
                            duration: 0, // Keep visible until we hide it
                            builder: (dynamic data, dynamic point, dynamic series, int pointIndex, int seriesIndex) {
                              // Check if widget is still mounted before building tooltip
                              if (_isDisposed || !mounted) {
                                return const SizedBox.shrink();
                              }
                              
                              // If we have a selected tooltip index from swipe, use that instead
                              final effectiveIndex = _selectedTooltipIndex ?? pointIndex;
                              
                              // Safety check: effectiveIndex must be valid
                              if (effectiveIndex < 0 || effectiveIndex >= chartDataList.length) {
                                return const SizedBox.shrink();
                              }
                              
                              final chartData = chartDataList[effectiveIndex];
                              if (!chartData.hasTransactions || chartData.events.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              
                              // Build compact tooltip: show debt and transaction count
                              final avgDebt = NumberFormat('#,###').format(chartData.debt.toInt());
                              final txCount = chartData.events.length;
                              
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: Theme.of(context).colorScheme.primary,
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  '$avgDebt IQD\n$txCount ${txCount == 1 ? 'transaction' : 'transactions'}',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface,
                                    fontSize: 9,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              );
                            },
                          );
                          
                          // Determine date format based on period
                          String dateFormat;
                          DateTimeIntervalType intervalType;
                          switch (_chartPeriod) {
                            case 'week':
                              dateFormat = 'MM/dd';
                              intervalType = DateTimeIntervalType.days;
                              break;
                            case 'month':
                              dateFormat = 'MM/dd';
                              intervalType = DateTimeIntervalType.days;
                              break;
                            case 'year':
                              dateFormat = 'MM/yy';
                              intervalType = DateTimeIntervalType.months;
                              break;
                            default:
                              dateFormat = 'MM/dd';
                              intervalType = DateTimeIntervalType.days;
                          }
                          
                          return Stack(
                            children: [
                              GestureDetector(
                                onHorizontalDragStart: (details) {
                              // Initialize drag - show tooltip for the starting point
                              // Only consider visible points (with transactions)
                              if (visiblePointIndices.isEmpty) return;
                              
                              final RenderBox? renderBox = _chartKey.currentContext?.findRenderObject() as RenderBox?;
                              if (renderBox == null) return;
                              
                              final localPosition = renderBox.globalToLocal(details.globalPosition);
                              final chartWidth = renderBox.size.width;
                              final xPercent = (localPosition.dx / chartWidth).clamp(0.0, 1.0);
                              
                              int closestVisibleIndex = 0;
                              double minDistance = double.infinity;
                              
                              // Only search through visible points
                              for (final i in visiblePointIndices) {
                                final point = chartDataList[i];
                                final pointXPercent = (point.date.millisecondsSinceEpoch - minX) / (maxX - minX);
                                final distance = (pointXPercent - xPercent).abs();
                                
                                if (distance < minDistance) {
                                  minDistance = distance;
                                  closestVisibleIndex = i;
                                }
                              }
                              
                              if (mounted && !_isDisposed) {
                                try {
                                  setState(() {
                                    _selectedTooltipIndex = closestVisibleIndex;
                                  });
                                  if (mounted && !_isDisposed) {
                                    _tooltipBehavior.showByIndex(closestVisibleIndex, 0);
                                  }
                                } catch (e) {
                                  // Chart might be disposed, ignore
                                }
                              }
                            },
                            onHorizontalDragUpdate: (details) {
                              // Calculate which point is closest to the drag position
                              // Only consider visible points (with transactions)
                              if (visiblePointIndices.isEmpty) return;
                              
                              final RenderBox? renderBox = _chartKey.currentContext?.findRenderObject() as RenderBox?;
                              if (renderBox == null) return;
                              
                              final localPosition = renderBox.globalToLocal(details.globalPosition);
                              final chartWidth = renderBox.size.width;
                              
                              // Calculate the X position as a percentage of chart width
                              final xPercent = (localPosition.dx / chartWidth).clamp(0.0, 1.0);
                              
                              // Find the closest visible point based on X position
                              int closestVisibleIndex = 0;
                              double minDistance = double.infinity;
                              
                              // Only search through visible points
                              for (final i in visiblePointIndices) {
                                final point = chartDataList[i];
                                // Calculate point's X position as percentage (0.0 to 1.0)
                                final pointXPercent = (point.date.millisecondsSinceEpoch - minX) / (maxX - minX);
                                final distance = (pointXPercent - xPercent).abs();
                                
                                if (distance < minDistance) {
                                  minDistance = distance;
                                  closestVisibleIndex = i;
                                }
                              }
                              
                              // Update tooltip to show the closest visible point
                              if (_selectedTooltipIndex != closestVisibleIndex) {
                                if (mounted && !_isDisposed) {
                                  try {
                                    setState(() {
                                      _selectedTooltipIndex = closestVisibleIndex;
                                    });
                                    if (mounted && !_isDisposed) {
                                      _tooltipBehavior.showByIndex(closestVisibleIndex, 0);
                                    }
                                  } catch (e) {
                                    // Chart might be disposed, ignore
                                  }
                                }
                              }
                            },
                            onHorizontalDragEnd: (details) {
                              // When gesture ends, select the current point but keep tooltip visible
                              if (_selectedTooltipIndex != null && 
                                  _selectedTooltipIndex! >= 0 &&
                                  _selectedTooltipIndex! < chartDataList.length) {
                                final point = chartDataList[_selectedTooltipIndex!];
                                if (point.hasTransactions) {
                                  _onChartPointTapped(point.intervalStart, point.intervalEnd);
                                }
                              }
                              // Keep tooltip visible - don't clear selection or hide
                              // This prevents the graph from rebuilding
                            },
                            onTapUp: (details) {
                              // Handle direct tap to show tooltip and select point
                              // Only consider visible points (with transactions)
                              if (visiblePointIndices.isEmpty) return;
                              
                              final RenderBox? renderBox = _chartKey.currentContext?.findRenderObject() as RenderBox?;
                              if (renderBox == null) return;
                              
                              final localPosition = renderBox.globalToLocal(details.globalPosition);
                              final chartWidth = renderBox.size.width;
                              final xPercent = (localPosition.dx / chartWidth).clamp(0.0, 1.0);
                              
                              int tappedVisibleIndex = 0;
                              double minDistance = double.infinity;
                              
                              // Only search through visible points
                              for (final i in visiblePointIndices) {
                                final point = chartDataList[i];
                                final pointXPercent = (point.date.millisecondsSinceEpoch - minX) / (maxX - minX);
                                final distance = (pointXPercent - xPercent).abs();
                                
                                if (distance < minDistance) {
                                  minDistance = distance;
                                  tappedVisibleIndex = i;
                                }
                              }
                              
                              if (tappedVisibleIndex >= 0 && tappedVisibleIndex < chartDataList.length) {
                                final point = chartDataList[tappedVisibleIndex];
                                if (mounted && !_isDisposed) {
                                  setState(() {
                                    _selectedTooltipIndex = tappedVisibleIndex;
                                  });
                                  try {
                                    if (mounted && !_isDisposed) {
                                      _tooltipBehavior.showByIndex(tappedVisibleIndex, 0);
                                    }
                                  } catch (e) {
                                    // Chart might be disposed, ignore
                                  }
                                  // Select the point after a short delay, but keep yellow marker visible briefly
                                  Future.delayed(const Duration(milliseconds: 500), () {
                                    if (mounted && !_isDisposed) {
                                      _onChartPointTapped(point.intervalStart, point.intervalEnd);
                                      try {
                                        if (mounted && !_isDisposed) {
                                          _tooltipBehavior.hide();
                                        }
                                      } catch (e) {
                                        // Chart might be disposed, ignore
                                      }
                                      // Keep yellow marker visible a bit longer for visual feedback
                                      Future.delayed(const Duration(milliseconds: 300), () {
                                        if (mounted && !_isDisposed) {
                                          setState(() {
                                            _selectedTooltipIndex = null;
                                          });
                                        }
                                      });
                                    }
                                  });
                                }
                              }
                            },
                            child: (_isDisposed || !mounted)
                                ? const SizedBox.shrink()
                                : SfCartesianChart(
                                    key: _chartKey,
                                    backgroundColor: Colors.transparent,
                                    plotAreaBorderWidth: 0,
                                    primaryXAxis: DateTimeAxis(
                              minimum: DateTime.fromMillisecondsSinceEpoch(minX.toInt()),
                              maximum: DateTime.fromMillisecondsSinceEpoch(maxX.toInt()),
                              intervalType: intervalType,
                              labelStyle: TextStyle(
                                fontSize: 9,
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                              ),
                              dateFormat: DateFormat(dateFormat),
                              majorGridLines: MajorGridLines(
                                width: 1,
                                color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
                              ),
                              axisLine: AxisLine(
                                width: 1,
                                color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                              ),
                            ),
                            primaryYAxis: NumericAxis(
                              minimum: finalMinY,
                              maximum: finalMaxY,
                              // Don't use isInversed since we're transforming the data values directly
                              labelStyle: TextStyle(
                                fontSize: 9,
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                              ),
                              axisLabelFormatter: (AxisLabelRenderDetails details) {
                                // Compact format: K for thousands, M for millions
                                final num = details.value.toInt();
                                String formatted;
                                if (num.abs() >= 1000000) {
                                  formatted = '${(num / 1000000).toStringAsFixed(1)}M';
                                } else if (num.abs() >= 1000) {
                                  formatted = '${(num / 1000).toStringAsFixed(1)}K';
                                } else {
                                  formatted = num.toString();
                                }
                                return ChartAxisLabel(
                                  formatted,
                                  details.textStyle?.copyWith(
                                    fontSize: 9,
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                  ),
                                );
                              },
                              majorGridLines: MajorGridLines(
                                width: 1,
                                color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
                              ),
                              axisLine: AxisLine(
                                width: 1,
                                color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                              ),
                            ),
                            series: <CartesianSeries<ChartData, DateTime>>[
                              // Main line series (all points for continuous line)
                              SplineAreaSeries<ChartData, DateTime>(
                                dataSource: chartDataList,
                                xValueMapper: (ChartData data, _) => data.date,
                                yValueMapper: (ChartData data, _) => data.debt,
                                borderColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                                borderWidth: 1.5,
                                splineType: _useCurvedLines ? SplineType.natural : SplineType.monotonic,
                                animationDuration: 0,
                                enableTooltip: _showTooltips, // Control tooltip visibility
                                emptyPointSettings: EmptyPointSettings(
                                  mode: EmptyPointMode.gap,
                                ),
                                markerSettings: const MarkerSettings(
                                  // Hide all markers on main series - we'll show markers separately
                                  isVisible: false,
                                ),
                                gradient: LinearGradient(
                                  colors: Theme.of(context).brightness == Brightness.dark
                                      ? [
                                          Theme.of(context).colorScheme.onSurface.withOpacity(0.25),
                                          Theme.of(context).colorScheme.onSurface.withOpacity(0.0),
                                        ]
                                      : [
                                          Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
                                          Theme.of(context).colorScheme.onSurface.withOpacity(0.0),
                                        ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                                onPointTap: (ChartPointDetails details) {
                                  // This is called from the marker series, so all points here have transactions
                                  if (details.pointIndex != null && 
                                      details.pointIndex! >= 0) {
                                    // Map marker series index to full chartDataList index
                                    final markerSeriesData = chartDataList.where((d) => d.hasTransactions).toList();
                                    if (details.pointIndex! < markerSeriesData.length) {
                                      final tappedPoint = markerSeriesData[details.pointIndex!];
                                      final fullIndex = chartDataList.indexOf(tappedPoint);
                                      
                                      if (fullIndex >= 0 && fullIndex < chartDataList.length) {
                                        // Show yellow marker for visual feedback
                                        if (mounted && !_isDisposed) {
                                          setState(() {
                                            _selectedTooltipIndex = fullIndex;
                                          });
                                          try {
                                            if (mounted && !_isDisposed) {
                                              _tooltipBehavior.showByIndex(fullIndex, 0);
                                            }
                                          } catch (e) {
                                            // Chart might be disposed, ignore
                                          }
                                          // Select the point after a short delay
                                          Future.delayed(const Duration(milliseconds: 300), () {
                                            if (mounted && !_isDisposed) {
                                              _onChartPointTapped(tappedPoint.intervalStart, tappedPoint.intervalEnd);
                                              try {
                                                if (mounted && !_isDisposed) {
                                                  _tooltipBehavior.hide();
                                                }
                                              } catch (e) {
                                                // Chart might be disposed, ignore
                                              }
                                              // Keep yellow marker visible briefly
                                              Future.delayed(const Duration(milliseconds: 300), () {
                                                if (mounted && !_isDisposed) {
                                                  setState(() {
                                                    _selectedTooltipIndex = null;
                                                  });
                                                }
                                              });
                                            }
                                          });
                                        }
                                      }
                                    }
                                  }
                                },
                                ),
                              // Separate series for markers - only points with transactions
                              // This allows the line to connect through all points while only showing markers for actual events
                              SplineAreaSeries<ChartData, DateTime>(
                                dataSource: chartDataList.where((d) => d.hasTransactions).toList(),
                                xValueMapper: (ChartData data, _) => data.date,
                                yValueMapper: (ChartData data, _) => data.debt,
                                borderColor: Colors.transparent, // Transparent line (only markers visible)
                                borderWidth: 0,
                                splineType: _useCurvedLines ? SplineType.natural : SplineType.monotonic,
                                animationDuration: 0,
                                enableTooltip: false,
                                markerSettings: MarkerSettings(
                                  // Show markers only for points with transactions
                                  isVisible: true,
                                  height: 5,
                                  width: 5,
                                  shape: DataMarkerType.circle,
                                  color: primaryColor,
                                  borderColor: primaryColor,
                                  borderWidth: 0,
                                ),
                                gradient: const LinearGradient(
                                  // Transparent gradient so only markers show
                                  colors: [Colors.transparent, Colors.transparent],
                                ),
                                onPointTap: null,
                              ),
                              // Overlay series for selected point (yellow highlight)
                              if (_selectedTooltipIndex != null && 
                                  _selectedTooltipIndex! >= 0 &&
                                  _selectedTooltipIndex! < chartDataList.length)
                                SplineAreaSeries<ChartData, DateTime>(
                                  dataSource: [chartDataList[_selectedTooltipIndex!]], // Only the selected point
                                  xValueMapper: (ChartData data, _) => data.date,
                                  yValueMapper: (ChartData data, _) => data.debt,
                                  borderColor: Colors.transparent, // Transparent line
                                  borderWidth: 0,
                                  splineType: _useCurvedLines ? SplineType.natural : SplineType.monotonic,
                                  animationDuration: 0,
                                  enableTooltip: false,
                                  color: Colors.transparent, // Transparent area
                                  markerSettings: MarkerSettings(
                                    isVisible: true,
                                    height: 8, // Selected point marker
                                    width: 8,
                                    shape: DataMarkerType.circle,
                                    color: Colors.yellow, // Solid yellow for selected point
                                    borderColor: Colors.yellow, // Same color as fill (no visible border)
                                    borderWidth: 0, // No border
                                  ),
                                  gradient: LinearGradient(
                                    colors: [Colors.transparent, Colors.transparent], // No gradient
                                  ),
                                ),
                            ],
                            tooltipBehavior: _tooltipBehavior,
                          ),
                        ),
                        // Custom tooltip widget that follows the selected point
                        if (_selectedTooltipIndex != null && 
                            _selectedTooltipIndex! >= 0 &&
                            _selectedTooltipIndex! < chartDataList.length)
                          _buildCustomTooltip(
                            context,
                            chartDataList[_selectedTooltipIndex!],
                            minX,
                            maxX,
                            finalMinY,
                            finalMaxY,
                            chartDataList,
                          ),
                      ],
                    );
                              },
                            ),
                          ),
                    
                    // Filters section (same as events log but without search)
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
                            // Event Type Filter
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
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                                _applyDateFilters();
                              },
                            ),
                            const SizedBox(height: 12),
                            // Aggregate Type Filter
                            DropdownButtonFormField<String>(
                              value: _aggregateTypeFilter,
                              decoration: InputDecoration(
                                labelText: 'Aggregate Type',
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
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                                _applyDateFilters();
                              },
                            ),
                            const SizedBox(height: 12),
                            // Date From
                            InkWell(
                              onTap: () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: _selectedDateFrom ?? DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now(),
                                );
                                if (date != null) {
                                  setState(() {
                                    _selectedDateFrom = date;
                                  });
                                  _applyDateFilters();
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
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                ),
                                child: Text(
                                  _selectedDateFrom != null
                                      ? DateFormat('yyyy-MM-dd').format(_selectedDateFrom!)
                                      : 'Select date',
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Date To
                            InkWell(
                              onTap: () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: _selectedDateTo ?? DateTime.now(),
                                  firstDate: _selectedDateFrom ?? DateTime(2020),
                                  lastDate: DateTime.now(),
                                );
                                if (date != null) {
                                  setState(() {
                                    _selectedDateTo = date;
                                  });
                                  _applyDateFilters();
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
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                ),
                                child: Text(
                                  _selectedDateTo != null
                                      ? DateFormat('yyyy-MM-dd').format(_selectedDateTo!)
                                      : 'Select date',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    // Event list section using _EventTableRow from events_log_screen
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  'Events',
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.refresh),
                                    onPressed: () {
                                      _resetFilters();
                                    },
                                    tooltip: 'Reset Filters',
                                  ),
                                  IconButton(
                                    icon: Icon(_showFilters ? Icons.filter_list : Icons.filter_list_outlined),
                                    onPressed: () {
                                      setState(() {
                                        _showFilters = !_showFilters;
                                      });
                                    },
                                    tooltip: 'Toggle Filters',
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (_filteredEvents != null && _filteredEvents!.isNotEmpty)
                            ..._filteredEvents!.take(20).map((event) {
                              return EventTableRow(
                                key: ValueKey('${event.id}_${_contactNameCache.length}_${_undoneEventsCache.length}'),
                                event: event,
                                dateFormat: DateFormat('MM/dd/yyyy HH:mm'),
                                allEvents: _allEvents ?? [],
                                contactNameCache: _contactNameCache,
                                undoneEventsCache: _undoneEventsCache,
                                isMobile: true,
                              );
                            }).toList()
                          else
                            Padding(
                              padding: const EdgeInsets.all(32),
                              child: Center(
                                child: Text(
                                  _selectedDateFrom != null || _selectedDateTo != null
                                      ? 'No events in selected period'
                                      : 'Tap a point on the chart to filter events',
                                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'No chart data available',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildPeriodButton(String period, String label) {
    final isSelected = _chartPeriod == period;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: ElevatedButton(
          onPressed: () {
            setState(() {
              _chartPeriod = period;
              _selectedDateFrom = null;
              _selectedDateTo = null;
            });
            _applyDateFilters();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.surface,
            foregroundColor: isSelected
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.onSurface,
            side: BorderSide(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outline.withOpacity(0.2),
            ),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            minimumSize: const Size(0, 32),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ),
    );
  }
  
  // Build custom tooltip widget that follows the selected point
  Widget _buildCustomTooltip(
    BuildContext context,
    ChartData selectedPoint,
    double minX,
    double maxX,
    double minY,
    double maxY,
    List<ChartData> chartDataList,
  ) {
    if (!selectedPoint.hasTransactions || selectedPoint.events.isEmpty) {
      return const SizedBox.shrink();
    }
    
    // Calculate position of the selected point on the chart
    final RenderBox? renderBox = _chartKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return const SizedBox.shrink();
    
    final chartWidth = renderBox.size.width;
    final chartHeight = renderBox.size.height;
    
    // Calculate X position (0.0 to 1.0)
    final xPercent = (selectedPoint.date.millisecondsSinceEpoch - minX) / (maxX - minX);
    final pointX = xPercent * chartWidth;
    
    // Calculate Y position (0.0 to 1.0, but Y axis is inverted in Flutter)
    final yRange = maxY - minY;
    final yPercent = (selectedPoint.debt - minY) / yRange;
    final pointY = chartHeight - (yPercent * chartHeight); // Invert Y for screen coordinates
    
    // Format debt amount and date
    final debtAmount = NumberFormat('#,###').format(selectedPoint.debt.toInt());
    final dateFormat = DateFormat('MM/dd/yyyy');
    final dateStr = dateFormat.format(selectedPoint.date);
    
    // Determine tooltip position ensuring it never covers the selected point
    const tooltipWidth = 120.0;
    const tooltipHeight = 70.0;
    const pointRadius = 5.0; // Radius of the yellow circle
    const spacing = 20.0; // Minimum space between point and tooltip
    
    double tooltipX;
    double tooltipY;
    
    // Check if point would be covered by tooltip in different positions
    // Try to place tooltip to the right of point
    final rightX = pointX + pointRadius + spacing;
    if (rightX + tooltipWidth < chartWidth) {
      // Check if this position would cover the point
      if (!(rightX <= pointX + pointRadius && rightX + tooltipWidth >= pointX - pointRadius &&
            pointY >= pointY - pointRadius && pointY <= pointY + pointRadius)) {
        tooltipX = rightX;
        tooltipY = pointY - (tooltipHeight / 2.0);
      } else {
        // Would cover, try left
        final leftX = pointX - pointRadius - spacing - tooltipWidth;
        if (leftX >= 0) {
          tooltipX = leftX;
          tooltipY = pointY - (tooltipHeight / 2.0);
        } else {
          // Try above
          tooltipX = pointX - (tooltipWidth / 2.0);
          tooltipY = pointY - tooltipHeight - spacing - pointRadius;
        }
      }
    }
    // Try to place tooltip to the left of point
    else {
      final leftX = pointX - pointRadius - spacing - tooltipWidth;
      if (leftX >= 0) {
        tooltipX = leftX;
        tooltipY = pointY - (tooltipHeight / 2.0);
      }
      // No space on sides, place above the point
      else if (pointY - tooltipHeight - spacing - pointRadius > 0) {
        tooltipX = pointX - (tooltipWidth / 2.0);
        tooltipY = pointY - tooltipHeight - spacing - pointRadius;
      }
      // No space above, place below the point
      else {
        tooltipX = pointX - (tooltipWidth / 2.0);
        tooltipY = pointY + pointRadius + spacing;
      }
    }
    
    // Clamp tooltip position to stay within chart bounds
    tooltipX = tooltipX.clamp(0.0, chartWidth - tooltipWidth);
    tooltipY = tooltipY.clamp(0.0, chartHeight - tooltipHeight);
    
    // Final check: ensure tooltip doesn't cover the point after clamping
    final pointInTooltipX = pointX >= tooltipX && pointX <= tooltipX + tooltipWidth;
    final pointInTooltipY = pointY >= tooltipY && pointY <= tooltipY + tooltipHeight;
    
    if (pointInTooltipX && pointInTooltipY) {
      // Point would be covered, adjust position
      if (pointY > tooltipY + tooltipHeight / 2.0) {
        // Point is in lower half, move tooltip up
        tooltipY = pointY - tooltipHeight - spacing - pointRadius;
      } else {
        // Point is in upper half, move tooltip down
        tooltipY = pointY + pointRadius + spacing;
      }
      // Re-clamp after adjustment
      tooltipY = tooltipY.clamp(0.0, chartHeight - tooltipHeight);
    }
    
    return Positioned(
      left: tooltipX,
      top: tooltipY,
      child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            color: Theme.of(context).colorScheme.surface,
            child: Container(
              width: tooltipWidth,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateStr,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$debtAmount IQD',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }
}


class ChartDataPoint {
  final double x;
  final double y;
  final DateTime intervalStart;
  final DateTime intervalEnd;
  final bool hasTransactions;
  final List<Event> events; // Store events in this interval for tooltip

  ChartDataPoint({
    required this.x,
    required this.y,
    required this.intervalStart,
    required this.intervalEnd,
    required this.hasTransactions,
    this.events = const [],
  });
}
