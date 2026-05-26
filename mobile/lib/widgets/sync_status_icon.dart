import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../api.dart';
import '../utils/theme_colors.dart';

/// Sync/connection status icon. Updates immediately when connection or sync error state changes.
/// Shows: synced (cloud done), offline (cloud-off), error (warning), or syncing (sync icon).
class SyncStatusIcon extends StatefulWidget {
  const SyncStatusIcon({super.key});

  @override
  State<SyncStatusIcon> createState() => _SyncStatusIconState();
}

class _SyncStatusIconState extends State<SyncStatusIcon> {
  Timer? _periodicTimer;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      Api.connectionStateRevision.addListener(_onConnectionStateChanged);
      _scheduleNextCheck();
    }
  }

  void _scheduleNextCheck() {
    _periodicTimer?.cancel();
    if (!mounted) return;
    const interval = Duration(seconds: 3);
    _periodicTimer = Timer(interval, () {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    if (!kIsWeb) {
      Api.connectionStateRevision.removeListener(_onConnectionStateChanged);
    }
    _periodicTimer?.cancel();
    super.dispose();
  }

  void _onConnectionStateChanged() {
    if (mounted) setState(() {});
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
    _scheduleNextCheck();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final state = Api.connectionState;
    final hasWalletSelected = Api.hasWalletSelected;
    if (!hasWalletSelected) {
      return Tooltip(
        message: 'Select a wallet to sync',
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            Icons.account_balance_wallet_outlined,
            size: 20,
            color: ThemeColors.gray(context, shade: 600),
          ),
        ),
      );
    }
    final isOffline = !state.isOnline;
    final hasError = state.hasSyncError;
    final hasAuthIssue = state.hasAuthIssue;
    final isSynced = state.isOnline && !state.hasSyncError;

    IconData icon;
    Color color;
    if (hasAuthIssue) {
      icon = Icons.warning_amber_rounded;
      color = ThemeColors.warning(context);
    } else if (isOffline) {
      icon = Icons.cloud_off_outlined;
      color = ThemeColors.gray(context, shade: 600);
    } else if (hasError) {
      icon = Icons.error_outline;
      color = ThemeColors.warning(context);
    } else if (isSynced) {
      icon = Icons.cloud_done_outlined;
      color = ThemeColors.success(context);
    } else {
      icon = Icons.sync;
      color = theme.colorScheme.primary;
    }

    final String tooltipText = hasAuthIssue
        ? 'Authorization issue - tap for details'
        : (isOffline
            ? 'Offline - tap to check'
            : (isSynced
                ? 'Synced - tap to refresh'
                : (hasError ? 'Sync error - tap to retry' : 'Syncing...')));

    return Tooltip(
      message: tooltipText,
      child: InkWell(
        onTap: () async {
          if (kIsWeb) return;
          if (hasAuthIssue) {
            if (!mounted) return;
            await showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Authorization required'),
                content: const Text(
                  'Your session is no longer valid. The app will keep working offline, '
                  'but syncing is paused until you log in again.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await Api.refreshConnectionAndSync();
                      _refresh();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
            return;
          }
          await Api.refreshConnectionAndSync();
          _refresh();
        },
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 20,
            color: color,
          ),
        ),
      ),
    );
  }
}