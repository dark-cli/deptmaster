import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_shapes.dart';

/// Complete Material Design 3 theme configuration
/// Follows academic design standards and WCAG accessibility guidelines
class AppTheme {
  AppTheme._(); // Private constructor to prevent instantiation

  /// Light theme configuration - Material Design 3 defaults
  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.lightBackground, // Material 3 default
      
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
        backgroundColor: AppColors.lightSurface, // Material 3 default
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
        backgroundColor: AppColors.lightSurface, // Material 3 default
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

  /// Dark theme configuration - Material Design 3 defaults
  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.lightBackground, // Material 3 default
      
      // Typography with Tajawal font (Kaleem.dev)
      textTheme: _buildTextTheme(GoogleFonts.tajawalTextTheme(), true),
      
      // AppBar theme - Solid dark green-black with shadow (Kaleem.dev)
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.tajawal(
          fontSize: 22, // Nav links: 1.375rem (22px)
          fontWeight: FontWeight.w700, // Bold
          color: AppColors.darkOnSurface,
        ),
        iconTheme: IconThemeData(
          color: AppColors.darkOnSurface,
          size: 24,
        ),
        backgroundColor: AppColors.darkSurface, // Material 3 default
        foregroundColor: AppColors.darkOnSurface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withOpacity(0.08),
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
        backgroundColor: AppColors.darkSurface, // Material 3 default
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
    final onSurface = isDark 
        ? base.bodyLarge?.color ?? Colors.white
        : base.bodyLarge?.color ?? Colors.black;
    
    return base;
  }
}
