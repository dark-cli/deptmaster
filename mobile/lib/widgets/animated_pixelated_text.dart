import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// A widget that transitions text changes with a "Glitch" / "Chromatic Aberration" effect.
/// 
/// It simulates a digital signal failure by separating color channels (Red/Blue)
/// and shaking them independently during the transition.
class AnimatedPixelatedText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration duration;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final TextOverflow? overflow;
  final int? maxLines;
  final bool animateFromEmpty;
  final String emptyTransitionText;
  final Duration emptyTransitionDelay;
  final String scrambleChars;
  final int scrambleMinLength;
  final int scrambleMaxLength;
  final bool forceScramble;

  const AnimatedPixelatedText(
    this.text, {
    super.key,
    this.style,
    this.duration = const Duration(milliseconds: 400), // Fast, punchy glitch
    this.textAlign,
    this.textDirection,
    this.overflow,
    this.maxLines,
    this.animateFromEmpty = true,
    this.emptyTransitionText = '',
    this.emptyTransitionDelay = const Duration(milliseconds: 400),
    this.scrambleChars = '@#\$%^&*',
    this.scrambleMinLength = 6,
    this.scrambleMaxLength = 10,
    this.forceScramble = false,
  });

  @override
  State<AnimatedPixelatedText> createState() => _AnimatedPixelatedTextState();
}

class _AnimatedPixelatedTextState extends State<AnimatedPixelatedText> {
  late String _displayText;
  Timer? _pending;
  final Random _random = Random();
  bool _showingScramble = false;
  Color? _scrambleColor;
  List<Color> _scrambleColors = const [];

  @override
  void initState() {
    super.initState();
    _displayText = widget.forceScramble
        ? _buildScrambleForLength(widget.text.length)
        : widget.text;
  }

  @override
  void didUpdateWidget(covariant AnimatedPixelatedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    final textChanged = oldWidget.text != widget.text;
    final isEmpty = widget.text.trim().isEmpty;

    _pending?.cancel();
    _pending = null;

    if (widget.forceScramble) {
      final scrambleText = _buildScrambleForLength(widget.text.length);
      _scrambleColors = _buildScrambleColors(context, scrambleText.length);
      setState(() {
        _showingScramble = true;
        _scrambleColor = null;
        _displayText = scrambleText;
      });
      return;
    }

    if (textChanged && !isEmpty && widget.animateFromEmpty) {
      final scrambleText = _buildScrambleForLength(widget.text.length);
      _scrambleColors = _buildScrambleColors(context, scrambleText.length);
      setState(() {
        _showingScramble = true;
        _scrambleColor = null;
        _displayText = scrambleText;
      });
      _pending = Timer(widget.emptyTransitionDelay, () {
        if (!mounted) return;
        setState(() {
          _showingScramble = false;
          _displayText = widget.text;
        });
      });
      return;
    }

    if (_displayText != widget.text) {
      setState(() {
        _showingScramble = false;
        _displayText = widget.text;
        _scrambleColors = const [];
      });
    }
  }

  @override
  void dispose() {
    _pending?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: widget.duration,
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return _GlitchTransition(
          animation: animation,
          child: child,
        );
      },
      child: _buildDisplayText(),
    );
  }

  Widget _buildDisplayText() {
    final key = ValueKey<String>(
      '${_displayText}_${widget.style?.color?.value ?? ''}_${widget.style?.fontWeight ?? ''}_${_showingScramble ? 'scramble' : 'value'}',
    );

    if (_showingScramble) {
      final baseStyle = widget.style ?? const TextStyle();
      final defaultColor =
          widget.style?.color ?? DefaultTextStyle.of(context).style.color;
      final spans = <TextSpan>[];
      for (var i = 0; i < _displayText.length; i++) {
        final color = i < _scrambleColors.length
            ? _scrambleColors[i]
            : defaultColor;
        spans.add(TextSpan(
          text: _displayText[i],
          style: baseStyle.copyWith(color: color),
        ));
      }

      // Use a Stack to stabilize the layout size.
      // We render the original text (invisible) to reserve space,
      // and overlay the scramble text.
      return Stack(
        alignment: widget.textAlign == TextAlign.center
            ? Alignment.center
            : widget.textAlign == TextAlign.right
                ? Alignment.centerRight
                : Alignment.centerLeft,
        clipBehavior: Clip.none,
        children: [
          // 1. Invisible target text to reserve layout space
          Text(
            widget.text,
            key: ValueKey('reserved_space_${widget.text}'),
            style: baseStyle.copyWith(color: Colors.transparent),
            textAlign: widget.textAlign,
            textDirection: widget.textDirection,
            overflow: widget.overflow,
            maxLines: widget.maxLines,
          ),
          // 2. Visible scramble text positioned over it (same length as text;
          // clip so it never wraps to more than one line)
          Positioned(
            left: 0,
            right: 0,
            child: RichText(
              key: key,
              textAlign: widget.textAlign ?? TextAlign.start,
              textDirection: widget.textDirection,
              maxLines: widget.maxLines ?? 1,
              overflow: TextOverflow.clip,
              text: TextSpan(style: baseStyle, children: spans),
            ),
          ),
        ],
      );
    }

    return Text(
      _displayText,
      key: key,
      style: widget.style,
      textAlign: widget.textAlign,
      textDirection: widget.textDirection,
      overflow: widget.overflow,
      maxLines: widget.maxLines,
    );
  }

  /// Builds a scramble string with exactly the same length as the target text
  /// so it doesn't overflow to an extra line. Capped at 512 chars for safety.
  String _buildScrambleForLength(int length) {
    final len = length.clamp(0, 512);
    if (len == 0) return '';
    final chars = widget.scrambleChars.isEmpty ? '@#\$%^&*' : widget.scrambleChars;
    final buf = StringBuffer();
    for (var i = 0; i < len; i++) {
      buf.write(chars[_random.nextInt(chars.length)]);
    }
    return buf.toString();
  }

  List<Color> _buildScrambleColors(BuildContext context, int length) {
    final baseColor =
        widget.style?.color ?? DefaultTextStyle.of(context).style.color ?? Colors.white;
    final colors = <Color>[];
    for (var i = 0; i < length; i++) {
      colors.add(baseColor);
    }
    return colors;
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

        // Random jitter based on intensity (reduced for stability)
        final double offsetX = (_random.nextDouble() - 0.5) * 4 * distortionIntensity;
        final double offsetY = (_random.nextDouble() - 0.5) * 2 * distortionIntensity;
        
        // Chromatic offsets (Red/Blue split) (reduced)
        final double rX = offsetX + (_random.nextDouble() * 2 * distortionIntensity);
        final double bX = offsetX - (_random.nextDouble() * 2 * distortionIntensity);

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
