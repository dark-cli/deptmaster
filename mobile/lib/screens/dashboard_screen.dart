import 'package:flutter/material.dart';
import '../utils/text_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/contact.dart';
import '../models/transaction.dart';
import '../services/realtime_service.dart';
import '../services/local_database_service_v2.dart';
import '../services/sync_service_v2.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive_flutter/hive_flutter.dart';
import '../services/dummy_data_service.dart';
import '../services/auth_service.dart';
import '../services/wallet_service.dart';
import '../providers/settings_provider.dart';
import '../utils/app_colors.dart';
import '../utils/theme_colors.dart';
import '../widgets/gradient_card.dart';
import '../widgets/sync_status_icon.dart';
import '../widgets/debt_chart_widget.dart';
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
  List<Contact>? _contacts;
  List<Transaction>? _transactions;
  bool _loading = true;
  Box<Contact>? _contactsBox;
  Box<Transaction>? _transactionsBox;

  @override
  void initState() {
    super.initState();
    _loadData();
    RealtimeService.addListener(_onRealtimeUpdate);
    RealtimeService.connect();
    _setupLocalListeners();
  }

  void _setupLocalListeners() {
    if (kIsWeb) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final userId = await AuthService.getUserId();
      final walletId = WalletService.getCurrentWalletId();
      if (userId == null || walletId == null || !mounted) return;
      final contactsBoxName = DummyDataService.getContactsBoxName(userId: userId, walletId: walletId);
      final transactionsBoxName = DummyDataService.getTransactionsBoxName(userId: userId, walletId: walletId);
      await Hive.openBox<Contact>(contactsBoxName);
      await Hive.openBox<Transaction>(transactionsBoxName);
      if (!mounted) return;
      final contactsBox = Hive.box<Contact>(contactsBoxName);
      final transactionsBox = Hive.box<Transaction>(transactionsBoxName);
      contactsBox.listenable().addListener(_onLocalDataChanged);
      transactionsBox.listenable().addListener(_onLocalDataChanged);
      setState(() {
        _contactsBox = contactsBox;
        _transactionsBox = transactionsBox;
      });
    });
  }

  void _onLocalDataChanged() {
    // Reload data when local database changes (works offline)
    if (mounted) {
      _loadData();
    }
  }

  void _onRealtimeUpdate(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    if (type == 'contact_created' || type == 'contact_updated' ||
        type == 'transaction_created' || type == 'transaction_updated' ||
        type == 'transaction_deleted') {
      _loadData();
    }
  }

  @override
  void dispose() {
    if (!kIsWeb && _contactsBox != null && _transactionsBox != null) {
      _contactsBox!.listenable().removeListener(_onLocalDataChanged);
      _transactionsBox!.listenable().removeListener(_onLocalDataChanged);
    }
    RealtimeService.removeListener(_onRealtimeUpdate);
    super.dispose();
  }

  Future<void> _loadData({bool sync = false}) async {
    setState(() {
      _loading = true;
    });

    try {
      // Local-first: read from local database (instant, snappy)
      List<Contact> contacts;
      List<Transaction> transactions;
      
      // Always use local database - never call API from UI
      contacts = await LocalDatabaseServiceV2.getContacts();
      transactions = await LocalDatabaseServiceV2.getTransactions();
      
      // If sync requested, do full sync in background
      if (sync && !kIsWeb) {
        SyncServiceV2.onPullToRefresh(); // Reset backoff and start sync
      }
      
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
    // Get all due dates: overdue or within next 30 days
    final upcoming = _transactions!
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
    // Watch due date enabled setting
    final dueDateEnabled = ref.watch(dueDateEnabledProvider);
    
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

    return Scaffold(
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
        onRefresh: () => _loadData(sync: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            // Stats Cards
            _buildStatsCard(context, totalBalance),
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
            if (_contacts != null && _contacts!.isNotEmpty) ...[
              _buildBalanceChart(context),
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
              Text(
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
                  _buildStatItem(context, 'Contacts', _contacts?.length ?? 0),
                  _buildStatItem(context, 'Transactions', _transactions?.length ?? 0),
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
                                    child: Text(
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
                                    child: Text(
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
                                Text(
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
