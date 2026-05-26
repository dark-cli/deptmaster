import 'package:flutter/material.dart';

/// Avatar with an optional checkmark badge when selected.
/// Same style for contact and transaction cards.
class AvatarWithSelection extends StatelessWidget {
  final Widget avatar;
  final double radius;
  final bool isSelected;

  const AvatarWithSelection({
    super.key,
    required this.avatar,
    required this.radius,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (!isSelected) return avatar;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).cardColor,
                width: 1.5,
              ),
            ),
            child: Icon(
              Icons.check,
              size: radius * 0.5,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
