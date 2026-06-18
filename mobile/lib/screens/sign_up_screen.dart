import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart';
import '../utils/carbon_tokens.dart';
import 'backend_setup_screen.dart';
import 'login_screen.dart';

/// Human-readable random username for debug sign-up prefills (e.g. swift_fox_42).
String _debugSignUpUsername() {
  const adjectives = ['swift', 'calm', 'brave', 'happy', 'bright', 'clever', 'gentle', 'lucky'];
  const nouns = ['fox', 'star', 'wave', 'bear', 'leaf', 'cloud', 'river', 'bird'];
  final r = Random();
  return '${adjectives[r.nextInt(adjectives.length)]}_${nouns[r.nextInt(nouns.length)]}_${r.nextInt(90) + 10}';
}

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController(
    text: kDebugMode ? _debugSignUpUsername() : '',
  );
  final _passwordController = TextEditingController(
    text: kDebugMode ? '12345678' : '',
  );
  final _confirmPasswordController = TextEditingController(
    text: kDebugMode ? '12345678' : '',
  );
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await Api.register(
        _usernameController.text.trim(),
        _passwordController.text,
      );
      if (!mounted) return;
      // Ensure wallet context
      try {
        await Api.ensureCurrentWallet();
      } catch (_) {}
      
      // Recovery: if we still have no current wallet but have wallets, set first
      if (await Api.getCurrentWalletId() == null) {
        try {
          final list = await Api.getWallets();
          if (list.isNotEmpty && list.first['id'] != null) {
            await Api.setCurrentWalletId(list.first['id'] as String);
          }
        } catch (_) {}
      }

      // Perform initial sync (wait for it to ensure data is ready)
      try {
        if (await Api.getCurrentWalletId() != null) {
          await Api.manualSync();
        }
      } catch (e) {
        debugPrint('Sign up sync failed: $e');
        // Continue anyway, dashboard will show empty/error state
      }
      
      Api.connectRealtime().catchError((_) {});
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
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
                          Icons.person_add,
                          size: 64,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Sign up',
                          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Create an account to get started',
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
                        ),
                        const SizedBox(height: 16),
                        CarbonTextInput(
                          controller: _passwordController,
                          label: 'Password',
                          placeholder: 'At least 8 characters',
                          obscureText: true,
                          textInputAction: TextInputAction.next,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Password is required';
                            }
                            if (value.length < 8) {
                              return 'Password must be at least 8 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        CarbonTextInput(
                          controller: _confirmPasswordController,
                          label: 'Confirm password',
                          placeholder: 'Re-enter your password',
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: () => _handleSubmit(),
                          validator: (value) {
                            if (value != _passwordController.text) {
                              return 'Passwords do not match';
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
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.error_outline,
                                        size: 20,
                                        color: Theme.of(context).colorScheme.onErrorContainer,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _error!,
                                          style: TextStyle(
                                            color: Theme.of(context).colorScheme.onErrorContainer,
                                            fontSize: 13,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
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
                              label: _loading ? 'Signing up...' : 'Sign up',
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
                              label: 'Already have an account? Sign in',
                              kind: ButtonKind.ghost,
                              onPressed: _loading
                                  ? null
                                  : () {
                                      Navigator.of(context).pushReplacement(
                                        MaterialPageRoute(
                                          builder: (context) => const LoginScreen(),
                                        ),
                                      );
                                    },
                            ),
                          ],
                        ),
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
