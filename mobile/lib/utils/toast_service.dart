import 'dart:async';
import 'package:flutter/material.dart';
import 'theme_colors.dart';
import '../main.dart'; // For navigatorKey

/// Centralized Toast Service
/// All toast notifications should use this service for consistency
class ToastService {
  /// Default duration for toasts (3 seconds)
  static const Duration defaultDuration = Duration(seconds: 3);
  
  /// Duration for error toasts (4 seconds - slightly longer for errors)
  static const Duration errorDuration = Duration(seconds: 4);
  
  /// Track active SnackBars to dismiss them after duration
  static final Map<ScaffoldMessengerState, Timer> _activeTimers = {};

  /// Show a success toast
  static void showSuccess(String message, {Duration? duration}) {
    _showToast(
      message: message,
      backgroundColor: ThemeColors.snackBarBackground,
      duration: duration ?? defaultDuration,
    );
  }

  /// Show an error toast
  static void showError(String message, {Duration? duration}) {
    _showToast(
      message: message,
      backgroundColor: ThemeColors.snackBarErrorBackground,
      duration: duration ?? errorDuration,
    );
  }

  /// Show an info toast
  static void showInfo(String message, {Duration? duration}) {
    _showToast(
      message: message,
      backgroundColor: ThemeColors.snackBarBackground,
      duration: duration ?? defaultDuration,
    );
  }

  /// Show a toast with undo action
  /// Returns a function to show success/error toast after undo
  static void showUndo({
    required String message,
    required VoidCallback onUndo,
    Duration? duration,
  }) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final actualDuration = duration ?? defaultDuration;
    
    // Dismiss any existing toast before showing new one
    scaffoldMessenger.hideCurrentSnackBar();
    
    // Cancel any existing timer for this scaffoldMessenger
    _activeTimers[scaffoldMessenger]?.cancel();
    
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: ThemeColors.snackBarTextColor(context),
          ),
        ),
        backgroundColor: ThemeColors.snackBarBackground(context),
        duration: const Duration(days: 1), // Set to very long duration since we'll dismiss manually
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'UNDO',
          textColor: ThemeColors.snackBarActionColor(context),
          onPressed: () {
            _activeTimers[scaffoldMessenger]?.cancel();
            _activeTimers.remove(scaffoldMessenger);
            scaffoldMessenger.hideCurrentSnackBar();
            onUndo();
          },
        ),
      ),
    );
    
    // Auto-dismiss after duration
    // Note: SnackBars with actions don't auto-dismiss, so we use a timer
    _activeTimers[scaffoldMessenger] = Timer(actualDuration, () {
      try {
        if (_activeTimers.containsKey(scaffoldMessenger)) {
          scaffoldMessenger.hideCurrentSnackBar();
          _activeTimers.remove(scaffoldMessenger);
        }
      } catch (e) {
        // SnackBar might already be dismissed, that's fine
        _activeTimers.remove(scaffoldMessenger);
      }
    });
  }

  /// Show a toast with undo action that handles errors
  /// onUndo should return a Future that may throw
  static void showUndoWithErrorHandling({
    required String message,
    required Future<void> Function() onUndo,
    required String successMessage,
    String? errorMessage,
    Duration? duration,
  }) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final actualDuration = duration ?? defaultDuration;
    
    // Dismiss any existing toast before showing new one
    scaffoldMessenger.hideCurrentSnackBar();
    
    // Cancel any existing timer for this scaffoldMessenger
    _activeTimers[scaffoldMessenger]?.cancel();
    
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: ThemeColors.snackBarTextColor(context),
          ),
        ),
        backgroundColor: ThemeColors.snackBarBackground(context),
        duration: const Duration(days: 1), // Set to very long duration since we'll dismiss manually
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'UNDO',
          textColor: ThemeColors.snackBarActionColor(context),
          onPressed: () async {
            _activeTimers[scaffoldMessenger]?.cancel();
            _activeTimers.remove(scaffoldMessenger);
            scaffoldMessenger.hideCurrentSnackBar();
            try {
              await onUndo();
              showSuccess(successMessage);
            } catch (e) {
              final errorMsg = errorMessage ?? 
                (e.toString().contains('too old') 
                  ? 'Cannot undo: Action is too old (must be within 5 seconds)'
                  : 'Error undoing: $e');
              showError(errorMsg);
            }
          },
        ),
      ),
    );
    
    // Auto-dismiss after duration
    // Note: SnackBars with actions don't auto-dismiss, so we use a timer
    _activeTimers[scaffoldMessenger] = Timer(actualDuration, () {
      try {
        if (_activeTimers.containsKey(scaffoldMessenger)) {
          scaffoldMessenger.hideCurrentSnackBar();
          _activeTimers.remove(scaffoldMessenger);
        }
      } catch (e) {
        // SnackBar might already be dismissed, that's fine
        _activeTimers.remove(scaffoldMessenger);
      }
    });
  }

  /// Internal method to show toast
  static void _showToast({
    required String message,
    required Color Function(BuildContext) backgroundColor,
    required Duration duration,
  }) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    // Dismiss any existing toast before showing new one
    scaffoldMessenger.hideCurrentSnackBar();
    
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: ThemeColors.snackBarTextColor(context),
          ),
        ),
        backgroundColor: backgroundColor(context),
        duration: duration,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Show toast from a BuildContext (for cases where context is available)
  /// This is useful when you have context and want to use it directly
  static void showSuccessFromContext(BuildContext context, String message, {Duration? duration}) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    // Dismiss any existing toast before showing new one
    scaffoldMessenger.hideCurrentSnackBar();
    
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: ThemeColors.snackBarTextColor(context),
          ),
        ),
        backgroundColor: ThemeColors.snackBarBackground(context),
        duration: duration ?? defaultDuration,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Show error toast from a BuildContext
  static void showErrorFromContext(BuildContext context, String message, {Duration? duration}) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    // Dismiss any existing toast before showing new one
    scaffoldMessenger.hideCurrentSnackBar();
    
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: ThemeColors.snackBarTextColor(context),
          ),
        ),
        backgroundColor: ThemeColors.snackBarErrorBackground(context),
        duration: duration ?? errorDuration,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Show info toast from a BuildContext
  static void showInfoFromContext(BuildContext context, String message, {Duration? duration}) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    // Dismiss any existing toast before showing new one
    scaffoldMessenger.hideCurrentSnackBar();
    
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: ThemeColors.snackBarTextColor(context),
          ),
        ),
        backgroundColor: ThemeColors.snackBarBackground(context),
        duration: duration ?? defaultDuration,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Show undo toast from a BuildContext
  static void showUndoFromContext({
    required BuildContext context,
    required String message,
    required VoidCallback onUndo,
    Duration? duration,
  }) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final actualDuration = duration ?? defaultDuration;
    
    // Dismiss any existing toast before showing new one
    scaffoldMessenger.hideCurrentSnackBar();
    
    // Cancel any existing timer for this scaffoldMessenger
    _activeTimers[scaffoldMessenger]?.cancel();
    
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: ThemeColors.snackBarTextColor(context),
          ),
        ),
        backgroundColor: ThemeColors.snackBarBackground(context),
        duration: const Duration(days: 1), // Set to very long duration since we'll dismiss manually
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'UNDO',
          textColor: ThemeColors.snackBarActionColor(context),
          onPressed: () {
            _activeTimers[scaffoldMessenger]?.cancel();
            _activeTimers.remove(scaffoldMessenger);
            scaffoldMessenger.hideCurrentSnackBar();
            onUndo();
          },
        ),
      ),
    );
    
    // Auto-dismiss after duration
    // Note: SnackBars with actions don't auto-dismiss, so we use a timer
    _activeTimers[scaffoldMessenger] = Timer(actualDuration, () {
      try {
        if (_activeTimers.containsKey(scaffoldMessenger)) {
          scaffoldMessenger.hideCurrentSnackBar();
          _activeTimers.remove(scaffoldMessenger);
        }
      } catch (e) {
        // SnackBar might already be dismissed, that's fine
        _activeTimers.remove(scaffoldMessenger);
      }
    });
  }

  /// Show undo toast from BuildContext with error handling
  static void showUndoWithErrorHandlingFromContext({
    required BuildContext context,
    required String message,
    required Future<void> Function() onUndo,
    required String successMessage,
    String? errorMessage,
    Duration? duration,
  }) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final actualDuration = duration ?? defaultDuration;
    
    // Dismiss any existing toast before showing new one
    scaffoldMessenger.hideCurrentSnackBar();
    
    // Cancel any existing timer for this scaffoldMessenger
    _activeTimers[scaffoldMessenger]?.cancel();
    
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: ThemeColors.snackBarTextColor(context),
          ),
        ),
        backgroundColor: ThemeColors.snackBarBackground(context),
        duration: const Duration(days: 1), // Set to very long duration since we'll dismiss manually
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'UNDO',
          textColor: ThemeColors.snackBarActionColor(context),
          onPressed: () async {
            _activeTimers[scaffoldMessenger]?.cancel();
            _activeTimers.remove(scaffoldMessenger);
            scaffoldMessenger.hideCurrentSnackBar();
            try {
              await onUndo();
              // Check if context is still valid before showing toast
              if (context.mounted) {
                showSuccessFromContext(context, successMessage);
              } else {
                showSuccess(successMessage);
              }
            } catch (e) {
              final errorMsg = errorMessage ?? 
                (e.toString().contains('too old') 
                  ? 'Cannot undo: Action is too old (must be within 5 seconds)'
                  : 'Error undoing: $e');
              // Check if context is still valid before showing toast
              if (context.mounted) {
                showErrorFromContext(context, errorMsg);
              } else {
                showError(errorMsg);
              }
            }
          },
        ),
      ),
    );
    
    // Auto-dismiss after duration
    // Note: SnackBars with actions don't auto-dismiss, so we use a timer
    _activeTimers[scaffoldMessenger] = Timer(actualDuration, () {
      try {
        if (_activeTimers.containsKey(scaffoldMessenger)) {
          scaffoldMessenger.hideCurrentSnackBar();
          _activeTimers.remove(scaffoldMessenger);
        }
      } catch (e) {
        // SnackBar might already be dismissed, that's fine
        _activeTimers.remove(scaffoldMessenger);
      }
    });
  }
  
  /// Cleanup method to cancel all active timers (useful for testing or cleanup)
  static void cancelAllTimers() {
    for (final timer in _activeTimers.values) {
      timer.cancel();
    }
    _activeTimers.clear();
  }
}
