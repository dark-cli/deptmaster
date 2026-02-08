import 'package:flutter/material.dart';
import '../api.dart';
import '../utils/text_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/contact.dart';
import '../models/transaction.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../providers/settings_provider.dart';
import '../providers/wallet_data_providers.dart';
import '../utils/app_colors.dart';
import '../utils/theme_colors.dart';
import '../widgets/empty_state.dart';
import '../widgets/gradient_card.dart';
import '../widgets/sync_status_icon.dart';
import '../widgets/debt_chart_widget.dart';
import '../widgets/animated_pixelated_text.dart';
import 'contact_transactions_screen.dart';
import 'add_transaction_screen.dart';
import 'debt_chart_detail_screen.dart';
import '../utils/bottom_sheet_helper.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  final VoidCallback? onOpenDrawer;
  
  const DashboardScreen({super.key, this.onOpenDrawer});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  List<Contact> _lastValidContacts = [];
  List<Transaction> _lastValidTransactions = [];

  @override
  void initState() {
    super.initState();
    _ensureWallet();
    Api.connectRealtime();
  }

  Future<void> _ensureWallet() async {
    if (kIsWeb) return;
    try {
      // Ensure we have a current wallet when we have wallets (e.g. ensureCurrentWallet failed at startup)
      if (await Api.getCurrentWalletId() == null) {
        final list = await Api.getWallets();
        if (list.isNotEmpty && list.first['id'] != null) {
          await Api.setCurrentWalletId(list.first['id'] as String);
        }
      }
    } catch (_) {}
  }

  int _calculateTotalBalance(List<Contact> contacts) {
    return contacts.fold<int>(0, (sum, contact) => sum + contact.balance);
  }

  List<Transaction> _getUpcomingDueDates(List<Transaction> transactions) {
    // Don't check _dueDateEnabled here - let the UI decide whether to show
    
    final now = DateTime.now();
    // Get all due dates: overdue or within next 30 days
    final upcoming = transactions
        .where((t) => t.dueDate != null && 
                      (t.dueDate!.isBefore(now) || // Include overdue
                       (t.dueDate!.isAfter(now) && t.dueDate!.difference(now).inDays <= 30))) // Or within 30 days
        .toList();
    
    // Sort: overdue first (most overdue first), then upcoming (soonest first)
    upcoming.sort((a, b) {
      final aDays = a.dueDate!.difference(now).inDays;
      final bDays = b.dueDate!.difference(now).inDays;
      // If both overdue or both upcoming, sort by date
      if ((aDays < 0 && bDays < 0) || (aDays >= 0 && bDays >= 0)) {
        return a.dueDate!.compareTo(b.dueDate!);
      }
      // Overdue comes before upcoming
      return aDays < 0 ? -1 : 1;
    });
    return upcoming.take(10).toList(); // Limit to top 10
  }

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(contactsProvider);
    final transactionsAsync = ref.watch(transactionsProvider);
    
    if (contactsAsync.hasValue) {
      _lastValidContacts = contactsAsync.value!;
    }
    if (transactionsAsync.hasValue) {
      _lastValidTransactions = transactionsAsync.value!;
    }
    
    final contacts = contactsAsync.valueOrNull ?? _lastValidContacts;
    final transactions = transactionsAsync.valueOrNull ?? _lastValidTransactions;

    // Watch due date enabled setting
    final dueDateEnabled = ref.watch(dueDateEnabledProvider);
    
    final loading = (contactsAsync.isLoading || transactionsAsync.isLoading) &&
        (contacts.isEmpty && transactions.isEmpty); // Only show loader if we have NO data at all
    if (loading) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final totalBalance = _calculateTotalBalance(contacts);
    final upcomingDueDates = _getUpcomingDueDates(transactions);
    final contactMap = contacts.isNotEmpty ? Map.fromEntries(contacts.map((c) => MapEntry(c.id, c))) : <String, Contact>{};

    if (contacts.isEmpty && transactions.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Dashboard'),
          leading: widget.onOpenDrawer != null
              ? IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: widget.onOpenDrawer,
                )
              : null,
          actions: const [
            Padding(
              padding: EdgeInsets.only(left: 24.0, right: 20.0),
              child: SyncStatusIcon(),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            await Api.refreshConnectionAndSync();
            ref.invalidate(contactsProvider);
            ref.invalidate(transactionsProvider);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.75,
              child: const EmptyState(
                icon: Icons.dashboard_outlined,
                title: 'Nothing here yet',
                subtitle: 'Add contacts and transactions to see your dashboard.',
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Dashboard'),
        leading: widget.onOpenDrawer != null
            ? IconButton(
                icon: const Icon(Icons.menu),
                onPressed: widget.onOpenDrawer,
              )
            : null,
        actions: const [
          Padding(
            padding: EdgeInsets.only(left: 24.0, right: 20.0),
            child: SyncStatusIcon(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Api.refreshConnectionAndSync();
          ref.invalidate(contactsProvider);
          ref.invalidate(transactionsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            // Stats Cards
            _buildStatsCard(
              context,
              totalBalance,
              contactCount: contacts.length,
              transactionCount: transactions.length,
            ),
            const SizedBox(height: 16),
            
            // Debt Over Time Chart (Simple) - only show if enabled
            Consumer(
              builder: (context, ref, child) {
                final showChart = ref.watch(showDashboardChartProvider);
                if (!showChart) {
                  return const SizedBox.shrink();
                }
                return Column(
                  children: [
                    DebtChartWidget(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const DebtChartDetailScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                );
              },
            ),
            
            // Balance Chart
            if (contacts.isNotEmpty) ...[
              _buildBalanceChart(context, contacts),
              const SizedBox(height: 16),
            ],
            
            // Upcoming Due Dates (show if enabled, even if empty)
            if (dueDateEnabled) ...[
              if (upcomingDueDates.isNotEmpty) ...[
                _buildDueDatesSection(context, upcomingDueDates, contactMap, 'Payment Reminders'),
                const SizedBox(height: 16),
              ] else ...[
                GradientCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Payment Reminders',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No upcoming payments in the next 30 days',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey,
                        ),
                      ),
                    ],
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

  Widget _buildStatsCard(
    BuildContext context,
    int totalBalance, {
    required int contactCount,
    required int transactionCount,
  }) {
    return Consumer(
      builder: (context, ref, child) {
        final flipColors = ref.watch(flipColorsProvider);
        final formatted = totalBalance.abs().toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        );
        final balanceText = totalBalance < 0 ? '-$formatted' : '$formatted';
        final isDark = Theme.of(context).brightness == Brightness.dark;
        // Standardized: Positive balance = Gave (green), Negative balance = Received (red)
        final balanceColor = totalBalance >= 0
            ? AppColors.getGiveColor(flipColors, isDark) // Positive = Gave = green
            : AppColors.getReceivedColor(flipColors, isDark); // Negative = Received = red
        
        return GradientCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TOTAL BALANCE',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 8),
              AnimatedPixelatedText(
                '$balanceText IQD',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: balanceColor,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem(context, 'Contacts', contactCount),
                  _buildStatItem(context, 'Transactions', transactionCount),
                ],
              ),
            ],
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
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  Widget _buildBalanceChart(BuildContext context, List<Contact> contacts) {
    if (contacts.isEmpty) return const SizedBox.shrink();
    
    return Consumer(
      builder: (context, ref, child) {
        final flipColors = ref.watch(flipColorsProvider);
        final positiveBalances = contacts.where((c) => c.balance > 0).toList();
        final negativeBalances = contacts.where((c) => c.balance < 0).toList();
        
        positiveBalances.sort((a, b) => b.balance.compareTo(a.balance));
        negativeBalances.sort((a, b) => a.balance.compareTo(b.balance));
        
        final topDebts = negativeBalances.take(5).toList();
        final topCredits = positiveBalances.take(5).toList();
        
        final isDark = Theme.of(context).brightness == Brightness.dark;
        // Standardized: Debts (negative balance, you owe) = Received = red, Credits (positive balance, they owe you) = Gave = green
        final debtColor = AppColors.getReceivedColor(flipColors, isDark); // Debts = Received = red
        final creditColor = AppColors.getGiveColor(flipColors, isDark); // Credits = Gave = green
        
        return GradientCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Outstanding Balances',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  // Stack vertically on small screens (width < 600)
                  final isSmallScreen = constraints.maxWidth < 600;
                  
                  return isSmallScreen
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDebtsColumn(context, topDebts, debtColor, flipColors, isDark),
                            const SizedBox(height: 24),
                            _buildCreditsColumn(context, topCredits, creditColor, flipColors, isDark),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _buildDebtsColumn(context, topDebts, debtColor, flipColors, isDark),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: _buildCreditsColumn(context, topCredits, creditColor, flipColors, isDark),
                            ),
                          ],
                        );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDebtsColumn(BuildContext context, List<Contact> topDebts, Color debtColor, bool flipColors, bool isDark) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
                      Text(
                        'Gave',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
          const SizedBox(height: 8),
                      ...topDebts.map((contact) {
                        final amount = contact.balance.abs();
                        final formatted = amount.toString().replaceAllMapped(
                          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                          (Match m) => '${m[1]},',
                        );
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ContactTransactionsScreen(contact: contact),
                                ),
                              );
                            },
                            onLongPress: () {
                              // Open close debt screen with reverse transaction
                              showScreenAsBottomSheet(
                                context: context,
                                screen: AddTransactionScreenWithData(
                                  contact: contact,
                                  amount: amount, // The absolute balance amount
                                  direction: TransactionDirection.lent, // Reverse direction to close debt
                                  description: 'Close debt',
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                              child: Row(
                                children: [
                                  Container(
                                    width: 4,
                                    height: 16,
                                    color: debtColor,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          TextUtils.forceLtr(contact.name),
                                          style: Theme.of(context).textTheme.bodySmall,
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                        if (contact.username != null && contact.username!.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            '@${contact.username}',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              color: ThemeColors.gray(context, shade: 500),
                                              fontSize: 10,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                          Flexible(
                            child: AnimatedPixelatedText(
                              '$formatted IQD',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: debtColor,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  );
  }

  Widget _buildCreditsColumn(BuildContext context, List<Contact> topCredits, Color creditColor, bool flipColors, bool isDark) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
                      Text(
                        'Received',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
          const SizedBox(height: 8),
          ...topCredits.map((contact) {
                        final amount = contact.balance;
                        final formatted = amount.toString().replaceAllMapped(
                          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                          (Match m) => '${m[1]},',
                        );
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ContactTransactionsScreen(contact: contact),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                              child: Row(
                                children: [
                                  Container(
                                    width: 4,
                                    height: 16,
                                    color: creditColor,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          TextUtils.forceLtr(contact.name),
                                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.w500,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                        if (contact.username != null && contact.username!.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            '@${contact.username}',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              color: ThemeColors.gray(context, shade: 500),
                                              fontSize: 12,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                          Flexible(
                            child: AnimatedPixelatedText(
                              '$formatted IQD',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: creditColor,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  );
  }

  Widget _buildDueDatesSection(
    BuildContext context,
    List<Transaction> upcoming,
    Map<String, Contact> contactMap,
    String title,
  ) {
    return Consumer(
      builder: (context, ref, child) {
        final warningColor = ThemeColors.warning(context);
        final errorColor = ThemeColors.error(context);
        
        return GradientCard(
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
              const SizedBox(height: 16),
              ...upcoming.map((transaction) {
                final contact = contactMap[transaction.contactId];
                final daysUntil = transaction.dueDate!.difference(DateTime.now()).inDays;
                final isOverdue = daysUntil < 0;
                final statusColor = isOverdue ? errorColor : warningColor;
                final formattedAmount = transaction.getFormattedAmount(2);
                final formattedDate = DateFormat('MMM d, y').format(transaction.dueDate!);
                final statusText = isOverdue ? 'Overdue' : '$daysUntil days';
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    onTap: () {
                      if (contact != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ContactTransactionsScreen(contact: contact),
                          ),
                        );
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 4,
                            height: 16,
                            color: statusColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  TextUtils.forceLtr(contact?.name ?? 'Unknown'),
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                                if (contact?.username != null && contact!.username!.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    '@${contact.username}',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: ThemeColors.gray(context, shade: 500),
                                      fontSize: 12,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ],
                                const SizedBox(height: 2),
                                AnimatedPixelatedText(
                                  '$formattedAmount • $formattedDate',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: ThemeColors.gray(context, shade: 600),
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              statusText,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}
