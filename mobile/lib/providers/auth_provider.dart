import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/lib.dart' as rust;
import 'data_change_provider.dart';
import '../api.dart';

/// Whether the user is currently logged in (a valid token is stored).
/// Reactive: invalidates on Permissions changes (covers logout +
/// role changes) and walletMembership (covers being removed from
/// the wallet they were viewing).
final isLoggedInProvider = FutureProvider<bool>((ref) async {
  invalidateOnDataChange(
    ref,
    kinds: [DataChangeKind.permissions, DataChangeKind.walletMembership],
  );
  return await rust.isLoggedIn();
});

/// Current user's UUID. Throws if not logged in — callers should
/// handle the error state (Riverpod's AsyncValue.error) by routing
/// to the login screen.
final currentUserIdProvider = FutureProvider<String>((ref) async {
  // Don't auto-invalidate; once you're logged in your id doesn't change.
  // Re-fetch only on login/logout, which the screens trigger manually
  // via `ref.invalidate(currentUserIdProvider)`.
  return await rust.getUserId();
});

/// Current user's display name (from the JWT). Throws if not logged in.
final currentUsernameProvider = FutureProvider<String>((ref) async {
  return await rust.getUsername();
});
