import 'dart:math';
import 'package:flutter/material.dart';

/// A widget that transitions text changes with a "Glitch" / "Chromatic Aberration" effect.
/// 
/// It simulates a digital signal failure by separating color channels (Red/Blue)
/// and shaking them independently during the transition.
class AnimatedPixelatedText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final Duration duration;
  final TextAlign? textAlign;
  final TextOverflow? overflow;
  final int? maxLines;

  const AnimatedPixelatedText(
    this.text, {
    super.key,
    this.style,
    this.duration = const Duration(milliseconds: 400), // Fast, punchy glitch
    this.textAlign,
    this.overflow,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return _GlitchTransition(
          animation: animation,
          child: child,
        );
      },
      child: Text(
        text,
        // Key includes style (color) to trigger animation when direction/style changes
        key: ValueKey<String>('${text}_${style?.color?.value ?? ''}_${style?.fontWeight ?? ''}'),
        style: style,
        textAlign: textAlign,
        overflow: overflow,
        maxLines: maxLines,
      ),
    );
  }
}

class _GlitchTransition extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;
  final Random _random = Random();

  _GlitchTransition({
    required this.animation,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final double t = animation.value;
        // If t is near 1.0 (fully visible) or 0.0 (fully invisible), 
        // the glitch intensity should be low.
        // If t is in the middle (0.5), glitch intensity is high.
        
        // Parabolic curve: 0 at 0.0, 1 at 0.5, 0 at 1.0
        final double distortionIntensity = (1.0 - (2 * t - 1.0).abs()) * 2.0;
        
        // If intensity is essentially zero, just show child
        if (distortionIntensity < 0.05) {
          return Opacity(opacity: t, child: child!);
        }

        // Random jitter based on intensity
        final double offsetX = (_random.nextDouble() - 0.5) * 10 * distortionIntensity;
        final double offsetY = (_random.nextDouble() - 0.5) * 5 * distortionIntensity;
        
        // Chromatic offsets (Red/Blue split)
        final double rX = offsetX + (_random.nextDouble() * 4 * distortionIntensity);
        final double bX = offsetX - (_random.nextDouble() * 4 * distortionIntensity);

        return Stack(
          alignment: Alignment.topLeft,
          clipBehavior: Clip.none,
          children: [
            // Cyan Channel (Ghost)
            Positioned(
              left: bX,
              top: offsetY,
              child: Opacity(
                opacity: 0.7 * t,
                child: ColorFiltered(
                  colorFilter: const ColorFilter.mode(
                    Colors.cyan,
                    BlendMode.srcIn,
                  ),
                  child: child!,
                ),
              ),
            ),
            // Red Channel (Ghost)
            Positioned(
              left: rX,
              top: offsetY,
              child: Opacity(
                opacity: 0.7 * t,
                child: ColorFiltered(
                  colorFilter: const ColorFilter.mode(
                    Colors.red,
                    BlendMode.srcIn,
                  ),
                  child: child!,
                ),
              ),
            ),
            // Main Text (White/Original)
            // We flicker the opacity of the main text to simulate signal loss
            Opacity(
              opacity: t * (_random.nextDouble() > 0.2 ? 1.0 : 0.5),
              child: Transform.translate(
                offset: Offset(offsetX, offsetY),
                child: child!,
              ),
            ),
          ],
        );
      },
      child: child,
    );
  }
}
