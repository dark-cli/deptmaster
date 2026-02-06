import 'dart:async';

import 'package:flutter/foundation.dart';

/// Fine-grained data change signal bus.
///
/// Step 3: Instead of "notify + refetch everything", we emit what changed and for which wallet.
/// Riverpod providers can watch the revision counters (via `select`) to refresh only the needed slices.
enum DataChangeType {
  wallet,
  contacts,
  transactions,
  events,
  all,
}

class DataChange {
  final DataChangeType type;
  final String? walletId;
  final DateTime at;

  const DataChange({
    required this.type,
    required this.walletId,
    required this.at,
  });
}

class DataBus extends ChangeNotifier {
  DataBus._();

  static final DataBus instance = DataBus._();

  final StreamController<DataChange> _controller = StreamController<DataChange>.broadcast();

  /// Stream of change events (optional consumers).
  Stream<DataChange> get stream => _controller.stream;

  DataChange? last;

  /// Revision counters used by providers for cheap dependency tracking.
  int revWallet = 0;
  int revContacts = 0;
  int revTransactions = 0;
  int revEvents = 0;
  int revAll = 0;

  void emit(DataChangeType type, {String? walletId}) {
    last = DataChange(type: type, walletId: walletId, at: DateTime.now());

    switch (type) {
      case DataChangeType.wallet:
        revWallet++;
        break;
      case DataChangeType.contacts:
        revContacts++;
        break;
      case DataChangeType.transactions:
        revTransactions++;
        break;
      case DataChangeType.events:
        revEvents++;
        break;
      case DataChangeType.all:
        revAll++;
        break;
    }

    // Notify provider listeners.
    notifyListeners();
    // Also emit on stream for any event-driven consumers.
    _controller.add(last!);
  }
}

