// ignore_for_file: unused_local_variable

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../api.dart';
import '../utils/theme_colors.dart';

/// Simple sync status icon widget
/// Shows: synced (cloud done), unsynced/syncing (sync icon), offline (cloud-off), error (warning)
class SyncStatusIcon extends StatefulWidget {
  const SyncStatusIcon({super.key});

  @override
  State<SyncStatusIcon> createState() => _SyncStatusIconState();
}

class _SyncStatusIconState extends State<SyncStatusIcon> {
  String _status = 'Synced';
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
      final status = await Api.getSyncStatusForUI();
      final hasError = Api.hasSyncError;
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
    final isSynced = _status == 'Synced';

    IconData icon;
    Color color;
    if (_hasError && !isSynced) {
      icon = Icons.error_outline;
      color = ThemeColors.warning(context);
    } else if (isSynced) {
      icon = Icons.cloud_done_outlined;
      color = ThemeColors.success(context);
    } else {
      icon = Icons.sync;
      color = theme.colorScheme.primary;
    }

    final String tooltipText = isSynced
        ? 'Synced'
        : (_hasError ? 'Sync error - tap to retry' : 'Syncing...');

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