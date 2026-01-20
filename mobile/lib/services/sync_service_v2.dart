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
    
    // Start periodic sync
    _startPeriodicSync();
    print('✅ SyncServiceV2 initialized');
  }

  /// Start periodic sync check
  static void _startPeriodicSync() {
    _periodicSyncTimer?.cancel();
    // Sync every 30 seconds
    _periodicSyncTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      sync();
    });
  }

  /// Perform full sync (hash-based comparison)
  static Future<void> sync() async {
    if (kIsWeb || _isSyncing) return;

    _isSyncing = true;
    try {
      print('🔄 Starting sync...');

      // 1. Get server hash
      final serverHashData = await ApiService.getSyncHash();
      final serverHash = serverHashData['hash'] as String;
      final serverEventCount = serverHashData['event_count'] as int;

      // 2. Get local hash
      final localHash = await EventStoreService.getEventHash();
      final localEventCount = await EventStoreService.getEventCount();

      print('📊 Sync status: Local=$localEventCount events (hash: ${localHash.substring(0, 8)}...), Server=$serverEventCount events (hash: ${serverHash.substring(0, 8)}...)');

      // 3. If hashes match, we're in sync
      if (localHash == serverHash && localEventCount == serverEventCount) {
        print('✅ Already in sync');
        final lastSync = await EventStoreService.getLastSyncTimestamp();
        if (lastSync == null) {
          // First sync - mark current time
          await EventStoreService.setLastSyncTimestamp(DateTime.now());
        }
        return;
      }

      // 4. Get last sync timestamp for incremental sync
      final lastSync = await EventStoreService.getLastSyncTimestamp();
      
      // 5. Pull new events from server (since last sync or all if first time)
      List<Map<String, dynamic>> serverEvents;
      if (lastSync != null) {
        serverEvents = await ApiService.getSyncEvents(since: lastSync.toIso8601String());
      } else {
        // First sync - get all events
        serverEvents = await ApiService.getSyncEvents();
      }

      print('📥 Received ${serverEvents.length} events from server');

      // 6. Insert missing events from server (by timestamp order)
      int insertedCount = 0;
      for (final serverEvent in serverEvents) {
        final eventId = serverEvent['id'] as String;
        
        // Check if event already exists locally
        final allEvents = await EventStoreService.getAllEvents();
        final exists = allEvents.any((e) => e.id == eventId);
        
        if (!exists) {
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
          final eventsBox = await Hive.openBox<Event>(EventStoreService.eventsBoxName);
          await eventsBox.put(event.id, event);
          insertedCount++;
        }
      }

      print('✅ Inserted $insertedCount new events from server');

      // 7. Get unsynced local events
      final unsyncedEvents = await EventStoreService.getUnsyncedEvents();
      print('📤 Sending ${unsyncedEvents.length} unsynced events to server');

      if (unsyncedEvents.isNotEmpty) {
        // 8. Convert local events to server format
        final eventsToSend = unsyncedEvents.map((e) => {
          'id': e.id,
          'aggregate_type': e.aggregateType,
          'aggregate_id': e.aggregateId,
          'event_type': e.eventType,
          'event_data': e.eventData,
          'timestamp': e.timestamp.toIso8601String(),
          'version': e.version,
        }).toList();

        // 9. Send to server
        final result = await ApiService.postSyncEvents(eventsToSend);
        final accepted = (result['accepted'] as List).cast<String>();
        final conflicts = (result['conflicts'] as List).cast<String>();

        print('✅ Server accepted ${accepted.length} events, ${conflicts.length} conflicts');

        // 10. Mark accepted events as synced
        for (final eventId in accepted) {
          await EventStoreService.markEventSynced(eventId);
        }

        // 11. Handle conflicts (for now, just log them)
        if (conflicts.isNotEmpty) {
          print('⚠️ Conflicts detected: $conflicts');
          // TODO: Handle conflicts (merge strategy)
        }
      }

      // 12. Rebuild state from all events
      await _rebuildState();

      // 13. Update last sync timestamp
      await EventStoreService.setLastSyncTimestamp(DateTime.now());

      print('✅ Sync completed');
    } catch (e) {
      print('❌ Sync error: $e');
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
    await sync();
  }

  /// Stop periodic sync
  static void stop() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
  }
}
