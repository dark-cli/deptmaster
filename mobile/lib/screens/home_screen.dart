import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'contacts_screen.dart';
import 'transactions_screen.dart';
import 'dashboard_screen.dart';
import 'settings_screen.dart';
import 'add_contact_screen.dart';
import 'add_transaction_screen.dart';
import '../services/auth_service.dart';
import '../widgets/gradient_background.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedIndex = 0; // Dashboard is default (index 0)
  bool _biometricEnabled = false;

  @override
  void initState() {
    super.initState();
    _checkBiometricAvailability();
  }

  Future<void> _checkBiometricAvailability() async {
    if (!kIsWeb) {
      final available = await AuthService.isBiometricAvailable();
      if (mounted) {
        setState(() {
          _biometricEnabled = available;
        });
      }
    }
  }

  Future<void> _handleBiometricAuth() async {
    if (!_biometricEnabled) return;
    
    final authenticated = await AuthService.authenticateWithBiometrics();
    if (authenticated && mounted) {
      // User authenticated, app is already unlocked
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Authenticated')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        child: IndexedStack(
          index: _selectedIndex,
          children: const [
            DashboardScreen(), // Dashboard tab
            ContactsScreen(), // Contacts tab
            TransactionsScreen(), // Transactions tab
            SettingsScreen(), // Settings tab
          ],
        ),
      ),
      floatingActionButton: _buildFloatingActionButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomAppBar(
          shape: const CircularNotchedRectangle(),
          notchMargin: 8.0,
          child: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: 'Dashboard',
              ),
              NavigationDestination(
                icon: Icon(Icons.contacts_outlined),
                selectedIcon: Icon(Icons.contacts),
                label: 'Contacts',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: 'Transactions',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _buildFloatingActionButton() {
    // Hide FAB on Settings tab
    if (_selectedIndex == 3) return null;
    
    // All tabs: Click = transaction, Long press = contact
    return Semantics(
      button: true,
      label: 'Add transaction (tap) or contact (long press)',
      child: GestureDetector(
        onLongPress: _showAddContactDialog,
        child: FloatingActionButton(
          onPressed: _showAddTransactionDialog,
          tooltip: 'Add Transaction (tap) or Contact (long press)',
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  void _showAddTransactionDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => const AddTransactionScreen(),
      ),
    );
  }

  void _showAddContactDialog() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const AddContactScreen(),
      ),
    );
  }
}
