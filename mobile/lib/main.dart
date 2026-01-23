import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'models/contact.dart';
import 'models/transaction.dart'; // This imports the generated adapters too
import 'models/event.dart';
import 'services/event_store_service.dart';
import 'services/state_builder.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/backend_setup_screen.dart';
import 'services/dummy_data_service.dart';
import 'services/data_service.dart';
import 'services/realtime_service.dart';
import 'services/settings_service.dart';
import 'services/auth_service.dart';
import 'services/backend_config_service.dart';
import 'services/sync_service_v2.dart';
import 'services/local_database_service_v2.dart';
import 'utils/app_theme.dart';

// Global navigator key for showing toasts from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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
    Hive.registerAdapter(EventAdapter());
    
    // Open boxes
    await Hive.openBox<Contact>(DummyDataService.contactsBoxName);
    await Hive.openBox<Transaction>(DummyDataService.transactionsBoxName);
    
    // Initialize EventStore for event sourcing
    await EventStoreService.initialize();
    
    // Initialize LocalDatabaseServiceV2 (rebuilds state from events)
    await LocalDatabaseServiceV2.initialize();
    
    // Initialize SyncServiceV2 for local-first architecture
    await SyncServiceV2.initialize();
    
    if (isBackendConfigured) {
      // Try to sync with server
      try {
        // Initial sync to get server events
        await SyncServiceV2.manualSync();
      } catch (e) {
        // Silently handle connection errors - app works offline
        final errorStr = e.toString();
        if (!errorStr.contains('Connection refused') && 
            !errorStr.contains('Failed host lookup') &&
            !errorStr.contains('Network is unreachable')) {
          print('⚠️ Could not sync with server, using local data: $e');
        }
      }
      
      // Connect to WebSocket for real-time updates (silently fails if offline)
      // Use runZoned to catch async exceptions
      runZoned(() {
      RealtimeService.connect().catchError((e) {
          // Error is handled by RealtimeService error callback
        });
      }, onError: (error, stack) {
        // Catch any unhandled async exceptions
        // Error is handled by RealtimeService error callback
      });
      
      // Sync when coming back online (silently fails if offline)
      RealtimeService.syncWhenOnline().catchError((e) {
        // Silently handle connection errors
      });
    } else {
      // Backend not configured - just open boxes, no dummy data
      // User will need to configure backend or import data
      await DummyDataService.initialize(); // Just opens boxes, doesn't create dummy data
    }
  }
  
  // For web, also connect WebSocket (only if backend is configured)
  if (kIsWeb && isBackendConfigured) {
    runZoned(() {
    RealtimeService.connect().catchError((e) {
        // Error is handled by RealtimeService error callback
      });
    }, onError: (error, stack) {
      // Catch any unhandled async exceptions
      // Error is handled by RealtimeService error callback
    });
  }
  
  // Load settings from backend on app start (only if configured)
  if (isBackendConfigured) {
    SettingsService.loadSettingsFromBackend().catchError((e) {
      // Silently handle connection errors
    });
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
  DateTime? _lastBackPressTime;

  @override
  void initState() {
    super.initState();
    _loadTheme();
    // Listen for theme changes
    _watchTheme();
    // Set up error callback for WebSocket connection errors
    _setupRealtimeErrorHandler();
  }

  void _setupRealtimeErrorHandler() {
    RealtimeService.setErrorCallback((message) {
      // Don't show toast for connection errors - they're handled in UI
      // The setup screen shows errors in the error box, and other screens
      // should handle connection errors gracefully without annoying toasts
      return;
    });
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
      navigatorKey: navigatorKey,
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
        '/': (context) => _DoubleBackToExitWrapper(child: const HomeScreen()),
        '/setup': (context) => const BackendSetupScreen(),
        '/login': (context) => const LoginScreen(),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}

// Widget to handle double-back-press to exit
class _DoubleBackToExitWrapper extends StatefulWidget {
  final Widget child;
  
  const _DoubleBackToExitWrapper({required this.child});

  @override
  State<_DoubleBackToExitWrapper> createState() => _DoubleBackToExitWrapperState();
}

class _DoubleBackToExitWrapperState extends State<_DoubleBackToExitWrapper> {
  @override
  Widget build(BuildContext context) {
    // Just wrap the child - back button handling is done in HomeScreen
    return widget.child;
  }
}