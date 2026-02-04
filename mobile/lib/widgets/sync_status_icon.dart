// ignore_for_file: unused_local_variable

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/sync_service_v2.dart';
import '../utils/theme_colors.dart';

/// Simple sync status icon widget
/// Shows: synced (cloud done), unsynced/syncing (sync icon), offline (cloud-off), error (warning)
class SyncStatusIcon extends StatefulWidget {
  const SyncStatusIcon({super.key});

  @override
  State<SyncStatusIcon> createState() => _SyncStatusIconState();
}

class _SyncStatusIconState extends State<SyncStatusIcon> {
  SyncStatus _status = SyncStatus.synced;
  bool _hasError = false;
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _updateStatus();
      _startPeriodicUpdate();
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  void _startPeriodicUpdate() {
    _updateTimer?.cancel();
    _updateTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        _updateStatus();
        _startPeriodicUpdate();
      }
    });
  }

  Future<void> _updateStatus() async {
    if (kIsWeb) return;

    try {
      final status = await SyncServiceV2.getSyncStatusForUI();
      final hasError = SyncServiceV2.hasSyncError;
      if (mounted && (_status != status || _hasError != hasError)) {
        setState(() {
          _status = status;
          _hasError = hasError;
        });
      }
    } catch (e) {
      // Ignore errors
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Determine icon and color based on status
    IconData icon;
    Color color;

    if (_hasError && _status == SyncStatus.unsynced) {
      // Show warning only if there's an actual error AND unsynced
      icon = Icons.error_outline;
      color = ThemeColors.warning(context);
    } else if (_status == SyncStatus.synced) {
      icon = Icons.cloud_done_outlined;
      color = ThemeColors.success(context);
    } else if (_status == SyncStatus.offline) {
      icon = Icons.cloud_off_outlined;
      color = ThemeColors.gray(context, shade: 500);
    } else {
      // For syncing or unsynced (without error), show sync icon
      icon = Icons.sync;
      color = theme.colorScheme.primary;
    }

    // Get tooltip text based on status
    String tooltipText;
    switch (_status) {
      case SyncStatus.synced:
        tooltipText = 'Synced';
        break;
      case SyncStatus.unsynced:
        tooltipText = _hasError ? 'Sync error - tap to retry' : 'Syncing...';
        break;
      case SyncStatus.syncing:
        tooltipText = 'Syncing...';
        break;
      case SyncStatus.offline:
        tooltipText = 'Offline';
        break;
    }

    return Tooltip(
      message: tooltipText,
      child: Icon(
        icon,
        size: 20,
        color: color,
      ),
    );
  }
}