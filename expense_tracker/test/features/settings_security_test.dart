import 'package:drift/native.dart';
import 'package:expense_tracker/app/state/ui_preferences.dart';
import 'package:expense_tracker/core/security/balance_pin.dart';
import 'package:expense_tracker/database/database.dart';
import 'package:expense_tracker/features/settings/settings_screen.dart';
import 'package:expense_tracker/repositories/drift/drift_settings_repository.dart';
import 'package:expense_tracker/repositories/providers.dart';
import 'package:expense_tracker/repositories/shared_preferences_ui_preferences.dart';
import 'package:expense_tracker/shared/models/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings -> Security, where the balance PIN is chosen.
///
/// The format rules themselves live in `test/core/balance_pin_test.dart`;
/// what is checked here is that the screen enforces them *at the point of
/// entry* - a too-short PIN, or a mistyped confirmation, must not quietly
/// install a lock nobody meant to set.
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

  /// Pumps Settings on a surface tall enough to lay every section out at once,
  /// so the Security tile is on screen without hunting for a scroll offset.
  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 4000);
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
        child: const MaterialApp(home: SettingsScreen()),
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

  /// Fills both PIN lines and taps the dialog's confirmation button.
  Future<void> submit(WidgetTester tester, String pin, String again) async {
    await tester.enterText(find.byType(TextField).at(0), pin);
    await tester.enterText(find.byType(TextField).at(1), again);
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pump(const Duration(milliseconds: 60));
  }

  testWidgets('offers the lock and reports it as off until it is set',
      (tester) async {
    await pumpSettings(tester);

    expect(find.text('Security'), findsOneWidget);
    expect(find.text('Protect account balances'), findsOneWidget);
    expect(
      find.text('Off - anyone holding the phone can see them'),
      findsOneWidget,
    );
    expect(find.text('Set a balance PIN'), findsNothing,
        reason: 'no dialog until it is asked for');

    await unmount(tester);
  });

  testWidgets('refuses a PIN shorter than five digits', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Protect account balances'));
    await tester.pump(const Duration(milliseconds: 60));

    expect(find.text('Set a balance PIN'), findsOneWidget);
    await submit(tester, '1234', '1234');

    expect(
      find.text('A PIN needs at least ${BalancePin.minLength} digits.'),
      findsOneWidget,
      reason: 'the dialog stays open and says why',
    );
    expect(
      (await DriftSettingsRepository(database).load()).hasBalanceLock,
      isFalse,
      reason: 'nothing may be written until the entry is valid',
    );

    await unmount(tester);
  });

  testWidgets('refuses a PIN longer than ten digits', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Protect account balances'));
    await tester.pump(const Duration(milliseconds: 60));
    await submit(tester, '12345678901', '12345678901');

    expect(
      find.text('A PIN can be at most ${BalancePin.maxLength} digits.'),
      findsOneWidget,
    );
    expect(
      (await DriftSettingsRepository(database).load()).hasBalanceLock,
      isFalse,
    );

    await unmount(tester);
  });

  testWidgets('the digits-only formatter strips letters while typing',
      (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Protect account balances'));
    await tester.pump(const Duration(milliseconds: 60));

    // '12ab5' is handed to the field whole; only the digits survive the
    // formatter, so three digits are left and the length rule is what fires.
    await submit(tester, '12ab5', '12ab5');

    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
      '125',
      reason: 'letters must never reach the PIN as characters',
    );
    expect(
      find.text('A PIN needs at least ${BalancePin.minLength} digits.'),
      findsOneWidget,
    );
    expect(
      find.text('Digits only - no letters, spaces or symbols.'),
      findsNothing,
      reason: 'the validator is the backstop, not the first line of defence',
    );
    expect(
      (await DriftSettingsRepository(database).load()).hasBalanceLock,
      isFalse,
    );

    await unmount(tester);
  });

  testWidgets('refuses a confirmation that does not match', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Protect account balances'));
    await tester.pump(const Duration(milliseconds: 60));
    await submit(tester, '48291', '48292');

    expect(find.text('The two PINs do not match.'), findsOneWidget);
    expect(
      (await DriftSettingsRepository(database).load()).hasBalanceLock,
      isFalse,
      reason: 'a mistyped confirmation must not install a lock',
    );

    await unmount(tester);
  });

  testWidgets('installs a salted hash once the entry is right', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Protect account balances'));
    await tester.pump(const Duration(milliseconds: 60));
    await submit(tester, '48291', '48291');

    expect(find.text('Set a balance PIN'), findsNothing);

    final stored = await DriftSettingsRepository(database).load();
    expect(stored.hasBalanceLock, isTrue);
    expect(
      stored.balancePinHash,
      isNot(anyOf(contains('48291'), equals('48291'))),
      reason: 'the PIN itself must never reach storage',
    );
    expect(stored.balancePinHash, hasLength(64));
    expect(stored.balancePinSalt, hasLength(BalancePin.saltBytes * 2));
    expect(
      BalancePin.matches('48291', stored.balancePinHash, stored.balancePinSalt),
      isTrue,
      reason: 'what was written has to be what the Accounts screen accepts',
    );

    expect(
      find.text('On - a PIN is asked for before balances are shown'),
      findsOneWidget,
      reason: 'the tile reflects the new state without a reload',
    );

    await unmount(tester);
  });

  testWidgets('leaves the rest of settings alone', (tester) async {
    await DriftSettingsRepository(database)
        .save(const AppSettings(currencySymbol: '€'));

    await pumpSettings(tester);
    await tester.tap(find.text('Protect account balances'));
    await tester.pump(const Duration(milliseconds: 60));
    await submit(tester, '48291', '48291');

    final stored = await DriftSettingsRepository(database).load();
    expect(stored.currencySymbol, '€',
        reason: 'installing a lock must not rewrite unrelated settings');
    expect(stored.hasBalanceLock, isTrue);

    await unmount(tester);
  });
}
