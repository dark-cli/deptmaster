import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
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
                      child: LineChart(
                        LineChartData(
                          clipData: FlClipData.all(), // Clip data to chart bounds
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            getDrawingHorizontalLine: (value) {
                              return FlLine(
                                color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
                                strokeWidth: 1,
                              );
                            },
                          ),
                          titlesData: FlTitlesData(
                            show: true,
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 20,
                                interval: chartData.length > 4 
                                    ? (chartData.last.x - chartData.first.x) / 4 
                                    : 1,
                                getTitlesWidget: (value, meta) {
                                  final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                                  String format;
                                  switch (_chartPeriod) {
                                    case 'week':
                                      format = 'MM/dd';
                                      break;
                                    case 'month':
                                      format = 'MM/dd';
                                      break;
                                    case 'year':
                                      format = 'MM/yy';
                                      break;
                                    default:
                                      format = 'MM/dd';
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      DateFormat(format).format(date),
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 40,
                                getTitlesWidget: (value, meta) {
                                  // Compact format: K for thousands, M for millions
                                  final num = value.toInt();
                                  String formatted;
                                  if (num.abs() >= 1000000) {
                                    formatted = '${(num / 1000000).toStringAsFixed(1)}M';
                                  } else if (num.abs() >= 1000) {
                                    formatted = '${(num / 1000).toStringAsFixed(1)}K';
                                  } else {
                                    formatted = num.toString();
                                  }
                                  return Text(
                                    formatted,
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          borderData: FlBorderData(
                            show: true,
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                            ),
                          ),
                          minX: chartData.isNotEmpty 
                              ? () {
                                  final allX = chartData.map((d) => d.x).toList();
                                  final rawMinX = allX.reduce((a, b) => a < b ? a : b);
                                  final rawMaxX = allX.reduce((a, b) => a > b ? a : b);
                                  final xRange = rawMaxX - rawMinX;
                                  final xPadding = xRange > 0 ? xRange * 0.02 : 86400000;
                                  return rawMinX - xPadding;
                                }()
                              : 0,
                          maxX: chartData.isNotEmpty
                              ? () {
                                  final allX = chartData.map((d) => d.x).toList();
                                  final rawMinX = allX.reduce((a, b) => a < b ? a : b);
                                  final rawMaxX = allX.reduce((a, b) => a > b ? a : b);
                                  final xRange = rawMaxX - rawMinX;
                                  final xPadding = xRange > 0 ? xRange * 0.02 : 86400000;
                                  return rawMaxX + xPadding;
                                }()
                              : 1,
                          minY: chartData.isNotEmpty 
                              ? () {
                                  final allY = chartData.map((d) => d.y).toList();
                                  final rawMinY = allY.reduce((a, b) => a < b ? a : b);
                                  final rawMaxY = allY.reduce((a, b) => a > b ? a : b);
                                  final yRange = rawMaxY - rawMinY;
                                  // Use larger padding at bottom to prevent touching X-axis (20% of range or minimum)
                                  final yPaddingBottom = yRange > 0 
                                      ? (yRange * 0.2).clamp(5000, 200000) 
                                      : (rawMinY.abs() * 0.15).clamp(5000, 200000);
                                  final yPaddingTop = yRange > 0 ? yRange * 0.1 : (rawMaxY.abs() * 0.05).clamp(1000, 100000);
                                  // Check invert Y-axis setting
                                  final invertY = ref.watch(invertYAxisProvider);
                                  // When inverted, multiply by -1 to flip the axis
                                  return invertY ? -(rawMaxY + yPaddingTop) : rawMinY - yPaddingBottom;
                                }()
                              : 0,
                          maxY: chartData.isNotEmpty
                              ? () {
                                  final allY = chartData.map((d) => d.y).toList();
                                  final rawMinY = allY.reduce((a, b) => a < b ? a : b);
                                  final rawMaxY = allY.reduce((a, b) => a > b ? a : b);
                                  final yRange = rawMaxY - rawMinY;
                                  // Top padding can be smaller
                                  final yPaddingTop = yRange > 0 ? yRange * 0.1 : (rawMaxY.abs() * 0.05).clamp(1000, 100000);
                                  final yPaddingBottom = yRange > 0 
                                      ? (yRange * 0.2).clamp(5000, 200000) 
                                      : (rawMinY.abs() * 0.15).clamp(5000, 200000);
                                  // Check invert Y-axis setting
                                  final invertY = ref.watch(invertYAxisProvider);
                                  // When inverted, multiply by -1 to flip the axis
                                  return invertY ? -(rawMinY - yPaddingBottom) : rawMaxY + yPaddingTop;
                                }()
                              : 1,
                          lineBarsData: [
                            LineChartBarData(
                              spots: () {
                                // When Y-axis is inverted, simply multiply Y values by -1
                                final invertY = ref.watch(invertYAxisProvider);
                                final allY = chartData.map((d) => d.y).toList();
                                if (allY.isEmpty) return <FlSpot>[];
                                final rawMinY = allY.reduce((a, b) => a < b ? a : b);
                                final rawMaxY = allY.reduce((a, b) => a > b ? a : b);
                                final yRange = rawMaxY - rawMinY;
                                if (yRange == 0) {
                                  return chartData.map((d) => FlSpot(d.x, invertY ? -d.y : d.y)).toList();
                                }
                                // Use larger padding at bottom to prevent touching X-axis
                                final yPaddingBottom = yRange > 0 
                                    ? (yRange * 0.2).clamp(5000, 200000) 
                                    : (rawMinY.abs() * 0.15).clamp(5000, 200000);
                                final yPaddingTop = yRange > 0 ? yRange * 0.1 : (rawMaxY.abs() * 0.05).clamp(1000, 100000);
                                final finalMinY = invertY ? -(rawMaxY + yPaddingTop) : rawMinY - yPaddingBottom;
                                final finalMaxY = invertY ? -(rawMinY - yPaddingBottom) : rawMaxY + yPaddingTop;
                                
                                return chartData.map((d) {
                                  // When inverted, multiply by -1; otherwise use original value
                                  final yValue = invertY ? -d.y : d.y;
                                  // Ensure point is within bounds with a small margin to avoid touching edges
                                  final margin = (finalMaxY - finalMinY) * 0.02; // 2% margin
                                  return FlSpot(d.x, yValue.clamp(finalMinY + margin, finalMaxY - margin));
                                }).toList();
                              }(),
                              isCurved: true,
                              color: primaryColor,
                              barWidth: 2,
                              dotData: FlDotData(
                                show: true,
                                getDotPainter: (spot, percent, barData, index) {
                                  final point = chartData[index];
                                  return FlDotCirclePainter(
                                    radius: point.hasTransactions ? 2.5 : 0,
                                    color: primaryColor,
                                    strokeWidth: 1.5,
                                    strokeColor: Theme.of(context).colorScheme.surface,
                                  );
                                },
                              ),
                              belowBarData: BarAreaData(
                                show: true,
                                color: primaryColor.withOpacity(0.1),
                              ),
                            ),
                          ],
                          lineTouchData: LineTouchData(
                            enabled: true,
                            touchTooltipData: LineTouchTooltipData(
                              tooltipRoundedRadius: 6,
                              tooltipPadding: const EdgeInsets.all(8),
                              tooltipBgColor: Theme.of(context).colorScheme.surface,
                              tooltipBorder: BorderSide(
                                color: primaryColor,
                                width: 1,
                              ),
                              getTooltipItems: (List<LineBarSpot> touchedSpots) {
                                // Must return one item per touched spot
                                return touchedSpots.map((touchedSpot) {
                                  final point = chartData[touchedSpot.spotIndex];
                                  
                                  // Only show tooltip if this point has transactions
                                  if (!point.hasTransactions || point.events.isEmpty) {
                                    // Return empty item to hide tooltip
                                    return LineTooltipItem(
                                      '',
                                      const TextStyle(fontSize: 0),
                                    );
                                  }
                                  
                                  // Build compact tooltip content
                                  final buffer = StringBuffer();
                                  
                                  // Compact time interval
                                  String titleFormat;
                                  switch (_chartPeriod) {
                                    case 'week':
                                    case 'month':
                                      titleFormat = 'MM/dd HH:mm';
                                      break;
                                    case 'year':
                                      titleFormat = 'MM/dd';
                                      break;
                                    default:
                                      titleFormat = 'MM/dd HH:mm';
                                  }
                                  
                                  final intervalFormat = DateFormat(titleFormat);
                                  buffer.write('${intervalFormat.format(point.intervalStart)}-${intervalFormat.format(point.intervalEnd)}');
                                  
                                  // Compact average and count
                                  final avgDebt = NumberFormat('#,###').format(point.y.toInt());
                                  buffer.write('\n$avgDebt IQD • ${point.events.length}tx');
                                  
                                  // Show up to 3 transactions (reduced from 4)
                                  final maxShow = 3;
                                  final eventsToShow = point.events.take(maxShow).toList();
                                  
                                  for (final event in eventsToShow) {
                                    final eventData = event.eventData;
                                    final timeStr = DateFormat('HH:mm').format(event.timestamp);
                                    
                                    buffer.write('\n$timeStr ');
                                    
                                    if (eventData['amount'] != null) {
                                      final amount = (eventData['amount'] as num).toDouble();
                                      final direction = eventData['direction'] as String? ?? 'owed';
                                      final sign = direction == 'lent' ? '+' : '-';
                                      // Use compact format without currency
                                      buffer.write('$sign${NumberFormat('#,###').format(amount.toInt())}');
                                    } else {
                                      // Abbreviate event type
                                      final eventType = event.eventType;
                                      if (eventType.length > 8) {
                                        buffer.write(eventType.substring(0, 8));
                                      } else {
                                        buffer.write(eventType);
                                      }
                                    }
                                    
                                    // Try to get contact name (abbreviated if long)
                                    final contactId = eventData['contact_id'] as String?;
                                    if (contactId != null) {
                                      final contactName = _contactNameCache[contactId] ?? '?';
                                      if (contactName.length > 12) {
                                        buffer.write(' • ${contactName.substring(0, 12)}...');
                                      } else {
                                        buffer.write(' • $contactName');
                                      }
                                    }
                                  }
                                  
                                  if (point.events.length > maxShow) {
                                    buffer.write('\n+${point.events.length - maxShow}');
                                  }
                                  
                                  return LineTooltipItem(
                                    buffer.toString().trim(),
                                    TextStyle(
                                      color: Theme.of(context).colorScheme.onSurface,
                                      fontSize: 9, // Reduced from 11
                                    ),
                                  );
                                }).toList();
                              },
                            ),
                            touchCallback: (FlTouchEvent event, LineTouchResponse? touchResponse) {
                              if (event is FlTapUpEvent && touchResponse != null) {
                                final spot = touchResponse.lineBarSpots?.firstOrNull;
                                if (spot != null) {
                                  final point = chartData[spot.spotIndex];
                                  if (point.hasTransactions) {
                                    _onChartPointTapped(point.intervalStart, point.intervalEnd);
                                  }
                                }
                              }
                            },
                          ),
                        ),
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
