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
    
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [
                  AppColors.darkBackground, // #1E221E
                  AppColors.darkBackgroundEnd, // #151815
                ]
              : [
                  AppColors.lightBackground, // #F5E7DE
                  AppColors.lightBackgroundEnd, // #F2BFA4
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
    
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurface // #151815 - solid
            : AppColors.lightBackgroundEnd.withOpacity(0.8), // Peach with 80% opacity
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
