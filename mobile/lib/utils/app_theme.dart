import 'package:flutter/material.dart';

/// Material Design 3 theme configuration using built-in palettes
class AppTheme {
  AppTheme._(); // Private constructor to prevent instantiation

  /// Light theme configuration - Material Design 3 with purple palette
  /// Using purple seed color for a softer, less bright appearance
  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6B46C1), // Purple 700 - softer purple
      brightness: Brightness.light,
    );
    
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      // Use softer surface colors for less brightness
      scaffoldBackgroundColor: Colors.transparent, // Let gradient show through
      // Card theme with slightly different background for better visibility
      cardTheme: CardThemeData(
        color: colorScheme.surface.withOpacity(0.95), // More neutral, closer to white/light
        elevation: 0, // No shadow for flat design
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  /// Dark theme configuration - Material Design 3 with purple palette
  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFA78BFA), // Purple 400 - lighter for dark mode
      brightness: Brightness.dark,
    );
    
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.transparent, // Let gradient show through
      // Card theme with slightly different background for better visibility
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerHigh.withOpacity(0.9), // Lighter surface for dark mode
        elevation: 0, // No shadow for flat design
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
