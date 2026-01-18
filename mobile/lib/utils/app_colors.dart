import 'package:flutter/material.dart';

/// Modern color palette following Material Design 3 guidelines
/// Supports both light and dark modes with proper contrast ratios
class AppColors {
  AppColors._(); // Private constructor to prevent instantiation

  // Light Mode Colors - Warm Sunset Orange Theme
  static const Color lightPrimary = Color(0xFFEA580C); // Orange 600 - Warm, inviting
  static const Color lightPrimaryDark = Color(0xFFC2410C); // Orange 700 - Rich orange
  static const Color lightSecondary = Color(0xFFF59E0B); // Amber 500 - Golden warmth
  static const Color lightSecondaryDark = Color(0xFFD97706); // Amber 600 - Deep gold
  static const Color lightTertiary = Color(0xFFF97316); // Orange 500 - Vibrant orange
  static const Color lightTertiaryDark = Color(0xFFEA580C); // Orange 600
  static const Color lightError = Color(0xFFDC2626); // Red 600
  static const Color lightSuccess = Color(0xFF16A34A); // Green 600
  static const Color lightWarning = Color(0xFFF59E0B); // Amber 500
  static const Color lightBackground = Color(0xFFFFFBF7); // Warm cream - Soft, inviting
  static const Color lightSurface = Color(0xFFFFFFFF); // White
  static const Color lightSurfaceVariant = Color(0xFFFFF5ED); // Warm beige - Soft surface
  static const Color lightOnPrimary = Color(0xFFFFFFFF); // White
  static const Color lightOnSecondary = Color(0xFFFFFFFF); // White
  static const Color lightOnSurface = Color(0xFF1C1917); // Warm dark - Brown-tinted for better contrast
  static const Color lightOnBackground = Color(0xFF1C1917); // Warm dark

  // Dark Mode Colors - Warm Sunset Orange Theme
  static const Color darkPrimary = Color(0xFFFB923C); // Orange 400 - Soft orange glow
  static const Color darkPrimaryLight = Color(0xFFFDBA74); // Orange 300 - Light orange
  static const Color darkSecondary = Color(0xFFFBBF24); // Amber 400 - Golden
  static const Color darkSecondaryLight = Color(0xFFFCD34D); // Amber 300 - Light gold
  static const Color darkTertiary = Color(0xFFF97316); // Orange 500 - Vibrant
  static const Color darkTertiaryLight = Color(0xFFFB923C); // Orange 400
  static const Color darkError = Color(0xFFF87171); // Red 400
  static const Color darkSuccess = Color(0xFF4ADE80); // Green 400
  static const Color darkWarning = Color(0xFFFBBF24); // Amber 400
  static const Color darkBackground = Color(0xFF1C1917); // Warm dark - Brown-tinted dark
  static const Color darkSurface = Color(0xFF2D2819); // Warm gray - Brown-gray surface
  static const Color darkSurfaceVariant = Color(0xFF3D3525); // Warm gray variant
  static const Color darkOnPrimary = Color(0xFF1C1917); // Warm dark
  static const Color darkOnSecondary = Color(0xFF1C1917); // Warm dark
  static const Color darkOnSurface = Color(0xFFFEF3C7); // Warm light - Cream for contrast
  static const Color darkOnBackground = Color(0xFFFEF3C7); // Warm light

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
