import 'package:flutter/material.dart';

/// Card widget with gradient background.
/// Optional [variationSeed] gives each card a stable, slightly different gradient (e.g. contact.id.hashCode).
class GradientCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final double? elevation;
  final BorderRadius? borderRadius;
  /// When set, gradient strength varies per card for subtle visual variety. Use a stable id (e.g. contact.id.hashCode).
  final int? variationSeed;

  const GradientCard({
    super.key,
    required this.child,
    this.margin,
    this.padding,
    this.elevation,
    this.borderRadius,
    this.variationSeed,
  });

  /// Deterministic 0.0–1.0 from seed for subtle variation
  static double _variation(int seed) => (seed % 101) / 101.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final v = variationSeed != null ? _variation(variationSeed!) : 0.5;
    // Same gradient and variation in both themes: surface containers + primary tint, right blends toward left
    final baseLeft = colorScheme.surfaceContainerLow;
    final baseRight = colorScheme.surfaceContainer;
    final leftLerp = 0.12 + v * 0.04;
    final leftColor = Color.lerp(baseLeft, colorScheme.primary, leftLerp)!;
    final rightBlend = (1.0 - v) * 0.05;
    final rightColor = Color.lerp(baseRight, baseLeft, rightBlend)!;
    return _buildCard(context, leftColor, rightColor);
  }

  Widget _buildCard(BuildContext context, Color leftColor, Color rightColor) {

    return Container(
      margin: margin ?? const EdgeInsets.all(0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [leftColor, rightColor],
          stops: const [0.0, 1.0],
        ),
        borderRadius: borderRadius ?? BorderRadius.circular(12),
      ),
      child: padding != null
          ? Padding(
              padding: padding!,
              child: child,
            )
          : child,
    );
  }
}
