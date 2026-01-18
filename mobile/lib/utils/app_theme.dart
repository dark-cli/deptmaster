import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_shapes.dart';

/// Complete Material Design 3 theme configuration
/// Follows academic design standards and WCAG accessibility guidelines
class AppTheme {
  AppTheme._(); // Private constructor to prevent instantiation

  /// Light theme configuration
  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.light(
      // Primary colors
      primary: AppColors.lightPrimary,
      onPrimary: AppColors.lightOnPrimary,
      primaryContainer: AppColors.lightPrimaryDark,
      onPrimaryContainer: AppColors.lightOnPrimary,
      
      // Secondary colors
      secondary: AppColors.lightSecondary,
      onSecondary: AppColors.lightOnSecondary,
      secondaryContainer: AppColors.lightSecondaryDark,
      onSecondaryContainer: AppColors.lightOnSecondary,
      
      // Tertiary colors
      tertiary: AppColors.lightTertiary,
      onTertiary: AppColors.lightOnPrimary,
      tertiaryContainer: AppColors.lightTertiaryDark,
      onTertiaryContainer: AppColors.lightOnPrimary,
      
      // Error colors
      error: AppColors.lightError,
      onError: AppColors.lightOnPrimary,
      errorContainer: AppColors.lightError,
      onErrorContainer: AppColors.lightOnPrimary,
      
      // Surface colors
      surface: AppColors.lightSurface,
      onSurface: AppColors.lightOnSurface,
      surfaceVariant: AppColors.lightSurfaceVariant,
      onSurfaceVariant: AppColors.lightOnSurface,
      
      // Background colors
      background: AppColors.lightBackground,
      onBackground: AppColors.lightOnBackground,
      
      // Outline colors
      outline: Colors.grey.shade400,
      outlineVariant: Colors.grey.shade300,
      
      // Shadow
      shadow: Colors.black.withOpacity(0.1),
      scrim: Colors.black.withOpacity(0.5),
      
      // Inverse colors
      inverseSurface: AppColors.darkSurface,
      onInverseSurface: AppColors.darkOnSurface,
      inversePrimary: AppColors.darkPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: Brightness.light,
      
      // Typography with Tajawal font (Kaleem.dev)
      textTheme: _buildTextTheme(GoogleFonts.tajawalTextTheme(), false),
      
      // AppBar theme - Semi-transparent peach with shadow (Kaleem.dev)
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.tajawal(
          fontSize: 22, // Nav links: 1.375rem (22px)
          fontWeight: FontWeight.w700, // Bold
          color: AppColors.lightOnSurface,
        ),
        iconTheme: IconThemeData(
          color: AppColors.lightOnSurface,
          size: 24,
        ),
        backgroundColor: AppColors.lightBackgroundEnd.withOpacity(0.8), // Peach with 80% opacity
        foregroundColor: AppColors.lightOnSurface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withOpacity(0.08),
      ),
      
      // Card theme
      cardTheme: CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: AppShapes.cardRadius,
        ),
        margin: EdgeInsets.symmetric(
          horizontal: AppSpacing.screenPadding,
          vertical: AppSpacing.sm,
        ),
      ),
      
      // Button themes
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 1,
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          minimumSize: Size(0, 40),
          shape: RoundedRectangleBorder(
            borderRadius: AppShapes.buttonRadius,
          ),
          textStyle: GoogleFonts.tajawal(
            fontSize: 16, // Body text: 1rem (16px)
            fontWeight: FontWeight.w400, // Regular
          ),
        ).copyWith(
          elevation: MaterialStateProperty.resolveWith<double>(
            (Set<MaterialState> states) {
              if (states.contains(MaterialState.pressed)) return 0;
              return 1;
            },
          ),
        ),
      ),
      
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          minimumSize: Size(0, 40),
          shape: RoundedRectangleBorder(
            borderRadius: AppShapes.buttonRadius,
          ),
          side: BorderSide(width: 1, color: colorScheme.outline),
          textStyle: GoogleFonts.tajawal(
            fontSize: 16, // Body text: 1rem (16px)
            fontWeight: FontWeight.w400, // Regular
          ),
        ),
      ),
      
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          minimumSize: Size(0, 40),
          shape: RoundedRectangleBorder(
            borderRadius: AppShapes.smallRadius,
          ),
          textStyle: GoogleFonts.tajawal(
            fontSize: 16, // Body text: 1rem (16px)
            fontWeight: FontWeight.w400, // Regular
          ),
        ),
      ),
      
      // Floating Action Button theme
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: AppShapes.fabRadius,
        ),
        sizeConstraints: BoxConstraints.tightFor(width: 56, height: 56),
      ),
      
      // Input decoration theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightSurfaceVariant,
        border: OutlineInputBorder(
          borderRadius: AppShapes.textFieldRadius,
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppShapes.textFieldRadius,
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppShapes.textFieldRadius,
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppShapes.textFieldRadius,
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppShapes.textFieldRadius,
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
        contentPadding: EdgeInsets.all(AppSpacing.md),
        labelStyle: GoogleFonts.tajawal(fontSize: 16), // Input: 16px
        helperStyle: GoogleFonts.tajawal(fontSize: 12),
        errorStyle: GoogleFonts.tajawal(fontSize: 12),
      ),
      
      // Chip theme
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: AppShapes.chipRadius,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        labelStyle: GoogleFonts.tajawal(
          fontSize: 12,
          fontWeight: FontWeight.w400, // Regular
        ),
      ),
      
      // Dialog theme
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: AppShapes.dialogRadius,
        ),
        elevation: 3,
        titleTextStyle: GoogleFonts.tajawal(
          fontSize: 22, // Nav links: 1.375rem (22px)
          fontWeight: FontWeight.w700, // Bold
          color: AppColors.lightOnSurface,
        ),
        contentTextStyle: GoogleFonts.inter(
          fontSize: 14,
          color: AppColors.lightOnSurface,
        ),
      ),
      
      // Bottom navigation bar theme
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        elevation: 8,
        backgroundColor: AppColors.lightSurface,
        selectedItemColor: AppColors.lightPrimary,
        unselectedItemColor: Colors.grey.shade600,
        selectedLabelStyle: GoogleFonts.tajawal(
          fontSize: 12,
          fontWeight: FontWeight.w700, // Bold
        ),
        unselectedLabelStyle: GoogleFonts.tajawal(
          fontSize: 12,
          fontWeight: FontWeight.w400, // Regular
        ),
      ),
      
      // Navigation bar theme (Material 3) - Semi-transparent peach (Kaleem.dev)
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: AppColors.lightBackgroundEnd.withOpacity(0.8), // Peach with 80% opacity
        indicatorColor: AppColors.lightSurfaceVariant,
        labelTextStyle: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return GoogleFonts.tajawal(
              fontSize: 12,
              fontWeight: FontWeight.w700, // Bold
              color: AppColors.lightPrimary,
            );
          }
          return GoogleFonts.tajawal(
            fontSize: 12,
            fontWeight: FontWeight.w400, // Regular
            color: Colors.grey.shade600,
          );
        }),
        iconTheme: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return IconThemeData(color: AppColors.lightPrimary, size: 24);
          }
          return IconThemeData(color: Colors.grey.shade600, size: 24);
        }),
      ),
      
      // List tile theme
      listTileTheme: ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        minVerticalPadding: AppSpacing.sm,
        titleTextStyle: GoogleFonts.tajawal(
          fontSize: 16, // Body: 1rem (16px)
          fontWeight: FontWeight.w700, // Bold
        ),
        subtitleTextStyle: GoogleFonts.tajawal(
          fontSize: 14,
          fontWeight: FontWeight.w400, // Regular
        ),
      ),
      
      // Switch theme
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return AppColors.lightPrimary;
          }
          return Colors.grey.shade400;
        }),
        trackColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return AppColors.lightPrimary.withOpacity(0.5);
          }
          return Colors.grey.shade300;
        }),
      ),
    );
  }

  /// Dark theme configuration
  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.dark(
      // Primary colors
      primary: AppColors.darkPrimary,
      onPrimary: AppColors.darkOnPrimary,
      primaryContainer: AppColors.darkPrimaryLight,
      onPrimaryContainer: AppColors.darkOnPrimary,
      
      // Secondary colors
      secondary: AppColors.darkSecondary,
      onSecondary: AppColors.darkOnSecondary,
      secondaryContainer: AppColors.darkSecondaryLight,
      onSecondaryContainer: AppColors.darkOnSecondary,
      
      // Tertiary colors
      tertiary: AppColors.darkTertiary,
      onTertiary: AppColors.darkOnPrimary,
      tertiaryContainer: AppColors.darkTertiaryLight,
      onTertiaryContainer: AppColors.darkOnPrimary,
      
      // Error colors
      error: AppColors.darkError,
      onError: AppColors.darkOnPrimary,
      errorContainer: AppColors.darkError,
      onErrorContainer: AppColors.darkOnPrimary,
      
      // Surface colors
      surface: AppColors.darkSurface,
      onSurface: AppColors.darkOnSurface,
      surfaceVariant: AppColors.darkSurfaceVariant,
      onSurfaceVariant: AppColors.darkOnSurface,
      
      // Background colors
      background: AppColors.darkBackground,
      onBackground: AppColors.darkOnBackground,
      
      // Outline colors
      outline: Colors.grey.shade600,
      outlineVariant: Colors.grey.shade700,
      
      // Shadow
      shadow: Colors.black.withOpacity(0.3),
      scrim: Colors.black.withOpacity(0.7),
      
      // Inverse colors
      inverseSurface: AppColors.lightSurface,
      onInverseSurface: AppColors.lightOnSurface,
      inversePrimary: AppColors.lightPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: Brightness.dark,
      
      // Typography with Tajawal font (Kaleem.dev)
      textTheme: _buildTextTheme(GoogleFonts.tajawalTextTheme(), true),
      
      // AppBar theme
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w500,
          color: AppColors.darkOnSurface,
        ),
        iconTheme: IconThemeData(
          color: AppColors.darkOnSurface,
          size: 24,
        ),
        backgroundColor: AppColors.darkSurface,
        foregroundColor: AppColors.darkOnSurface,
      ),
      
      // Card theme
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppShapes.cardRadius,
          side: BorderSide(
            color: AppColors.darkSurfaceVariant,
            width: 1,
          ),
        ),
        margin: EdgeInsets.symmetric(
          horizontal: AppSpacing.screenPadding,
          vertical: AppSpacing.sm,
        ),
        color: AppColors.darkSurface,
      ),
      
      // Button themes
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 2,
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          minimumSize: Size(0, 40),
          shape: RoundedRectangleBorder(
            borderRadius: AppShapes.buttonRadius,
          ),
          textStyle: GoogleFonts.tajawal(
            fontSize: 16, // Body text: 1rem (16px)
            fontWeight: FontWeight.w400, // Regular
          ),
        ).copyWith(
          elevation: MaterialStateProperty.resolveWith<double>(
            (Set<MaterialState> states) {
              if (states.contains(MaterialState.pressed)) return 1;
              return 2;
            },
          ),
        ),
      ),
      
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          minimumSize: Size(0, 40),
          shape: RoundedRectangleBorder(
            borderRadius: AppShapes.buttonRadius,
          ),
          side: BorderSide(width: 1, color: colorScheme.outline),
          textStyle: GoogleFonts.tajawal(
            fontSize: 16, // Body text: 1rem (16px)
            fontWeight: FontWeight.w400, // Regular
          ),
        ),
      ),
      
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          minimumSize: Size(0, 40),
          shape: RoundedRectangleBorder(
            borderRadius: AppShapes.smallRadius,
          ),
          textStyle: GoogleFonts.tajawal(
            fontSize: 16, // Body text: 1rem (16px)
            fontWeight: FontWeight.w400, // Regular
          ),
        ),
      ),
      
      // Floating Action Button theme
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: AppShapes.fabRadius,
        ),
        sizeConstraints: BoxConstraints.tightFor(width: 56, height: 56),
      ),
      
      // Input decoration theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkSurfaceVariant,
        border: OutlineInputBorder(
          borderRadius: AppShapes.textFieldRadius,
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppShapes.textFieldRadius,
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppShapes.textFieldRadius,
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppShapes.textFieldRadius,
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppShapes.textFieldRadius,
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
        contentPadding: EdgeInsets.all(AppSpacing.md),
        labelStyle: GoogleFonts.tajawal(fontSize: 16), // Input: 16px
        helperStyle: GoogleFonts.tajawal(fontSize: 12),
        errorStyle: GoogleFonts.tajawal(fontSize: 12),
      ),
      
      // Chip theme
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: AppShapes.chipRadius,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        labelStyle: GoogleFonts.tajawal(
          fontSize: 12,
          fontWeight: FontWeight.w400, // Regular
        ),
      ),
      
      // Dialog theme
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: AppShapes.dialogRadius,
        ),
        elevation: 3,
        backgroundColor: AppColors.darkSurface,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w500,
          color: AppColors.darkOnSurface,
        ),
        contentTextStyle: GoogleFonts.inter(
          fontSize: 14,
          color: AppColors.darkOnSurface,
        ),
      ),
      
      // Bottom navigation bar theme
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        elevation: 8,
        backgroundColor: AppColors.darkSurface,
        selectedItemColor: AppColors.darkPrimary,
        unselectedItemColor: Colors.grey.shade400,
        selectedLabelStyle: GoogleFonts.tajawal(
          fontSize: 12,
          fontWeight: FontWeight.w700, // Bold
        ),
        unselectedLabelStyle: GoogleFonts.tajawal(
          fontSize: 12,
          fontWeight: FontWeight.w400, // Regular
        ),
      ),
      
      // Navigation bar theme (Material 3) - Solid dark green-black (Kaleem.dev)
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: AppColors.darkSurface, // #151815 - solid
        indicatorColor: AppColors.darkSurfaceVariant,
        labelTextStyle: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.darkPrimary,
            );
          }
          return GoogleFonts.inter(
            fontSize: 12,
            color: Colors.grey.shade400,
          );
        }),
        iconTheme: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return IconThemeData(color: AppColors.darkPrimary, size: 24);
          }
          return IconThemeData(color: Colors.grey.shade400, size: 24);
        }),
      ),
      
      // List tile theme
      listTileTheme: ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        minVerticalPadding: AppSpacing.sm,
        titleTextStyle: GoogleFonts.tajawal(
          fontSize: 16, // Body: 1rem (16px)
          fontWeight: FontWeight.w700, // Bold
        ),
        subtitleTextStyle: GoogleFonts.tajawal(
          fontSize: 14,
          fontWeight: FontWeight.w400, // Regular
        ),
      ),
      
      // Switch theme
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return AppColors.darkPrimary;
          }
          return Colors.grey.shade500;
        }),
        trackColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return AppColors.darkPrimary.withOpacity(0.5);
          }
          return Colors.grey.shade700;
        }),
      ),
    );
  }

  /// Build text theme with proper Material 3 type scale
  static TextTheme _buildTextTheme(TextTheme base, bool isDark) {
    // Use Kaleem.dev inspired text colors for optimal contrast
    final onSurface = isDark 
        ? AppColors.darkOnSurface 
        : AppColors.lightOnSurface; // Dark charcoal for clean contrast
    
    return base.copyWith(
      // H1: 3.5625rem (57px)
      displayLarge: GoogleFonts.tajawal(
        fontSize: 57,
        fontWeight: FontWeight.w700, // Bold
        height: 1.5, // Line height 1.5
        color: onSurface,
      ),
      // H2: 2.8125rem (45px)
      displayMedium: GoogleFonts.tajawal(
        fontSize: 45,
        fontWeight: FontWeight.w700, // Bold
        height: 1.5,
        color: onSurface,
      ),
      // H3: 2.25rem (36px)
      displaySmall: GoogleFonts.tajawal(
        fontSize: 36,
        fontWeight: FontWeight.w700, // Bold
        height: 1.5,
        color: onSurface,
      ),
      // H4: 2rem (32px)
      headlineLarge: GoogleFonts.tajawal(
        fontSize: 32,
        fontWeight: FontWeight.w700, // Bold
        height: 1.5,
        color: onSurface,
      ),
      headlineMedium: GoogleFonts.tajawal(
        fontSize: 28,
        fontWeight: FontWeight.w700, // Bold
        height: 1.5,
        color: onSurface,
      ),
      headlineSmall: GoogleFonts.tajawal(
        fontSize: 24,
        fontWeight: FontWeight.w700, // Bold
        height: 1.5,
        color: onSurface,
      ),
      // Nav links: 1.375rem (22px)
      titleLarge: GoogleFonts.tajawal(
        fontSize: 22,
        fontWeight: FontWeight.w700, // Bold
        height: 1.5,
        color: onSurface,
      ),
      // Blockquote: 1.333em (~21.3px)
      titleMedium: GoogleFonts.tajawal(
        fontSize: 21.3,
        fontWeight: FontWeight.w400, // Regular
        height: 1.5,
        color: onSurface,
      ),
      titleSmall: GoogleFonts.tajawal(
        fontSize: 18,
        fontWeight: FontWeight.w400, // Regular
        height: 1.5,
        color: onSurface,
      ),
      // Body text: 1rem (16px), line height 1.5
      bodyLarge: GoogleFonts.tajawal(
        fontSize: 16,
        fontWeight: FontWeight.w400, // Regular
        height: 1.5, // Line height 1.5
        color: onSurface,
      ),
      bodyMedium: GoogleFonts.tajawal(
        fontSize: 16,
        fontWeight: FontWeight.w400, // Regular
        height: 1.5,
        color: onSurface,
      ),
      bodySmall: GoogleFonts.tajawal(
        fontSize: 14,
        fontWeight: FontWeight.w400, // Regular
        height: 1.5,
        color: onSurface,
      ),
      labelLarge: GoogleFonts.tajawal(
        fontSize: 16,
        fontWeight: FontWeight.w400, // Regular
        height: 1.5,
        color: onSurface,
      ),
      labelMedium: GoogleFonts.tajawal(
        fontSize: 14,
        fontWeight: FontWeight.w400, // Regular
        height: 1.5,
        color: onSurface,
      ),
      labelSmall: GoogleFonts.tajawal(
        fontSize: 12,
        fontWeight: FontWeight.w400, // Regular
        height: 1.5,
        color: onSurface,
      ),
    );
  }
}
