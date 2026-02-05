import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart';
import '../models/wallet.dart';
import '../utils/toast_service.dart';
import '../utils/theme_colors.dart';

/// Shows wallet selection as a small, light modal bottom sheet that follows app theme.
/// Use [showWalletSelectionSheet] to present it.
Future<bool?> showWalletSelectionSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const _WalletSelectionSheet(),
  );
}

class _WalletSelectionSheet extends ConsumerStatefulWidget {
  const _WalletSelectionSheet();

  @override
  ConsumerState<_WalletSelectionSheet> createState() => _WalletSelectionSheetState();
}

class _WalletSelectionSheetState extends ConsumerState<_WalletSelectionSheet> {
  List<Wallet> _wallets = [];
  String? _currentWalletId;
  bool _loading = true;
  bool _selecting = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadWallets();
  }

  Future<void> _loadWallets() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final list = await Api.getWallets();
      final wallets = list.map((m) => Wallet.fromJson(m)).toList();
      final currentWalletId = await Api.getCurrentWalletId();
      if (mounted) {
        setState(() {
          _wallets = wallets;
          _currentWalletId = currentWalletId;
          _loading = false;
          _loadError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = e.toString().replaceFirst('Exception: ', '');
        });
        ToastService.showErrorFromContext(context, 'Could not load wallets. Tap Retry.');
      }
    }
  }

  Future<void> _selectWallet(Wallet wallet) async {
    if (_selecting) return;

    setState(() {
      _selecting = true;
    });

    try {
      await Api.setCurrentWalletId(wallet.id);
      if (mounted) {
        setState(() {
          _currentWalletId = wallet.id;
          _selecting = false;
        });
        ToastService.showSuccessFromContext(context, 'Switched to ${wallet.name}');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _selecting = false;
        });
        ToastService.showErrorFromContext(context, 'Failed to select wallet: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black45 : Colors.black26,
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(
              children: [
                Icon(Icons.account_balance_wallet_outlined, color: colorScheme.primary, size: 24),
                const SizedBox(width: 12),
                Text(
                  'Select Wallet',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: _loading
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: colorScheme.primary,
                        strokeWidth: 2,
                      ),
                    ),
                  )
                : _loadError != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.cloud_off_outlined,
                              size: 48,
                              color: ThemeColors.error(context),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Couldn\'t load wallets',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _loadError!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              onPressed: _loadWallets,
                              icon: const Icon(Icons.refresh, size: 20),
                              label: const Text('Retry'),
                              style: FilledButton.styleFrom(
                                backgroundColor: colorScheme.primary,
                                foregroundColor: colorScheme.onPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () {
                                Navigator.pop(context, false);
                                Navigator.pushNamed(context, '/create-wallet');
                              },
                              icon: const Icon(Icons.add, size: 20),
                              label: const Text('Create new wallet anyway'),
                            ),
                          ],
                        ),
                      )
                    : _wallets.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.account_balance_wallet_outlined,
                                  size: 48,
                                  color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No wallets yet',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Create your first wallet to track contacts and transactions.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 20),
                                FilledButton.icon(
                                  onPressed: () {
                                    Navigator.pop(context, false);
                                    Navigator.pushNamed(context, '/create-wallet');
                                  },
                                  icon: const Icon(Icons.add, size: 20),
                                  label: const Text('Create your first wallet'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: colorScheme.primary,
                                    foregroundColor: colorScheme.onPrimary,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                            itemCount: _wallets.length,
                            itemBuilder: (context, index) {
                              final wallet = _wallets[index];
                              final isSelected = wallet.id == _currentWalletId;
                              final isActive = wallet.isActive;

                              return Material(
                                color: isSelected
                                    ? colorScheme.primaryContainer.withOpacity(0.5)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                child: ListTile(
                                  leading: Icon(
                                    isSelected
                                        ? Icons.account_balance_wallet
                                        : Icons.account_balance_wallet_outlined,
                                    color: isSelected
                                        ? colorScheme.primary
                                        : colorScheme.onSurfaceVariant,
                                    size: 28,
                                  ),
                                  title: Text(
                                    wallet.name,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                      color: isActive
                                          ? colorScheme.onSurface
                                          : colorScheme.onSurface.withOpacity(0.6),
                                    ),
                                  ),
                                  subtitle: wallet.description != null &&
                                          wallet.description!.isNotEmpty
                                      ? Text(
                                          wallet.description!,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        )
                                      : null,
                                  trailing: isSelected
                                      ? Icon(
                                          Icons.check_circle,
                                          color: colorScheme.primary,
                                          size: 24,
                                        )
                                      : null,
                                  enabled: isActive && !_selecting,
                                  onTap: isActive ? () => _selectWallet(wallet) : null,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen wallet selection (e.g. for direct route). Prefer [showWalletSelectionSheet] for in-app.
class WalletSelectionScreen extends ConsumerStatefulWidget {
  const WalletSelectionScreen({super.key});

  @override
  ConsumerState<WalletSelectionScreen> createState() => _WalletSelectionScreenState();
}

class _WalletSelectionScreenState extends ConsumerState<WalletSelectionScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Wallet'),
      ),
      body: const _WalletSelectionSheet(),
    );
  }
}
