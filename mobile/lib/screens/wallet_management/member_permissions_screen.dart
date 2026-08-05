import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MemberPermissionsScreen extends ConsumerWidget {
  final String walletId;

  const MemberPermissionsScreen({
    super.key,
    required this.walletId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Member Permissions')),
      body: const Center(
        child: Text('Member Permissions\n(Group-scoped delegable permissions)\nComing soon...'),
      ),
    );
  }
}
