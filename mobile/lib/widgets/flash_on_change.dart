import 'dart:math';
import 'package:flutter/material.dart';

/// Adds a subtle flash overlay when [signature] changes.
///
/// Useful to visually indicate "this row changed" without rebuilding the whole list.
class FlashOnChange extends StatefulWidget {
  final Object? signature;
  final Widget child;
  final Duration duration;
  final Color color;
  final bool glitch;

  const FlashOnChange({
    super.key,
    required this.signature,
    required this.child,
    this.duration = const Duration(milliseconds: 250),
    this.color = Colors.transparent, // Disable color flash since we have glitch text
    this.glitch = false,
  });

  @override
  State<FlashOnChange> createState() => _FlashOnChangeState();
}

class _FlashOnChangeState extends State<FlashOnChange> {
  /// Only show overlay after a real signature change (not on first build or selection toggles).
  int _token = 0;
  final Random _random = Random();

  @override
  void didUpdateWidget(covariant FlashOnChange oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.signature != widget.signature) {
      setState(() => _token++);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Skip overlay on first build so we don't cover the screen when list appears or selection mode changes.
    if (_token == 0) {
      return widget.child;
    }
    return TweenAnimationBuilder<double>(
      key: ValueKey(_token),
      tween: Tween<double>(begin: 1.0, end: 0.0),
      duration: widget.duration,
      child: widget.child,
      builder: (context, t, child) {
        if (t <= 0.01) return child!;
        final intensity = t.clamp(0.0, 1.0);
        final seed = (_token * 1000) + (t * 1000).round();
        final rand = Random(seed);
        final offsetX = (rand.nextDouble() - 0.5) * 10 * intensity;
        final offsetY = (rand.nextDouble() - 0.5) * 6 * intensity;
        final flicker = rand.nextDouble() > 0.3 ? 1.0 : 0.6;

        final base = Transform.translate(
          offset: Offset(offsetX, offsetY),
          child: Opacity(opacity: flicker, child: child),
        );

        if (!widget.glitch || widget.color.opacity == 0) {
          return base;
        }

        return Stack(
          children: [
            base,
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.color.withOpacity(intensity * 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

