import 'dart:math';
import 'package:flutter/material.dart';
import 'glitch_scramble_overlay.dart';

/// A lightweight glitchy jitter transition for a single child.
/// Uses translation + flicker without duplicating the child widget.
class GlitchTransition extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;
  final double maxX;
  final double maxY;
  final double flickerChance;
  final bool showScramble;

  const GlitchTransition({
    super.key,
    required this.animation,
    required this.child,
    this.maxX = 12,
    this.maxY = 6,
    this.flickerChance = 0.4,
    this.showScramble = true,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = animation.value;
        final intensity = 1.0 - (2 * t - 1.0).abs();
        if (intensity <= 0.01) return child!;

        final seed = (t * 1000).round();
        final rand = Random(seed);
        final offsetX = (rand.nextDouble() - 0.5) * maxX * intensity;
        final offsetY = (rand.nextDouble() - 0.5) * maxY * intensity;
        final flicker = rand.nextDouble() > flickerChance ? 1.0 : 0.6;

        final base = Opacity(
          opacity: flicker,
          child: Transform.translate(
            offset: Offset(offsetX, offsetY),
            child: child!,
          ),
        );

        if (!showScramble) return base;

        return Stack(
          children: [
            base,
            Positioned.fill(
              child: IgnorePointer(
                child: GlitchScrambleOverlay(
                  intensity: intensity,
                  seed: seed,
                  fontSize: 10,
                  opacity: 0.35,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
