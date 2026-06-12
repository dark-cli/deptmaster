import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';

/// Current [ConnectionState] as a reactive Stream. Backed by
/// `Api.connectionStateStream` which fires whenever the underlying
/// WebSocket state, sync error flag, or auth issue flag flips.
///
/// Widgets typically use `.when(data: ..., loading: ..., error: ...)`
/// or just `.value?.isOnline ?? true` for a quick boolean.
final connectionStateProvider = StreamProvider<ConnectionState>((ref) {
  return Api.connectionStateStream;
});
