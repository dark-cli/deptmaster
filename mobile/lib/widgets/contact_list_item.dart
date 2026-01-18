import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/contact.dart';
import '../models/transaction.dart';
import '../services/dummy_data_service.dart';
import '../services/settings_service.dart';
import '../providers/settings_provider.dart';
import '../utils/app_colors.dart';
import '../utils/theme_colors.dart';

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
      return flipColors ? 'GIVE' : 'RECEIVED';
    } else {
      return flipColors ? 'RECEIVED' : 'GIVE';
    }
  }

  Color _getAvatarColor(int balance, bool flipColors, BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (balance == 0) {
      return ThemeColors.gray(context, shade: 600);
    } else if (balance < 0) {
      // Negative balance = money received (owed to us)
      return AppColors.getReceivedColor(flipColors, isDark);
    } else {
      // Positive balance = money given (we owe)
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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: isSelected
            ? Checkbox(
                value: true,
                onChanged: (value) => onSelectionChanged?.call(),
              )
            : CircleAvatar(
                backgroundColor: avatarColor.withOpacity(0.2),
                child: Text(
                  contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: avatarColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
        title: Text(
          contact.name,
          semanticsLabel: 'Contact ${contact.name}',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              status,
              style: TextStyle(
                color: ThemeColors.gray(context, shade: 600),
              ),
            ),
            if (balance != 0) ...[
              const SizedBox(height: 2),
              Text(
                '${_formatAmount(balance)} IQD',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: avatarColor,
                ),
              ),
            ],
          ],
        ),
        onTap: onTap,
        onLongPress: onSelectionChanged != null ? () {
          onSelectionChanged?.call();
        } : null,
      ),
    );
  }
}
