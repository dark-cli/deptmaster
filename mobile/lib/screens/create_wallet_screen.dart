import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../services/wallet_service.dart';
import '../services/auth_service.dart';
import '../services/dummy_data_service.dart';
import '../widgets/gradient_background.dart';
import '../utils/toast_service.dart';

/// Shown when the user has no wallets. They must create one to use the app.
class CreateWalletScreen extends ConsumerStatefulWidget {
  const CreateWalletScreen({super.key});

  @override
  ConsumerState<CreateWalletScreen> createState() => _CreateWalletScreenState();
}

class _CreateWalletScreenState extends ConsumerState<CreateWalletScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _createWallet() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      final name = _nameController.text.trim();
      final description = _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim();

      final wallet = await ApiService.createWallet(name: name, description: description);
      if (wallet == null || !mounted) {
        setState(() => _loading = false);
        ToastService.showErrorFromContext(context, 'Failed to create wallet');
        return;
      }

      await WalletService.setCurrentWalletId(wallet.id);
      await WalletService.getUserWallets(); // Refresh cache

      final userId = await AuthService.getUserId();
      if (userId != null) {
        await DummyDataService.initializeForUserAndWallet(userId, wallet.id);
      }

      if (!mounted) return;
      ToastService.showSuccessFromContext(context, 'Wallet "${wallet.name}" created');
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ToastService.showErrorFromContext(context, 'Error: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text('Create your first wallet'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  Icon(
                    Icons.account_balance_wallet,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'You need a wallet to track contacts and transactions. Create one to continue.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Wallet name',
                      hintText: 'e.g. Personal',
                      prefixIcon: Icon(Icons.label_outline),
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Name is required';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                      hintText: 'e.g. Day-to-day expenses',
                      prefixIcon: Icon(Icons.description_outlined),
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: _loading ? null : _createWallet,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _loading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Create wallet'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
