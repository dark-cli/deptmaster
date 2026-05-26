import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'custom_app_colors_extension.dart';

/// Helper class to get theme-consistent colors from Theme and CustomAppColorsExtension.
/// Prefer these over hard-coded AppColors.lightX/darkX so theming stays in one place.
class ThemeColors {
  ThemeColors._();

  static ColorScheme _scheme(BuildContext context) => Theme.of(context).colorScheme;
  static bool _isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;
  static CustomAppColorsExtension? _extension(BuildContext context) =>
      Theme.of(context).extension<CustomAppColorsExtension>();

  /// Error color from theme
  static Color error(BuildContext context) => _scheme(context).error;

  /// Success color (from extension or AppColors fallback)
  static Color success(BuildContext context) {
    final ext = _extension(context);
    if (ext?.success != null) return ext!.success!;
    return _isDark(context) ? AppColors.darkSuccess : AppColors.lightSuccess;
  }

  /// Warning color (from extension or AppColors fallback)
  static Color warning(BuildContext context) {
    final ext = _extension(context);
    if (ext?.warning != null) return ext!.warning!;
    return _isDark(context) ? AppColors.darkWarning : AppColors.lightWarning;
  }

  /// Give (positive/lent) color. Pass [flipColors] from settings to swap with received.
  static Color give(BuildContext context, {bool flipColors = false}) {
    if (flipColors) return received(context, flipColors: false);
    final ext = _extension(context);
    final isDark = _isDark(context);
    if (ext != null) return isDark ? (ext.darkGive ?? AppColors.darkGive) : (ext.lightGive ?? AppColors.lightGive);
    return isDark ? AppColors.darkGive : AppColors.lightGive;
  }

  /// Received (negative/owed) color. Pass [flipColors] from settings to swap with give.
  static Color received(BuildContext context, {bool flipColors = false}) {
    if (flipColors) return give(context, flipColors: false);
    final ext = _extension(context);
    final isDark = _isDark(context);
    if (ext != null) return isDark ? (ext.darkReceived ?? AppColors.darkReceived) : (ext.lightReceived ?? AppColors.lightReceived);
    return isDark ? AppColors.darkReceived : AppColors.lightReceived;
  }

  /// Surface variant (cards, chips) from theme
  static Color surfaceVariant(BuildContext context) => _scheme(context).surfaceContainerHigh;

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

  /// Surface color from theme
  static Color surface(BuildContext context) => _scheme(context).surface;

  /// On-surface text/icon color
  static Color onSurface(BuildContext context) => _scheme(context).onSurface;

  /// Primary brand color
  static Color primary(BuildContext context) => _scheme(context).primary;

  /// On-primary text/icon color (e.g. for FAB, primary buttons)
  static Color onPrimary(BuildContext context) => _scheme(context).onPrimary;

  /// Background color from theme
  static Color background(BuildContext context) => _scheme(context).background;

  /// SnackBar background (elevated surface)
  static Color snackBarBackground(BuildContext context) => _scheme(context).surfaceContainerHighest;

  static Color snackBarTextColor(BuildContext context) => _scheme(context).onSurface;
  static Color snackBarActionColor(BuildContext context) => _scheme(context).primary;
  static Color snackBarErrorBackground(BuildContext context) => _scheme(context).errorContainer;
  static Color snackBarErrorTextColor(BuildContext context) => _scheme(context).onErrorContainer;
  static Color snackBarSuccessBackground(BuildContext context) => success(context);
}
