import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'api.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/backend_setup_screen.dart';
import 'screens/create_wallet_screen.dart';
import 'utils/app_theme.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Api.init();
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
      final isValid = await Api.validateAuth();
      initialRoute = isValid ? '/' : '/login';
    } else {
      initialRoute = '/login';
    }
  }

  Api.onLogout = () {
    final context = navigatorKey.currentContext;
    if (context != null) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (Route<dynamic> route) => false,
      );
    }
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
    return MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      title: 'Debt Tracker',
      builder: (context, child) => Directionality(textDirection: TextDirection.ltr, child: child!),
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _darkMode ? ThemeMode.dark : ThemeMode.light,
      initialRoute: widget.initialRoute,
      routes: {
        '/': (context) => _Wrapper(child: const HomeScreen()),
        '/setup': (context) => const BackendSetupScreen(),
        '/login': (context) => const LoginScreen(),
        '/create-wallet': (context) => const CreateWalletScreen(),
      },
      debugShowCheckedModeBanner: false,
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
