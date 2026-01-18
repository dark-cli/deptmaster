import 'package:flutter/material.dart';

/// Modern color palette following Material Design 3 guidelines
/// Supports both light and dark modes with proper contrast ratios
class AppColors {
  AppColors._(); // Private constructor to prevent instantiation

  // Light Mode Colors
  static const Color lightPrimary = Color(0xFF4F46E5); // Indigo 600
  static const Color lightPrimaryDark = Color(0xFF4338CA); // Indigo 700
  static const Color lightSecondary = Color(0xFF14B8A6); // Teal 500
  static const Color lightSecondaryDark = Color(0xFF0D9488); // Teal 600
  static const Color lightTertiary = Color(0xFFF59E0B); // Amber 500
  static const Color lightTertiaryDark = Color(0xFFD97706); // Amber 600
  static const Color lightError = Color(0xFFDC2626); // Red 600
  static const Color lightSuccess = Color(0xFF16A34A); // Green 600
  static const Color lightWarning = Color(0xFFF97316); // Orange 500
  static const Color lightBackground = Color(0xFFF9FAFB); // Gray 50
  static const Color lightSurface = Color(0xFFFFFFFF); // White
  static const Color lightSurfaceVariant = Color(0xFFF3F4F6); // Gray 100
  static const Color lightOnPrimary = Color(0xFFFFFFFF); // White
  static const Color lightOnSecondary = Color(0xFFFFFFFF); // White
  static const Color lightOnSurface = Color(0xFF111827); // Gray 900
  static const Color lightOnBackground = Color(0xFF111827); // Gray 900

  // Dark Mode Colors
  static const Color darkPrimary = Color(0xFF818CF8); // Indigo 400
  static const Color darkPrimaryLight = Color(0xFFA5B4FC); // Indigo 300
  static const Color darkSecondary = Color(0xFF2DD4BF); // Teal 400
  static const Color darkSecondaryLight = Color(0xFF5EEAD4); // Teal 300
  static const Color darkTertiary = Color(0xFFFBBF24); // Amber 400
  static const Color darkTertiaryLight = Color(0xFFFCD34D); // Amber 300
  static const Color darkError = Color(0xFFF87171); // Red 400
  static const Color darkSuccess = Color(0xFF4ADE80); // Green 400
  static const Color darkWarning = Color(0xFFFB923C); // Orange 400
  static const Color darkBackground = Color(0xFF111827); // Gray 900
  static const Color darkSurface = Color(0xFF1F2937); // Gray 800
  static const Color darkSurfaceVariant = Color(0xFF374151); // Gray 700
  static const Color darkOnPrimary = Color(0xFF111827); // Gray 900
  static const Color darkOnSecondary = Color(0xFF111827); // Gray 900
  static const Color darkOnSurface = Color(0xFFF9FAFB); // Gray 50
  static const Color darkOnBackground = Color(0xFFF9FAFB); // Gray 50

  // Semantic Colors (Balance) - Respects flipColors setting
  // These will be used with Consumer to watch flipColorsProvider
  static Color getBalanceColor(bool isPositive, bool flipColors, bool isDark) {
    if (isPositive) {
      return flipColors
          ? (isDark ? darkError : lightError)
          : (isDark ? darkSuccess : lightSuccess);
    } else {
      return flipColors
          ? (isDark ? darkSuccess : lightSuccess)
          : (isDark ? darkError : lightError);
    }
  }

  // Legacy support (deprecated - use theme colors instead)
  @Deprecated('Use Theme.of(context).colorScheme.primary instead')
  static const primary = lightPrimary;
  
  @Deprecated('Use Theme.of(context).colorScheme.secondary instead')
  static const secondary = lightSecondary;
  
  @Deprecated('Use Theme.of(context).colorScheme.error instead')
  static const error = lightError;
  
  @Deprecated('Use Theme.of(context).colorScheme.primaryContainer for success')
  static const success = lightSuccess;
  
  @Deprecated('Use Theme.of(context).colorScheme.tertiary for warning')
  static const warning = lightWarning;
}
