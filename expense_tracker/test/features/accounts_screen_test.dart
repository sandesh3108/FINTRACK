import 'package:drift/native.dart';
import 'package:expense_tracker/core/security/balance_pin.dart';
import 'package:expense_tracker/database/database.dart';
import 'package:expense_tracker/features/accounts/accounts_screen.dart';
import 'package:expense_tracker/repositories/drift/drift_settings_repository.dart';
import 'package:expense_tracker/repositories/providers.dart';
import 'package:expense_tracker/shared/models/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers the balances screen end to end: the four seeded accounts must be
/// listed, typing an opening balance must move the remaining balance, and the
/// figure must be derived rather than entered twice.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;

  setUp(() => database = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => database.close());

  /// Lets the balances future and the catalog streams resolve.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(database),
        ],
        child: const MaterialApp(home: AccountsScreen()),
      ),
    );
    await settle(tester);
  }

  /// Drift closes its streams with zero-duration timers created during
  /// teardown, so the tree has to go while the test body is still running.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('lists every seeded account with a zero balance',
      (tester) async {
    await pumpScreen(tester);

    expect(tester.takeException(), isNull);
    for (final name in const <String>[
      'BOI(Saving)',
      'Cash',
      'Google Pay',
      'PhonePe',
    ]) {
      expect(find.text(name), findsOneWidget, reason: '"$name" must appear');
    }
    expect(find.text('Total balance'), findsOneWidget);
    expect(find.text('Remaining balance'), findsNWidgets(4));

    await unmount(tester);
  });

  testWidgets('an entered opening balance drives the remaining balance',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(
      find.byTooltip('Edit opening balance for Cash'),
      warnIfMissed: false,
    );
    await settle(tester);
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.enterText(find.byType(TextField), '5000');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(tester);

    expect(find.byType(AlertDialog), findsNothing);

    // ₹5,000 on the Cash card, and the total must include it.
    expect(
      find.text('₹5,000'),
      findsWidgets,
      reason: 'the card and the total both reflect the balance',
    );

    final method = await (database.select(database.paymentMethods)
          ..where((m) => m.name.equals('Cash')))
        .getSingle();
    expect(method.openingBalance, 500000, reason: 'stored in paise');

    await unmount(tester);
  });

  testWidgets('rejects an amount that is not a number', (tester) async {
    await pumpScreen(tester);

    await tester.tap(
      find.byTooltip('Edit opening balance for Cash'),
      warnIfMissed: false,
    );
    await settle(tester);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(tester);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Enter a valid amount.'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await settle(tester);

    final method = await (database.select(database.paymentMethods)
          ..where((m) => m.name.equals('Cash')))
        .getSingle();
    expect(method.openingBalance, 0);

    await unmount(tester);
  });

  // ------------------------------------------------------------------ lock

  /// Turns the balance lock on for [pin], exactly as Settings would.
  Future<void> enableLock(String pin) async {
    final salt = BalancePin.newSalt();
    await DriftSettingsRepository(database).save(
      AppSettings(
        balancePinHash: BalancePin.hash(pin, salt),
        balancePinSalt: salt,
      ),
    );
  }

  testWidgets('hides every balance until the PIN is entered', (tester) async {
    await enableLock('48291');
    await pumpScreen(tester);

    expect(find.text('Balances are locked'), findsOneWidget);
    expect(
      find.text('Cash'),
      findsNothing,
      reason: 'the lock must not leak which accounts exist or what is in them',
    );
    expect(find.text('₹5,000'), findsNothing);
    expect(find.text('Total balance'), findsNothing);

    await unmount(tester);
  });

  testWidgets('a wrong PIN keeps the balances closed', (tester) async {
    await enableLock('48291');
    await pumpScreen(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await settle(tester);
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.enterText(find.byType(TextField), '00000');
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await settle(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Balances are locked'), findsOneWidget);
    expect(find.text('Cash'), findsNothing);

    // The refusal arrives as a snackbar, which carries its own 4s timer.
    // Drain it so the tree can be unmounted without a pending-timer failure.
    for (var i = 0; i < 140; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }

    await unmount(tester);
  });

  testWidgets('the right PIN reveals the balances and can re-lock them',
      (tester) async {
    await enableLock('48291');
    await pumpScreen(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await settle(tester);

    await tester.enterText(find.byType(TextField), '48291');
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await settle(tester);

    expect(find.text('Balances are locked'), findsNothing);
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('Total balance'), findsOneWidget);

    // The padlock in the app bar puts it back without leaving the screen.
    await tester.tap(find.byTooltip('Lock balances again'));
    await settle(tester);
    expect(find.text('Balances are locked'), findsOneWidget);
    expect(find.text('Cash'), findsNothing);

    await unmount(tester);
  });

  testWidgets('an unconfigured lock never blocks the screen', (tester) async {
    // Settings loaded but no PIN set - the screen must not padlock itself.
    await pumpScreen(tester);

    expect(find.text('Balances are locked'), findsNothing);
    expect(find.text('Cash'), findsOneWidget);
    expect(find.byTooltip('Lock balances again'), findsNothing);

    await unmount(tester);
  });

  testWidgets('re-locks the moment the screen is left', (tester) async {
    await enableLock('48291');

    // A host screen, so the Accounts route can really be pushed and popped -
    // that exit is the one the lock has to catch.
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(database),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const AccountsScreen(),
                    ),
                  ),
                  child: const Text('OPEN ACCOUNTS'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    await tester.tap(find.text('OPEN ACCOUNTS'));
    await settle(tester);
    expect(find.text('Balances are locked'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '48291');
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await settle(tester);
    expect(find.text('Total balance'), findsOneWidget,
        reason: 'the PIN was accepted, so the figures are shown');

    // Leave the section.
    Navigator.pop(tester.element(find.byType(AccountsScreen)));
    await settle(tester);
    expect(find.text('OPEN ACCOUNTS'), findsOneWidget,
        reason: 'back on the host screen');

    // Coming straight back must ask again: the session flag did not survive
    // the exit, which is the whole point of the behaviour under test.
    await tester.tap(find.text('OPEN ACCOUNTS'));
    await settle(tester);
    expect(
      find.text('Balances are locked'),
      findsOneWidget,
      reason: 'returning to the section must not still be unlocked',
    );
    expect(find.text('Total balance'), findsNothing);
    expect(find.text('Cash'), findsNothing);

    await unmount(tester);
  });
}
