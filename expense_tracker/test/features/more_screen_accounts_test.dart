import 'package:drift/native.dart';
import 'package:expense_tracker/app/state/ui_preferences.dart';
import 'package:expense_tracker/core/security/balance_pin.dart';
import 'package:expense_tracker/database/database.dart';
import 'package:expense_tracker/features/more/more_screen.dart';
import 'package:expense_tracker/repositories/drift/drift_catalog_repository.dart';
import 'package:expense_tracker/repositories/drift/drift_settings_repository.dart';
import 'package:expense_tracker/repositories/drift/drift_transaction_repository.dart';
import 'package:expense_tracker/repositories/providers.dart';
import 'package:expense_tracker/repositories/shared_preferences_ui_preferences.dart';
import 'package:expense_tracker/shared/models/app_settings.dart';
import 'package:expense_tracker/shared/models/catalog_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The accounts section now lives on **More**, not on Home.
///
/// Two things are pinned down here: that it really did move (Home no longer
/// owns it), and that it honours the balance lock the same way - account names
/// readable, amounts as dots until the PIN has been accepted.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late SharedPreferencesUiPreferencesRepository preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase.forTesting(NativeDatabase.memory());
    preferences = await SharedPreferencesUiPreferencesRepository.open();
  });

  tearDown(() => database.close());

  Future<void> pumpMore(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final initial = await preferences.load();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(database),
          uiPreferencesRepositoryProvider.overrideWithValue(preferences),
          uiPreferencesInitialProvider.overrideWithValue(initial),
        ],
        child: const MaterialApp(home: MoreScreen()),
      ),
    );
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Gives Cash a ₹5,000 opening balance so the chip has something to show.
  Future<void> seedBalance() async {
    final transactions = DriftTransactionRepository(database);
    final catalog = DriftCatalogRepository(database, transactions);
    final cash = await catalog.findOrCreate(CatalogKind.paymentMethod, 'Cash');
    await catalog.setOpeningBalance(CatalogKind.paymentMethod, cash, 500000);
  }

  /// Turns the balance lock on, exactly as Settings would.
  Future<void> enableLock() async {
    final salt = BalancePin.newSalt();
    await DriftSettingsRepository(database).save(
      AppSettings(
        balancePinHash: BalancePin.hash('48291', salt),
        balancePinSalt: salt,
      ),
    );
  }

  testWidgets('shows the accounts section and the spreadsheet import entry',
      (tester) async {
    await seedBalance();
    await pumpMore(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Your accounts'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
    expect(
      find.text('₹5,000'),
      findsOneWidget,
      reason: 'with no lock on, the strip reads the balance',
    );
    expect(find.text('See all'), findsOneWidget);

    expect(find.text('Import spreadsheet'), findsOneWidget);
    expect(
      find.text('From Google Sheets, or a file on this phone'),
      findsOneWidget,
      reason: 'the import entry must be discoverable without knowing that '
          'Backup also accepts spreadsheets',
    );

    await unmount(tester);
  });

  testWidgets('masks the amounts while the balance lock is on', (tester) async {
    await seedBalance();
    await enableLock();
    await pumpMore(tester);

    expect(find.text('Cash'), findsOneWidget,
        reason: 'which accounts you have is not the secret');
    expect(
      find.text('₹5,000'),
      findsNothing,
      reason: 'a locked balance must not be readable from a menu screen',
    );
    expect(find.text('\u2022\u2022\u2022\u2022'), findsWidgets);
    expect(find.byIcon(Icons.lock_rounded), findsWidgets);

    await unmount(tester);
  });

  testWidgets('the section collapses when there are no accounts', (tester) async {
    // A fresh database is seeded with four payment methods, so emptiness has
    // to be arranged - and the strip must take it in stride rather than
    // rendering a heading over nothing.
    await DriftCatalogRepository(database, DriftTransactionRepository(database))
        .clear(CatalogKind.paymentMethod);
    await pumpMore(tester);

    expect(find.text('Your accounts'), findsNothing);
    expect(find.text('See all'), findsNothing);
    expect(
      find.text('Import spreadsheet'),
      findsOneWidget,
      reason: 'the import entry does not depend on account state',
    );

    await unmount(tester);
  });
}
