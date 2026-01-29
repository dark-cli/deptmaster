import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'event_store_service.dart';
import 'api_service.dart';
import 'state_builder.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/contact.dart';
import '../models/transaction.dart';
import '../models/event.dart';

/// Simplified Sync Service - KISS approach
/// Uses hash comparison and timestamp-based incremental sync
class SyncServiceV2 {
  static bool _isSyncing = false;
  static Timer? _periodicSyncTimer;

  /// Initialize sync service
  static Future<void> initialize() async {
    if (kIsWeb) return;
    
    // No periodic sync - WebSocket handles all real-time updates
    // WebSocket will trigger sync immediately when server sends updates
    print('✅ SyncServiceV2 initialized (WebSocket-only, no timers)');
  }

  /// Perform full sync (hash-based comparison)
  static Future<void> sync() async {
    if (kIsWeb || _isSyncing) return;

    _isSyncing = true;
    try {
      print('🔄 Starting sync...');

      // 1. Get server hash
      print('📡 Fetching server hash...');
      final serverHashData = await ApiService.getSyncHash();
      final serverHash = serverHashData['hash'] as String;
      final serverEventCount = serverHashData['event_count'] as int;
      print('✅ Server hash received: $serverEventCount events (hash: ${serverHash.substring(0, 8)}...)');

      // 2. Get local hash
      print('💾 Checking local events...');
      final localHash = await EventStoreService.getEventHash();
      final localEventCount = await EventStoreService.getEventCount();
      print('✅ Local hash: $localEventCount events (hash: ${localHash.substring(0, 8)}...)');

      print('📊 Sync status: Local=$localEventCount events (hash: ${localHash.substring(0, 8)}...), Server=$serverEventCount events (hash: ${serverHash.substring(0, 8)}...)');

      // 3. Check for unsynced events first (even if hashes match, we might have offline events)
      final unsyncedEvents = await EventStoreService.getUnsyncedEvents();
      
      // 4. If hashes match and no unsynced events, we're fully in sync
      if (localHash == serverHash && localEventCount == serverEventCount && unsyncedEvents.isEmpty) {
        print('✅ Already in sync');
        final lastSync = await EventStoreService.getLastSyncTimestamp();
        if (lastSync == null) {
          // First sync - mark current time
          await EventStoreService.setLastSyncTimestamp(DateTime.now());
        }
        // Skip rebuilding state if already in sync - saves significant time
        // State will be rebuilt automatically when new events arrive
        return;
      }
      
      // If we have unsynced events, continue with sync even if hashes match
      if (unsyncedEvents.isNotEmpty) {
        print('📤 Found ${unsyncedEvents.length} unsynced events, syncing...');
      }

      // 5. Get last sync timestamp for incremental sync
      final lastSync = await EventStoreService.getLastSyncTimestamp();
      
      // 6. Pull new events from server (since last sync or all if first time)
      List<Map<String, dynamic>> serverEvents;
      if (lastSync != null) {
        serverEvents = await ApiService.getSyncEvents(since: lastSync.toIso8601String());
      } else {
        // First sync - get all events
        serverEvents = await ApiService.getSyncEvents();
      }

      print('📥 Received ${serverEvents.length} events from server');

      // 7. Load all local events once (performance optimization)
      // Create a Set of event IDs for O(1) lookup instead of O(n) search in loop
      final allLocalEvents = await EventStoreService.getAllEvents();
      final localEventIds = allLocalEvents.map((e) => e.id).toSet();
      
      // 8. Insert missing events from server (by timestamp order)
      int insertedCount = 0;
      final eventsBox = await Hive.openBox<Event>(EventStoreService.eventsBoxName);
      
      for (final serverEvent in serverEvents) {
        final eventId = serverEvent['id'] as String;
        
        // Check if event already exists locally using Set lookup (O(1) instead of O(n))
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
          localEventIds.add(eventId); // Update Set for subsequent checks
          insertedCount++;
        }
      }

      print('✅ Inserted $insertedCount new events from server');

      // 8. Send unsynced local events to server (re-fetch to get latest)
      final unsyncedEventsToSend = await EventStoreService.getUnsyncedEvents();
      print('📤 Sending ${unsyncedEventsToSend.length} unsynced events to server');

      if (unsyncedEventsToSend.isNotEmpty) {
        // 9. Convert local events to server format
        final eventsToSend = unsyncedEventsToSend.map((e) {
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

        // 10. Send to server
        print('📤 Sending ${eventsToSend.length} events to server...');
        final result = await ApiService.postSyncEvents(eventsToSend);
        final accepted = (result['accepted'] as List).cast<String>();
        final conflicts = (result['conflicts'] as List).cast<String>();

        print('✅ Server accepted ${accepted.length} events, ${conflicts.length} conflicts');
        
        if (accepted.isEmpty && conflicts.isEmpty && eventsToSend.isNotEmpty) {
          print('⚠️ Warning: No events were accepted or conflicted. This might indicate a server error.');
        }

        // 11. Mark accepted events as synced (batch operation for performance)
        if (accepted.isNotEmpty) {
          final eventsBoxForMarking = await Hive.openBox<Event>(EventStoreService.eventsBoxName);
          for (final eventId in accepted) {
            final event = eventsBoxForMarking.get(eventId);
            if (event != null) {
              final syncedEvent = Event(
                id: event.id,
                aggregateType: event.aggregateType,
                aggregateId: event.aggregateId,
                eventType: event.eventType,
                eventData: event.eventData,
                timestamp: event.timestamp,
                version: event.version,
                synced: true, // Mark as synced
              );
              await eventsBoxForMarking.put(eventId, syncedEvent);
            }
          }
        }

        // 12. Handle conflicts (for now, just log them)
        if (conflicts.isNotEmpty) {
          print('⚠️ Conflicts detected: $conflicts');
          // TODO: Handle conflicts (merge strategy)
        }
      } else {
        print('✅ No unsynced events to send');
      }

      // 13. Rebuild state from all events
      await _rebuildState();

      // 14. Update last sync timestamp
      await EventStoreService.setLastSyncTimestamp(DateTime.now());

      print('✅ Sync completed');
      
      // 15. State was already rebuilt in step 13 (_rebuildState)
      // The UI will automatically refresh via Hive box listeners when state changes
    } catch (e, stackTrace) {
      // Check if it's an authentication error
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('authentication') || errorStr.contains('expired') || errorStr.contains('401')) {
        print('⚠️ Sync failed due to authentication error - user has been logged out');
        print('   Error: $e');
        // Don't retry - user needs to login again
        return;
      }
      
      // Check if it's a network error
      if (errorStr.contains('connection refused') || 
          errorStr.contains('failed host lookup') ||
          errorStr.contains('network is unreachable') ||
          errorStr.contains('socketexception') ||
          errorStr.contains('timeout')) {
        print('⚠️ Sync failed due to network error (offline or server unreachable)');
        print('   Error: $e');
        // Don't throw - network errors are expected when offline
        return;
      }
      
      // For other errors, log them with full details
      print('❌ Sync error: $e');
      print('   Stack trace: $stackTrace');
      
      // Check if there are unsynced events that failed to sync
      try {
        final unsyncedCount = (await EventStoreService.getUnsyncedEvents()).length;
        if (unsyncedCount > 0) {
          print('   ⚠️ Warning: $unsyncedCount events remain unsynced');
        }
      } catch (_) {
        // Ignore errors checking unsynced events
      }
      
      // Don't throw - sync failures shouldn't break the app
    } finally {
      _isSyncing = false;
    }
  }

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

  /// Manual sync trigger
  static Future<void> manualSync() async {
    if (_isSyncing) {
      print('⚠️ Sync already in progress, skipping...');
      return;
    }
    await sync();
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
        'is_syncing': _isSyncing,
        'local_event_count': localEventCount,
        'unsynced_event_count': unsyncedCount,
        'last_sync': lastSync?.toIso8601String(),
        'has_unsynced_events': unsyncedCount > 0,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Stop periodic sync
  static void stop() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
  }
}
