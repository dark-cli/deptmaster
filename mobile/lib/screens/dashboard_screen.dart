import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../utils/text_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/contact.dart';
import '../models/transaction.dart';
import '../services/api_service.dart';
import '../services/realtime_service.dart';
import '../services/settings_service.dart';
import '../providers/settings_provider.dart';
import '../utils/app_colors.dart';
import '../utils/theme_colors.dart';
import 'contact_transactions_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  List<Contact>? _contacts;
  List<Transaction>? _transactions;
  bool _loading = true;
  bool _dueDateEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    RealtimeService.addListener(_onRealtimeUpdate);
    RealtimeService.connect();
    _loadSettings();
  }

  void _onRealtimeUpdate(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    if (type == 'contact_created' || type == 'contact_updated' ||
        type == 'transaction_created' || type == 'transaction_updated' ||
        type == 'transaction_deleted') {
      _loadData();
    }
  }

  Future<void> _loadSettings() async {
    final enabled = await SettingsService.getDueDateEnabled();
    if (mounted) {
      setState(() {
        _dueDateEnabled = enabled;
      });
      // Reload data after settings change to show/hide due dates
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
    });

    try {
      final contacts = await ApiService.getContacts();
      final transactions = await ApiService.getTransactions();
      
      if (mounted) {
        setState(() {
          _contacts = contacts;
          _transactions = transactions;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  int _calculateTotalBalance() {
    if (_contacts == null) return 0;
    return _contacts!.fold<int>(0, (sum, contact) => sum + contact.balance);
  }

  List<Transaction> _getUpcomingDueDates() {
    if (_transactions == null) return [];
    // Don't check _dueDateEnabled here - let the UI decide whether to show
    
    final now = DateTime.now();
    // Get all upcoming due dates (not overdue, within next 30 days)
    final upcoming = _transactions!
        .where((t) => t.dueDate != null && 
                      t.dueDate!.isAfter(now) && 
                      t.dueDate!.difference(now).inDays <= 30)
        .toList();
    
    upcoming.sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
    return upcoming.take(5).toList(); // Limit to top 5
  }

  @override
  void dispose() {
    RealtimeService.removeListener(_onRealtimeUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final totalBalance = _calculateTotalBalance();
    final upcomingDueDates = _getUpcomingDueDates();
    final contactMap = _contacts != null
        ? Map.fromEntries(_contacts!.map((c) => MapEntry(c.id, c)))
        : <String, Contact>{};
    
    // Debug: Print due dates info
    print('🔍 Dashboard Debug:');
    print('  Due Date Enabled: $_dueDateEnabled');
    print('  Total Transactions: ${_transactions?.length ?? 0}');
    final transactionsWithDueDates = _transactions?.where((t) => t.dueDate != null).toList() ?? [];
    print('  Transactions with due dates: ${transactionsWithDueDates.length}');
    if (transactionsWithDueDates.isNotEmpty) {
      for (var t in transactionsWithDueDates.take(5)) {
        print('    - ${t.id}: due_date=${t.dueDate}, days_until=${t.dueDate?.difference(DateTime.now()).inDays}');
      }
    }
    print('  Upcoming Due Dates: ${upcomingDueDates.length}');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Stats Cards
            _buildStatsCard(context, totalBalance),
            const SizedBox(height: 16),
            
            // Balance Chart
            if (_contacts != null && _contacts!.isNotEmpty) ...[
              _buildBalanceChart(context),
              const SizedBox(height: 16),
            ],
            
            // Upcoming Due Dates (show if enabled, even if empty)
            if (_dueDateEnabled) ...[
              if (upcomingDueDates.isNotEmpty) ...[
                _buildDueDatesSection(context, upcomingDueDates, contactMap, 'Upcoming Due Dates'),
                const SizedBox(height: 16),
              ] else ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Upcoming Due Dates',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No upcoming due dates in the next 30 days',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard(BuildContext context, int totalBalance) {
    return Consumer(
      builder: (context, ref, child) {
        final flipColors = ref.watch(flipColorsProvider);
        final formatted = totalBalance.abs().toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        );
        final balanceText = totalBalance < 0 ? '-$formatted' : '$formatted';
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final balanceColor = totalBalance < 0
            ? AppColors.getReceivedColor(flipColors, isDark)
            : AppColors.getGiveColor(flipColors, isDark);
        
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TOTAL BALANCE',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '$balanceText IQD',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: balanceColor,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem(context, 'Contacts', _contacts?.length ?? 0),
                    _buildStatItem(context, 'Transactions', _transactions?.length ?? 0),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatItem(BuildContext context, String label, int value) {
    return Column(
      children: [
        Text(
          value.toString(),
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildBalanceChart(BuildContext context) {
    if (_contacts == null || _contacts!.isEmpty) return const SizedBox.shrink();
    
    return Consumer(
      builder: (context, ref, child) {
        final flipColors = ref.watch(flipColorsProvider);
        final positiveBalances = _contacts!.where((c) => c.balance > 0).toList();
        final negativeBalances = _contacts!.where((c) => c.balance < 0).toList();
        
        positiveBalances.sort((a, b) => b.balance.compareTo(a.balance));
        negativeBalances.sort((a, b) => a.balance.compareTo(b.balance));
        
        final topDebts = negativeBalances.take(5).toList();
        final topCredits = positiveBalances.take(5).toList();
        
        final isDark = Theme.of(context).brightness == Brightness.dark;
        // Apply flip colors: debts should be opposite of credits
        final debtColor = AppColors.getReceivedColor(flipColors, isDark);
        final creditColor = AppColors.getGiveColor(flipColors, isDark);
        
        return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Top Debts & Credits',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Top Debts',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      ...topDebts.map((contact) {
                        final amount = contact.balance.abs();
                        final formatted = amount.toString().replaceAllMapped(
                          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                          (Match m) => '${m[1]},',
                        );
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Container(
                                width: 4,
                                height: 16,
                                color: debtColor,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  TextUtils.forceLtr(contact.name), // Force LTR for mixed Arabic/English text
                                  style: Theme.of(context).textTheme.bodySmall,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '$formatted IQD',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: debtColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Top Credits',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      ...topCredits.map((contact) {
                        final amount = contact.balance;
                        final formatted = amount.toString().replaceAllMapped(
                          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                          (Match m) => '${m[1]},',
                        );
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Container(
                                width: 4,
                                height: 16,
                                color: creditColor,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  TextUtils.forceLtr(contact.name), // Force LTR for mixed Arabic/English text
                                  style: Theme.of(context).textTheme.bodySmall,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '$formatted IQD',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: creditColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
      },
    );
  }

  Widget _buildDueDatesSection(
    BuildContext context,
    List<Transaction> upcoming,
    Map<String, Contact> contactMap,
    String title,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ...upcoming.map((transaction) {
              final contact = contactMap[transaction.contactId];
              final daysUntil = transaction.dueDate!.difference(DateTime.now()).inDays;
              final isOverdue = daysUntil < 0;
              
              return ListTile(
                leading: CircleAvatar(
                  child: Text(contact?.name[0] ?? '?'),
                ),
                title: Text(contact?.name ?? 'Unknown'),
                subtitle: Text(
                  '${transaction.getFormattedAmount(2)} • ${DateFormat('MMM d, y').format(transaction.dueDate!)}',
                ),
                trailing: Chip(
                  label: Text(
                    isOverdue ? 'Overdue' : '$daysUntil days',
                    style: TextStyle(
                      color: isOverdue ? ThemeColors.error(context) : ThemeColors.warning(context),
                      fontSize: 12,
                    ),
                  ),
                  backgroundColor: isOverdue 
                      ? ThemeColors.error(context).withOpacity(0.1)
                      : ThemeColors.warning(context).withOpacity(0.1),
                ),
                onTap: () {
                  if (contact != null) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => ContactTransactionsScreen(contact: contact),
                      ),
                    );
                  }
                },
              );
            }),
          ],
        ),
      ),
    );
  }

}
