import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PermissionRulesScreen extends ConsumerWidget {
  final String walletId;

  const PermissionRulesScreen({
    super.key,
    required this.walletId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Permission Rules')),
      body: const Center(
        child: Text('Permission Rules (Matrix)\nComing soon...'),
      ),
    );
  }
}
