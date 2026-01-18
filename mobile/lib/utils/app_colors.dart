import 'package:flutter/material.dart';

/// Modern color palette following Material Design 3 guidelines
/// Supports both light and dark modes with proper contrast ratios
class AppColors {
  AppColors._(); // Private constructor to prevent instantiation

  // Light Mode Colors - Exact Kaleem.dev Palette
  static const Color lightPrimary = Color(0xFF964A4A); // Reddish-brown accent
  static const Color lightPrimaryDark = Color(0xFF7A3B3B); // Darker reddish-brown
  static const Color lightSecondary = Color(0xFF964A4A); // Same as accent
  static const Color lightSecondaryDark = Color(0xFF7A3B3B); // Darker variant
  static const Color lightTertiary = Color(0xFF964A4A); // Accent color
  static const Color lightTertiaryDark = Color(0xFF7A3B3B); // Darker accent
  static const Color lightError = Color(0xFFDC2626); // Red 600
  static const Color lightSuccess = Color(0xFF16A34A); // Green 600
  static const Color lightWarning = Color(0xFFF59E0B); // Amber 500
  // Background: Gradient from #F5E7DE → #F2BFA4 (beige to peach)
  static const Color lightBackground = Color(0xFFF5E7DE); // Beige/cream - start of gradient
  static const Color lightBackgroundEnd = Color(0xFFF2BFA4); // Peach - end of gradient
  static const Color lightSurface = Color(0xFFFFFFFF); // White header background
  static const Color lightSurfaceVariant = Color(0xFFF5F5F5); // Very light gray
  static const Color lightOnPrimary = Color(0xFFFFFFFF); // White
  static const Color lightOnSecondary = Color(0xFFFFFFFF); // White
  static const Color lightOnSurface = Color(0xFF34495E); // Dark blue-gray - header text
  static const Color lightOnBackground = Color(0xFF34495E); // Dark blue-gray - black
  static const Color lightGray = Color(0xFFDCDCDC); // Light gray (220, 220, 220)
  static const Color lightGrayLight = Color(0xFFF5F5F5); // Very light gray (245, 245, 245)
  static const Color lightGrayDark = Color(0xFF212529); // Dark gray (33, 37, 41)

  // Dark Mode Colors - Exact Kaleem.dev Palette
  static const Color darkPrimary = Color(0xFF4CAF50); // Green accent
  static const Color darkPrimaryLight = Color(0xFF66BB6A); // Lighter green
  static const Color darkPrimaryDark = Color(0xFF388E3C); // Darker green
  static const Color darkSecondary = Color(0xFF4CAF50); // Same as accent
  static const Color darkSecondaryLight = Color(0xFF66BB6A); // Lighter green
  static const Color darkSecondaryDark = Color(0xFF388E3C); // Darker variant
  static const Color darkTertiary = Color(0xFF4CAF50); // Accent color
  static const Color darkTertiaryLight = Color(0xFF66BB6A); // Lighter green
  static const Color darkError = Color(0xFFF87171); // Red 400
  static const Color darkSuccess = Color(0xFF4CAF50); // Green accent
  static const Color darkWarning = Color(0xFFFBBF24); // Amber 400
  // Background: Gradient from #1E221E → #151815 (dark green-black gradient)
  static const Color darkBackground = Color(0xFF1E221E); // Dark green-black - start of gradient
  static const Color darkBackgroundEnd = Color(0xFF151815); // Very dark green-black - end of gradient
  static const Color darkSurface = Color(0xFF151815); // Very dark green-black - header background
  static const Color darkSurfaceVariant = Color(0xFF3E463E); // Dark green-gray
  static const Color darkOnPrimary = Color(0xFFFFFFFF); // White
  static const Color darkOnSecondary = Color(0xFFFFFFFF); // White
  static const Color darkOnSurface = Color(0xFFF0FFF0); // Light green-tinted white - header text
  static const Color darkOnBackground = Color(0xFFF0FFF0); // Light green-tinted white - black
  static const Color darkGray = Color(0xFF3C463C); // Dark green-gray (60, 70, 60)
  static const Color darkGrayLight = Color(0xFF1E231E); // Very dark green-gray (30, 35, 30)
  static const Color darkGrayDark = Color(0xFFF0FFF0); // Light green-tinted white (240, 255, 240)

  // Semantic Colors for Give/Received - Fits Kaleem.dev theme
  // Light Mode: Give = reddish-brown (accent), Received = warm teal
  static const Color lightGive = Color(0xFF964A4A); // Reddish-brown - matches accent
  static const Color lightReceived = Color(0xFF0D9488); // Warm teal - complements beige background
  
  // Dark Mode: Give = green (accent), Received = warm amber
  static const Color darkGive = Color(0xFF4CAF50); // Green - matches accent
  static const Color darkReceived = Color(0xFFF59E0B); // Warm amber - complements dark green
  
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
  
  // Get Give color (money going out)
  static Color getGiveColor(bool flipColors, bool isDark) {
    return flipColors
        ? (isDark ? darkReceived : lightReceived)
        : (isDark ? darkGive : lightGive);
  }
  
  // Get Received color (money coming in)
  static Color getReceivedColor(bool flipColors, bool isDark) {
    return flipColors
        ? (isDark ? darkGive : lightGive)
        : (isDark ? darkReceived : lightReceived);
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
