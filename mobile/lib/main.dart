import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'models/contact.dart';
import 'models/transaction.dart'; // This imports the generated adapters too
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/backend_setup_screen.dart';
import 'services/dummy_data_service.dart';
import 'services/data_service.dart';
import 'services/realtime_service.dart';
import 'services/settings_service.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/backend_config_service.dart';
import 'utils/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Check if backend is configured (check this first, before any API calls)
  final isBackendConfigured = await BackendConfigService.isConfigured();
  
  // Hive doesn't work in web, skip initialization for web
  if (!kIsWeb) {
    // Initialize Hive for mobile/desktop
    await Hive.initFlutter();
    
    // Register adapters
    Hive.registerAdapter(ContactAdapter());
    Hive.registerAdapter(TransactionAdapter());
    Hive.registerAdapter(TransactionTypeAdapter());
    Hive.registerAdapter(TransactionDirectionAdapter());
    
    // Open boxes
    await Hive.openBox<Contact>(DummyDataService.contactsBoxName);
    await Hive.openBox<Transaction>(DummyDataService.transactionsBoxName);
    
    if (isBackendConfigured) {
      // Try to load from API, fallback to dummy data if API fails
      try {
        await DataService.loadFromApi();
      } catch (e) {
        print('⚠️ Could not load from API, using dummy data: $e');
        await DummyDataService.initialize();
      }
      
      // Connect to WebSocket for real-time updates
      RealtimeService.connect();
      
      // Sync when coming back online
      RealtimeService.syncWhenOnline();
    } else {
      // Use dummy data if backend is not configured
      await DummyDataService.initialize();
    }
  }
  
  // For web, also connect WebSocket (only if backend is configured)
  if (kIsWeb && isBackendConfigured) {
    RealtimeService.connect();
  }
  
  // Load settings from backend on app start (only if configured)
  if (isBackendConfigured) {
    SettingsService.loadSettingsFromBackend();
  }
    
    // Initialize flip colors provider
    // This will be done automatically when the provider is first accessed
    
    // Determine initial route
    String initialRoute;
    if (!isBackendConfigured) {
      initialRoute = '/setup';
    } else {
      final isLoggedIn = await AuthService.isLoggedIn();
      initialRoute = isLoggedIn ? '/' : '/login';
    }
    
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
  bool _darkMode = true; // Default to dark mode

  @override
  void initState() {
    super.initState();
    _loadTheme();
    // Listen for theme changes
    _watchTheme();
  }

  Future<void> _loadTheme() async {
    final darkMode = await SettingsService.getDarkMode();
    if (mounted) {
      setState(() {
        _darkMode = darkMode;
      });
    }
  }

  void _watchTheme() {
    // Periodically check for theme changes
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        _loadTheme();
        _watchTheme();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Debt Tracker',
      // Force LTR text direction to prevent RTL issues
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: child!,
        );
      },
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _darkMode ? ThemeMode.dark : ThemeMode.light,
      initialRoute: widget.initialRoute,
      routes: {
        '/': (context) => const HomeScreen(),
        '/setup': (context) => const BackendSetupScreen(),
        '/login': (context) => const LoginScreen(),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}
