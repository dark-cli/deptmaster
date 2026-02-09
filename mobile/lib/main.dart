import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint, defaultTargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'api.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/sign_up_screen.dart';
import 'screens/backend_setup_screen.dart';
import 'screens/create_wallet_screen.dart';
import 'utils/app_theme.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final rustOk = await Api.init();
  if (!kIsWeb && !rustOk) {
    runApp(ProviderScope(
      child: DebtTrackerApp(initialRoute: '/rust-load-error'),
    ));
    return;
  }
  if (!kIsWeb) {
    try {
      final dir = await getApplicationDocumentsDirectory();
      await Api.initStorage(dir.path);
    } catch (e, st) {
      debugPrint('Api.initStorage failed: $e');
      debugPrint('$st');
    }
  }

  void _handleNetworkError(dynamic error, StackTrace? stack) {}

  FlutterError.onError = (FlutterErrorDetails details) {
    final errorStr = details.exception.toString().toLowerCase();
    if (errorStr.contains('socketexception') ||
        errorStr.contains('connection refused') ||
        errorStr.contains('connection reset') ||
        errorStr.contains('failed host lookup') ||
        errorStr.contains('network is unreachable') ||
        errorStr.contains('no route to host') ||
        errorStr.contains('httpexception')) {
      _handleNetworkError(details.exception, details.stack);
      return;
    }
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    final errorStr = error.toString().toLowerCase();
    if (errorStr.contains('socketexception') ||
        errorStr.contains('connection refused') ||
        errorStr.contains('connection reset') ||
        errorStr.contains('failed host lookup') ||
        errorStr.contains('network is unreachable') ||
        errorStr.contains('no route to host') ||
        errorStr.contains('httpexception')) {
      return true;
    }
    return false;
  };

  final isBackendConfigured = await Api.isBackendConfigured();

  if (!kIsWeb && isBackendConfigured) {
    final isLoggedIn = await Api.isLoggedIn();
    if (isLoggedIn) {
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
    }
    try {
      await Api.manualSync();
    } catch (e) {
      debugPrint('main: manualSync failed: $e');
      await Api.drainRustLogsToConsole();
    }
    runZoned(() {
      Api.connectRealtime().catchError((_) {});
    }, onError: (_, __) {});
    Api.syncWhenOnline().catchError((_) {});
  }

  if (kIsWeb && isBackendConfigured) {
    runZoned(() {
      Api.connectRealtime().catchError((_) {});
    }, onError: (_, __) {});
  }

  if (isBackendConfigured) {
    Api.loadSettingsFromBackend().catchError((_) {});
  }

  String initialRoute;
  if (!isBackendConfigured) {
    initialRoute = '/setup';
  } else {
    final isLoggedIn = await Api.isLoggedIn();
    if (isLoggedIn) {
      bool isValid = true;
      try {
        isValid = await Api.validateAuth();
      } catch (_) {
        isValid = true; // Offline or network error: stay in app.
      }
      initialRoute = isValid ? '/' : '/login';
    } else {
      initialRoute = '/login';
    }
  }

  Api.onLogout = () {
    // Defer navigation to next frame so we never run during build (avoids Navigator _history.isNotEmpty).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/login',
          (Route<dynamic> route) => false,
        );
      }
    });
  };

  runApp(ProviderScope(
    child: DebtTrackerApp(initialRoute: initialRoute),
  ));
}

class DebtTrackerApp extends ConsumerStatefulWidget {
  final String initialRoute;

  const DebtTrackerApp({super.key, this.initialRoute = '/'});

  @override
  ConsumerState<DebtTrackerApp> createState() => _DebtTrackerAppState();
}

class _DebtTrackerAppState extends ConsumerState<DebtTrackerApp> {
  bool _darkMode = true;
  Timer? _themeTimer;

  @override
  void initState() {
    super.initState();
    _loadTheme();
    _watchTheme();
    Api.setRealtimeErrorCallback((_) {});
  }

  @override
  void dispose() {
    _themeTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadTheme() async {
    final dark = await Api.getDarkMode();
    if (mounted) setState(() => _darkMode = dark);
  }

  void _watchTheme() {
    _themeTimer?.cancel();
    _themeTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        _loadTheme();
        _watchTheme();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final instanceId = const String.fromEnvironment('INSTANCE_ID', defaultValue: '');
    final appTitle = instanceId.isEmpty ? 'Debt Tracker' : 'Instance $instanceId';
    return MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      title: appTitle,
      builder: (context, child) => Directionality(textDirection: TextDirection.ltr, child: child!),
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _darkMode ? ThemeMode.dark : ThemeMode.light,
      initialRoute: widget.initialRoute,
      routes: {
        '/': (context) => _Wrapper(child: const HomeScreen()),
        '/setup': (context) => const BackendSetupScreen(),
        '/login': (context) => const LoginScreen(),
        '/signup': (context) => const SignUpScreen(),
        '/create-wallet': (context) => const CreateWalletScreen(),
        '/rust-load-error': (context) => const RustLoadErrorScreen(),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Shown when the Rust native library fails to load (e.g. Android .so not in jniLibs).
class RustLoadErrorScreen extends StatelessWidget {
  const RustLoadErrorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final rawError = Api.initError ?? '';
    final error = rawError.isEmpty
        ? 'Rust library (libdebitum_client_core.so) could not be loaded.'
        : rawError;
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 24),
              const Icon(Icons.error_outline, size: 64, color: Colors.orange),
              const SizedBox(height: 24),
              const Text(
                'Native library not loaded',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              SelectableText(
                error,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                maxLines: 6,
              ),
              if (isAndroid) ...[
                const SizedBox(height: 28),
                const Text(
                  'Build and run from the project root (the folder that contains manage.sh and the mobile/ directory).',
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                ),
                const SizedBox(height: 12),
                const Text('In a terminal:', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 6),
                SelectableText(
                  './manage.sh run-flutter-app android',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    backgroundColor: Color(0xFF1E1E1E),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Prerequisites (run once):', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                const SelectableText(
                  'cargo install cargo-ndk\n'
                  'rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android i686-linux-android',
                  style: TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Android NDK is also required (e.g. via Android Studio SDK Manager).',
                  style: TextStyle(fontSize: 11),
                ),
                const SizedBox(height: 16),
                const Text(
                  'If the script failed before launching, fix the error it printed (e.g. install cargo-ndk, set ANDROID_NDK). If it launched but you still see this, the .so files may not have been copied into the app—run the script again and check that it says "Rust Android libs ready".',
                  style: TextStyle(fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Wrapper extends StatefulWidget {
  final Widget child;

  const _Wrapper({required this.child});

  @override
  State<_Wrapper> createState() => _WrapperState();
}

class _WrapperState extends State<_Wrapper> {
  @override
  Widget build(BuildContext context) => widget.child;
}
