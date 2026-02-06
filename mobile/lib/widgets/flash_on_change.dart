import 'package:flutter/material.dart';

/// Adds a subtle flash overlay when [signature] changes.
///
/// Useful to visually indicate "this row changed" without rebuilding the whole list.
class FlashOnChange extends StatefulWidget {
  final Object? signature;
  final Widget child;
  final Duration duration;
  final Color color;

  const FlashOnChange({
    super.key,
    required this.signature,
    required this.child,
    this.duration = const Duration(milliseconds: 900),
    this.color = const Color(0xFF4FC3F7), // light blue-ish
  });

  @override
  State<FlashOnChange> createState() => _FlashOnChangeState();
}

class _FlashOnChangeState extends State<FlashOnChange> {
  int _token = 0;

  @override
  void didUpdateWidget(covariant FlashOnChange oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.signature != widget.signature) {
      setState(() => _token++);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: TweenAnimationBuilder<double>(
              key: ValueKey(_token),
              tween: Tween<double>(begin: 0.30, end: 0.0),
              duration: widget.duration,
              builder: (context, opacity, _) {
                if (opacity <= 0.001) return const SizedBox.shrink();
                return DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.color.withOpacity(opacity),
                    borderRadius: BorderRadius.circular(12),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

