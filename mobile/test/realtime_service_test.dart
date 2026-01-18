import 'package:flutter_test/flutter_test.dart';
import 'package:debt_tracker_mobile/services/realtime_service.dart';
import 'package:debt_tracker_mobile/services/api_service.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

// Generate mocks
@GenerateMocks([ApiService])
import 'realtime_service_test.mocks.dart';

void main() {
  group('RealtimeService', () {
    test('handles transaction_created event', () {
      bool listenerCalled = false;
      Map<String, dynamic>? receivedData;

      // Add a listener
      RealtimeService.addListener((data) {
        listenerCalled = true;
        receivedData = data;
      });

      // Simulate receiving a transaction_created event
      final eventData = {
        'type': 'transaction_created',
        'data': {'id': 'test-id', 'contact_id': 'contact-id'},
      };

      // In a real test, we'd need to mock the WebSocket connection
      // For now, we test the handler logic
      RealtimeService._handleRealtimeUpdate(eventData);

      // Note: This test is simplified - in reality, we'd need to mock WebSocket
      // and verify that _syncTransaction was called
    });

    test('handles transaction_updated event', () {
      bool listenerCalled = false;

      RealtimeService.addListener((data) {
        listenerCalled = true;
      });

      final eventData = {
        'type': 'transaction_updated',
        'data': {'id': 'test-id'},
      };

      RealtimeService._handleRealtimeUpdate(eventData);
    });

    test('handles transaction_deleted event', () {
      bool listenerCalled = false;

      RealtimeService.addListener((data) {
        listenerCalled = true;
      });

      final eventData = {
        'type': 'transaction_deleted',
        'data': {'id': 'test-id'},
      };

      RealtimeService._handleRealtimeUpdate(eventData);
    });

    test('notifies all listeners on event', () {
      int callCount = 0;

      // Add multiple listeners
      RealtimeService.addListener((data) {
        callCount++;
      });

      RealtimeService.addListener((data) {
        callCount++;
      });

      final eventData = {
        'type': 'transaction_created',
        'data': {},
      };

      RealtimeService._notifyListeners(eventData);

      // Both listeners should be called
      expect(callCount, equals(2));
    });
  });
}
