// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debt_tracker_mobile/main.dart';
import 'package:debt_tracker_mobile/models/contact.dart';
import 'package:debt_tracker_mobile/models/transaction.dart';
import 'package:debt_tracker_mobile/models/event.dart';
import 'package:debt_tracker_mobile/models/wallet.dart';
import 'package:debt_tracker_mobile/services/event_store_service.dart';
import 'package:debt_tracker_mobile/services/wallet_service.dart';
import 'package:debt_tracker_mobile/services/dummy_data_service.dart';
import 'package:debt_tracker_mobile/services/local_database_service_v2.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'current_wallet_id': 'test-wallet-id'});
    Hive.init('./test/hive_test_data_widget');
    Hive.registerAdapter(ContactAdapter());
    Hive.registerAdapter(TransactionAdapter());
    Hive.registerAdapter(TransactionTypeAdapter());
    Hive.registerAdapter(TransactionDirectionAdapter());
    Hive.registerAdapter(EventAdapter());
    Hive.registerAdapter(WalletAdapter());
    await Hive.openBox<Contact>(DummyDataService.contactsBoxName);
    await Hive.openBox<Transaction>(DummyDataService.transactionsBoxName);
    await Hive.openBox<Wallet>('wallets');
    await EventStoreService.initialize();
    await WalletService.initialize();
    await LocalDatabaseServiceV2.initialize();
    final walletsBox = Hive.box<Wallet>('wallets');
    final now = DateTime.now();
    await walletsBox.put('test-wallet-id', Wallet(
      id: 'test-wallet-id',
      name: 'Test Wallet',
      description: null,
      createdAt: now,
      updatedAt: now,
      isActive: true,
      createdBy: null,
    ));
  });

  testWidgets('App starts without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: DebtTrackerApp(initialRoute: '/login'),
      ),
    );
    expect(find.byType(MaterialApp), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
