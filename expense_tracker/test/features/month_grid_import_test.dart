import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:expense_tracker/app/routes.dart';
import 'package:expense_tracker/database/database.dart';
import 'package:expense_tracker/repositories/providers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

/// Importing a month grid, end to end.
///
/// The file under test is the layout people keep for themselves rather than
/// the one this app exports: months across the top, days down the left, and
/// event blocks below the table. The whole point of the feature is that such
/// a file - which has no `Date` / `Amount` header row - can still be imported
/// after being asked once for the columns it never had.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late FilePickerPlatform originalPicker;
  late _FakeFilePicker picker;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    originalPicker = FilePickerPlatform.instance;
    picker = _FakeFilePicker();
    FilePickerPlatform.instance = picker;
  });

  tearDown(() {
    FilePickerPlatform.instance = originalPicker;
    return database.close();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  /// Drift closes its streams with zero-duration timers created during
  /// teardown, so the tree has to go while the test body is still running.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// The month grid: six months, four days, two event blocks.
  ///
  /// Note the absence of any `Date` or `Amount` heading - that is what makes
  /// this file interesting.
  String gridCsv() => <String>[
        'Date/Months,Jan,,Feb,,March,,April,,May,,June,,',
        ',Things,Amount,Things,Amount,Things,Amount,Things,Amount,Things,Amount,Things,Amount',
        '1,rentina,800,brother,1200,,,,,,,,',
        '2,hotel,450,,,,,,,,,',
        '3,,,,,,,,,,,,',
        '4,travel,250,,,,,,,,,',
        'Totals,1500,,,,,,,,,,,',
        ',,,,,,,,,,,,',
        'Mumbai (8-9)',
        ',Things,Amount',
        ',sweets,500',
        ',cake,600',
        ',Total,1100',
        ',,,,,,,,,,,,',
        'Birthday (14)',
        'Things,Amount',
        'flowers,200',
        'decorations,100',
      ].join('\r\n');

  /// Pumps the real navigator and pushes the device reader with [csv] queued
  /// as the file the picker hands back.
  Future<void> pumpGrid(WidgetTester tester, String csv) async {
    // Tall window: the whole import flow fits on screen, so every assertion
    // below reads a built widget instead of one the list has not reached yet.
    tester.view.physicalSize = const Size(1100, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    picker.responses.add(<PlatformFile>[
      _FakePlatformFile(
        name: 'budget.csv',
        uri: Uri.parse('content://expenses/budget.csv'),
        bytes: csv,
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(database),
        ],
        child: const MaterialApp(onGenerateRoute: onGenerateRoute),
      ),
    );
    await settle(tester);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pushNamed(AppRoutes.importFile);
    await settle(tester);
  }

  testWidgets('a month grid is recognised, asked about, then imported',
      (tester) async {
    await pumpGrid(tester, gridCsv());

    expect(tester.takeException(), isNull);
    expect(
      find.text('Month grid detected'),
      findsOneWidget,
      reason: 'a sheet with no Date / Amount header must still be understood',
    );
    expect(find.text('Set import options'), findsOneWidget);
    expect(
      find.textContaining('Mumbai'),
      findsWidgets,
      reason: 'the blocks below the table are reported as events',
    );
    expect(
      find.textContaining('Birthday'),
      findsWidgets,
      reason: 'the blocks below the table are reported as events',
    );

    // Nothing is written before the options are even known.
    expect(await database.select(database.transactions).get(), isEmpty);

    // The sheet's missing fields are asked for the moment it is understood -
    // nobody should have to go looking for the question.
    expect(find.text('Before importing'), findsOneWidget);
    expect(
      find.text('Year'),
      findsOneWidget,
      reason: 'the sheet never states one, so it has to be asked',
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await settle(tester);
    expect(find.text('Before importing'), findsNothing,
        reason: 'the dialog closes on Import');

    expect(find.text('Applied to every row'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Import 8 rows'),
      findsOneWidget,
      reason: 'four monthly rows and four event rows',
    );
    expect(await database.select(database.transactions).get(), isEmpty,
        reason: 'answering the dialog is not itself an import');

    // ------------------------------------------------------------ the import
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Import 8 rows'),
      240,
    );
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Import 8 rows'));
    await settle(tester);
    expect(find.text('Import these rows?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await settle(tester);
    await settle(tester);

    final rows = await database.select(database.transactions).get();
    expect(rows, hasLength(8));

    final events = await database.select(database.specialEvents).get();
    expect(events.map((e) => e.name).toSet(), <String>{'Mumbai', 'Birthday'},
        reason: 'each block became an event; its brackets gave the event its '
            'days rather than becoming part of the name');

    final withEvent = rows.where((r) => r.specialEventId != null).length;
    expect(
      withEvent,
      4,
      reason: 'the monthly table stays out of the events, as it must',
    );
    expect(rows.where((r) => r.specialEventId == null).length, 4);

    // Money arrives as paise: 800 + 1200 + 450 + 250 + 500 + 600 + 200 + 100.
    final total = rows.fold<int>(0, (sum, r) => sum + r.amount);
    expect(total, 410000, reason: 'every rupee in the sheet, as paise');

    // Close the report dialog and let the snackbar's timer run out, so the
    // tree can be unmounted without a pending-timer failure.
    final report = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(FilledButton),
    );
    if (report.evaluate().isNotEmpty) {
      await tester.tap(report.first);
      await settle(tester);
    }
    for (var i = 0; i < 140; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }

    await unmount(tester);
  });

  testWidgets('cancelling the options dialog leaves the import waiting',
      (tester) async {
    await pumpGrid(tester, gridCsv());
    expect(find.text('Before importing'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await settle(tester);

    expect(find.text('Before importing'), findsNothing);
    expect(
      find.text('Month grid detected'),
      findsOneWidget,
      reason: 'backing out must not throw the file away',
    );
    expect(
      find.widgetWithText(OutlinedButton, 'Set import options'),
      findsOneWidget,
      reason: 'the question can be asked again',
    );

    // ...and it is, on demand.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Set import options'));
    await settle(tester);
    expect(find.text('Before importing'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await settle(tester);

    expect(
      await database.select(database.transactions).get(),
      isEmpty,
      reason: 'answering nothing writes nothing',
    );

    await unmount(tester);
  });
}

/// Stands in for the platform file picker: every call answers from
/// [responses], and an exhausted queue reads as "the user cancelled".
class _FakeFilePicker extends FilePickerPlatform {
  final List<List<PlatformFile>> responses = <List<PlatformFile>>[];
  int calls = 0;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    calls++;
    if (responses.isEmpty) return const <PlatformFile>[];
    return responses.removeAt(0);
  }
}

/// A picked file backed by [bytes]: [uri] is not a local path, so the screen
/// reads the bytes straight from the picker rather than touching disk - real
/// file I/O does not settle inside the test's fake-async zone.
final class _FakePlatformFile extends PlatformFile {
  _FakePlatformFile({
    required this.name,
    required Uri uri,
    required String bytes,
  })  : _uri = uri,
        _bytes = Uint8List.fromList(utf8.encode(bytes));

  @override
  final String name;

  final Uri _uri;
  final Uint8List _bytes;

  @override
  Uri get uri => _uri;

  @override
  XFile get xFile => XFile.fromData(_bytes, name: name);

  @override
  int? lengthSync() => _bytes.length;

  @override
  Future<int?> length() async => _bytes.length;

  @override
  Future<Uint8List> readAsBytes() async => _bytes;

  @override
  Stream<Uint8List> readAsByteStream() => Stream<Uint8List>.value(_bytes);
}
