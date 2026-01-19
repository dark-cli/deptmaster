import 'dart:ui';
import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

/// Gradient background widget matching Kaleem.dev design
/// Supports both light and dark modes with fixed attachment
class GradientBackground extends StatelessWidget {
  final Widget child;

  const GradientBackground({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [
                  AppColors.darkBackground, // Keep existing dark gradient
                  AppColors.darkBackgroundEnd,
                ]
              : [
                  // Use Material 3 surface colors for softer light mode
                  colorScheme.surfaceContainerHighest, // Softer top - no opacity needed
                  colorScheme.surfaceContainerHigh, // Softer bottom - no opacity needed
                ],
        ),
      ),
      child: child,
    );
  }
}

/// Semi-transparent header background with backdrop blur
class HeaderBackground extends StatelessWidget {
  final Widget child;

  const HeaderBackground({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurface // Keep existing dark surface
            : colorScheme.surfaceContainerHighest.withOpacity(0.7), // Softer Material 3 surface
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0), // No blur for header, just transparency
          child: child,
        ),
      ),
    );
  }
}
