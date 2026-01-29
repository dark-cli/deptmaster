import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/settings_service.dart';
import '../providers/settings_provider.dart';
import '../utils/app_colors.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _darkMode = true; // Default to dark mode
  String _defaultDirection = 'give';
  // ignore: unused_field
  bool _dueDateEnabled = false;
  int _defaultDueDateDays = 30;
  bool _defaultDueDateSwitch = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final darkMode = await SettingsService.getDarkMode();
    final defaultDir = await SettingsService.getDefaultDirection();
    await SettingsService.getFlipColors();
    final dueDateEnabled = await SettingsService.getDueDateEnabled();
    final defaultDays = await SettingsService.getDefaultDueDateDays();
    final defaultDueDateSwitch = await SettingsService.getDefaultDueDateSwitch();
    
    if (mounted) {
      setState(() {
        _darkMode = darkMode;
        _defaultDirection = defaultDir;
        _dueDateEnabled = dueDateEnabled;
        _defaultDueDateDays = defaultDays;
        _defaultDueDateSwitch = defaultDueDateSwitch;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
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
              // Trigger theme rebuild
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
              final isDark = Theme.of(context).brightness == Brightness.dark;
              // Standardized colors: Received = green (positive), Gave = red (negative)
              final gaveColor = AppColors.getGiveColor(flipColors, isDark);
              final receivedColor = AppColors.getReceivedColor(flipColors, isDark);
              
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
                            color: gaveColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.grey, width: 1),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '(-) Gave',
                          style: TextStyle(
                            fontSize: 12,
                            color: gaveColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
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
                        Text(
                          '(+) Received',
                          style: TextStyle(
                            fontSize: 12,
                            color: receivedColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
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
          SwitchListTile(
            title: const Text('Enable Due Dates'),
            subtitle: const Text('Show due dates on dashboard'),
            value: _dueDateEnabled,
            onChanged: (value) async {
              await SettingsService.setDueDateEnabled(value);
              setState(() {
                _dueDateEnabled = value;
              });
            },
          ),
          if (_dueDateEnabled) ...[
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
        ],
      ),
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
}