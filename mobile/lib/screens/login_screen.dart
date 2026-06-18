// ignore_for_file: unused_import

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart';
import '../utils/carbon_tokens.dart';
import '../providers/wallets_provider.dart';
import '../providers/contacts_provider.dart';
import '../providers/transactions_provider.dart';
import '../providers/events_provider.dart';
import 'backend_setup_screen.dart';
import 'sign_up_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController(text: kDebugMode ? 'max' : '');
  final _passwordController = TextEditingController(text: kDebugMode ? '12345678' : '');
  bool _loading = false;
  bool _signInPressed = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    debugPrint('[login] _handleSubmit fired');
    if (!_formKey.currentState!.validate()) {
      debugPrint('[login] form validation failed — aborting');
      return;
    }
    debugPrint('[login] validation passed, username="${_usernameController.text.trim()}"');

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      debugPrint('[login] calling Api.login...');
      await Api.login(
        _usernameController.text.trim(),
        _passwordController.text,
      );
      debugPrint('[login] Api.login returned successfully');
      if (!mounted) return;
      try {
        await Api.ensureCurrentWallet();
        debugPrint('[login] ensureCurrentWallet OK');
      } catch (e) {
        debugPrint('[login] ensureCurrentWallet skipped: $e');
      }

      var currentWallet = await Api.getCurrentWalletId();
      debugPrint('[login] currentWalletId after login: $currentWallet');
      if (currentWallet == null) {
        try {
          final list = await Api.getWallets();
          debugPrint('[login] getWallets returned ${list.length} wallets');
          if (list.isNotEmpty && list.first['id'] != null) {
            final pick = list.first['id'] as String;
            debugPrint('[login] selecting wallet: $pick');
            await Api.setCurrentWalletId(pick);
            currentWallet = pick;
            debugPrint('[login] setCurrentWalletId OK');
          } else {
            debugPrint('[login] user has no wallets yet — will need to create one');
          }
        } catch (e, st) {
          debugPrint('[login] wallet selection FAILED: $e');
          debugPrint('[login] $st');
        }
      }

      try {
        if (currentWallet != null) {
          await Api.manualSync();
          debugPrint('[login] manualSync OK');
        } else {
          debugPrint('[login] skipping manualSync (no wallet)');
        }
      } catch (e) {
        debugPrint('[login] manualSync failed: $e');
      }

      Api.connectRealtime().catchError((Object e) {
        debugPrint('[login] connectRealtime failed: $e');
      });
      if (!mounted) return;
      // Force data providers to refetch so home screen shows synced data (e.g. after permission change).
      ref.invalidate(activeWalletIdProvider);
      ref.invalidate(contactsProvider);
      ref.invalidate(transactionsProvider);
      ref.invalidate(eventsProvider);
      ref.invalidate(walletsProvider);
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } catch (e, stackTrace) {
      debugPrint('[login] FAILED: $e');
      debugPrint('[login] stack: $stackTrace');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 32,
                ),
                child: IntrinsicHeight(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 48),
                        Icon(
                          Icons.account_balance_wallet,
                          size: 64,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Sign in',
                          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Enter your credentials to continue',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        CarbonTextInput(
                          controller: _usernameController,
                          label: 'Username',
                          placeholder: 'Enter your username',
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.next,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Username is required';
                            }
                            return null;
                          },
                          onFieldSubmitted: () => _handleSubmit(),
                        ),
                        const SizedBox(height: 16),
                        CarbonTextInput(
                          controller: _passwordController,
                          label: 'Password',
                          placeholder: 'Enter your password',
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: () => _handleSubmit(),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Password is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 56,
                          child: _error != null
                              ? Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.errorContainer,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.error_outline,
                                        color: Theme.of(context).colorScheme.onErrorContainer,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _error!,
                                          style: TextStyle(
                                            color: Theme.of(context).colorScheme.onErrorContainer,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                        const SizedBox(height: 24),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            CarbonButton(
                              label: _loading ? 'Signing in...' : 'Sign in',
                              kind: ButtonKind.primary,
                              onPressed: _loading ? null : _handleSubmit,
                              isLoading: _loading,
                            ),
                            const SizedBox(height: 12),
                            CarbonButton(
                              label: 'Back to Backend Setup',
                              kind: ButtonKind.secondary,
                              onPressed: _loading
                                  ? null
                                  : () {
                                      Navigator.of(context).pushReplacement(
                                        MaterialPageRoute(
                                          builder: (context) => const BackendSetupScreen(),
                                        ),
                                      );
                                    },
                            ),
                            const SizedBox(height: 12),
                            CarbonButton(
                              label: 'Don\'t have an account? Sign up',
                              kind: ButtonKind.ghost,
                              onPressed: _loading
                                  ? null
                                  : () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) => const SignUpScreen(),
                                        ),
                                      );
                                    },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}