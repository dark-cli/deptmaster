import 'package:flutter/material.dart';

/// Helper function to show a screen as a floating bottom sheet
Future<T?> showScreenAsBottomSheet<T>({
  required BuildContext context,
  required Widget screen,
  String? title,
  double initialChildSize = 0.9,
  double minChildSize = 0.5,
  double maxChildSize = 0.95,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: initialChildSize,
      minChildSize: minChildSize,
      maxChildSize: maxChildSize,
      expand: false,
      builder: (context, scrollController) => screen,
    ),
  );
}
