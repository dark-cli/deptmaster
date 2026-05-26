import 'package:flutter/material.dart';

/// Modern color palette following Material Design 3 guidelines
/// Supports both light and dark modes with proper contrast ratios
class AppColors {
  AppColors._(); // Private constructor to prevent instantiation

  // Light Mode Colors - Material Design 3 Defaults
  // Using Material 3 default blue seed color
  static const Color lightPrimary = Color(0xFF6750A4); // Material 3 default primary
  static const Color lightPrimaryDark = Color(0xFF4F378B); // Darker primary
  static const Color lightSecondary = Color(0xFF625B71); // Material 3 default secondary
  static const Color lightSecondaryDark = Color(0xFF4A4458); // Darker secondary
  static const Color lightTertiary = Color(0xFF7D5260); // Material 3 default tertiary
  static const Color lightTertiaryDark = Color(0xFF633B48); // Darker tertiary
  static const Color lightError = Color(0xFFBA1A1A); // Material 3 default error
  static const Color lightSuccess = Color(0xFF029C76); // Custom green
  static const Color lightWarning = Color(0xFFF59E0B); // Amber 500
  static const Color lightBackground = Color(0xFFFFFBFE); // Material 3 default background
  static const Color lightBackgroundEnd = Color(0xFFFFFBFE); // Same for no gradient
  static const Color lightSurface = Color(0xFFFFFBFE); // Material 3 default surface
  static const Color lightSurfaceVariant = Color(0xFFE7E0EC); // Material 3 surface variant
  static const Color lightOnPrimary = Color(0xFFFFFFFF); // White
  static const Color lightOnSecondary = Color(0xFFFFFFFF); // White
  static const Color lightOnSurface = Color(0xFF1C1B1F); // Material 3 on surface
  static const Color lightOnBackground = Color(0xFF1C1B1F); // Material 3 on background
  static const Color lightGray = Color(0xFF79747E); // Material 3 outline
  static const Color lightGrayLight = Color(0xFFE7E0EC); // Surface variant
  static const Color lightGrayDark = Color(0xFF49454F); // On surface variant

  // Dark Mode Colors - Material Design 3 Defaults
  static const Color darkPrimary = Color(0xFFD0BCFF); // Material 3 default primary (light)
  static const Color darkPrimaryLight = Color(0xFFEADDFF); // Lighter primary
  static const Color darkPrimaryDark = Color(0xFFB69DF8); // Darker primary
  static const Color darkSecondary = Color(0xFFCCC2DC); // Material 3 default secondary
  static const Color darkSecondaryLight = Color(0xFFE8DEF8); // Lighter secondary
  static const Color darkSecondaryDark = Color(0xFFB0A6C0); // Darker secondary
  static const Color darkTertiary = Color(0xFFEFB8C8); // Material 3 default tertiary
  static const Color darkTertiaryLight = Color(0xFFF2D8E4); // Lighter tertiary
  static const Color darkError = Color(0xFFFFB4AB); // Material 3 default error
  static const Color darkSuccess = Color(0xFF029C76); // Custom green
  static const Color darkWarning = Color(0xFFFBBF24); // Amber 400
  static const Color darkBackground = Color(0xFF1C1B1F); // Material 3 default background
  static const Color darkBackgroundEnd = Color(0xFF1C1B1F); // Same for no gradient
  static const Color darkSurface = Color(0xFF1C1B1F); // Material 3 default surface
  static const Color darkSurfaceVariant = Color(0xFF49454F); // Material 3 surface variant
  static const Color darkOnPrimary = Color(0xFF381E72); // Material 3 on primary
  static const Color darkOnSecondary = Color(0xFF332D41); // Material 3 on secondary
  static const Color darkOnSurface = Color(0xFFE6E1E5); // Material 3 on surface
  static const Color darkOnBackground = Color(0xFFE6E1E5); // Material 3 on background
  static const Color darkGray = Color(0xFF938F99); // Material 3 outline
  static const Color darkGrayLight = Color(0xFF49454F); // Surface variant
  static const Color darkGrayDark = Color(0xFFCAC4D0); // On surface variant

  // Semantic Colors for Give/Received - same green/red feel in both themes for directions
  // Standardized: Received = red (negative), Gave = green (positive)
  // Light: same green as dark; clear red so directions match dark theme visibility
  static const Color lightGive = Color(0xFF029C76);   // Same green as dark
  static const Color lightReceived = Color(0xFFC62828); // Strong red for directions (matches dark feel)
  // Dark: green and light red for contrast on dark background
  static const Color darkGive = Color(0xFF029C76);
  static const Color darkReceived = Color(0xFFFFB4AB);
  
  // Semantic Colors (Balance) - Respects flipColors setting
  // These will be used with Consumer to watch flipColorsProvider
  static Color getBalanceColor(bool isPositive, bool flipColors, bool isDark) {
    if (isPositive) {
      return flipColors
          ? (isDark ? darkReceived : lightReceived)
          : (isDark ? darkGive : lightGive);
    } else {
      return flipColors
          ? (isDark ? darkGive : lightGive)
          : (isDark ? darkReceived : lightReceived);
    }
  }
  
  // Get Gave color (positive, green) - maps to TransactionDirection.lent
  static Color getGiveColor(bool flipColors, bool isDark) {
    // When flipColors is true, swap the colors
    if (flipColors) {
      return isDark ? darkReceived : lightReceived; // Swapped to red
    }
    return isDark ? darkGive : lightGive; // Default: green
  }
  
  // Get Received color (negative, red) - maps to TransactionDirection.owed
  static Color getReceivedColor(bool flipColors, bool isDark) {
    // When flipColors is true, swap the colors
    if (flipColors) {
      return isDark ? darkGive : lightGive; // Swapped to green
    }
    return isDark ? darkReceived : lightReceived; // Default: red
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
