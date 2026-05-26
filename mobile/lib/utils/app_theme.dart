import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'custom_app_colors_extension.dart';

/// Material Design 3 theme configuration using built-in palettes
class AppTheme {
  AppTheme._(); // Private constructor to prevent instantiation

  /// Shared semantic colors for both themes (give/received, success, warning)
  static CustomAppColorsExtension get _appColorsExtension => const CustomAppColorsExtension(
        success: AppColors.lightSuccess,
        warning: AppColors.lightWarning,
        lightGive: AppColors.lightGive,
        lightReceived: AppColors.lightReceived,
        darkGive: AppColors.darkGive,
        darkReceived: AppColors.darkReceived,
      );

  /// Light theme configuration - Material Design 3 purple palette
  /// Softer surface/background so the app is not over-bright; direction green/red match dark.
  static ThemeData get lightTheme {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6B46C1), // Purple 700
      brightness: Brightness.light,
    );
    // Softer off-white so it's not pure white; keeps primary and onSurface from seed
    final colorScheme = baseScheme.copyWith(
      surface: const Color(0xFFF3EFF8),
      background: const Color(0xFFF3EFF8),
      surfaceContainerLow: const Color(0xFFEDE9F2),
      surfaceContainer: const Color(0xFFE7E3EC),
      surfaceContainerHigh: const Color(0xFFE1DDE6),
      surfaceContainerHighest: const Color(0xFFDBD7E0),
    );
    final typography = Typography.material2021(colorScheme: colorScheme);
    final textTheme = GoogleFonts.tajawalTextTheme(typography.black);
    final primaryTextTheme = GoogleFonts.tajawalTextTheme(typography.white);

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.transparent,
      textTheme: textTheme,
      primaryTextTheme: primaryTextTheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: colorScheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface.withOpacity(0.95),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.6),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant, fontFamily: GoogleFonts.tajawal().fontFamily),
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withOpacity(0.7), fontFamily: GoogleFonts.tajawal().fontFamily),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withOpacity(0.6),
        thickness: 1,
        space: 1,
      ),
      extensions: [_appColorsExtension],
    );
  }

  /// Dark theme configuration - Material Design 3 purple palette
  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFA78BFA), // Purple 400 (lighter for dark mode)
      brightness: Brightness.dark,
    );
    final typography = Typography.material2021(colorScheme: colorScheme);
    final textTheme = GoogleFonts.tajawalTextTheme(typography.white);
    final primaryTextTheme = GoogleFonts.tajawalTextTheme(typography.black);

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.transparent,
      textTheme: textTheme,
      primaryTextTheme: primaryTextTheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: colorScheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerHigh.withOpacity(0.9),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.5),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant, fontFamily: GoogleFonts.tajawal().fontFamily),
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withOpacity(0.7), fontFamily: GoogleFonts.tajawal().fontFamily),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withOpacity(0.5),
        thickness: 1,
        space: 1,
      ),
      extensions: [_appColorsExtension],
    );
  }
}
