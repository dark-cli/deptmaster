// ignore_for_file: unnecessary_null_comparison

import 'dart:async';
import 'package:flutter/material.dart';
import 'theme_colors.dart';
import '../main.dart'; // For navigatorKey and scaffoldMessengerKey

/// Centralized Toast Service
/// All toast notifications should use this service for consistency
class ToastService {
  /// Default duration for toasts (2.5 seconds)
  static const Duration defaultDuration = Duration(milliseconds: 2500);
  
  /// Duration for error toasts (5 seconds - longer for errors with dismiss button)
  static const Duration errorDuration = Duration(seconds: 5);
  
  /// Duration for undo snack bars (2.5 seconds)
  static const Duration undoDuration = Duration(milliseconds: 2500);
  
  /// Margin for snack bars to position them above FAB and bottom navigation
  /// This prevents snack bars from overlapping with the floating action button
  static const EdgeInsets snackBarMargin = EdgeInsets.only(
    bottom: 24.0, // Small space above bottom navigation bar and FAB
    left: 16.0,
    right: 16.0,
  );
  
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

  /// Show an error toast with dismiss button
  static void showError(String message, {Duration? duration}) {
    _showErrorToast(
      message: message,
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
    // Get context for theme colors and ScaffoldMessenger
    final context = navigatorKey.currentContext;
    
    // Try to use scaffoldMessengerKey first (most reliable)
    ScaffoldMessengerState? scaffoldMessenger;
    if (scaffoldMessengerKey.currentState != null) {
      scaffoldMessenger = scaffoldMessengerKey.currentState;
    } else {
      // Fallback to using context
      if (context == null) {
        print('⚠️ ToastService.showUndo: navigatorKey.currentContext is null and scaffoldMessengerKey is null');
        return;
      }
      
      // Check if context is still mounted
      if (!context.mounted) {
        print('⚠️ ToastService.showUndo: context is not mounted');
        return;
      }

      // Try to get ScaffoldMessenger, but catch any errors if context is deactivated
      try {
        scaffoldMessenger = ScaffoldMessenger.of(context);
      } catch (e) {
        // Context is deactivated, can't show toast
        print('⚠️ ToastService.showUndo: ScaffoldMessenger.of failed: $e');
        return;
      }
    }
    
    if (scaffoldMessenger == null) {
      print('⚠️ ToastService.showUndo: scaffoldMessenger is null');
      return;
    }
    
    // Store in non-nullable variable for use in closures
    final messenger = scaffoldMessenger;
    final actualDuration = duration ?? undoDuration;
    
    // Get theme colors
    final textColor = context != null 
        ? ThemeColors.snackBarTextColor(context)
        : Colors.white;
    final backgroundColor = context != null
        ? ThemeColors.snackBarBackground(context)
        : Colors.grey[800]!;
    final actionColor = context != null
        ? ThemeColors.snackBarActionColor(context)
        : Colors.blue;
    
    try {
      // Dismiss any existing toast before showing new one
      try {
        messenger.hideCurrentSnackBar();
      } catch (e) {
        // Context became deactivated, ignore
      }
      
      // Cancel any existing timer for this scaffoldMessenger
      _activeTimers[messenger]?.cancel();
      _activeTimers.remove(messenger);
      
      try {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              message,
              style: TextStyle(
                color: textColor,
              ),
            ),
            backgroundColor: backgroundColor,
            duration: actualDuration, // Use actual duration - Flutter will handle auto-dismiss
            behavior: SnackBarBehavior.floating,
            margin: snackBarMargin, // Position above FAB and bottom navigation
            action: SnackBarAction(
              label: 'UNDO',
              textColor: actionColor,
              onPressed: () {
                _activeTimers[messenger]?.cancel();
                _activeTimers.remove(messenger);
                try {
                  messenger.hideCurrentSnackBar();
                } catch (e) {
                  // Context deactivated, ignore
                }
                onUndo();
              },
            ),
          ),
        );
        print('✅ ToastService.showUndo: SnackBar shown successfully');
      } catch (e) {
        print('❌ ToastService.showUndo: Error showing SnackBar: $e');
        rethrow;
      }
      
      // Set up a backup timer to ensure dismissal even if Flutter's auto-dismiss fails
      // This is a safety net for snack bars with actions
      _activeTimers[messenger] = Timer(actualDuration + const Duration(milliseconds: 500), () {
        try {
          if (_activeTimers.containsKey(messenger)) {
            messenger.hideCurrentSnackBar();
            _activeTimers.remove(messenger);
          }
        } catch (e) {
          // SnackBar might already be dismissed or context deactivated, that's fine
          _activeTimers.remove(messenger);
        }
      });
    } catch (e) {
      // Context became deactivated while showing snackbar, log the error
      print('❌ ToastService.showUndo: Exception while showing snackbar: $e');
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
    // Try to use scaffoldMessengerKey first (most reliable)
    ScaffoldMessengerState? scaffoldMessenger;
    if (scaffoldMessengerKey.currentState != null) {
      scaffoldMessenger = scaffoldMessengerKey.currentState;
    } else {
      // Fallback to using context
      final context = navigatorKey.currentContext;
      if (context == null) return;
      
      // Check if context is still mounted
      if (!context.mounted) return;

      // Try to get ScaffoldMessenger, but catch any errors if context is deactivated
      try {
        scaffoldMessenger = ScaffoldMessenger.of(context);
      } catch (e) {
        // Context is deactivated, can't show toast
        return;
      }
    }
    
    if (scaffoldMessenger == null) return;
    
    // Store in non-nullable variable for use in closures
    final messenger = scaffoldMessenger;
    final actualDuration = duration ?? undoDuration;
    
    // Get context for theme colors
    final context = navigatorKey.currentContext;
    final textColor = context != null 
        ? ThemeColors.snackBarTextColor(context)
        : Colors.white;
    final backgroundColor = context != null
        ? ThemeColors.snackBarBackground(context)
        : Colors.grey[800]!;
    final actionColor = context != null
        ? ThemeColors.snackBarActionColor(context)
        : Colors.blue;
    
    try {
      // Dismiss any existing toast before showing new one
      try {
        messenger.hideCurrentSnackBar();
      } catch (e) {
        // Context became deactivated, ignore
      }
      
      // Cancel any existing timer for this scaffoldMessenger
      _activeTimers[messenger]?.cancel();
      _activeTimers.remove(messenger);
      
      messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: textColor,
          ),
        ),
        backgroundColor: backgroundColor,
        duration: actualDuration, // Use actual duration - Flutter will handle auto-dismiss
        behavior: SnackBarBehavior.floating,
        margin: snackBarMargin, // Position above FAB and bottom navigation
        action: SnackBarAction(
          label: 'UNDO',
          textColor: actionColor,
          onPressed: () async {
            _activeTimers[messenger]?.cancel();
            _activeTimers.remove(messenger);
            try {
              messenger.hideCurrentSnackBar();
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
    
    // Set up a backup timer to ensure dismissal even if Flutter's auto-dismiss fails
    // This is a safety net for snack bars with actions
    _activeTimers[messenger] = Timer(actualDuration + const Duration(milliseconds: 500), () {
      try {
        if (_activeTimers.containsKey(messenger)) {
          messenger.hideCurrentSnackBar();
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
      print('❌ ToastService.showUndoWithErrorHandling: Exception: $e');
    }
  }

  /// Internal method to show error toast with dismiss button
  static void _showErrorToast({
    required String message,
    required Duration duration,
  }) {
    // Try to use scaffoldMessengerKey first (most reliable)
    ScaffoldMessengerState? scaffoldMessenger;
    if (scaffoldMessengerKey.currentState != null) {
      scaffoldMessenger = scaffoldMessengerKey.currentState;
    } else {
      // Fallback to using context
      final context = navigatorKey.currentContext;
      if (context == null) {
        print('⚠️ ToastService._showErrorToast: navigatorKey.currentContext is null and scaffoldMessengerKey is null');
        return;
      }

      // Check if context is still mounted
      if (!context.mounted) {
        print('⚠️ ToastService._showErrorToast: context is not mounted');
        return;
      }

      // Try to get ScaffoldMessenger, but catch any errors if context is deactivated
      try {
        scaffoldMessenger = ScaffoldMessenger.of(context);
      } catch (e) {
        // Context is deactivated, can't show toast
        print('⚠️ ToastService._showErrorToast: ScaffoldMessenger.of failed: $e');
        return;
      }
    }
    
    if (scaffoldMessenger == null) {
      print('⚠️ ToastService._showErrorToast: scaffoldMessenger is null');
      return;
    }
    
    // Store in non-nullable variable
    final messenger = scaffoldMessenger;
    
    // Get context for theme colors
    final context = navigatorKey.currentContext;
    final bgColor = context != null 
        ? ThemeColors.snackBarErrorBackground(context)
        : Colors.red[800]!;
    final textColor = context != null 
        ? ThemeColors.snackBarTextColor(context)
        : Colors.white;
    final actionColor = context != null
        ? ThemeColors.snackBarActionColor(context)
        : Colors.white;
    
    try {
      // Dismiss any existing toast before showing new one
      try {
        messenger.hideCurrentSnackBar();
      } catch (e) {
        // Context became deactivated, ignore
      }
      
      try {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              message,
              style: TextStyle(
                color: textColor,
              ),
            ),
            backgroundColor: bgColor,
            duration: duration,
            behavior: SnackBarBehavior.floating,
            margin: snackBarMargin, // Position above FAB and bottom navigation
            action: SnackBarAction(
              label: 'DISMISS',
              textColor: actionColor,
              onPressed: () {
                messenger.hideCurrentSnackBar();
              },
            ),
          ),
        );
        print('✅ ToastService._showErrorToast: SnackBar shown successfully');
      } catch (e) {
        print('❌ ToastService._showErrorToast: Error showing SnackBar: $e');
        rethrow;
      }
    } catch (e) {
      // Context became deactivated while showing snackbar, log the error
      print('❌ ToastService._showErrorToast: Exception while showing snackbar: $e');
    }
  }

  /// Internal method to show toast
  static void _showToast({
    required String message,
    required Color Function(BuildContext) backgroundColor,
    required Duration duration,
  }) {
    // Try to use scaffoldMessengerKey first (most reliable)
    ScaffoldMessengerState? scaffoldMessenger;
    if (scaffoldMessengerKey.currentState != null) {
      scaffoldMessenger = scaffoldMessengerKey.currentState;
    } else {
      // Fallback to using context
      final context = navigatorKey.currentContext;
      if (context == null) {
        print('⚠️ ToastService._showToast: navigatorKey.currentContext is null and scaffoldMessengerKey is null');
        return;
      }

      // Check if context is still mounted
      if (!context.mounted) {
        print('⚠️ ToastService._showToast: context is not mounted');
        return;
      }

      // Try to get ScaffoldMessenger, but catch any errors if context is deactivated
      try {
        scaffoldMessenger = ScaffoldMessenger.of(context);
      } catch (e) {
        // Context is deactivated, can't show toast
        print('⚠️ ToastService._showToast: ScaffoldMessenger.of failed: $e');
        return;
      }
    }
    
    if (scaffoldMessenger == null) {
      print('⚠️ ToastService._showToast: scaffoldMessenger is null');
      return;
    }
    
    // Store in non-nullable variable
    final messenger = scaffoldMessenger;
    
    // Get context for theme colors
    final context = navigatorKey.currentContext;
    final bgColor = context != null ? backgroundColor(context) : Colors.grey[800]!;
    final textColor = context != null 
        ? ThemeColors.snackBarTextColor(context)
        : Colors.white;
    
    try {
      // Dismiss any existing toast before showing new one
      try {
        messenger.hideCurrentSnackBar();
      } catch (e) {
        // Context became deactivated, ignore
      }
      
      try {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              message,
              style: TextStyle(
                color: textColor,
              ),
            ),
            backgroundColor: bgColor,
            duration: duration,
            behavior: SnackBarBehavior.floating,
            margin: snackBarMargin, // Position above FAB and bottom navigation
          ),
        );
        print('✅ ToastService._showToast: SnackBar shown successfully');
      } catch (e) {
        print('❌ ToastService._showToast: Error showing SnackBar: $e');
        rethrow;
      }
    } catch (e) {
      // Context became deactivated while showing snackbar, log the error
      print('❌ ToastService._showToast: Exception while showing snackbar: $e');
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
        // Context is deactivated, try scaffoldMessengerKey as fallback
        if (scaffoldMessengerKey.currentState != null) {
          scaffoldMessenger = scaffoldMessengerKey.currentState;
        } else {
          // Fallback to global method
          showSuccess(message, duration: duration);
          return;
        }
      }
      
      if (scaffoldMessenger == null) {
        showSuccess(message, duration: duration);
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
          backgroundColor: ThemeColors.snackBarBackground(context),
          duration: duration ?? defaultDuration,
          behavior: SnackBarBehavior.floating,
          margin: snackBarMargin, // Position above FAB and bottom navigation
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
        // Context is deactivated, try scaffoldMessengerKey as fallback
        if (scaffoldMessengerKey.currentState != null) {
          scaffoldMessenger = scaffoldMessengerKey.currentState;
        } else {
          // Fallback to global method
          showError(message, duration: duration);
          return;
        }
      }
      
      if (scaffoldMessenger == null) {
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
          margin: snackBarMargin, // Position above FAB and bottom navigation
          action: SnackBarAction(
            label: 'DISMISS',
            textColor: ThemeColors.snackBarActionColor(context),
            onPressed: () {
              scaffoldMessenger.hideCurrentSnackBar();
            },
          ),
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
        // Context is deactivated, try scaffoldMessengerKey as fallback
        if (scaffoldMessengerKey.currentState != null) {
          scaffoldMessenger = scaffoldMessengerKey.currentState;
        } else {
          // Fallback to global method
          showInfo(message, duration: duration);
          return;
        }
      }
      
      if (scaffoldMessenger == null) {
        showInfo(message, duration: duration);
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
          backgroundColor: ThemeColors.snackBarBackground(context),
          duration: duration ?? defaultDuration,
          behavior: SnackBarBehavior.floating,
          margin: snackBarMargin, // Position above FAB and bottom navigation
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
        // Context is deactivated, try scaffoldMessengerKey as fallback
        if (scaffoldMessengerKey.currentState != null) {
          scaffoldMessenger = scaffoldMessengerKey.currentState;
        } else {
          // Fallback to global method
          showUndo(message: message, onUndo: onUndo, duration: duration);
          return;
        }
      }
      
      if (scaffoldMessenger == null) {
        showUndo(message: message, onUndo: onUndo, duration: duration);
        return;
      }
      final actualDuration = duration ?? undoDuration;
      
      // Dismiss any existing toast before showing new one
      scaffoldMessenger.hideCurrentSnackBar();
      
      // Cancel any existing timer for this scaffoldMessenger
      _activeTimers[scaffoldMessenger]?.cancel();
      _activeTimers.remove(scaffoldMessenger);
      
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: TextStyle(
              color: ThemeColors.snackBarTextColor(context),
            ),
          ),
          backgroundColor: ThemeColors.snackBarBackground(context),
          duration: actualDuration, // Use actual duration - Flutter will handle auto-dismiss
          behavior: SnackBarBehavior.floating,
          margin: snackBarMargin, // Position above FAB and bottom navigation
          action: SnackBarAction(
            label: 'UNDO',
            textColor: ThemeColors.snackBarActionColor(context),
            onPressed: () {
              _activeTimers[scaffoldMessenger!]?.cancel();
              _activeTimers.remove(scaffoldMessenger);
              scaffoldMessenger.hideCurrentSnackBar();
              onUndo();
            },
          ),
        ),
      );
      
      // Set up a backup timer to ensure dismissal even if Flutter's auto-dismiss fails
      // This is a safety net for snack bars with actions
      _activeTimers[scaffoldMessenger] = Timer(actualDuration + const Duration(milliseconds: 500), () {
        try {
          if (scaffoldMessenger != null && _activeTimers.containsKey(scaffoldMessenger)) {
            scaffoldMessenger.hideCurrentSnackBar();
            _activeTimers.remove(scaffoldMessenger);
          }
        } catch (e) {
          // SnackBar might already be dismissed, that's fine
          if (scaffoldMessenger != null) {
            _activeTimers.remove(scaffoldMessenger);
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
        // Context is deactivated, try scaffoldMessengerKey as fallback
        if (scaffoldMessengerKey.currentState != null) {
          scaffoldMessenger = scaffoldMessengerKey.currentState;
        } else {
          // Fallback to global method
          showUndoWithErrorHandling(
            message: message,
            onUndo: onUndo,
            successMessage: successMessage,
            errorMessage: errorMessage,
            duration: duration,
          );
          return;
        }
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
      final actualDuration = duration ?? undoDuration;
      
      // Dismiss any existing toast before showing new one
      scaffoldMessenger.hideCurrentSnackBar();
      
      // Cancel any existing timer for this scaffoldMessenger
      _activeTimers[scaffoldMessenger]?.cancel();
      _activeTimers.remove(scaffoldMessenger);
      
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: TextStyle(
              color: ThemeColors.snackBarTextColor(context),
            ),
          ),
          backgroundColor: ThemeColors.snackBarBackground(context),
          duration: actualDuration, // Use actual duration - Flutter will handle auto-dismiss
          behavior: SnackBarBehavior.floating,
          margin: snackBarMargin, // Position above FAB and bottom navigation
          action: SnackBarAction(
            label: 'UNDO',
            textColor: ThemeColors.snackBarActionColor(context),
            onPressed: () async {
              _activeTimers[scaffoldMessenger!]?.cancel();
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
      
      // Set up a backup timer to ensure dismissal even if Flutter's auto-dismiss fails
      // This is a safety net for snack bars with actions
      _activeTimers[scaffoldMessenger] = Timer(actualDuration + const Duration(milliseconds: 500), () {
        try {
          if (scaffoldMessenger != null && _activeTimers.containsKey(scaffoldMessenger)) {
            scaffoldMessenger.hideCurrentSnackBar();
            _activeTimers.remove(scaffoldMessenger);
          }
        } catch (e) {
          // SnackBar might already be dismissed, that's fine
          if (scaffoldMessenger != null) {
            _activeTimers.remove(scaffoldMessenger);
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