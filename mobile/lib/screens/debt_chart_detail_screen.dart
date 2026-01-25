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
  
  // Filters (same as events log but without search)
  String _eventTypeFilter = 'all';
  String _aggregateTypeFilter = 'all';
  bool _showFilters = false;

  @override
  void initState() {
    super.initState();
    _selectedDateFrom = widget.initialDateFrom;
    _selectedDateTo = widget.initialDateTo;
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

  Future<void> _loadChartData() async {
    setState(() {
      _loading = true;
    });

    try {
      final events = await EventStoreService.getAllEvents();
      // Filter events that have total_debt in eventData
      final eventsWithDebt = events.where((e) {
        final totalDebt = e.eventData['total_debt'];
        return totalDebt != null && totalDebt is num;
      }).toList();
      
      // Sort by timestamp (oldest first for chart)
      eventsWithDebt.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      
      // Pre-load contact names for tooltip
      await _preloadContactNames(eventsWithDebt);
      
      // Pre-load undone events cache
      await _preloadUndoneEvents(eventsWithDebt);
      
      setState(() {
        _allEvents = eventsWithDebt;
        _filteredEvents = eventsWithDebt;
        _loading = false;
      });
      
      _applyDateFilters();
    } catch (e) {
      print('Error loading chart data: $e');
      setState(() {
        _loading = false;
      });
    }
  }

  void _applyDateFilters() {
    if (_allEvents == null) return;
    
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
    
    setState(() {
      _filteredEvents = filtered;
    });
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
      _selectedDateFrom = intervalStart;
      _selectedDateTo = intervalEnd;
    });
    _applyDateFilters();
  }

  List<ChartDataPoint> _buildChartData() {
    if (_allEvents == null || _allEvents!.isEmpty) return [];
    
    final now = DateTime.now();
    DateTime periodStart;
    int intervalMs;
    
    switch (_chartPeriod) {
      case 'week':
        periodStart = now.subtract(const Duration(days: 7));
        intervalMs = 24 * 60 * 60 * 1000; // 1 day intervals
        break;
      case 'month':
        periodStart = now.subtract(const Duration(days: 30));
        intervalMs = 24 * 60 * 60 * 1000; // 1 day intervals
        break;
      case 'year':
        periodStart = now.subtract(const Duration(days: 365));
        intervalMs = 7 * 24 * 60 * 60 * 1000; // 1 week intervals
        break;
      default:
        periodStart = now.subtract(const Duration(days: 30));
        intervalMs = 24 * 60 * 60 * 1000;
    }
    
    final eventsInPeriod = _allEvents!.where((e) => 
      e.timestamp.isAfter(periodStart) || e.timestamp.isAtSameMomentAs(periodStart)
    ).toList();
    
    if (eventsInPeriod.isEmpty) return [];
    
    final minDate = periodStart.millisecondsSinceEpoch;
    final maxDate = now.millisecondsSinceEpoch;
    final numIntervals = ((maxDate - minDate) / intervalMs).ceil();
    
    final chartData = <ChartDataPoint>[];
    
    for (int i = 0; i <= numIntervals; i++) {
      final intervalStart = minDate + (i * intervalMs);
      final intervalEnd = (intervalStart + intervalMs).clamp(minDate, maxDate);
      final intervalCenter = (intervalStart + intervalEnd) / 2;
      
      final intervalStartDate = DateTime.fromMillisecondsSinceEpoch(intervalStart.toInt());
      final intervalEndDate = DateTime.fromMillisecondsSinceEpoch(intervalEnd.toInt());
      
      // Find events in this interval
      final eventsInInterval = eventsInPeriod.where((e) {
        final eventTime = e.timestamp.millisecondsSinceEpoch;
        return eventTime >= intervalStart && eventTime < intervalEnd;
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
                      child: Builder(
                        builder: (context) {
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
                              ? (yRange * 0.2).clamp(5000, 200000) 
                              : (rawMinY.abs() * 0.15).clamp(5000, 200000);
                          final yPaddingTop = yRange > 0 ? yRange * 0.1 : (rawMaxY.abs() * 0.05).clamp(1000, 100000);
                          
                          final invertY = ref.watch(invertYAxisProvider);
                          final finalMinY = invertY ? -(rawMaxY + yPaddingTop) : rawMinY - yPaddingBottom;
                          final finalMaxY = invertY ? -(rawMinY - yPaddingBottom) : rawMaxY + yPaddingTop;
                          
                          // Convert to Syncfusion format - include ALL points for line connection
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
                          
                          // Use accent color for all points
                          final primaryColor = Theme.of(context).colorScheme.primary;
                          
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
                          
                          return SfCartesianChart(
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
                              majorGridLines: const MajorGridLines(width: 0),
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
                                splineType: SplineType.natural,
                                animationDuration: 0,
                                enableTooltip: true, // Enable tooltip on series
                                emptyPointSettings: EmptyPointSettings(
                                  mode: EmptyPointMode.gap,
                                ),
                                markerSettings: MarkerSettings(
                                  isVisible: true, // Show markers with accent color
                                  height: 6,
                                  width: 6,
                                  shape: DataMarkerType.circle,
                                  color: primaryColor,
                                  borderColor: primaryColor,
                                  borderWidth: 0,
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
                                  if (details.pointIndex != null && 
                                      details.pointIndex! >= 0 &&
                                      details.pointIndex! < chartDataList.length) {
                                    final point = chartDataList[details.pointIndex!];
                                    if (point.hasTransactions) {
                                      _onChartPointTapped(point.intervalStart, point.intervalEnd);
                                    }
                                  }
                                },
                                ),
                            ],
                            tooltipBehavior: TooltipBehavior(
                              enable: true,
                              activationMode: ActivationMode.singleTap, // Show on tap, not hover
                              color: Theme.of(context).colorScheme.surface,
                              textStyle: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 9,
                              ),
                              borderWidth: 1,
                              borderColor: primaryColor,
                              duration: 3000, // Show for 3 seconds
                              builder: (dynamic data, dynamic point, dynamic series, int pointIndex, int seriesIndex) {
                                // Safety check: pointIndex must be valid
                                if (pointIndex < 0 || pointIndex >= chartDataList.length) {
                                  return const SizedBox.shrink();
                                }
                                
                                final chartData = data as ChartData;
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
                            ),
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
