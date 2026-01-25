import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive_flutter/hive_flutter.dart';
import '../models/event.dart';
import '../services/event_store_service.dart';
import '../services/local_database_service_v2.dart';
import '../services/realtime_service.dart';
import '../providers/settings_provider.dart';
import '../utils/app_colors.dart';

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

// Data model for Syncfusion charts
class ChartData {
  final DateTime date;
  final double debt; // Debt value after inversion/clamping (for display)
  final double originalDebt; // Original debt value before inversion (for coloring)
  final bool hasTransactions;
  final List<Event> events;
  final String? dominantDirection; // 'lent' or 'owed' - dominant direction in this point's events

  ChartData({
    required this.date,
    required this.debt,
    required this.originalDebt,
    required this.hasTransactions,
    this.events = const [],
    this.dominantDirection,
  });
}

/// Simple debt over time chart widget for dashboard
class DebtChartWidget extends ConsumerStatefulWidget {
  final VoidCallback? onTap; // Called when chart is tapped to open detailed view
  
  const DebtChartWidget({super.key, this.onTap});

  @override
  ConsumerState<DebtChartWidget> createState() => _DebtChartWidgetState();
}

class _DebtChartWidgetState extends ConsumerState<DebtChartWidget> {
  List<Event>? _events;
  bool _loading = true;
  Map<String, String> _contactNameCache = {}; // Cache for contact names

  @override
  void initState() {
    super.initState();
    _loadChartData();
    
    // Listen for real-time updates
    RealtimeService.addListener(_onRealtimeUpdate);
    
    // Listen to Hive events box changes for offline updates
    if (!kIsWeb) {
      _setupEventBoxListener();
    }
  }
  
  void _setupEventBoxListener() {
    try {
      final eventsBox = Hive.box<Event>(EventStoreService.eventsBoxName);
      eventsBox.listenable().addListener(_onEventsChanged);
    } catch (e) {
      // Box might not be open yet, will retry in _loadChartData
    }
  }
  
  void _onEventsChanged() {
    // Reload chart when events box changes
    if (mounted) {
      _loadChartData();
    }
  }
  
  void _onRealtimeUpdate(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    // Reload chart on any event-related updates
    if (type != null && (type.contains('transaction') || type.contains('contact'))) {
      if (mounted) {
        _loadChartData();
      }
    }
  }
  
  @override
  void dispose() {
    if (!kIsWeb) {
      try {
        final eventsBox = Hive.box<Event>(EventStoreService.eventsBoxName);
        eventsBox.listenable().removeListener(_onEventsChanged);
      } catch (e) {
        // Box might not be open, ignore
      }
    }
    RealtimeService.removeListener(_onRealtimeUpdate);
    super.dispose();
  }

  Future<void> _loadChartData() async {
    if (!mounted) return;
    
    try {
      final events = await EventStoreService.getAllEvents();
      
      if (!mounted) return;
      
      print('📊 Loaded ${events.length} total events from EventStoreService');
      
      // Filter events that have total_debt in eventData
      final eventsWithDebt = events.where((e) {
        final totalDebt = e.eventData['total_debt'];
        final hasDebt = totalDebt != null && totalDebt is num;
        if (!hasDebt && events.indexOf(e) < 5) {
          // Log first 5 events without total_debt for debugging
          print('⚠️ Event ${e.id} (${e.eventType}) missing total_debt. eventData keys: ${e.eventData.keys.toList()}');
        }
        return hasDebt;
      }).toList();
      
      print('📊 Found ${eventsWithDebt.length} events with total_debt out of ${events.length} total events');
      
      if (eventsWithDebt.isEmpty && events.isNotEmpty) {
        print('⚠️ WARNING: No events have total_debt! This may indicate a data issue.');
        // Show sample of event types
        final eventTypes = events.take(10).map((e) => e.eventType).toSet();
        print('📊 Sample event types: ${eventTypes.join(", ")}');
      }
      
      // Sort by timestamp (oldest first for chart)
      eventsWithDebt.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      
      if (!mounted) return;
      
      // Pre-load contact names for tooltip
      await _preloadContactNames(eventsWithDebt);
      
      if (!mounted) return;
      
      setState(() {
        _events = eventsWithDebt;
        _loading = false;
      });
    } catch (e) {
      print('❌ Error loading chart data: $e');
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }
  
  Future<void> _preloadContactNames(List<Event> events) async {
    if (!mounted) return;
    
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

  List<ChartDataPoint> _buildChartData() {
    if (_events == null || _events!.isEmpty) {
      print('⚠️ No events available for chart');
      return [];
    }
    
    if (!mounted) {
      return [];
    }
    
    print('📊 Building chart from ${_events!.length} events');
    
    // Get period from settings - watch it so it updates reactively
    final period = ref.watch(dashboardDefaultPeriodProvider);
    final now = DateTime.now();
    DateTime periodStart;
    int intervalMs;
    
    switch (period) {
      case 'day':
        periodStart = now.subtract(const Duration(days: 1));
        intervalMs = 60 * 60 * 1000; // 1 hour intervals
        break;
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
        intervalMs = 24 * 60 * 60 * 1000; // 1 day intervals
    }
    
    // Get all events (not just recent ones) for fallback
    final allEvents = _events!;
    
    // Get events in period
    final eventsInPeriod = allEvents.where((e) => 
      e.timestamp.isAfter(periodStart.subtract(const Duration(seconds: 1))) || 
      e.timestamp.isAtSameMomentAs(periodStart)
    ).toList();
    
    print('📊 Events in period (last 30 days): ${eventsInPeriod.length}');
    
    final minDate = periodStart.millisecondsSinceEpoch;
    final maxDate = now.millisecondsSinceEpoch;
    final numIntervals = ((maxDate - minDate) / intervalMs).ceil();
    
    print('📊 Creating $numIntervals intervals from ${DateTime.fromMillisecondsSinceEpoch(minDate)} to ${DateTime.fromMillisecondsSinceEpoch(maxDate)}');
    
    final chartData = <ChartDataPoint>[];
    
    // Get the most recent total_debt before period start for fallback
    double? fallbackDebt;
    final beforePeriodEvents = allEvents.where((e) => 
      e.timestamp.isBefore(periodStart)
    ).toList();
    if (beforePeriodEvents.isNotEmpty) {
      final lastBeforePeriod = beforePeriodEvents.last;
      fallbackDebt = (lastBeforePeriod.eventData['total_debt'] as num).toDouble();
      print('📊 Using fallback debt: $fallbackDebt from event at ${lastBeforePeriod.timestamp}');
    } else if (allEvents.isNotEmpty) {
      fallbackDebt = (allEvents.first.eventData['total_debt'] as num).toDouble();
      print('📊 Using first event debt as fallback: $fallbackDebt');
    }
    
    // If no fallback debt, we can't build a chart
    if (fallbackDebt == null) {
      print('⚠️ No fallback debt available, cannot build chart');
      return [];
    }
    
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
        // Find closest event before this interval (within period)
        final beforeEvents = eventsInPeriod.where((e) => 
          e.timestamp.millisecondsSinceEpoch < intervalStart
        ).toList();
        if (beforeEvents.isNotEmpty) {
          final closestBefore = beforeEvents.last;
          avgDebt = (closestBefore.eventData['total_debt'] as num).toDouble();
        } else {
          // Use fallback debt (from before period or first event)
          avgDebt = fallbackDebt!;
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
    
    print('📊 Built ${chartData.length} chart data points');
    if (chartData.isNotEmpty) {
      print('📊 First point: x=${chartData.first.x}, y=${chartData.first.y}');
      print('📊 Last point: x=${chartData.last.x}, y=${chartData.last.y}');
    }
    return chartData;
  }

  @override
  Widget build(BuildContext context) {
    if (!mounted) {
      return const SizedBox.shrink();
    }
    
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.darkPrimary : AppColors.lightPrimary;
    
    if (_loading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    
    final chartData = _buildChartData();
    
    if (chartData.isEmpty) {
      print('⚠️ Chart data is empty, showing empty state');
      return Container(
        height: 200,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          ),
        ),
        child: Center(
          child: Text(
            'No chart data available',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ),
      );
    }
    
    print('📊 Rendering chart with ${chartData.length} points');
    
    // Calculate min/max for proper boundaries with padding
    final allYValues = chartData.map((d) => d.y).toList();
    final rawMinY = allYValues.reduce((a, b) => a < b ? a : b);
    final rawMaxY = allYValues.reduce((a, b) => a > b ? a : b);
    
    // Add padding to Y axis to ensure points don't touch the X-axis
    final yRange = rawMaxY - rawMinY;
    // Calculate padding: 10% of range, but ensure at least some minimum padding
    final yPaddingTop = yRange > 0 ? yRange * 0.1 : (rawMaxY.abs() * 0.05).clamp(1000, 100000);
    // For bottom padding, ensure there's always room below the lowest point
    // Use larger padding at bottom to prevent touching X-axis (20% of range or minimum)
    final yPaddingBottom = yRange > 0 
        ? (yRange * 0.2).clamp(5000, 200000) 
        : (rawMinY.abs() * 0.15).clamp(5000, 200000);
    
    // Check invert Y-axis setting - use watch so it updates reactively
    final invertY = ref.watch(invertYAxisProvider);
    
    // Calculate bounds - when inverted, multiply by -1 to flip the axis
    final finalMinY = invertY ? -(rawMaxY + yPaddingTop) : rawMinY - yPaddingBottom;
    final finalMaxY = invertY ? -(rawMinY - yPaddingBottom) : rawMaxY + yPaddingTop;
    
    // Ensure X bounds cover all points with small padding
    final allXValues = chartData.map((d) => d.x).toList();
    final rawMinX = allXValues.reduce((a, b) => a < b ? a : b);
    final rawMaxX = allXValues.reduce((a, b) => a > b ? a : b);
    final xRange = rawMaxX - rawMinX;
    final xPadding = xRange > 0 ? xRange * 0.02 : 86400000; // 1 day if no range
    final minX = rawMinX - xPadding;
    final maxX = rawMaxX + xPadding;
    
    print('📊 Chart bounds: X=[$minX, $maxX], Y=[$finalMinY, $finalMaxY]');
    print('📊 Data range: X=[$rawMinX, $rawMaxX], Y=[$rawMinY, $rawMaxY]');
    print('📊 Inverted: $invertY, minY=$finalMinY, maxY=$finalMaxY');
    
    // Build chart data for Syncfusion - include ALL points for smooth line connection
    // Sort by date to ensure proper line connection
    final sortedChartData = List<ChartDataPoint>.from(chartData)
      ..sort((a, b) => a.x.compareTo(b.x));
    
    // When Y-axis is inverted, transform the Y values (multiply by -1)
    // We transform the data, not the axis, so we don't use isInversed
    final chartDataList = sortedChartData
        .map((point) {
          // When inverted, multiply by -1; otherwise use original value
          final yValue = invertY ? -point.y : point.y;
          // Ensure point is within bounds with a small margin to avoid touching edges
          final margin = (finalMaxY - finalMinY) * 0.02; // 2% margin
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
            dominantDirection: dominantDirection,
          );
        })
        .toList();
    
    // Use accent color for all points
    
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        height: 250, // Increased height to give more space
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Debt Over Time',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SfCartesianChart(
                backgroundColor: Colors.transparent,
                plotAreaBorderWidth: 0,
                enableAxisAnimation: false,
                primaryXAxis: DateTimeAxis(
                  minimum: DateTime.fromMillisecondsSinceEpoch(minX.toInt()),
                  maximum: DateTime.fromMillisecondsSinceEpoch(maxX.toInt()),
                  intervalType: chartDataList.length > 4 ? DateTimeIntervalType.days : DateTimeIntervalType.auto,
                  labelStyle: TextStyle(
                    fontSize: 9,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                  labelFormat: '{value}',
                  dateFormat: DateFormat('MM/dd'),
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
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                  labelFormat: '{value}',
                  numberFormat: NumberFormat.compact(),
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
                        fontSize: 10,
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
                    enableTooltip: false, // Disable interaction on dashboard chart
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
                  ),
                ],
                tooltipBehavior: TooltipBehavior(
                  enable: false, // Disable interaction on dashboard chart
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Tap to view detailed chart',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
