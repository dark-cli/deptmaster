// ignore_for_file: unused_import

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';
import '../services/sync_service_v2.dart';
import '../services/realtime_service.dart';
import '../services/wallet_service.dart';
import 'home_screen.dart';
import 'backend_setup_screen.dart';
import '../widgets/gradient_background.dart';
import '../widgets/gradient_card.dart';
import 'dart:async';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController(text: 'max');
  final _passwordController = TextEditingController(text: '12345678');
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      Map<String, dynamic> result = await AuthService.login(
        _usernameController.text.trim(),
        _passwordController.text,
      );

      if (mounted) {
        if (result['success'] == true) {
          try {
            print('🔄 Ensuring wallet after login...');
            await WalletService.ensureCurrentWallet();
            print('✅ Wallet ready');
          } catch (e) {
            print('⚠️ Error ensuring wallet: $e');
          }

          // After successful login, trigger sync and WebSocket
          // Sync happens immediately, not waiting for WebSocket
          try {
            // Trigger immediate sync first (don't wait for WebSocket)
            print('🔄 Triggering immediate sync after login...');
            SyncServiceV2.manualSync().then((_) {
              print('✅ Initial sync completed after login');
            }).catchError((e, stackTrace) {
              // Log all sync errors for debugging
              final errorStr = e.toString().toLowerCase();
              print('❌ Initial sync error after login: $e');
              if (!errorStr.contains('connection refused') && 
                  !errorStr.contains('failed host lookup') &&
                  !errorStr.contains('network is unreachable')) {
                print('   Stack trace: $stackTrace');
              }
            });
            
            // Connect WebSocket for real-time updates (in background)
            RealtimeService.connect().catchError((e) {
              // Silently handle connection errors
            });
          } catch (e) {
            // Silently handle initialization errors
            print('⚠️ Error initializing after login: $e');
          }
          
          if (!mounted) return;
          Navigator.of(context).pushNamedAndRemoveUntil(
            '/',
            (route) => false,
          );
        } else {
          setState(() {
            _error = result['error'] as String? ?? 'Unknown error occurred';
            _loading = false;
          });
        }
      }
    } catch (e, stackTrace) {
      print('Login error: $e');
      print('Stack trace: $stackTrace');
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
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 32, // Account for padding
                  ),
                  child: IntrinsicHeight(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                  Icon(
                    Icons.account_balance_wallet,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Login',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
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
                  TextFormField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                      labelText: 'Username',
                      hintText: 'Enter your username',
                      prefixIcon: const Icon(Icons.person),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
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
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _handleSubmit(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Password is required';
                      }
                      return null;
                    },
                  ),
                  // Always reserve space for error message to prevent layout shifts
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 56, // Fixed height to reserve space
                    child: _error != null
                        ? Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(8),
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
                        : const SizedBox.shrink(), // Empty space when no error
                  ),
                  const SizedBox(height: 24),
                  // Stack buttons vertically on mobile (matching backend setup page)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton(
                        onPressed: _loading ? null : _handleSubmit,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Theme.of(context).colorScheme.onPrimary,
                        ),
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text(
                                'Login',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _loading ? null : () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(builder: (context) => const BackendSetupScreen()),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2,
                          ),
                        ),
                        child: Text(
                          'Back to Backend Setup',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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
      ),
    );
  }
}