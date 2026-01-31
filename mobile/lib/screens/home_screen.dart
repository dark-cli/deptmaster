// ignore_for_file: unused_element, unused_import

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'contacts_screen.dart';
import 'transactions_screen.dart';
import 'dashboard_screen.dart';
import 'add_contact_screen.dart';
import 'add_transaction_screen.dart';
import 'backend_setup_screen.dart';
import 'login_screen.dart';
import 'events_log_screen.dart';
import '../services/auth_service.dart';
import '../services/settings_service.dart';
import '../services/backend_config_service.dart';
import '../providers/settings_provider.dart';
import '../widgets/gradient_background.dart';
import '../utils/bottom_sheet_helper.dart';
import '../utils/theme_colors.dart';
import '../utils/toast_service.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedIndex = 2; // Dashboard is default (index 2)
  bool _biometricEnabled = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  DateTime? _lastBackPressTime;

  @override
  void initState() {
    super.initState();
    _checkBiometricAvailability();
  }

  Future<bool> _onWillPop() async {
    // If not at root route, allow normal back navigation
    if (Navigator.of(context).canPop()) {
      return true;
    }

    // If on Contacts or Transactions tab, prevent pop to let child screen handle it
    // (Child screens have PopScope that handles selection mode)
    if (_selectedIndex == 0 || _selectedIndex == 1) {
      // Return false to prevent pop, allowing child's PopScope to handle it
      return false;
    }

    // Only on dashboard - require double back press to exit
    final now = DateTime.now();
    if (_lastBackPressTime == null || 
        now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
      // First back press - show message and record time
      _lastBackPressTime = now;
      ToastService.showInfoFromContext(context, 'Press back again to exit', duration: const Duration(seconds: 2));
      return false; // Don't exit yet
    }
    
    // Second back press within 2 seconds - exit app
    SystemNavigator.pop();
    return false;
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
      ToastService.showSuccessFromContext(context, '✅ Authenticated');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Block pop only when on dashboard (for double-back-to-exit)
      // When on Contacts/Transactions, allow pop to propagate to child screens
      canPop: _selectedIndex != 2,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        // If we're on Contacts/Transactions, let the child screen handle it
        if (_selectedIndex == 0 || _selectedIndex == 1) {
          // Child screen's PopScope will handle the back button
          return;
        }
        
        // We're on dashboard - handle double-back-to-exit
        if (_selectedIndex == 2 && !didPop) {
          final now = DateTime.now();
          if (_lastBackPressTime == null || 
              now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
            // First back press - show message and record time
            _lastBackPressTime = now;
            ToastService.showInfoFromContext(context, 'Press back again to exit', duration: const Duration(seconds: 2));
          } else {
            // Second back press within 2 seconds - exit app
            SystemNavigator.pop();
          }
        }
      },
      child: GradientBackground(
        child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.transparent,
        drawer: _buildDrawer(),
        body: IndexedStack(
          index: _selectedIndex,
          children: [
            TransactionsScreen(
              onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
              onNavigateToDashboard: () {
                setState(() {
                  _selectedIndex = 2; // Navigate to Dashboard
                });
              },
            ), // Transactions tab (index 0)
            ContactsScreen(
              onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
              onNavigateToDashboard: () {
                setState(() {
                  _selectedIndex = 2; // Navigate to Dashboard
                });
              },
            ), // Contacts tab (index 1)
            DashboardScreen(
              onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
            ), // Dashboard tab (index 2)
          ],
        ),
        floatingActionButton: _buildFloatingActionButton(),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
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
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long),
                  label: 'Transactions',
                ),
                NavigationDestination(
                  icon: Icon(Icons.contacts_outlined),
                  selectedIcon: Icon(Icons.contacts),
                  label: 'Contacts',
                ),
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard),
                  label: 'Dashboard',
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  String _getAppBarTitle() {
    switch (_selectedIndex) {
      case 0:
        return 'Transactions';
      case 1:
        return 'Contacts';
      case 2:
        return 'Dashboard';
      default:
        return 'Debt Tracker';
    }
  }

  Widget? _buildFloatingActionButton() {
    // All tabs: Click = transaction, Long press = contact
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0), // Raise the FAB position
      child: Semantics(
        button: true,
        label: 'Add transaction (tap) or contact (long press)',
        child: GestureDetector(
          onLongPress: _showAddContactDialog,
          child: Tooltip(
            message: 'Add Transaction (tap) or Contact (long press)',
            child: FloatingActionButton(
              onPressed: _showAddTransactionDialog,
              child: const Icon(Icons.add),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.primaryContainer,
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(
                  Icons.settings,
                  size: 48,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
                const SizedBox(height: 8),
                Text(
                  'Settings',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Events Log
          ListTile(
            leading: const Icon(Icons.event_note),
            title: const Text('Events Log'),
            subtitle: const Text('View all local events'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const EventsLogScreen(),
                ),
              );
            },
          ),
          const Divider(),
          // Settings content (without Scaffold wrapper)
          const _SettingsContent(),
        ],
      ),
    );
  }

  void _showAddTransactionDialog() {
    showScreenAsBottomSheet(
      context: context,
      screen: const AddTransactionScreen(),
    );
  }

  void _showAddContactDialog() {
    showScreenAsBottomSheet(
      context: context,
      screen: const AddContactScreen(),
    );
  }
}

// Extracted settings content for drawer
class _SettingsContent extends ConsumerStatefulWidget {
  const _SettingsContent();

  @override
  ConsumerState<_SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends ConsumerState<_SettingsContent> {
  bool _darkMode = true;
  String _defaultDirection = 'give';
  int _defaultDueDateDays = 30;
  bool _defaultDueDateSwitch = false;
  String _backendIp = '';
  int _backendPort = 8000;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final darkMode = await SettingsService.getDarkMode();
    final defaultDir = await SettingsService.getDefaultDirection();
    final defaultDays = await SettingsService.getDefaultDueDateDays();
    final defaultDueDateSwitch = await SettingsService.getDefaultDueDateSwitch();
    final backendIp = await BackendConfigService.getBackendIp();
    final backendPort = await BackendConfigService.getBackendPort();
    
    if (mounted) {
      setState(() {
        _darkMode = darkMode;
        _defaultDirection = defaultDir;
        _defaultDueDateDays = defaultDays;
        _defaultDueDateSwitch = defaultDueDateSwitch;
        _backendIp = backendIp;
        _backendPort = backendPort;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Appearance
        _buildSectionHeader('Appearance'),
        SwitchListTile(
          title: const Text('Dark Mode'),
          value: _darkMode,
          onChanged: (value) async {
            await SettingsService.setDarkMode(value);
            setState(() {
              _darkMode = value;
            });
            if (mounted) {
              (context as Element).markNeedsBuild();
            }
          },
        ),
        
        // Transaction Defaults
        _buildSectionHeader('Transaction Defaults'),
        ListTile(
          title: const Text('Default Direction'),
          subtitle: Text(_defaultDirection == 'give' ? 'Give' : 'Received'),
          trailing: DropdownButton<String>(
            value: _defaultDirection,
            items: const [
              DropdownMenuItem(value: 'give', child: Text('Give')),
              DropdownMenuItem(value: 'received', child: Text('Received')),
            ],
            onChanged: (value) async {
              if (value != null) {
                await SettingsService.setDefaultDirection(value);
                setState(() {
                  _defaultDirection = value;
                });
              }
            },
          ),
        ),
        Consumer(
          builder: (context, ref, child) {
            final flipColors = ref.watch(flipColorsProvider);
            final giveColor = flipColors ? Colors.red : Colors.green;
            final receivedColor = flipColors ? Colors.green : Colors.red;
            
            return SwitchListTile(
              title: const Text('Flip Colors'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Swap green/red for give/received'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: giveColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.grey, width: 1),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('Give', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 16),
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: receivedColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.grey, width: 1),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('Received', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ],
              ),
              value: flipColors,
              onChanged: (value) async {
                await ref.read(flipColorsProvider.notifier).setFlipColors(value);
              },
            );
          },
        ),
        
        // Due Date Settings
        _buildSectionHeader('Due Date'),
        Consumer(
          builder: (context, ref, child) {
            final dueDateEnabled = ref.watch(dueDateEnabledProvider);
            return Column(
              children: [
                SwitchListTile(
                  title: const Text('Enable Due Dates'),
                  subtitle: const Text('Show due dates on dashboard'),
                  value: dueDateEnabled,
                  onChanged: (value) async {
                    await ref.read(dueDateEnabledProvider.notifier).setDueDateEnabled(value);
                  },
                ),
                if (dueDateEnabled) ...[
                  SwitchListTile(
                    title: const Text('Default Due Date Switch'),
                    subtitle: const Text('Due date switch default state in transaction form'),
                    value: _defaultDueDateSwitch,
                    onChanged: (value) async {
                      await SettingsService.setDefaultDueDateSwitch(value);
                      setState(() {
                        _defaultDueDateSwitch = value;
                      });
                    },
                  ),
                  ListTile(
                    title: const Text('Default Due Date (Days)'),
                    subtitle: Text('$_defaultDueDateDays days from transaction date'),
                    trailing: SizedBox(
                      width: 100,
                      child: TextField(
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.right,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                        ),
                        controller: TextEditingController(text: _defaultDueDateDays.toString()),
                        onSubmitted: (value) async {
                          final days = int.tryParse(value) ?? 30;
                          await SettingsService.setDefaultDueDateDays(days);
                          setState(() {
                            _defaultDueDateDays = days;
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
        
        // Graph Settings
        _buildSectionHeader('Graphs'),
        Consumer(
          builder: (context, ref, child) {
            final showChart = ref.watch(showDashboardChartProvider);
            return SwitchListTile(
              title: const Text('Show Dashboard Chart'),
              subtitle: const Text('Display debt over time chart on dashboard'),
              value: showChart,
              onChanged: (value) async {
                await ref.read(showDashboardChartProvider.notifier).setShowDashboardChart(value);
              },
            );
          },
        ),
        FutureBuilder<String>(
          future: SettingsService.getDashboardDefaultPeriod(),
          builder: (context, snapshot) {
            final period = snapshot.data ?? 'month';
            // If period is 'day', reset to 'month'
            final safePeriod = period == 'day' ? 'month' : period;
            if (period == 'day') {
              // Reset to month if day was selected
              SettingsService.setDashboardDefaultPeriod('month');
            }
            return ListTile(
              title: const Text('Dashboard Default Period'),
              subtitle: Text(_getPeriodLabel(safePeriod)),
              trailing: DropdownButton<String>(
                value: safePeriod,
                items: const [
                  DropdownMenuItem(value: 'week', child: Text('Week')),
                  DropdownMenuItem(value: 'month', child: Text('Month')),
                  DropdownMenuItem(value: 'year', child: Text('Year')),
                ],
                onChanged: (value) async {
                  if (value != null) {
                    // Update the provider which will also save to service
                    await ref.read(dashboardDefaultPeriodProvider.notifier).setDashboardDefaultPeriod(value);
                    setState(() {});
                  }
                },
              ),
            );
          },
        ),
        FutureBuilder<String>(
          future: SettingsService.getGraphDefaultPeriod(),
          builder: (context, snapshot) {
            final period = snapshot.data ?? 'month';
            // If period is 'day', reset to 'month'
            final safePeriod = period == 'day' ? 'month' : period;
            if (period == 'day') {
              // Reset to month if day was selected
              SettingsService.setGraphDefaultPeriod('month');
            }
            return ListTile(
              title: const Text('Graph Page Default Period'),
              subtitle: Text(_getPeriodLabel(safePeriod)),
              trailing: DropdownButton<String>(
                value: safePeriod,
                items: const [
                  DropdownMenuItem(value: 'week', child: Text('Week')),
                  DropdownMenuItem(value: 'month', child: Text('Month')),
                  DropdownMenuItem(value: 'year', child: Text('Year')),
                ],
                onChanged: (value) async {
                  if (value != null) {
                    await SettingsService.setGraphDefaultPeriod(value);
                    setState(() {});
                  }
                },
              ),
            );
          },
        ),
        Consumer(
          builder: (context, ref, child) {
            final invertY = ref.watch(invertYAxisProvider);
            return SwitchListTile(
              title: const Text('Invert Y-Axis'),
              subtitle: const Text('Reverse Y-axis orientation (larger values at bottom)'),
              value: invertY,
              onChanged: (value) async {
                await ref.read(invertYAxisProvider.notifier).setInvertYAxis(value);
              },
            );
          },
        ),
        
        // Backend Configuration
        _buildSectionHeader('Backend Configuration'),
        ListTile(
          title: const Text('Change Backend Settings'),
          subtitle: const Text('Update server IP and port'),
          leading: const Icon(Icons.settings_ethernet),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _navigateToBackendSetup(),
        ),
        
        // Account
        _buildSectionHeader('Account'),
        ListTile(
          title: const Text('Logout'),
          leading: const Icon(Icons.logout, color: Colors.red),
          onTap: () => _handleLogout(),
        ),
      ],
    );
  }

  String _getPeriodLabel(String period) {
    switch (period) {
      case 'week':
        return 'Last 7 days';
      case 'month':
        return 'Last 30 days';
      case 'year':
        return 'Last 365 days';
      default:
        return 'Last 30 days';
    }
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  void _showBackendConfigDialog() {
    showDialog(
      context: context,
      builder: (context) => _BackendConfigDialog(
        currentIp: _backendIp,
        currentPort: _backendPort,
        onSaved: () async {
          await _loadSettings();
          if (!mounted) return;
          Navigator.of(context).pop();
        },
      ),
    );
  }

  void _navigateToBackendSetup() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const BackendSetupScreen(),
      ),
    ).then((_) async {
      // Reload settings after returning from setup screen
      await _loadSettings();
    });
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await AuthService.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (Route<dynamic> route) => false,
      );
    }
  }
}

// Dialog for quick backend config edit
class _BackendConfigDialog extends StatefulWidget {
  final String currentIp;
  final int currentPort;
  final VoidCallback onSaved;

  const _BackendConfigDialog({
    required this.currentIp,
    required this.currentPort,
    required this.onSaved,
  });

  @override
  State<_BackendConfigDialog> createState() => _BackendConfigDialogState();
}

class _BackendConfigDialogState extends State<_BackendConfigDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _ipController;
  late TextEditingController _portController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController(text: widget.currentIp);
    _portController = TextEditingController(text: widget.currentPort.toString());
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
    });

    try {
      final ip = _ipController.text.trim();
      final port = int.parse(_portController.text.trim());
      
      await BackendConfigService.setBackendConfig(ip, port);
      
      if (mounted) {
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        ToastService.showErrorFromContext(context, 'Error saving configuration: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Backend Configuration'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _ipController,
              decoration: const InputDecoration(
                labelText: 'Server IP',
                hintText: 'e.g., 192.168.1.100 or localhost',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter server IP';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _portController,
              decoration: const InputDecoration(
                labelText: 'Port',
                hintText: 'e.g., 8000',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter port number';
                }
                final port = int.tryParse(value);
                if (port == null || port < 1 || port > 65535) {
                  return 'Please enter a valid port (1-65535)';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _handleSave,
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}