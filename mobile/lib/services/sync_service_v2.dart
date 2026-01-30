import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'event_store_service.dart';
import 'api_service.dart';
import 'state_builder.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/contact.dart';
import '../models/transaction.dart';
import '../models/event.dart';
import 'realtime_service.dart';
import 'retry_backoff.dart';
import 'backend_config_service.dart';
import 'auth_service.dart';

/// Sync result enum
enum SyncResult { done, failed }

/// Sync status enum for UI
enum SyncStatus {
  synced,      // All events synced
  unsynced,    // Has unsynced events
  syncing,     // Currently syncing
  offline,     // Server not reachable
}

/// Simplified Sync Service - Event-driven architecture
/// Uses hash comparison and timestamp-based incremental sync
/// Separates local-to-server and server-to-local sync operations
class SyncServiceV2 {
  static final RetryBackoff _retryBackoff = RetryBackoff();
  static Timer? _webSocketNotificationTimer;
  static Timer? _localToServerSyncTimer;
  static bool _isLocalToServerSyncing = false;
  static bool _isServerToLocalSyncing = false;
  static bool _firstWebSocketRun = true;
  static bool _firstLocalToServerRun = true;
  static bool _needsServerToLocalRetry = false;
  static bool? _serverReachableCache;
  static DateTime? _serverReachableCacheTime;
  static const Duration _serverReachableCacheDuration = Duration(seconds: 10);
  static bool _hasSyncError = false; // Track if sync has failed with error

  /// Initialize sync service
  static Future<void> initialize() async {
    if (kIsWeb) return;

    // Start WebSocket notification listening (permanent loop)
    startWebSocketNotificationListening();

    print('✅ SyncServiceV2 initialized');
  }

  // ========== HELPER FUNCTIONS ==========

  /// Check if server is reachable via HTTP
  /// Uses caching to avoid too many checks
  static Future<bool> _isServerReachable() async {
    if (kIsWeb) return false;

    // Check cache first
    if (_serverReachableCache != null && _serverReachableCacheTime != null) {
      final elapsed = DateTime.now().difference(_serverReachableCacheTime!);
      if (elapsed < _serverReachableCacheDuration) {
        return _serverReachableCache!;
      }
    }

    try {
      final baseUrl = await BackendConfigService.getBaseUrl();
      final uri = Uri.parse('$baseUrl/api/sync/hash');
      final token = await AuthService.getToken();
      
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }

      // Try a lightweight request with short timeout
      final response = await http.get(uri, headers: headers).timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          throw Exception('Server reachability check timed out');
        },
      );

      final isReachable = response.statusCode == 200 || response.statusCode == 401; // 401 means server is reachable but auth failed
      
      // Cache the result
      _serverReachableCache = isReachable;
      _serverReachableCacheTime = DateTime.now();
      
      return isReachable;
    } catch (e) {
      // Server not reachable
      _serverReachableCache = false;
      _serverReachableCacheTime = DateTime.now();
      return false;
    }
  }

  // ========== PURE SYNC FUNCTIONS ==========

  /// Sync local events to server
  /// Returns SyncResult.done on success, SyncResult.failed on failure
  static Future<SyncResult> syncLocalToServer() async {
    if (kIsWeb) return SyncResult.done;

    print('🔄 syncLocalToServer: Starting...');

    // Check if we have unsynced events
    final unsyncedEvents = await EventStoreService.getUnsyncedEvents();
    if (unsyncedEvents.isEmpty) {
      print('✅ syncLocalToServer: No unsynced events to send');
      return SyncResult.done;
    }

      print('📤 syncLocalToServer: Found ${unsyncedEvents.length} unsynced events');

    // Check if server is reachable
    final isReachable = await _isServerReachable();
    print('🌐 syncLocalToServer: Server reachable = $isReachable');
    if (!isReachable) {
      print('⚠️ syncLocalToServer: Server not reachable, will retry...');
      return SyncResult.failed;
    }

    try {
      // Sort events by priority: DELETED first, then UPDATED, then CREATED
      final sortedEvents = List<Event>.from(unsyncedEvents);
      sortedEvents.sort((a, b) {
        if (a.eventType == 'DELETED' && b.eventType != 'DELETED') return -1;
        if (a.eventType != 'DELETED' && b.eventType == 'DELETED') return 1;
        if (a.eventType == 'UPDATED' && b.eventType == 'CREATED') return -1;
        if (a.eventType == 'CREATED' && b.eventType == 'UPDATED') return 1;
        return 0;
      });

      print('📤 Sending ${sortedEvents.length} unsynced events to server (priority: DELETED > UPDATED > CREATED)...');

      // Convert local events to server format
      final eventsToSend = sortedEvents.map((e) {
        // Ensure timestamp is in RFC3339 format (with Z suffix for UTC)
        String timestamp = e.timestamp.toUtc().toIso8601String();
        if (!timestamp.endsWith('Z')) {
          timestamp = '${timestamp}Z';
        }

        return {
          'id': e.id,
          'aggregate_type': e.aggregateType,
          'aggregate_id': e.aggregateId,
          'event_type': e.eventType,
          'event_data': e.eventData,
          'timestamp': timestamp,
          'version': e.version,
        };
      }).toList();

      // Send to server
      print('📤 syncLocalToServer: Sending ${eventsToSend.length} events to server...');
      final result = await ApiService.postSyncEvents(eventsToSend);
      final accepted = (result['accepted'] as List).cast<String>();
      final conflicts = (result['conflicts'] as List).cast<String>();

      print('✅ syncLocalToServer: Server accepted ${accepted.length} events, ${conflicts.length} conflicts');

      if (accepted.isEmpty && conflicts.isEmpty && eventsToSend.isNotEmpty) {
        print('⚠️ Warning: No events were accepted or conflicted. This might indicate a server error.');
        return SyncResult.failed;
      }

      // Mark accepted events as synced
      if (accepted.isNotEmpty) {
        final eventsBox = await Hive.openBox<Event>(EventStoreService.eventsBoxName);
        for (final eventId in accepted) {
          final event = eventsBox.get(eventId);
          if (event != null) {
            final syncedEvent = Event(
              id: event.id,
              aggregateType: event.aggregateType,
              aggregateId: event.aggregateId,
              eventType: event.eventType,
              eventData: event.eventData,
              timestamp: event.timestamp,
              version: event.version,
              synced: true,
            );
            await eventsBox.put(eventId, syncedEvent);
          }
        }
      }

      // Handle conflicts (for now, just log them)
      if (conflicts.isNotEmpty) {
        print('⚠️ Conflicts detected: $conflicts');
        // TODO: Handle conflicts (merge strategy)
      }

      // Rebuild state only if we marked events as synced
      if (accepted.isNotEmpty) {
        await _rebuildState();
      } else {
        print('✅ No events were synced, skipping state rebuild');
      }

      print('✅ Local to server sync completed');
      _hasSyncError = false; // Clear error on success
      return SyncResult.done;
    } catch (e) {
      // Check if it's an authentication error
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('authentication') || errorStr.contains('expired') || errorStr.contains('401')) {
        print('⚠️ Sync failed due to authentication error');
        _hasSyncError = true; // Mark as error (not just network issue)
        return SyncResult.failed;
      }

      // Check if it's a network error
      if (errorStr.contains('connection refused') ||
          errorStr.contains('failed host lookup') ||
          errorStr.contains('network is unreachable') ||
          errorStr.contains('socketexception') ||
          errorStr.contains('timeout')) {
        print('⚠️ Sync failed due to network error (offline or server unreachable)');
        // Don't mark as error for network issues - these are expected when offline
        return SyncResult.failed;
      }

      // For other errors, log them and mark as error
      print('❌ Local to server sync error: $e');
      _hasSyncError = true;
      return SyncResult.failed;
    }
  }

  /// Sync server events to local
  /// Returns SyncResult.done on success, SyncResult.failed on failure
  static Future<SyncResult> syncServerToLocal() async {
    if (kIsWeb) return SyncResult.done;

    // Check if server is reachable
    final isReachable = await _isServerReachable();
    print('🌐 syncServerToLocal: Server reachable = $isReachable');
    if (!isReachable) {
      print('⚠️ syncServerToLocal: Server not reachable, will retry...');
      return SyncResult.failed;
    }

    try {
      print('🔄 Starting server to local sync...');

      // 1. Get server hash
      final serverHashData = await ApiService.getSyncHash();
      final serverHash = serverHashData['hash'] as String;
      final serverEventCount = serverHashData['event_count'] as int;

      // 2. Get local hash
      final localHash = await EventStoreService.getEventHash();
      final localEventCount = await EventStoreService.getEventCount();

      print('📊 Sync status: Local=$localEventCount events, Server=$serverEventCount events');

      // 3. If hashes match, we're in sync
      if (localHash == serverHash && localEventCount == serverEventCount) {
        print('✅ Already in sync with server');
        final lastSync = await EventStoreService.getLastSyncTimestamp();
        if (lastSync == null) {
          await EventStoreService.setLastSyncTimestamp(DateTime.now());
        }
        return SyncResult.done;
      }

      // 4. Get last sync timestamp for incremental sync
      final lastSync = await EventStoreService.getLastSyncTimestamp();

      // 5. Pull new events from server
      print('📥 Fetching events from server...');
      List<Map<String, dynamic>> serverEvents;
      if (lastSync != null) {
        print('📥 Using incremental sync since: ${lastSync.toIso8601String()}');
        serverEvents = await ApiService.getSyncEvents(since: lastSync.toIso8601String());
      } else {
        // First sync - get all events
        print('📥 First sync - fetching all events from server...');
        serverEvents = await ApiService.getSyncEvents();
      }

      print('📥 Received ${serverEvents.length} events from server');

      // 6. Load all local events once (performance optimization)
      final allLocalEvents = await EventStoreService.getAllEvents();
      final localEventIds = allLocalEvents.map((e) => e.id).toSet();

      // 7. Insert missing events from server
      int insertedCount = 0;
      final eventsBox = await Hive.openBox<Event>(EventStoreService.eventsBoxName);

      for (final serverEvent in serverEvents) {
        final eventId = serverEvent['id'] as String;

        // Check if event already exists locally
        if (!localEventIds.contains(eventId)) {
          // Convert server event to local Event
          final event = Event(
            id: eventId,
            aggregateType: serverEvent['aggregate_type'] as String,
            aggregateId: serverEvent['aggregate_id'] as String,
            eventType: serverEvent['event_type'] as String,
            eventData: Map<String, dynamic>.from(serverEvent['event_data'] as Map),
            timestamp: DateTime.parse(serverEvent['timestamp'] as String),
            version: serverEvent['version'] as int,
            synced: true, // From server, so already synced
          );

          // Insert into local event store
          await eventsBox.put(event.id, event);
          localEventIds.add(eventId);
          insertedCount++;
        }
      }

      print('✅ Inserted $insertedCount new events from server');

      // 8. Rebuild state only if we inserted new events
      if (insertedCount > 0) {
        await _rebuildState();
      } else {
        print('✅ No new events inserted, skipping state rebuild');
      }

      // 9. Update last sync timestamp
      await EventStoreService.setLastSyncTimestamp(DateTime.now());

      print('✅ Server to local sync completed');
      _hasSyncError = false; // Clear error on success
      return SyncResult.done;
    } catch (e) {
      // Check if it's an authentication error
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('authentication') || errorStr.contains('expired') || errorStr.contains('401')) {
        print('⚠️ Sync failed due to authentication error');
        _hasSyncError = true; // Mark as error
        return SyncResult.failed;
      }

      // Check if it's a network error
      if (errorStr.contains('connection refused') ||
          errorStr.contains('failed host lookup') ||
          errorStr.contains('network is unreachable') ||
          errorStr.contains('socketexception') ||
          errorStr.contains('timeout')) {
        print('⚠️ Sync failed due to network error (offline or server unreachable)');
        // Don't mark as error for network issues
        return SyncResult.failed;
      }

      // For other errors, log them and mark as error
      print('❌ Server to local sync error: $e');
      _hasSyncError = true;
      return SyncResult.failed;
    }
  }

  // ========== LOOP FUNCTIONS ==========

  /// Start WebSocket notification listening (permanent loop)
  /// Manages retry loop for server-to-local sync failures
  /// WebSocket notifications are handled by RealtimeService, which calls syncServerToLocal()
  static void startWebSocketNotificationListening() {
    if (kIsWeb) return;

    // Cancel existing if any
    _webSocketNotificationTimer?.cancel();
    _webSocketNotificationTimer = null;
    _firstWebSocketRun = true;
    _needsServerToLocalRetry = false;

    // Start permanent loop for retry management
    _webSocketNotificationTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      // Check if sync already running
      if (_isServerToLocalSyncing) {
        return;
      }

      // First run: no wait
      if (_firstWebSocketRun) {
        _firstWebSocketRun = false;
        return;
      }

      // If we need retry, wait per backoff and retry
      if (_needsServerToLocalRetry) {
        final waitDuration = _retryBackoff.getWaiting();
        await Future.delayed(waitDuration);

        // Retry server to local sync
        _isServerToLocalSyncing = true;
        try {
          final result = await syncServerToLocal();
          if (result == SyncResult.done) {
            // Success, reset retry flag and backoff
            _needsServerToLocalRetry = false;
            _retryBackoff.reset();
          } else {
            // Still failed, will retry again
            _needsServerToLocalRetry = true;
          }
        } catch (e) {
          print('❌ Server to local sync retry error: $e');
          _needsServerToLocalRetry = true;
        } finally {
          _isServerToLocalSyncing = false;
        }
      }
    });
  }

  /// Start local to server sync loop (temporary loop)
  /// Runs until sync succeeds, then stops
  static void startLocalToServerSync() {
    if (kIsWeb) return;

    print('🔄 Starting local to server sync loop...');

    // Cancel existing if any
    _localToServerSyncTimer?.cancel();
    _localToServerSyncTimer = null;
    _firstLocalToServerRun = true;

    // Reset backoff for immediate sync
    _retryBackoff.reset();

    // Start temporary loop
    _localToServerSyncTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      // Check if sync already running
      if (_isLocalToServerSyncing) {
        print('⚠️ Local to server sync loop: sync already running, skipping...');
        return;
      }

      // Check if we have unsynced events
      final unsyncedEvents = await EventStoreService.getUnsyncedEvents();
      if (unsyncedEvents.isEmpty) {
        // No unsynced events, stop loop
        timer.cancel();
        _localToServerSyncTimer = null;
        _retryBackoff.reset();
        print('✅ Local to server sync loop stopped - no unsynced events');
        return;
      }

      print('🔄 Local to server sync loop: found ${unsyncedEvents.length} unsynced events');

      // First run: no wait
      if (_firstLocalToServerRun) {
        _firstLocalToServerRun = false;
        print('🔄 Local to server sync loop: first run, no wait');
      } else {
        // Subsequent runs: wait per backoff
        final waitDuration = _retryBackoff.getWaiting();
        print('🔄 Local to server sync loop: waiting ${waitDuration.inSeconds}s before retry...');
        await Future.delayed(waitDuration);
      }

      // Attempt sync
      _isLocalToServerSyncing = true;
      try {
        print('🔄 Local to server sync loop: attempting sync...');
        final result = await syncLocalToServer();
        if (result == SyncResult.done) {
          // Sync succeeded, stop loop
          timer.cancel();
          _localToServerSyncTimer = null;
          _retryBackoff.reset();
          print('✅ Local to server sync loop stopped - sync succeeded');
        } else {
          // Sync failed, will retry on next iteration
          print('⚠️ Local to server sync failed, will retry...');
        }
      } catch (e) {
        print('❌ Local to server sync error: $e');
        // Will retry on next iteration
      } finally {
        _isLocalToServerSyncing = false;
      }
    });
  }

  /// Handle server-to-local sync request (called by RealtimeService on notification)
  /// If sync fails, sets retry flag for the notification loop to handle
  static Future<void> handleServerToLocalSyncRequest() async {
    if (kIsWeb || _isServerToLocalSyncing) return;

    _isServerToLocalSyncing = true;
    try {
      final result = await syncServerToLocal();
      if (result == SyncResult.failed) {
        // Set retry flag - the notification loop will handle retry
        _needsServerToLocalRetry = true;
        _retryBackoff.reset(); // Reset backoff for new retry cycle
      } else {
        // Success, reset retry flag and backoff
        _needsServerToLocalRetry = false;
        _retryBackoff.reset();
      }
    } catch (e) {
      print('❌ Server to local sync error: $e');
      _needsServerToLocalRetry = true;
      _retryBackoff.reset();
    } finally {
      _isServerToLocalSyncing = false;
    }
  }

  // ========== EVENT HANDLERS ==========

  /// Called when coming back online
  /// Resets backoff and runs both syncs
  static void onBackOnline() {
    if (kIsWeb) return;

    print('🔄 Back online - resetting backoff and running both syncs');

    // Reset backoff
    _retryBackoff.reset();

    // Trigger server to local sync first (to get server updates)
    print('🔄 onBackOnline: Triggering server to local sync...');
    if (!_isServerToLocalSyncing) {
      _isServerToLocalSyncing = true;
      syncServerToLocal().then((result) {
        _isServerToLocalSyncing = false;
        if (result == SyncResult.done) {
          print('✅ onBackOnline: Server to local sync completed');
        } else {
          print('⚠️ onBackOnline: Server to local sync failed, will retry via notification loop');
          _needsServerToLocalRetry = true;
          _retryBackoff.reset();
        }
      }).catchError((e) {
        print('❌ onBackOnline: Server to local sync error: $e');
        _isServerToLocalSyncing = false;
        _needsServerToLocalRetry = true;
        _retryBackoff.reset();
      });
    }

    // Check if we have unsynced events and start local to server sync
    EventStoreService.getUnsyncedEvents().then((unsynced) {
      if (unsynced.isNotEmpty) {
        print('🔄 onBackOnline: Found ${unsynced.length} unsynced events, starting local to server sync...');
        startLocalToServerSync();
      } else {
        print('✅ onBackOnline: No unsynced events to sync');
      }
    });
  }

  /// Called on pull-to-refresh (swipe down)
  /// Resets backoff and starts local to server sync
  static void onPullToRefresh() {
    if (kIsWeb) return;

    print('🔄 Pull to refresh - resetting backoff and starting sync');

    // Reset backoff
    _retryBackoff.reset();

    // Start local to server sync
    startLocalToServerSync();
  }

  // ========== HELPER FUNCTIONS ==========

  /// Rebuild application state from events
  static Future<void> _rebuildState() async {
    if (kIsWeb) return;

    try {
      print('🔄 Rebuilding state from events...');

      // Get all events
      final events = await EventStoreService.getAllEvents();

      // Build state using StateBuilder
      final state = StateBuilder.buildState(events);

      // Save to Hive boxes
      final contactsBox = await Hive.openBox<Contact>('contacts');
      final transactionsBox = await Hive.openBox<Transaction>('transactions');

      // Clear existing data
      await contactsBox.clear();
      await transactionsBox.clear();

      // Write new state
      for (final contact in state.contacts) {
        await contactsBox.put(contact.id, contact);
      }

      for (final transaction in state.transactions) {
        await transactionsBox.put(transaction.id, transaction);
      }

      print('✅ State rebuilt: ${state.contacts.length} contacts, ${state.transactions.length} transactions');
    } catch (e) {
      print('❌ Error rebuilding state: $e');
    }
  }

  /// Get sync status for debugging
  static Future<Map<String, dynamic>> getSyncStatus() async {
    if (kIsWeb) {
      return {'error': 'Sync not available on web'};
    }

    try {
      final localEventCount = await EventStoreService.getEventCount();
      final unsyncedEvents = await EventStoreService.getUnsyncedEvents();
      final unsyncedCount = unsyncedEvents.length;
      final lastSync = await EventStoreService.getLastSyncTimestamp();

      return {
        'is_local_to_server_syncing': _isLocalToServerSyncing,
        'is_server_to_local_syncing': _isServerToLocalSyncing,
        'local_event_count': localEventCount,
        'unsynced_event_count': unsyncedCount,
        'last_sync': lastSync?.toIso8601String(),
        'has_unsynced_events': unsyncedCount > 0,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Get sync status for UI (simplified)
  static Future<SyncStatus> getSyncStatusForUI() async {
    if (kIsWeb) return SyncStatus.synced;

    // Check if currently syncing
    if (_isLocalToServerSyncing || _isServerToLocalSyncing) {
      return SyncStatus.syncing;
    }

    // Check if server is reachable
    final isReachable = await _isServerReachable();
    if (!isReachable) {
      return SyncStatus.offline;
    }

    // Check if we have unsynced events
    final unsyncedEvents = await EventStoreService.getUnsyncedEvents();
    if (unsyncedEvents.isNotEmpty) {
      return SyncStatus.unsynced;
    }

    return SyncStatus.synced;
  }

  /// Check if sync has failed with an error (not just network issue)
  static bool get hasSyncError => _hasSyncError;

  /// Stop all sync operations
  static void stop() {
    _webSocketNotificationTimer?.cancel();
    _webSocketNotificationTimer = null;
    _localToServerSyncTimer?.cancel();
    _localToServerSyncTimer = null;
  }

  /// Manual sync trigger (for backward compatibility)
  /// Triggers both server-to-local and local-to-server sync
  static Future<void> manualSync() async {
    if (kIsWeb) return;

    print('🔄 manualSync: Triggering both syncs...');

    // First sync server to local (to get latest from server)
    if (!_isServerToLocalSyncing) {
      _isServerToLocalSyncing = true;
      syncServerToLocal().then((result) {
        _isServerToLocalSyncing = false;
        if (result == SyncResult.done) {
          print('✅ manualSync: Server to local sync completed');
        } else {
          print('⚠️ manualSync: Server to local sync failed');
        }
      }).catchError((e) {
        print('❌ manualSync: Server to local sync error: $e');
        _isServerToLocalSyncing = false;
      });
    }

    // Then start local to server sync (if there are unsynced events)
    startLocalToServerSync();
  }
}
