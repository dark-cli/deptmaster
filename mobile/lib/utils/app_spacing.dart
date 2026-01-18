/// Spacing system following 8dp grid
/// Based on Material Design 3 guidelines
class AppSpacing {
  AppSpacing._(); // Private constructor to prevent instantiation

  // Base spacing units (8dp grid)
  static const double spacing0 = 0.0;
  static const double spacing4 = 4.0;
  static const double spacing8 = 8.0;
  static const double spacing12 = 12.0;
  static const double spacing16 = 16.0;
  static const double spacing24 = 24.0;
  static const double spacing32 = 32.0;
  static const double spacing48 = 48.0;
  static const double spacing64 = 64.0;

  // Semantic spacing names
  static const double xs = spacing4;   // Extra small: 4dp
  static const double sm = spacing8;    // Small: 8dp
  static const double md = spacing16;  // Medium: 16dp
  static const double lg = spacing24;   // Large: 24dp
  static const double xl = spacing32;  // Extra large: 32dp
  static const double xxl = spacing48; // 2x extra large: 48dp

  // Component-specific spacing
  static const double cardPadding = spacing16;
  static const double cardPaddingLarge = spacing24;
  static const double screenPadding = spacing16;
  static const double screenPaddingTablet = spacing24;
  static const double sectionSpacing = spacing24;
  static const double componentGap = spacing8;
  static const double componentGapLarge = spacing16;
}
