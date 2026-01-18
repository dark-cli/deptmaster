import 'package:flutter/material.dart';

/// Material Design 3 theme configuration using defaults
class AppTheme {
  AppTheme._(); // Private constructor to prevent instantiation

  /// Light theme configuration - Material Design 3 defaults
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.light,
      ),
    );
  }

  /// Dark theme configuration - Material Design 3 defaults
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      ),
    );
  }
}
