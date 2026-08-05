import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api.dart';
import '../utils/toast_service.dart';

class InviteCodeDialog extends StatefulWidget {
  final String walletId;

  const InviteCodeDialog({
    super.key,
    required this.walletId,
  });

  @override
  State<InviteCodeDialog> createState() => _InviteCodeDialogState();
}

class _InviteCodeDialogState extends State<InviteCodeDialog> {
  String? _code;
  bool _loading = false;
  String? _error;

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
      _code = null;
    });
    try {
      final code = await Api.createWalletInviteCode(widget.walletId);
      if (mounted) {
        setState(() {
          _code = code;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Invite by code'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Share this 4-digit code. Anyone who enters it will join this wallet as a member.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13),
            )
          else if (_code != null) ...[
            Center(
              child: SelectableText(
                _code!,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  letterSpacing: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  if (_code != null && context.mounted) {
                    Clipboard.setData(ClipboardData(text: _code!));
                    ToastService.showSuccessFromContext(context, 'Code copied');
                  }
                },
                icon: const Icon(Icons.copy, size: 20),
                label: const Text('Copy'),
              ),
            ),
          ] else
            FilledButton.icon(
              onPressed: _generate,
              icon: const Icon(Icons.qr_code, size: 20),
              label: const Text('Generate invite code'),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
