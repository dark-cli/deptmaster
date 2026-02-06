import 'dart:math';
import 'package:flutter/material.dart';

/// Paints a random-character scramble overlay across available space.
class GlitchScrambleOverlay extends StatelessWidget {
  final double intensity; // 0.0 - 1.0
  final int seed;
  final double fontSize;
  final double opacity;
  final String chars;

  const GlitchScrambleOverlay({
    super.key,
    required this.intensity,
    required this.seed,
    this.fontSize = 10,
    this.opacity = 0.35,
    this.chars = '@#\$%^&*',
  });

  @override
  Widget build(BuildContext context) {
    if (intensity <= 0.01) {
      return const SizedBox.shrink();
    }
    return CustomPaint(
      painter: _GlitchScramblePainter(
        intensity: intensity,
        seed: seed,
        fontSize: fontSize,
        opacity: opacity,
        chars: chars,
      ),
      size: Size.infinite,
    );
  }
}

class _GlitchScramblePainter extends CustomPainter {
  final double intensity;
  final int seed;
  final double fontSize;
  final double opacity;
  final String chars;

  _GlitchScramblePainter({
    required this.intensity,
    required this.seed,
    required this.fontSize,
    required this.opacity,
    required this.chars,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rand = Random(seed);
    final paint = Paint();
    final textStyle = TextStyle(
      color: Colors.white.withOpacity(opacity * intensity),
      fontSize: fontSize,
      height: 1.0,
    );
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    final stepX = fontSize * 0.9;
    final stepY = fontSize * 1.2;

    for (double y = 0; y < size.height; y += stepY) {
      for (double x = 0; x < size.width; x += stepX) {
        final ch = chars.isEmpty ? '@' : chars[rand.nextInt(chars.length)];
        textPainter.text = TextSpan(text: ch, style: textStyle);
        textPainter.layout();
        textPainter.paint(canvas, Offset(x, y));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GlitchScramblePainter oldDelegate) {
    return oldDelegate.intensity != intensity ||
        oldDelegate.seed != seed ||
        oldDelegate.fontSize != fontSize ||
        oldDelegate.opacity != opacity ||
        oldDelegate.chars != chars;
  }
}
