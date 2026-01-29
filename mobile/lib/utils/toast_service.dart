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
    
    // Check if context is still mounted
    if (!context.mounted) return;

    // Try to get ScaffoldMessenger, but catch any errors if context is deactivated
    ScaffoldMessengerState? scaffoldMessenger;
    try {
      scaffoldMessenger = ScaffoldMessenger.of(context);
    } catch (e) {
      // Context is deactivated, can't show toast
      return;
    }
    
    // Double-check mounted after getting scaffoldMessenger
    if (!context.mounted || scaffoldMessenger == null) return;
    
    // Store in non-nullable variable for use in closures
    final messenger = scaffoldMessenger!;
    final actualDuration = duration ?? defaultDuration;
    
    try {
      // Dismiss any existing toast before showing new one
      // Wrap in try-catch to handle deactivated widget errors
      try {
        if (context.mounted) {
          messenger.hideCurrentSnackBar();
        }
      } catch (e) {
        // Context became deactivated, ignore
      }
      
      // Cancel any existing timer for this scaffoldMessenger
      _activeTimers[messenger]?.cancel();
      
      // Check context is still mounted before showing snackbar
      if (!context.mounted) return;
      
      messenger.showSnackBar(
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
              _activeTimers[messenger]?.cancel();
              _activeTimers.remove(messenger);
              try {
                if (context.mounted) {
                  messenger.hideCurrentSnackBar();
                }
              } catch (e) {
                // Context deactivated, ignore
              }
              onUndo();
            },
          ),
        ),
      );
      
      // Auto-dismiss after duration
      // Note: SnackBars with actions don't auto-dismiss, so we use a timer
      _activeTimers[messenger] = Timer(actualDuration, () {
        try {
          if (_activeTimers.containsKey(messenger)) {
            // Check if context is still mounted before hiding (context is accessible in closure)
            if (context.mounted) {
              messenger.hideCurrentSnackBar();
            }
            _activeTimers.remove(messenger);
          }
        } catch (e) {
          // SnackBar might already be dismissed or context deactivated, that's fine
          _activeTimers.remove(messenger);
        }
      });
    } catch (e) {
      // Context became deactivated while showing snackbar, ignore
      // This can happen if the widget is disposed during async operations
    }
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
    
    // Check if context is still mounted
    if (!context.mounted) return;

    // Try to get ScaffoldMessenger, but catch any errors if context is deactivated
    ScaffoldMessengerState? scaffoldMessenger;
    try {
      scaffoldMessenger = ScaffoldMessenger.of(context);
    } catch (e) {
      // Context is deactivated, can't show toast
      return;
    }
    
    // Double-check mounted after getting scaffoldMessenger
    if (!context.mounted || scaffoldMessenger == null) return;
    
    // Store in non-nullable variable for use in closures
    final messenger = scaffoldMessenger!;
    final actualDuration = duration ?? defaultDuration;
    
    try {
      // Dismiss any existing toast before showing new one
      // Wrap in try-catch to handle deactivated widget errors
      try {
        if (context.mounted) {
          messenger.hideCurrentSnackBar();
        }
      } catch (e) {
        // Context became deactivated, ignore
      }
      
      // Cancel any existing timer for this scaffoldMessenger
      _activeTimers[messenger]?.cancel();
      
      // Check context is still mounted before showing snackbar
      if (!context.mounted) return;
      
      messenger.showSnackBar(
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
            _activeTimers[messenger]?.cancel();
            _activeTimers.remove(messenger);
            try {
              if (context.mounted) {
                messenger.hideCurrentSnackBar();
              }
            } catch (e) {
              // Context deactivated, ignore
            }
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
    _activeTimers[messenger] = Timer(actualDuration, () {
      try {
        if (_activeTimers.containsKey(messenger)) {
          // Check if context is still mounted before hiding (context is accessible in closure)
          if (context.mounted) {
            messenger.hideCurrentSnackBar();
          }
          _activeTimers.remove(messenger);
        }
      } catch (e) {
        // SnackBar might already be dismissed or context deactivated, that's fine
        _activeTimers.remove(messenger);
      }
    });
    } catch (e) {
      // Context became deactivated while showing snackbar, ignore
      // This can happen if the widget is disposed during async operations
    }
  }

  /// Internal method to show toast
  static void _showToast({
    required String message,
    required Color Function(BuildContext) backgroundColor,
    required Duration duration,
  }) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    // Check if context is still mounted
    if (!context.mounted) return;

    // Try to get ScaffoldMessenger, but catch any errors if context is deactivated
    ScaffoldMessengerState? scaffoldMessenger;
    try {
      scaffoldMessenger = ScaffoldMessenger.of(context);
    } catch (e) {
      // Context is deactivated, can't show toast
      return;
    }
    
    // Double-check mounted after getting scaffoldMessenger
    if (!context.mounted || scaffoldMessenger == null) return;
    
    // Store in non-nullable variable
    final messenger = scaffoldMessenger!;
    
    try {
      // Dismiss any existing toast before showing new one
      // Wrap in try-catch to handle deactivated widget errors
      try {
        if (context.mounted) {
          messenger.hideCurrentSnackBar();
        }
      } catch (e) {
        // Context became deactivated, ignore
      }
      
      // Check context is still mounted before showing snackbar
      if (!context.mounted) return;
      
      messenger.showSnackBar(
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
    } catch (e) {
      // Context became deactivated while showing snackbar, ignore
      // This can happen if the widget is disposed during async operations
    }
  }

  /// Show toast from a BuildContext (for cases where context is available)
  /// This is useful when you have context and want to use it directly
  static void showSuccessFromContext(BuildContext context, String message, {Duration? duration}) {
    try {
      // Check if context is still mounted/valid before using it
      if (!context.mounted) {
        // Fallback to global navigator if context is invalid
        showSuccess(message, duration: duration);
        return;
      }
      
      // Try to get ScaffoldMessenger, but catch any errors if context is deactivated
      ScaffoldMessengerState? scaffoldMessenger;
      try {
        scaffoldMessenger = ScaffoldMessenger.of(context);
      } catch (e) {
        // Context is deactivated, fallback to global navigator
        showSuccess(message, duration: duration);
        return;
      }
      
      if (scaffoldMessenger == null) {
        showSuccess(message, duration: duration);
        return;
      }
      
      // Dismiss any existing toast before showing new one
      scaffoldMessenger!.hideCurrentSnackBar();
      
      scaffoldMessenger!.showSnackBar(
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
    } catch (e) {
      // Context is deactivated or any other error, fallback to global navigator
      showSuccess(message, duration: duration);
    }
  }

  /// Show error toast from a BuildContext
  static void showErrorFromContext(BuildContext context, String message, {Duration? duration}) {
    try {
      // Check if context is still mounted/valid before using it
      if (!context.mounted) {
        // Fallback to global navigator if context is invalid
        showError(message, duration: duration);
        return;
      }
      
      // Try to get ScaffoldMessenger, but catch any errors if context is deactivated
      ScaffoldMessengerState? scaffoldMessenger;
      try {
        scaffoldMessenger = ScaffoldMessenger.of(context);
      } catch (e) {
        // Context is deactivated, fallback to global navigator
        showError(message, duration: duration);
        return;
      }
      
      // Double-check mounted after getting scaffoldMessenger
      if (!context.mounted) {
        showError(message, duration: duration);
        return;
      }
      
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
    } catch (e) {
      // Context is deactivated or any other error, fallback to global navigator
      showError(message, duration: duration);
    }
  }

  /// Show info toast from a BuildContext
  static void showInfoFromContext(BuildContext context, String message, {Duration? duration}) {
    try {
      // Check if context is still mounted/valid before using it
      if (!context.mounted) {
        // Fallback to global navigator if context is invalid
        showInfo(message, duration: duration);
        return;
      }
      
      // Try to get ScaffoldMessenger, but catch any errors if context is deactivated
      ScaffoldMessengerState? scaffoldMessenger;
      try {
        scaffoldMessenger = ScaffoldMessenger.of(context);
      } catch (e) {
        // Context is deactivated, fallback to global navigator
        showInfo(message, duration: duration);
        return;
      }
      
      if (scaffoldMessenger == null) {
        showInfo(message, duration: duration);
        return;
      }
      
      // Dismiss any existing toast before showing new one
      scaffoldMessenger!.hideCurrentSnackBar();
      
      scaffoldMessenger!.showSnackBar(
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
    } catch (e) {
      // Context is deactivated or any other error, fallback to global navigator
      showInfo(message, duration: duration);
    }
  }

  /// Show undo toast from a BuildContext
  static void showUndoFromContext({
    required BuildContext context,
    required String message,
    required VoidCallback onUndo,
    Duration? duration,
  }) {
    try {
      // Check if context is still mounted/valid before using it
      if (!context.mounted) {
        // Fallback to global navigator if context is invalid
        showUndo(message: message, onUndo: onUndo, duration: duration);
        return;
      }
      
      // Try to get ScaffoldMessenger, but catch any errors if context is deactivated
      ScaffoldMessengerState? scaffoldMessenger;
      try {
        scaffoldMessenger = ScaffoldMessenger.of(context);
      } catch (e) {
        // Context is deactivated, fallback to global navigator
        showUndo(message: message, onUndo: onUndo, duration: duration);
        return;
      }
      
      if (scaffoldMessenger == null) {
        showUndo(message: message, onUndo: onUndo, duration: duration);
        return;
      }
      final actualDuration = duration ?? defaultDuration;
      
      // Dismiss any existing toast before showing new one
      scaffoldMessenger!.hideCurrentSnackBar();
      
      // Cancel any existing timer for this scaffoldMessenger
      _activeTimers[scaffoldMessenger!]?.cancel();
      
      scaffoldMessenger!.showSnackBar(
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
              _activeTimers[scaffoldMessenger!]?.cancel();
              _activeTimers.remove(scaffoldMessenger!);
              scaffoldMessenger!.hideCurrentSnackBar();
              onUndo();
            },
          ),
        ),
      );
      
      // Auto-dismiss after duration
      // Note: SnackBars with actions don't auto-dismiss, so we use a timer
      _activeTimers[scaffoldMessenger!] = Timer(actualDuration, () {
        try {
          if (scaffoldMessenger != null && _activeTimers.containsKey(scaffoldMessenger!)) {
            scaffoldMessenger!.hideCurrentSnackBar();
            _activeTimers.remove(scaffoldMessenger!);
          }
        } catch (e) {
          // SnackBar might already be dismissed, that's fine
          if (scaffoldMessenger != null) {
            _activeTimers.remove(scaffoldMessenger!);
          }
        }
      });
    } catch (e) {
      // Context is deactivated, fallback to global navigator
      showUndo(message: message, onUndo: onUndo, duration: duration);
    }
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
    try {
      // Check if context is still mounted/valid before using it
      if (!context.mounted) {
        // Fallback to global navigator if context is invalid
        showUndoWithErrorHandling(
          message: message,
          onUndo: onUndo,
          successMessage: successMessage,
          errorMessage: errorMessage,
          duration: duration,
        );
        return;
      }
      
      // Try to get ScaffoldMessenger, but catch any errors if context is deactivated
      ScaffoldMessengerState? scaffoldMessenger;
      try {
        scaffoldMessenger = ScaffoldMessenger.of(context);
      } catch (e) {
        // Context is deactivated, fallback to global navigator
        showUndoWithErrorHandling(
          message: message,
          onUndo: onUndo,
          successMessage: successMessage,
          errorMessage: errorMessage,
          duration: duration,
        );
        return;
      }
      
      if (scaffoldMessenger == null) {
        showUndoWithErrorHandling(
          message: message,
          onUndo: onUndo,
          successMessage: successMessage,
          errorMessage: errorMessage,
          duration: duration,
        );
        return;
      }
      final actualDuration = duration ?? defaultDuration;
      
      // Dismiss any existing toast before showing new one
      scaffoldMessenger!.hideCurrentSnackBar();
      
      // Cancel any existing timer for this scaffoldMessenger
      _activeTimers[scaffoldMessenger!]?.cancel();
      
      scaffoldMessenger!.showSnackBar(
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
              _activeTimers[scaffoldMessenger!]?.cancel();
              _activeTimers.remove(scaffoldMessenger!);
              scaffoldMessenger!.hideCurrentSnackBar();
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
      _activeTimers[scaffoldMessenger!] = Timer(actualDuration, () {
        try {
          if (scaffoldMessenger != null && _activeTimers.containsKey(scaffoldMessenger!)) {
            scaffoldMessenger!.hideCurrentSnackBar();
            _activeTimers.remove(scaffoldMessenger!);
          }
        } catch (e) {
          // SnackBar might already be dismissed, that's fine
          if (scaffoldMessenger != null) {
            _activeTimers.remove(scaffoldMessenger!);
          }
        }
      });
    } catch (e) {
      // Context is deactivated, fallback to global navigator
      showUndoWithErrorHandling(
        message: message,
        onUndo: onUndo,
        successMessage: successMessage,
        errorMessage: errorMessage,
        duration: duration,
      );
    }
  }
  
  /// Cleanup method to cancel all active timers (useful for testing or cleanup)
  static void cancelAllTimers() {
    for (final timer in _activeTimers.values) {
      timer.cancel();
    }
    _activeTimers.clear();
  }
}
