import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/contact.dart';
import '../providers/settings_provider.dart';
import '../utils/app_colors.dart';
import '../utils/theme_colors.dart';
import '../utils/text_utils.dart';
import 'animated_pixelated_text.dart';
import 'avatar_with_selection.dart';

class ContactListItem extends StatelessWidget {
  final Contact contact;
  final VoidCallback? onTap;
  final bool? isSelected;
  final VoidCallback? onSelectionChanged;
  final bool flipColors;

  const ContactListItem({
    super.key,
    required this.contact,
    this.onTap,
    this.isSelected,
    this.onSelectionChanged,
    this.flipColors = false,
  });

  String _getStatus(int balance, bool flipColors) {
    if (balance == 0) {
      return 'NO DEBT';
    } else if (balance < 0) {
      // Negative balance = they owe you = Received (positive for you)
      return 'RECEIVED';
    } else {
      // Positive balance = you owe them = Gave (negative for you)
      return 'GAVE';
    }
  }

  Color _getAvatarColor(int balance, bool flipColors, BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (balance == 0) {
      return ThemeColors.gray(context, shade: 600);
    } else if (balance < 0) {
      // Negative balance = Received (positive for you) = green
      return AppColors.getReceivedColor(flipColors, isDark);
    } else {
      // Positive balance = Gave (negative for you) = red
      return AppColors.getGiveColor(flipColors, isDark);
    }
  }

  String _formatAmount(int amount) {
    // Amount is stored as whole units (IQD), format with commas
    return amount.abs().toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }

  @override
  Widget build(BuildContext context) {
    // Always use provider for reactive updates
    return Consumer(
      builder: (context, ref, child) {
        final flipColorsValue = ref.watch(flipColorsProvider);
        return _buildListTile(context, flipColorsValue);
      },
    );
  }

  Widget _buildListTile(BuildContext context, bool flipColorsValue) {
    // Balance is stored as whole units (IQD), not cents
    final balance = contact.balance;
    final status = _getStatus(balance, flipColorsValue);
    final avatarColor = _getAvatarColor(balance, flipColorsValue, context);
    final isSelected = this.isSelected ?? false;

    // Pre-allocate width for amount section to ensure names align
    // Width calculated to fit "1000,000 IQD" (approximately 110-120 pixels)
    const double amountSectionWidth = 120.0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: onTap,
        onLongPress: onSelectionChanged != null ? () {
          onSelectionChanged?.call();
        } : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            textDirection: TextDirection.rtl, // RTL layout: start from right
            children: [
              // Right side: Amount and Status (fixed width)
              SizedBox(
                width: amountSectionWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 22, // Reserve space when balance is 0
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: AnimatedPixelatedText(
                          balance == 0 ? '' : '${_formatAmount(balance)} IQD',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: avatarColor,
                          ),
                          textAlign: TextAlign.right,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status,
                      style: TextStyle(
                        fontSize: 11,
                        color: ThemeColors.gray(context, shade: 600),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Name and Username
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      TextUtils.forceLtr(contact.name), // Force LTR for mixed Arabic/English text
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.right,
                      semanticsLabel: 'Contact ${contact.name}',
                    ),
                    if (contact.username != null && contact.username!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '@${contact.username}',
                        style: TextStyle(
                          color: ThemeColors.gray(context, shade: 500),
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Left side: Avatar with optional selection checkmark
              AvatarWithSelection(
                avatar: CircleAvatar(
                  backgroundColor: avatarColor.withOpacity(0.2),
                  radius: 24,
                  child: Text(
                    contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: avatarColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                radius: 24,
                isSelected: isSelected,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

