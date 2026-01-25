import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/event.dart';
import '../services/event_store_service.dart';
import '../services/local_database_service_v2.dart';
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
  }

  Future<void> _loadChartData() async {
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
      
      setState(() {
        _events = eventsWithDebt;
        _loading = false;
      });
    } catch (e) {
      print('Error loading chart data: $e');
      setState(() {
        _loading = false;
      });
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

  List<ChartDataPoint> _buildChartData() {
    if (_events == null || _events!.isEmpty) {
      print('⚠️ No events available for chart');
      return [];
    }
    
    print('📊 Building chart from ${_events!.length} events');
    
    // Get last month (30 days) of data for simple dashboard view
    final now = DateTime.now();
    final periodStart = now.subtract(const Duration(days: 30));
    final intervalMs = 24 * 60 * 60 * 1000; // 1 day intervals
    
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
    
    // Build spots - only include points with transactions for display
    // When Y-axis is inverted, simply multiply Y values by -1
    final spots = chartData
        .where((point) => point.hasTransactions)
        .map((point) {
          // When inverted, multiply by -1; otherwise use original value
          final yValue = invertY ? -point.y : point.y;
          // Ensure point is within bounds with a small margin to avoid touching edges
          final margin = (finalMaxY - finalMinY) * 0.02; // 2% margin
          return FlSpot(point.x, yValue.clamp(finalMinY + margin, finalMaxY - margin));
        })
        .toList();
    
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
              child: SizedBox.expand(
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
                            ? (maxX - minX) / 4 
                            : 1,
                        getTitlesWidget: (value, meta) {
                          final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              DateFormat('MM/dd').format(date),
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
                        reservedSize: 35,
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
                              fontSize: 10,
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
                  minX: minX,
                  maxX: maxX,
                  minY: finalMinY,
                  maxY: finalMaxY,
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
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
                    enabled: false, // Disable interaction on dashboard chart
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
                          
                          // Compact time interval (single line)
                          final intervalFormat = DateFormat('MM/dd HH:mm');
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
                  ),
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
