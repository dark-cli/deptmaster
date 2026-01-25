import '../models/event.dart';
import '../services/event_store_service.dart';
import '../services/local_database_service_v2.dart';

/// Helper class to format events for display, matching admin page format
class EventFormatter {
  /// Format event type to match admin page (e.g., "Undo Contact Delete", "Delete Transaction")
  static String formatEventType(Event event, Map<String, Event>? undoneEventsCache) {
    final eventType = event.eventType.toUpperCase();
    
    // Handle UNDO events specially
    if (eventType == 'UNDO') {
      final undoneEventId = event.eventData['undone_event_id'] as String?;
      if (undoneEventId != null && undoneEventsCache != null) {
        final undoneEvent = undoneEventsCache[undoneEventId];
        if (undoneEvent != null) {
          final undoneType = undoneEvent.eventType.toUpperCase();
          final undoneAggregate = undoneEvent.aggregateType;
          
          // Format: "Undo [Aggregate] [Action]"
          String undoneAction = '';
          if (undoneType.contains('DELETE') || undoneType.contains('DELETED')) {
            undoneAction = 'Delete';
          } else if (undoneType.contains('UPDATE') || undoneType.contains('UPDATED')) {
            undoneAction = 'Update';
          } else if (undoneType.contains('CREATE') || undoneType.contains('CREATED')) {
            undoneAction = 'Create';
          } else {
            undoneAction = undoneType.replaceAll('_', ' ').split(' ').map((w) => 
              w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1).toLowerCase()
            ).join(' ');
          }
          
          final aggregateName = undoneAggregate.isEmpty 
              ? '' 
              : undoneAggregate[0].toUpperCase() + undoneAggregate.substring(1);
          return 'Undo $aggregateName $undoneAction';
        }
      }
      return 'Undo';
    }
    
    // Handle DELETE events
    if (eventType.contains('DELETE') || eventType.contains('DELETED')) {
      final aggregateName = event.aggregateType.isEmpty
          ? ''
          : event.aggregateType[0].toUpperCase() + event.aggregateType.substring(1);
      return 'Delete $aggregateName';
    }
    
    // Handle generic CREATED/UPDATED events
    final genericTypes = ['CREATED', 'UPDATED', 'DELETED', 'CREATE', 'UPDATE', 'DELETE'];
    final isGeneric = genericTypes.any((gt) => eventType == gt || eventType.contains(gt));
    
    if (isGeneric && event.aggregateType.isNotEmpty) {
      String specificAction = '';
      if (eventType.contains('CREATED') || eventType.contains('CREATE')) {
        specificAction = 'Created';
      } else if (eventType.contains('UPDATED') || eventType.contains('UPDATE')) {
        specificAction = 'Update';
      } else if (eventType.contains('DELETED') || eventType.contains('DELETE')) {
        specificAction = 'Delete';
      } else {
        specificAction = eventType.replaceAll('_', ' ').split(' ').map((w) => 
          w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1).toLowerCase()
        ).join(' ');
      }
      
      final aggregateName = event.aggregateType[0].toUpperCase() + event.aggregateType.substring(1);
      return '$specificAction $aggregateName';
    }
    
    // Default: format the event type
    return eventType.replaceAll('_', ' ').split(' ').map((w) => 
      w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1).toLowerCase()
    ).join(' ');
  }
  
  /// Get contact name for an event, matching admin page logic
  static Future<String?> getContactName(
    Event event,
    Map<String, String> contactNameCache,
    Map<String, Event>? undoneEventsCache,
    List<Event> allEvents,
  ) async {
    final eventData = event.eventData;
    final eventType = event.eventType.toUpperCase();
    
    // Handle UNDO events
    if (eventType == 'UNDO') {
      final undoneEventId = eventData['undone_event_id'] as String?;
      if (undoneEventId != null && undoneEventsCache != null) {
        final undoneEvent = undoneEventsCache[undoneEventId];
        if (undoneEvent != null) {
          if (undoneEvent.aggregateType == 'contact') {
            // Try to get name from undone event
            final undoneName = undoneEvent.eventData['name'] as String?;
            if (undoneName != null) {
              return undoneName;
            }
            // Try to find CREATED event for this contact
            final createdEvent = allEvents.firstWhere(
              (e) => e.aggregateType == 'contact' &&
                     e.aggregateId == undoneEvent.aggregateId &&
                     (e.eventType == 'CREATED' || e.eventType.contains('CREATE')),
              orElse: () => event,
            );
            if (createdEvent != event && createdEvent.eventData['name'] != null) {
              return createdEvent.eventData['name'] as String;
            }
            return 'Unknown';
          } else if (undoneEvent.aggregateType == 'transaction') {
            // Get contact_id from undone transaction event
            final contactId = undoneEvent.eventData['contact_id'] as String?;
            if (contactId != null) {
              String? contactName = contactNameCache[contactId];
              if (contactName == null) {
                try {
                  final contact = await LocalDatabaseServiceV2.getContact(contactId);
                  if (contact != null) {
                    contactName = contact.name;
                    contactNameCache[contactId] = contactName;
                  }
                } catch (e) {
                  print('Error loading contact for UNDO transaction: $e');
                }
              }
              return contactName ?? 'Unknown Contact';
            }
            return 'Unknown Contact';
          }
        }
      }
      return 'Unknown';
    }
    
    // Handle DELETE events
    if (eventType.contains('DELETE') || eventType.contains('DELETED')) {
      if (event.aggregateType == 'contact') {
        // Try deleted_contact.name first
        final deletedContact = eventData['deleted_contact'] as Map<String, dynamic>?;
        if (deletedContact != null && deletedContact['name'] != null) {
          return deletedContact['name'] as String;
        }
        // Try cache
        if (contactNameCache.containsKey(event.aggregateId)) {
          return contactNameCache[event.aggregateId];
        }
        // Try to find CREATED event
        final createdEvent = allEvents.firstWhere(
          (e) => e.aggregateType == 'contact' &&
                 e.aggregateId == event.aggregateId &&
                 (e.eventType == 'CREATED' || e.eventType.contains('CREATE')),
          orElse: () => event,
        );
        if (createdEvent != event && createdEvent.eventData['name'] != null) {
          return createdEvent.eventData['name'] as String;
        }
        return 'Unknown';
      } else if (event.aggregateType == 'transaction') {
        // Try deleted_transaction.contact_id
        final deletedTransaction = eventData['deleted_transaction'] as Map<String, dynamic>?;
        if (deletedTransaction != null) {
          final contactId = deletedTransaction['contact_id'] as String?;
          if (contactId != null) {
            String? contactName = contactNameCache[contactId];
            if (contactName == null) {
              try {
                final contact = await LocalDatabaseServiceV2.getContact(contactId);
                if (contact != null) {
                  contactName = contact.name;
                  contactNameCache[contactId] = contactName;
                }
              } catch (e) {
                print('Error loading contact for DELETE transaction: $e');
              }
            }
            return contactName ?? 'Unknown Contact';
          }
        }
        // Fallback: try to find CREATED transaction event
        final createdEvent = allEvents.firstWhere(
          (e) => e.aggregateType == 'transaction' &&
                 e.aggregateId == event.aggregateId &&
                 (e.eventType == 'CREATED' || e.eventType.contains('CREATE')),
          orElse: () => event,
        );
        if (createdEvent != event) {
          final contactId = createdEvent.eventData['contact_id'] as String?;
          if (contactId != null) {
            String? contactName = contactNameCache[contactId];
            if (contactName == null) {
              try {
                final contact = await LocalDatabaseServiceV2.getContact(contactId);
                if (contact != null) {
                  contactName = contact.name;
                  contactNameCache[contactId] = contactName;
                }
              } catch (e) {
                print('Error loading contact for DELETE transaction: $e');
              }
            }
            return contactName ?? 'Unknown Contact';
          }
        }
        return 'Unknown Contact';
      }
    }
    
    // Handle regular events
    if (event.aggregateType == 'contact') {
      final name = eventData['name'] as String?;
      if (name != null) {
        contactNameCache[event.aggregateId] = name;
        return name;
      }
      return contactNameCache[event.aggregateId] ?? 'Unknown';
    } else if (event.aggregateType == 'transaction') {
      final contactId = eventData['contact_id'] as String?;
      if (contactId != null) {
        String? contactName = contactNameCache[contactId];
        if (contactName == null) {
          try {
            final contact = await LocalDatabaseServiceV2.getContact(contactId);
            if (contact != null) {
              contactName = contact.name;
              contactNameCache[contactId] = contactName;
            }
          } catch (e) {
            print('Error loading contact: $e');
          }
        }
        return contactName ?? 'Unknown Contact';
      }
    }
    
    return null;
  }
  
  /// Get contact username for an event, matching admin page logic
  static Future<String?> getContactUsername(
    Event event,
    Map<String, String> contactNameCache, // Used for contactId lookup
    Map<String, Event>? undoneEventsCache,
    List<Event> allEvents,
  ) async {
    final eventData = event.eventData;
    final eventType = event.eventType.toUpperCase();
    String? username;

    if (eventType == 'UNDO') {
      final undoneEventId = eventData['undone_event_id'] as String?;
      if (undoneEventId != null && undoneEventsCache != null && undoneEventsCache.containsKey(undoneEventId)) {
        final undoneEvent = undoneEventsCache[undoneEventId]!;
        if (undoneEvent.aggregateType == 'contact') {
          username = undoneEvent.eventData['username'] as String?;
          if (username == null) {
            final createdEvent = allEvents.firstWhere(
              (e) => e.aggregateType == 'contact' &&
                     e.aggregateId == undoneEvent.aggregateId &&
                     (e.eventType == 'CREATED' || e.eventType.contains('CREATE')),
              orElse: () => undoneEvent,
            );
            if (createdEvent != undoneEvent) {
              username = createdEvent.eventData['username'] as String?;
            }
          }
        } else if (undoneEvent.aggregateType == 'transaction') {
          final contactId = undoneEvent.eventData['contact_id'] as String?;
          if (contactId != null) {
            final createdContactEvent = allEvents.firstWhere(
              (e) => e.aggregateType == 'contact' &&
                     e.aggregateId == contactId &&
                     (e.eventType == 'CREATED' || e.eventType.contains('CREATE')),
              orElse: () => event,
            );
            if (createdContactEvent != event) {
              username = createdContactEvent.eventData['username'] as String?;
            }
          }
        }
      }
    } else if (eventType.contains('DELETE') || eventType.contains('DELETED')) {
      if (event.aggregateType == 'contact') {
        username = eventData['deleted_contact']?['username'] as String?;
        if (username == null) {
          final createdEvent = allEvents.firstWhere(
            (e) => e.aggregateType == 'contact' &&
                   e.aggregateId == event.aggregateId &&
                   (e.eventType == 'CREATED' || e.eventType.contains('CREATE')),
            orElse: () => event,
          );
          if (createdEvent != event) {
            username = createdEvent.eventData['username'] as String?;
          }
        }
      } else if (event.aggregateType == 'transaction') {
        final contactId = eventData['deleted_transaction']?['contact_id'] as String?;
        if (contactId != null) {
          final createdContactEvent = allEvents.firstWhere(
            (e) => e.aggregateType == 'contact' &&
                   e.aggregateId == contactId &&
                   (e.eventType == 'CREATED' || e.eventType.contains('CREATE')),
            orElse: () => event,
          );
          if (createdContactEvent != event) {
            username = createdContactEvent.eventData['username'] as String?;
          }
        }
      }
    } else if (event.aggregateType == 'contact') {
      username = eventData['username'] as String?;
    } else if (event.aggregateType == 'transaction') {
      final contactId = eventData['contact_id'] as String?;
      if (contactId != null) {
        final createdContactEvent = allEvents.firstWhere(
          (e) => e.aggregateType == 'contact' &&
                 e.aggregateId == contactId &&
                 (e.eventType == 'CREATED' || e.eventType.contains('CREATE')),
          orElse: () => event,
        );
        if (createdContactEvent != event) {
          username = createdContactEvent.eventData['username'] as String?;
        }
      }
    }
    return username;
  }
  
  /// Get amount display for an event, matching admin page logic
  static Future<AmountDisplay?> getAmount(
    Event event,
    Map<String, Event>? undoneEventsCache,
    List<Event> allEvents,
  ) async {
    final eventData = event.eventData;
    final eventType = event.eventType.toUpperCase();
    
    // Handle UNDO events
    if (eventType == 'UNDO') {
      final undoneEventId = eventData['undone_event_id'] as String?;
      if (undoneEventId != null && undoneEventsCache != null) {
        final undoneEvent = undoneEventsCache[undoneEventId];
        if (undoneEvent != null) {
          // If undoing a transaction, show transaction amount
          if (undoneEvent.aggregateType == 'transaction') {
            int? undoneAmount;
            String? undoneDirection;
            
            // Try to get from undone event's event_data (for UPDATE events)
            if (undoneEvent.eventData['amount'] != null) {
              undoneAmount = (undoneEvent.eventData['amount'] as num?)?.toInt();
              undoneDirection = undoneEvent.eventData['direction'] as String?;
            }
            // If undone event is DELETE, try to get from deleted_transaction
            else if (undoneEvent.eventData['deleted_transaction'] != null) {
              final deletedTx = undoneEvent.eventData['deleted_transaction'] as Map<String, dynamic>?;
              if (deletedTx != null) {
                undoneAmount = (deletedTx['amount'] as num?)?.toInt();
                undoneDirection = deletedTx['direction'] as String?;
              }
            }
            
            // If still no amount, try to find CREATED transaction event
            if (undoneAmount == null && undoneEvent.aggregateId.isNotEmpty) {
              final createdEvent = allEvents.firstWhere(
                (e) => e.aggregateType == 'transaction' &&
                       e.aggregateId == undoneEvent.aggregateId &&
                       (e.eventType == 'CREATED' || e.eventType.contains('CREATE')),
                orElse: () => event,
              );
              if (createdEvent != event && createdEvent.eventData['amount'] != null) {
                undoneAmount = (createdEvent.eventData['amount'] as num?)?.toInt();
                undoneDirection = createdEvent.eventData['direction'] as String? ?? 'owed';
              }
            }
            
            if (undoneAmount != null) {
              return AmountDisplay(
                amount: undoneAmount,
                direction: undoneDirection ?? 'owed',
                isNetImpact: false,
              );
            }
          }
          // If undoing a contact delete, calculate net balance impact
          else if (undoneEvent.aggregateType == 'contact') {
            // Find the DELETE event for this contact
            final deleteEvent = allEvents.firstWhere(
              (e) => e.aggregateType == 'contact' &&
                     e.aggregateId == undoneEvent.aggregateId &&
                     (e.eventType == 'DELETED' || e.eventType.contains('DELETE')),
              orElse: () => event,
            );
            
            if (deleteEvent != event) {
              final deleteTotalDebt = (deleteEvent.eventData['total_debt'] as num?)?.toInt();
              final undoTotalDebt = (eventData['total_debt'] as num?)?.toInt();
              
              if (deleteTotalDebt != null && undoTotalDebt != null) {
                final netImpact = undoTotalDebt - deleteTotalDebt;
                if (netImpact != 0) {
                  return AmountDisplay(
                    amount: netImpact.abs(),
                    direction: netImpact > 0 ? 'lent' : 'owed',
                    isNetImpact: true,
                  );
                }
              }
            }
          }
        }
      }
      return null;
    }
    
    // Handle DELETE contact events
    if ((eventType.contains('DELETE') || eventType.contains('DELETED')) && 
        event.aggregateType == 'contact') {
      // Find the event before this DELETE to get total_debt before deletion
      final currentIndex = allEvents.indexWhere((e) => e.id == event.id);
      if (currentIndex > 0) {
        final previousEvent = allEvents[currentIndex - 1];
        final previousTotalDebt = (previousEvent.eventData['total_debt'] as num?)?.toInt();
        final afterTotalDebt = (eventData['total_debt'] as num?)?.toInt();
        
        if (previousTotalDebt != null && afterTotalDebt != null) {
          final netImpact = afterTotalDebt - previousTotalDebt;
          if (netImpact != 0) {
            return AmountDisplay(
              amount: netImpact.abs(),
              direction: netImpact > 0 ? 'lent' : 'owed',
              isNetImpact: true,
            );
          }
        }
      }
      return null;
    }
    
    // Handle DELETE transaction events
    if ((eventType.contains('DELETE') || eventType.contains('DELETED')) && 
        event.aggregateType == 'transaction') {
      // Try deleted_transaction first
      final deletedTransaction = eventData['deleted_transaction'] as Map<String, dynamic>?;
      if (deletedTransaction != null) {
        final amount = (deletedTransaction['amount'] as num?)?.toInt();
        final direction = deletedTransaction['direction'] as String?;
        if (amount != null && direction != null) {
          return AmountDisplay(
            amount: amount,
            direction: direction,
            isNetImpact: false,
          );
        }
      }
      // Try to find CREATED transaction event
      final createdEvent = allEvents.firstWhere(
        (e) => e.aggregateType == 'transaction' &&
               e.aggregateId == event.aggregateId &&
               (e.eventType == 'CREATED' || e.eventType.contains('CREATE')),
        orElse: () => event,
      );
      if (createdEvent != event && createdEvent.eventData['amount'] != null) {
        final amount = (createdEvent.eventData['amount'] as num?)?.toInt();
        final direction = createdEvent.eventData['direction'] as String? ?? 'owed';
        if (amount != null) {
          return AmountDisplay(
            amount: amount,
            direction: direction,
            isNetImpact: false,
          );
        }
      }
      return null;
    }
    
    // Handle regular transaction events
    if (event.aggregateType == 'transaction' && eventData['amount'] != null) {
      final amount = (eventData['amount'] as num?)?.toInt();
      final direction = eventData['direction'] as String? ?? 'owed';
      if (amount != null) {
        return AmountDisplay(
          amount: amount,
          direction: direction,
          isNetImpact: false,
        );
      }
    }
    
    return null;
  }
}

/// Data class for amount display
class AmountDisplay {
  final int amount;
  final String direction; // 'lent' or 'owed'
  final bool isNetImpact; // true if this is a net balance impact (for DELETE/UNDO contact)
  
  AmountDisplay({
    required this.amount,
    required this.direction,
    required this.isNetImpact,
  });
  
  String get sign => direction == 'lent' ? '+' : '-';
  bool get isPositive => direction == 'lent';
}
