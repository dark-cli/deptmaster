import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WalletPermissionsScreen extends ConsumerWidget {
  final String walletId;

  const WalletPermissionsScreen({
    super.key,
    required this.walletId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wallet Permissions')),
      body: const Center(
        child: Text('Wallet Permissions\n(Delegable - Who can manage wallet)\nComing soon...'),
      ),
    );
  }
}
