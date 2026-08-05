import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ContactGroupsScreen extends ConsumerWidget {
  final String walletId;
  final List<Map<String, dynamic>> contactGroups;
  final VoidCallback onReload;

  const ContactGroupsScreen({
    super.key,
    required this.walletId,
    required this.contactGroups,
    required this.onReload,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contact Groups')),
      body: Center(
        child: Text(
          'Contact Groups (${contactGroups.length} groups)\nComing soon...',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
