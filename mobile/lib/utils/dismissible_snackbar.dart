import 'package:flutter/material.dart';
import 'theme_colors.dart';

/// Helper function to create a SnackBar that can be dismissed by swiping left or right
/// This makes it easier to dismiss toasts on mobile devices
SnackBar createDismissibleSnackBar(
  BuildContext context, {
  required Widget content,
  String? actionLabel,
  VoidCallback? onAction,
  Color? backgroundColor,
  Duration? duration,
  SnackBarBehavior? behavior,
}) {
  return SnackBar(
    content: _SwipeableContent(
      snackBarContext: context,
      child: content,
    ),
    backgroundColor: backgroundColor ?? ThemeColors.snackBarBackground(context),
    duration: duration ?? const Duration(seconds: 4),
    behavior: behavior ?? SnackBarBehavior.floating,
    action: actionLabel != null && onAction != null
        ? SnackBarAction(
            label: actionLabel,
            textColor: ThemeColors.snackBarActionColor(context),
            onPressed: onAction,
          )
        : null,
  );
}

/// Widget that detects horizontal swipe gestures and dismisses the SnackBar
class _SwipeableContent extends StatefulWidget {
  final Widget child;
  final BuildContext snackBarContext;

  const _SwipeableContent({
    required this.child,
    required this.snackBarContext,
  });

  @override
  State<_SwipeableContent> createState() => _SwipeableContentState();
}

class _SwipeableContentState extends State<_SwipeableContent> {
  double _dragStartX = 0;
  double _dragDeltaX = 0;

  void _dismissSnackBar() {
    ScaffoldMessenger.of(widget.snackBarContext).hideCurrentSnackBar();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragStart: (details) {
        _dragStartX = details.globalPosition.dx;
      },
      onHorizontalDragUpdate: (details) {
        setState(() {
          _dragDeltaX = details.globalPosition.dx - _dragStartX;
        });
      },
      onHorizontalDragEnd: (details) {
        // Dismiss if swiped more than 80 pixels horizontally (easier threshold)
        if (_dragDeltaX.abs() > 80) {
          _dismissSnackBar();
        } else {
          // Reset position if not enough swipe
          setState(() {
            _dragDeltaX = 0;
          });
        }
      },
      child: Transform.translate(
        offset: Offset(_dragDeltaX * 0.5, 0), // Visual feedback during drag
        child: Opacity(
          opacity: _dragDeltaX.abs() > 80 ? 0.6 : 1.0,
          child: widget.child,
        ),
      ),
    );
  }
}
