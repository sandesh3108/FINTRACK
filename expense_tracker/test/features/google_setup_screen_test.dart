import 'package:drift/native.dart';
import 'package:expense_tracker/database/database.dart';
import 'package:expense_tracker/features/google_sheets/google_setup_screen.dart';
import 'package:expense_tracker/repositories/drift/drift_settings_repository.dart';
import 'package:expense_tracker/repositories/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers the runtime Google setup screen: the instructions must show the
/// package name and the Cloud Console link, a pasted client id must reach
/// SQLite and flip the status line, an absent platform channel must degrade
/// to the documented SHA-1 fallback instead of throwing, and Clear must
/// remove what was stored.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;

  setUp(() => database = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => database.close());

  /// Lets the settings stream resolve; deliberately not `pumpAndSettle`,
  /// because a `CircularProgressIndicator` would animate forever.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  /// Pumps the screen in a window tall enough to lay every section out at
  /// once, so finders and taps never depend on scroll position.
  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(database),
        ],
        child: const MaterialApp(home: GoogleSetupScreen()),
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

  testWidgets('shows the console link, package name and unconfigured state',
      (tester) async {
    await pumpScreen(tester);

    expect(tester.takeException(), isNull, reason: 'the screen must build');
    expect(
      find.textContaining('https://console.cloud.google.com/'),
      findsOneWidget,
      reason: 'the Cloud Console link has to be on screen',
    );
    expect(
      find.text('com.sandeep.expense_tracker'),
      findsOneWidget,
      reason: 'the console needs the exact application id',
    );
    expect(
      find.text('Not configured — sign-in is disabled'),
      findsOneWidget,
      reason: 'nothing is stored, so sign-in must be reported as disabled',
    );

    await unmount(tester);
  });

  testWidgets('saving an Android client id persists it and flips the status',
      (tester) async {
    await pumpScreen(tester);

    const clientId = '1234567890-abc123.apps.googleusercontent.com';

    // Fields are built in order: Android client ID, Web client ID, Project ID.
    await tester.enterText(find.byType(TextField).at(0), clientId);
    await tester.pump(const Duration(milliseconds: 40));

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(tester);

    final stored = await DriftSettingsRepository(database).load();
    expect(
      stored.googleClientIdAndroid,
      clientId,
      reason: 'the id must land in the SQLite settings table',
    );
    expect(
      find.text('Configured — ids saved on this device'),
      findsOneWidget,
      reason: 'an id pasted here is attributed to this device, not to the '
          'build, so the user knows which one is in charge',
    );

    await unmount(tester);
  });

  testWidgets('falls back to the documented SHA-1 when the channel is absent',
      (tester) async {
    await pumpScreen(tester);

    // Widget tests have no platform channel, so `getSha1` cannot answer.
    expect(tester.takeException(), isNull, reason: 'a missing channel must '
        'never break the screen');
    expect(
      find.text('FA:A5:B3:31:B7:CA:FD:6E:FD:1D:71:96:20:B8:9C:DB:32:4F:FE:A1'),
      findsOneWidget,
      reason: 'the SHA-1 box falls back to the documented literal',
    );
    expect(find.textContaining('keytool'), findsWidgets);
    expect(tester.takeException(), isNull);

    await unmount(tester);
  });

  testWidgets('clearing removes the stored ids', (tester) async {
    await pumpScreen(tester);

    await tester.enterText(
      find.byType(TextField).at(0),
      '1234567890-abc123.apps.googleusercontent.com',
    );
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(tester);

    var stored = await DriftSettingsRepository(database).load();
    expect(stored.googleClientIdAndroid, isNotEmpty);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Clear'));
    await settle(tester);

    stored = await DriftSettingsRepository(database).load();
    expect(stored.googleClientIdAndroid, isEmpty);
    expect(stored.googleClientIdWeb, isEmpty);
    expect(stored.googleProjectId, isEmpty);
    expect(find.text('Not configured — sign-in is disabled'), findsOneWidget);

    await unmount(tester);
  });
}
