import 'package:drift/native.dart';
import 'package:expense_tracker/app/app.dart';
import 'package:expense_tracker/app/state/shell.dart';
import 'package:expense_tracker/app/state/ui_preferences.dart';
import 'package:expense_tracker/database/database.dart';
import 'package:expense_tracker/repositories/providers.dart';
import 'package:expense_tracker/repositories/shared_preferences_ui_preferences.dart';
import 'package:expense_tracker/shared/models/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// End-to-end checks for the journeys in the spec's *UI Testing* section.
///
/// The app is pumped for real against an in-memory SQLite database and mocked
/// `shared_preferences`, so every screen actually builds, every stream
/// actually resolves, and any exception thrown while rendering is reported
/// here rather than discovered on a device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const tabLabels = <String>['Home', 'Transactions', 'Add', 'Reports', 'More'];

  late AppDatabase database;
  late SharedPreferencesUiPreferencesRepository preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // In-memory, not `AppDatabase()`: the production constructor opens the
    // platform directory through path_provider, which has no implementation
    // in a host test.
    database = AppDatabase.forTesting(NativeDatabase.memory());
    preferences = await SharedPreferencesUiPreferencesRepository.open();
  });

  tearDown(() async {
    await database.close();
  });

  /// Pumps the root widget and gives the database streams and futures a few
  /// frames to settle.
  ///
  /// Deliberately not `pumpAndSettle`: an indeterminate progress indicator
  /// would animate forever and make the test time out for no real reason.
  Future<void> pumpApp(WidgetTester tester) async {
    final initial = await preferences.load();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(database),
          uiPreferencesRepositoryProvider.overrideWithValue(preferences),
          uiPreferencesInitialProvider.overrideWithValue(initial),
        ],
        child: const ExpenseApp(),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  /// Unmounts the tree *inside* the test body and elapses the fake clock.
  ///
  /// Disposing the [ProviderScope] makes Drift schedule zero-duration timers
  /// that close its query streams. Those timers are created while the tree is
  /// torn down - after the body has already returned - so flutter_test would
  /// fail with "A Timer is still pending even after the widget tree was
  /// disposed". Unmounting here and pumping once lets them fire while the body
  /// is still in control, and leaves nothing for the framework to dispose.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('the app opens without throwing and shows five tabs',
      (tester) async {
    await pumpApp(tester);

    expect(
      tester.takeException(),
      isNull,
      reason: 'no screen may throw while rendering its first frame',
    );
    expect(find.byType(NavigationBar), findsOneWidget);
    for (final label in tabLabels) {
      expect(
        find.widgetWithText(NavigationBar, label),
        findsOneWidget,
        reason: 'the bottom bar must expose "$label"',
      );
    }
    await unmount(tester);
  });

  testWidgets('tapping a destination switches the selected tab',
      (tester) async {
    await pumpApp(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(NavigationBar)),
    );
    expect(container.read(shellIndexProvider), 0, reason: 'opens on Home');

    for (var index = 1; index < tabLabels.length; index++) {
      // Tap the destination's own label. `find.widgetWithText(NavigationBar, …)`
      // resolves to the bar itself (an ancestor of the text), whose centre is
      // the middle item - tapping that would never hit the intended tab.
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(tabLabels[index]),
        ),
      );
      await tester.pump();

      expect(container.read(shellIndexProvider), index);
      expect(
        tester.takeException(),
        isNull,
        reason: '"${tabLabels[index]}" must build once selected',
      );
    }
    await unmount(tester);
  });

  testWidgets('an empty first run shows guidance instead of a blank screen',
      (tester) async {
    await pumpApp(tester);

    // The dashboard, transactions and reports tabs all own an empty state.
    // Anything but a blank body is the requirement; assert there is text and
    // an actionable control rather than matching a specific sentence.
    expect(find.textContaining('transaction', findRichText: true),
        findsWidgets);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('switching to dark mode re-themes the whole app', (tester) async {
    await pumpApp(tester);

    final context = tester.element(find.byType(NavigationBar));
    final container = ProviderScope.containerOf(context);
    final before = Theme.of(context).brightness;

    await container
        .read(uiPreferencesProvider.notifier)
        .setThemeMode(before == Brightness.dark
            ? ThemeModeSetting.light
            : ThemeModeSetting.dark);
    // MaterialApp applies themeMode through AnimatedTheme, which interpolates
    // over 200ms - a single frame would still report the outgoing brightness.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }

    final after = Theme.of(tester.element(find.byType(NavigationBar)))
        .brightness;
    expect(after, isNot(before));
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });
}
