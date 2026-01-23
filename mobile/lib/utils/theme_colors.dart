import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Helper class to get theme-consistent colors
/// Use this instead of hard-coded Colors.red, Colors.green, etc.
class ThemeColors {
  ThemeColors._();

  /// Get error color from theme
  static Color error(BuildContext context) {
    return Theme.of(context).colorScheme.error;
  }

  /// Get success color from theme
  static Color success(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? AppColors.darkSuccess : AppColors.lightSuccess;
  }

  /// Get warning color from theme
  static Color warning(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? AppColors.darkWarning : AppColors.lightWarning;
  }

  /// Get gray color from theme
  static Color gray(BuildContext context, {int shade = 600}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      switch (shade) {
        case 400:
          return AppColors.darkGray;
        case 500:
          return AppColors.darkGray;
        case 600:
          return AppColors.darkGray;
        default:
          return AppColors.darkGray;
      }
    } else {
      switch (shade) {
        case 400:
          return AppColors.lightGray;
        case 500:
          return AppColors.lightGray;
        case 600:
          return AppColors.lightGrayDark;
        default:
          return AppColors.lightGray;
      }
    }
  }

  /// Get surface color from theme
  static Color surface(BuildContext context) {
    return Theme.of(context).colorScheme.surface;
  }

  /// Get onSurface color from theme
  static Color onSurface(BuildContext context) {
    return Theme.of(context).colorScheme.onSurface;
  }

  /// Get primary color from theme
  static Color primary(BuildContext context) {
    return Theme.of(context).colorScheme.primary;
  }

  /// Get background color from theme
  static Color background(BuildContext context) {
    return Theme.of(context).colorScheme.background;
  }

  /// Get SnackBar background color from theme
  static Color snackBarBackground(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark 
        ? const Color(0xFF323232) // Dark surface for dark mode
        : const Color(0xFF323232); // Dark surface for light mode (standard Material)
  }

  /// Get SnackBar text color from theme
  static Color snackBarTextColor(BuildContext context) {
    return Colors.white; // Always white for good contrast on dark SnackBar
  }

  /// Get accent color for SnackBar actions (UNDO button)
  static Color snackBarActionColor(BuildContext context) {
    return Theme.of(context).colorScheme.primary; // Use primary/accent color
  }

  /// Get SnackBar error background color from theme
  static Color snackBarErrorBackground(BuildContext context) {
    return Theme.of(context).colorScheme.error;
  }

  /// Get SnackBar success background color from theme
  static Color snackBarSuccessBackground(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? AppColors.darkSuccess : AppColors.lightSuccess;
  }
}
