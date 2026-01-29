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
  bool _isDisposed = false; // Flag to prevent operations after disposal
  bool _isLoading = false; // Guard to prevent concurrent loads
  int _lastEventCount = 0; // Track event count to avoid unnecessary reloads

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
    // Reload chart when events box changes, but only if not already loading
    // and if the event count actually changed (to prevent infinite loops)
    if (!_isDisposed && mounted && !_isLoading) {
      // Check if event count changed before reloading
      EventStoreService.getEventCount().then((count) {
        if (!_isDisposed && mounted && count != _lastEventCount) {
          _lastEventCount = count;
          _loadChartData();
        }
      }).catchError((e) {
        // If we can't get count, reload anyway (better safe than sorry)
        if (!_isDisposed && mounted && !_isLoading) {
          _loadChartData();
        }
      });
    }
  }
  
  void _onRealtimeUpdate(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    // Reload chart on any event-related updates
    if (type != null && (type.contains('transaction') || type.contains('contact'))) {
      if (!_isDisposed && mounted) {
        _loadChartData();
      }
    }
  }
  
  @override
  void dispose() {
    _isDisposed = true; // Set flag before disposal
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
    if (_isDisposed || !mounted || _isLoading) return;
    
    _isLoading = true;
    try {
      final events = await EventStoreService.getAllEvents();
      
      if (_isDisposed || !mounted) return;
      
      // Update last event count to prevent unnecessary reloads
      _lastEventCount = events.length;
      
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
      
      if (_isDisposed || !mounted) return;
      
      // Pre-load contact names for tooltip
      await _preloadContactNames(eventsWithDebt);
      
      if (_isDisposed || !mounted) return;
      
      setState(() {
        if (!_isDisposed) {
          _events = eventsWithDebt;
          _loading = false;
        }
      });
    } catch (e) {
      print('❌ Error loading chart data: $e');
      if (!_isDisposed && mounted) {
        setState(() {
          _loading = false;
        });
      }
    } finally {
      _isLoading = false;
    }
  }
  
  Future<void> _preloadContactNames(List<Event> events) async {
    if (_isDisposed || !mounted) return;
    
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

  List<ChartDataPoint> _buildChartData(String period, bool invertY) {
    if (_events == null || _events!.isEmpty) {
      print('⚠️ No events available for chart');
      return [];
    }
    
    if (!mounted) {
      return [];
    }
    
    print('📊 Building chart from ${_events!.length} events');
    final now = DateTime.now();
    DateTime periodStart;
    int intervalMs;
    
    switch (period) {
      case 'day':
        // Last 24 hours, but align to day boundaries
        periodStart = _alignToDayStart(now.subtract(const Duration(days: 1)));
        intervalMs = 60 * 60 * 1000; // 1 hour intervals
        break;
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
        intervalMs = 24 * 60 * 60 * 1000; // 1 day intervals
    }
    
    // Get all events (not just recent ones) for fallback
    final allEvents = _events!;
    
    // Get events in period
    final eventsInPeriod = allEvents.where((e) => 
      e.timestamp.isAfter(periodStart.subtract(const Duration(seconds: 1))) || 
      e.timestamp.isAtSameMomentAs(periodStart)
    ).toList();
    
    print('📊 Events in period: ${eventsInPeriod.length}');
    
    // Find the actual first event date in the period (or use periodStart if no events)
    DateTime actualStartDate = periodStart;
    if (eventsInPeriod.isNotEmpty) {
      final firstEventDate = eventsInPeriod.map((e) => e.timestamp).reduce((a, b) => a.isBefore(b) ? a : b);
      // Start from the first event date, but align to interval boundary
      // For year view, align to month start; for month view, align to week start; etc.
      if (period == 'year') {
        // Align to month start
        actualStartDate = DateTime(firstEventDate.year, firstEventDate.month, 1);
      } else if (period == 'month') {
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
      print('📊 First event date: $firstEventDate, aligned start: $actualStartDate');
    }
    
    final minDate = actualStartDate.millisecondsSinceEpoch;
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
      // Calculate interval boundaries aligned to calendar units
      DateTime intervalStartDate;
      DateTime intervalEndDate;
      
      if ((period == 'week' || period == 'month') && intervalMs == 24 * 60 * 60 * 1000) {
        // For day intervals in week/month views, align to day boundaries (00:00:00 to 23:59:59.999)
        final baseDate = DateTime.fromMillisecondsSinceEpoch(minDate.toInt());
        intervalStartDate = _alignToDayStart(baseDate.add(Duration(days: i)));
        intervalEndDate = intervalStartDate.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
      } else if (period == 'year' && intervalMs == 7 * 24 * 60 * 60 * 1000) {
        // For week intervals in year view, align to week boundaries (Sunday to Saturday)
        final baseDate = DateTime.fromMillisecondsSinceEpoch(minDate.toInt());
        intervalStartDate = _alignToWeekStart(baseDate.add(Duration(days: i * 7)));
        intervalEndDate = intervalStartDate.add(const Duration(days: 7)).subtract(const Duration(milliseconds: 1));
      } else {
        // For hour intervals or other cases, use millisecond-based calculation
        final intervalStart = minDate + (i * intervalMs);
        final intervalEnd = (intervalStart + intervalMs).clamp(minDate, maxDate);
        intervalStartDate = DateTime.fromMillisecondsSinceEpoch(intervalStart.toInt());
        intervalEndDate = DateTime.fromMillisecondsSinceEpoch(intervalEnd.toInt());
      }
      
      final intervalStart = intervalStartDate.millisecondsSinceEpoch;
      final intervalEnd = intervalEndDate.millisecondsSinceEpoch;
      final intervalCenter = (intervalStart + intervalEnd) / 2;
      
      // Find events in this interval - use proper boundaries
      final eventsInInterval = eventsInPeriod.where((e) {
        final eventTime = e.timestamp.millisecondsSinceEpoch;
        // Include events that fall within the interval (inclusive start, exclusive end for consistency)
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
    if (_isDisposed || !mounted) {
      return const SizedBox.shrink();
    }
    
    // Watch settings providers in build method to ensure widget rebuilds when settings change
    final period = ref.watch(dashboardDefaultPeriodProvider);
    final invertY = ref.watch(invertYAxisProvider);
    
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.darkPrimary : AppColors.lightPrimary;
    
    if (_loading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    
    // Don't build chart if disposed
    if (_isDisposed || !mounted) {
      return const SizedBox.shrink();
    }
    
    final chartData = _buildChartData(period, invertY);
    
    if (chartData.isEmpty) {
      print('⚠️ Chart data is empty, showing empty state');
      return Container(
        height: 200,
        padding: const EdgeInsets.all(8),
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
    
    // Build chart key separately to avoid string interpolation issues
    final chartKeySuffix = invertY ? 'inverted' : 'normal';
    final chartKeyState = _isDisposed ? 'disposed' : 'active';
    final chartKey = 'chart_${period}_${chartKeySuffix}_${chartKeyState}';
    
    // Calculate min/max for proper boundaries with padding
    final allYValues = chartData.map((d) => d.y).toList();
    final rawMinY = allYValues.reduce((a, b) => a < b ? a : b);
    final rawMaxY = allYValues.reduce((a, b) => a > b ? a : b);
    
    // Add padding to Y axis to ensure points don't touch the X-axis
    final yRange = rawMaxY - rawMinY;
    // Calculate padding: 40% of range for both top and bottom (increased buffer)
    final yPaddingTop = yRange > 0 ? yRange * 0.4 : (rawMaxY.abs() * 0.35).clamp(1000, 100000);
    // For bottom padding, ensure there's always room below the lowest point
    // Use same padding at bottom as top for consistency (40% of range or minimum)
    final yPaddingBottom = yRange > 0 
        ? (yRange * 0.4).clamp(5000, 200000) 
        : (rawMinY.abs() * 0.35).clamp(5000, 200000);
    
    // Calculate bounds - when inverted, multiply by -1 to flip the axis
    final finalMinY = invertY ? -(rawMaxY + yPaddingTop) : rawMinY - yPaddingBottom;
    final finalMaxY = invertY ? -(rawMinY - yPaddingBottom) : rawMaxY + yPaddingTop;
    
    // Ensure X bounds cover all points with small padding
    final allXValues = chartData.map((d) => d.x).toList();
    final rawMinX = allXValues.reduce((a, b) => a < b ? a : b);
    final rawMaxX = allXValues.reduce((a, b) => a > b ? a : b);
    final xRange = rawMaxX - rawMinX;
    final xPadding = xRange > 0 ? xRange * 0.02 : 86400000; // 1 day if no range
    var minX = rawMinX - xPadding;
    var maxX = rawMaxX + xPadding;
    
    // Calculate interval for even spacing based on period
    double xInterval;
    int minorTicksPerInterval;
    DateTimeIntervalType xIntervalType;
    DateFormat dateFormat;
    
    if (period == 'year') {
      // Year View: Major marks each month, minor marks each week
      xIntervalType = DateTimeIntervalType.months;
      xInterval = 1.0;
      minorTicksPerInterval = 3; // Approximately 4 weeks per month
      dateFormat = DateFormat('MMM'); // e.g., "Dec", "Jan", "Feb"
    } else if (period == 'month') {
      // Month View: Major marks each week, minor marks each day
      // Align minimum to ensure first mark appears near data start
      // Calculate where the first mark should be (nearest 7-day boundary from data start)
      final dataStartDate = DateTime.fromMillisecondsSinceEpoch(rawMinX.toInt());
      final weekday = dataStartDate.weekday; // 1=Monday, 7=Sunday
      final daysSinceSunday = weekday == 7 ? 0 : weekday; // Days since last Sunday
      // Round down to nearest 7-day boundary, but only if it's close (within 2 days) to avoid large empty space
      if (daysSinceSunday <= 2) {
        final alignedStart = dataStartDate.subtract(Duration(days: daysSinceSunday));
        // Only adjust if it doesn't create too much empty space (max 2 days)
        final daysDifference = (minX - alignedStart.millisecondsSinceEpoch) / (1000 * 60 * 60 * 24);
        if (daysDifference <= 2) {
          minX = alignedStart.millisecondsSinceEpoch.toDouble();
        }
      }
      
      // Use fixed 7-day interval for consistent weekly marks
      xIntervalType = DateTimeIntervalType.days;
      xInterval = 7.0; // Fixed weekly interval
      minorTicksPerInterval = 6; // Daily minor ticks (6 days between weekly marks)
      dateFormat = DateFormat('MM/dd'); // e.g., "12/28", "01/04"
    } else {
      // Week View: Major marks each day, no minor marks
      xIntervalType = DateTimeIntervalType.days;
      xInterval = 1.0;
      minorTicksPerInterval = 0;
      dateFormat = DateFormat('MM/dd'); // e.g., "12/28", "12/29"
    }
    
    print('📊 Chart bounds: X=[$minX, $maxX], Y=[$finalMinY, $finalMaxY]');
    print('📊 Data range: X=[$rawMinX, $rawMaxX], Y=[$rawMinY, $rawMaxY]');
    print('📊 Inverted: $invertY, minY=$finalMinY, maxY=$finalMaxY');
    print('📊 X-axis interval: $xInterval, type: $xIntervalType, minorTicks: $minorTicksPerInterval');
    if (minorTicksPerInterval > 0) {
      print('📊 Minor ticks should be visible: $minorTicksPerInterval ticks per interval');
    }
    
    // Build chart data for Syncfusion - include ALL points for correct line progression
    // Points without transactions will have hidden markers but still contribute to the line
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
        padding: const EdgeInsets.all(8),
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
            Expanded(
              child: (_isDisposed || !mounted)
                  ? const SizedBox.shrink()
                  : RepaintBoundary(
                      child: SfCartesianChart(
                        key: ValueKey(chartKey),
                        backgroundColor: Colors.transparent,
                        plotAreaBorderWidth: 0,
                        plotAreaBorderColor: Colors.transparent,
                        plotAreaBackgroundColor: Colors.transparent,
                        margin: EdgeInsets.zero,
                        enableAxisAnimation: false,
                        primaryXAxis: DateTimeAxis(
                    minimum: DateTime.fromMillisecondsSinceEpoch(minX.toInt()),
                    maximum: DateTime.fromMillisecondsSinceEpoch(maxX.toInt()),
                    intervalType: xIntervalType,
                    interval: xInterval, // Dynamically calculated for even spacing
                    // NOTE: Syncfusion Flutter Charts does NOT support minor ticks for DateTimeAxis
                    // The minorTicksPerInterval property exists but has no effect on DateTimeAxis
                    // This is a known limitation of the library - minor marks cannot be displayed
                    labelStyle: TextStyle(
                      fontSize: 9,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                    labelFormat: '{value}',
                    dateFormat: dateFormat,
                    majorGridLines: MajorGridLines(
                      width: 1,
                      color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
                    ),
                    majorTickLines: MajorTickLines(
                      width: 1,
                      color: Theme.of(context).colorScheme.outline.withOpacity(0.4),
                    ),
                    minorTickLines: const MinorTickLines(width: 0),
                    minorGridLines: const MinorGridLines(width: 0),
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
                  // Main line series (all points for continuous line, no markers)
                  SplineAreaSeries<ChartData, DateTime>(
                    dataSource: chartDataList,
                    xValueMapper: (ChartData data, _) => data.date,
                    yValueMapper: (ChartData data, _) => data.debt,
                    borderColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                    borderWidth: 1.5,
                    splineType: SplineType.natural, // Smooth curved lines
                    animationDuration: 0,
                    enableTooltip: false, // Disable interaction on dashboard chart
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
                    onPointTap: null, // Explicitly disable point tap
                  ),
                  // Separate series for markers - only points with transactions
                  // This allows the line to connect through all points while only showing markers for actual events
                  SplineAreaSeries<ChartData, DateTime>(
                    dataSource: chartDataList.where((d) => d.hasTransactions).toList(),
                    xValueMapper: (ChartData data, _) => data.date,
                    yValueMapper: (ChartData data, _) => data.debt,
                    borderColor: Colors.transparent, // Transparent line (only markers visible)
                    borderWidth: 0,
                    splineType: SplineType.natural, // Smooth curved lines
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
                ],
                tooltipBehavior: TooltipBehavior(
                  enable: false, // Disable interaction on dashboard chart
                ),
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
