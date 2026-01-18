import 'package:flutter/material.dart';

/// Modern color palette following Material Design 3 guidelines
/// Supports both light and dark modes with proper contrast ratios
class AppColors {
  AppColors._(); // Private constructor to prevent instantiation

  // Light Mode Colors - Kaleem.dev Inspired Theme
  static const Color lightPrimary = Color(0xFFE65F1E); // Deep orange/red - Kaleem accent
  static const Color lightPrimaryDark = Color(0xFFD35400); // Darker orange - Rich accent
  static const Color lightSecondary = Color(0xFFF97316); // Orange 500 - Secondary accent
  static const Color lightSecondaryDark = Color(0xFFEA580C); // Orange 600
  static const Color lightTertiary = Color(0xFFF59E0B); // Amber 500 - Tertiary
  static const Color lightTertiaryDark = Color(0xFFD97706); // Amber 600
  static const Color lightError = Color(0xFFDC2626); // Red 600
  static const Color lightSuccess = Color(0xFF16A34A); // Green 600
  static const Color lightWarning = Color(0xFFF59E0B); // Amber 500
  static const Color lightBackground = Color(0xFFFAFAFA); // Clean off-white - Kaleem style
  static const Color lightSurface = Color(0xFFFFFFFF); // Pure white
  static const Color lightSurfaceVariant = Color(0xFFF5F5F5); // Light gray variant
  static const Color lightOnPrimary = Color(0xFFFFFFFF); // White
  static const Color lightOnSecondary = Color(0xFFFFFFFF); // White
  static const Color lightOnSurface = Color(0xFF2B2B2B); // Dark charcoal - Kaleem text
  static const Color lightOnBackground = Color(0xFF2B2B2B); // Dark charcoal

  // Dark Mode Colors - Kaleem.dev Inspired Theme
  static const Color darkPrimary = Color(0xFFFF8147); // Lighter orange - Better contrast on dark
  static const Color darkPrimaryLight = Color(0xFFFF9D6B); // Light orange - Highlight
  static const Color darkSecondary = Color(0xFFF28C38); // Orange - Secondary accent
  static const Color darkSecondaryLight = Color(0xFFFFA366); // Light orange
  static const Color darkTertiary = Color(0xFFFBBF24); // Amber 400 - Tertiary
  static const Color darkTertiaryLight = Color(0xFFFCD34D); // Amber 300
  static const Color darkError = Color(0xFFF87171); // Red 400
  static const Color darkSuccess = Color(0xFF4ADE80); // Green 400
  static const Color darkWarning = Color(0xFFFBBF24); // Amber 400
  static const Color darkBackground = Color(0xFF0F0F0F); // Near-black - Kaleem dark mode
  static const Color darkSurface = Color(0xFF1C1C1C); // Dark gray - Kaleem surface
  static const Color darkSurfaceVariant = Color(0xFF2A2A2A); // Medium dark gray
  static const Color darkOnPrimary = Color(0xFF0F0F0F); // Near-black
  static const Color darkOnSecondary = Color(0xFF0F0F0F); // Near-black
  static const Color darkOnSurface = Color(0xFFEFEFEF); // Light gray/white - Kaleem text
  static const Color darkOnBackground = Color(0xFFEFEFEF); // Light gray/white

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
