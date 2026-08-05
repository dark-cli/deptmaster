import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ContactPermissionsScreen extends ConsumerWidget {
  final String walletId;

  const ContactPermissionsScreen({
    super.key,
    required this.walletId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contact Permissions')),
      body: const Center(
        child: Text('Contact Permissions\n(Contact-group-scoped delegable permissions)\nComing soon...'),
      ),
    );
  }
}
