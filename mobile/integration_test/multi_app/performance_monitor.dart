import 'dart:async';
import 'package:debt_tracker_mobile/services/event_store_service.dart';
import 'app_instance.dart';
import 'server_verifier.dart';

/// Performance monitoring and metrics collection
class PerformanceMonitor {
  final List<AppInstance> instances;
  final ServerVerifier serverVerifier;
  
  final Map<String, List<Duration>> _syncTimes = {};
  final Map<String, List<Duration>> _operationTimes = {};
  final Map<String, int> _retryCounts = {};
  final Map<String, int> _eventCounts = {};
  
  PerformanceMonitor(this.instances, this.serverVerifier) {
    for (final instance in instances) {
      _syncTimes[instance.id] = [];
      _operationTimes[instance.id] = [];
      _retryCounts[instance.id] = 0;
      _eventCounts[instance.id] = 0;
    }
  }
  
  /// Track sync operation time
  Future<T> trackSync<T>(String instanceId, Future<T> Function() operation) async {
    final startTime = DateTime.now();
    try {
      final result = await operation();
      final duration = DateTime.now().difference(startTime);
      _syncTimes[instanceId]!.add(duration);
      return result;
    } catch (e) {
      _retryCounts[instanceId] = (_retryCounts[instanceId] ?? 0) + 1;
      rethrow;
    }
  }
  
  /// Track operation time
  Future<T> trackOperation<T>(String instanceId, Future<T> Function() operation) async {
    final startTime = DateTime.now();
    final result = await operation();
    final duration = DateTime.now().difference(startTime);
    _operationTimes[instanceId]!.add(duration);
    return result;
  }
  
  /// Get average sync time for an instance
  Duration getAverageSyncTime(String instanceId) {
    final times = _syncTimes[instanceId] ?? [];
    if (times.isEmpty) return Duration.zero;
    
    final total = times.fold<Duration>(Duration.zero, (sum, time) => sum + time);
    return Duration(milliseconds: total.inMilliseconds ~/ times.length);
  }
  
  /// Get average operation time for an instance
  Duration getAverageOperationTime(String instanceId) {
    final times = _operationTimes[instanceId] ?? [];
    if (times.isEmpty) return Duration.zero;
    
    final total = times.fold<Duration>(Duration.zero, (sum, time) => sum + time);
    return Duration(milliseconds: total.inMilliseconds ~/ times.length);
  }
  
  /// Get total retry count for an instance
  int getRetryCount(String instanceId) {
    return _retryCounts[instanceId] ?? 0;
  }
  
  /// Get performance report
  Future<PerformanceReport> generateReport() async {
    final report = PerformanceReport();
    
    // Collect metrics for each instance
    for (final instance in instances) {
      final instanceMetrics = InstanceMetrics();
      instanceMetrics.instanceId = instance.id;
      instanceMetrics.averageSyncTime = getAverageSyncTime(instance.id);
      instanceMetrics.averageOperationTime = getAverageOperationTime(instance.id);
      instanceMetrics.retryCount = getRetryCount(instance.id);
      
      // Get event counts
      final events = await instance.getEvents();
      final unsynced = await instance.getUnsyncedEvents();
      instanceMetrics.totalEvents = events.length;
      instanceMetrics.unsyncedEvents = unsynced.length;
      
      // Get sync times statistics
      final syncTimes = _syncTimes[instance.id] ?? [];
      if (syncTimes.isNotEmpty) {
        syncTimes.sort((a, b) => a.compareTo(b));
        instanceMetrics.minSyncTime = syncTimes.first;
        instanceMetrics.maxSyncTime = syncTimes.last;
        instanceMetrics.medianSyncTime = syncTimes[syncTimes.length ~/ 2];
      }
      
      report.instanceMetrics[instance.id] = instanceMetrics;
    }
    
    // Calculate overall statistics
    final allSyncTimes = _syncTimes.values.expand((times) => times).toList();
    if (allSyncTimes.isNotEmpty) {
      allSyncTimes.sort((a, b) => a.compareTo(b));
      report.overallMinSyncTime = allSyncTimes.first;
      report.overallMaxSyncTime = allSyncTimes.last;
      report.overallAverageSyncTime = Duration(
        milliseconds: allSyncTimes.fold<int>(0, (sum, time) => sum + time.inMilliseconds) ~/ allSyncTimes.length,
      );
      report.overallMedianSyncTime = allSyncTimes[allSyncTimes.length ~/ 2];
    }
    
    report.totalRetries = _retryCounts.values.fold<int>(0, (sum, count) => sum + count);
    report.totalSyncOperations = allSyncTimes.length;
    
    // Get server metrics
    try {
      final serverEventCount = await serverVerifier.getServerEventCount();
      report.serverEventCount = serverEventCount;
    } catch (e) {
      print('⚠️ Could not get server event count: $e');
    }
    
    return report;
  }
  
  /// Print performance report
  Future<void> printReport() async {
    final report = await generateReport();
    print('\n📊 Performance Report');
    print('=' * 60);
    print('Overall Statistics:');
    print('  Total Sync Operations: ${report.totalSyncOperations}');
    print('  Total Retries: ${report.totalRetries}');
    print('  Average Sync Time: ${report.overallAverageSyncTime.inMilliseconds}ms');
    print('  Min Sync Time: ${report.overallMinSyncTime.inMilliseconds}ms');
    print('  Max Sync Time: ${report.overallMaxSyncTime.inMilliseconds}ms');
    print('  Median Sync Time: ${report.overallMedianSyncTime.inMilliseconds}ms');
    print('  Server Event Count: ${report.serverEventCount}');
    print('');
    print('Per-Instance Statistics:');
    for (final entry in report.instanceMetrics.entries) {
      final metrics = entry.value;
      print('  ${metrics.instanceId}:');
      print('    Total Events: ${metrics.totalEvents}');
      print('    Unsynced Events: ${metrics.unsyncedEvents}');
      print('    Average Sync Time: ${metrics.averageSyncTime.inMilliseconds}ms');
      print('    Average Operation Time: ${metrics.averageOperationTime.inMilliseconds}ms');
      print('    Retry Count: ${metrics.retryCount}');
      if (metrics.minSyncTime != null) {
        print('    Min Sync Time: ${metrics.minSyncTime!.inMilliseconds}ms');
        print('    Max Sync Time: ${metrics.maxSyncTime!.inMilliseconds}ms');
        print('    Median Sync Time: ${metrics.medianSyncTime!.inMilliseconds}ms');
      }
    }
    print('=' * 60);
  }
  
  /// Reset all metrics
  void reset() {
    for (final instance in instances) {
      _syncTimes[instance.id] = [];
      _operationTimes[instance.id] = [];
      _retryCounts[instance.id] = 0;
      _eventCounts[instance.id] = 0;
    }
  }
}

/// Performance report
class PerformanceReport {
  Map<String, InstanceMetrics> instanceMetrics = {};
  int totalSyncOperations = 0;
  int totalRetries = 0;
  Duration overallAverageSyncTime = Duration.zero;
  Duration overallMinSyncTime = Duration.zero;
  Duration overallMaxSyncTime = Duration.zero;
  Duration overallMedianSyncTime = Duration.zero;
  int serverEventCount = 0;
}

/// Metrics for a single instance
class InstanceMetrics {
  String instanceId = '';
  int totalEvents = 0;
  int unsyncedEvents = 0;
  Duration averageSyncTime = Duration.zero;
  Duration averageOperationTime = Duration.zero;
  int retryCount = 0;
  Duration? minSyncTime;
  Duration? maxSyncTime;
  Duration? medianSyncTime;
}
