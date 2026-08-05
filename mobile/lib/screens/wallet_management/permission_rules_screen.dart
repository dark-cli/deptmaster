import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api.dart';
import '../../utils/toast_service.dart';

class PermissionRulesScreen extends ConsumerStatefulWidget {
  final String walletId;

  const PermissionRulesScreen({
    super.key,
    required this.walletId,
  });

  @override
  ConsumerState<PermissionRulesScreen> createState() => _PermissionRulesScreenState();
}

class _PermissionRulesScreenState extends ConsumerState<PermissionRulesScreen> {
  List<Map<String, dynamic>> _matrix = [];
  List<Map<String, dynamic>> _actions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        Api.getWalletPermissionMatrix(widget.walletId),
        Api.getWalletPermissionActions(widget.walletId),
      ]);

      if (mounted) {
        setState(() {
          _matrix = results[0] as List<Map<String, dynamic>>;
          _actions = results[1] as List<Map<String, dynamic>>;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ToastService.showErrorFromContext(
          context,
          e.toString().replaceFirst('Exception: ', ''),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Permission Rules')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_matrix.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Permission Rules')),
        body: Center(
          child: Text(
            'No permission rules configured',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Permission Rules')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Permission Matrix',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            ..._matrix.map((rule) {
              final role = rule['role'] as String? ?? 'Unknown';
              final action = rule['action'] as String? ?? '';
              final isAllowed = rule['is_allowed'] as bool? ?? false;

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(role),
                  subtitle: Text(action),
                  trailing: Chip(
                    label: Text(isAllowed ? 'Allowed' : 'Denied'),
                    backgroundColor: isAllowed ? Colors.green : Colors.red,
                  ),
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
}
