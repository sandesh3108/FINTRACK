import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:expense_tracker/app/routes.dart';
import 'package:expense_tracker/database/database.dart';
import 'package:expense_tracker/features/backup/backup_screen.dart';
import 'package:expense_tracker/features/backup/import_spreadsheet_screen.dart';
import 'package:expense_tracker/repositories/providers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

/// Covers the `Import spreadsheet` entry: `/import-sheet` must offer both
/// sources, `/import-file` must land on the backup screen in import mode and
/// reach for the picker after the first frame without ever popping on a cancel
/// or a failure, and a picked spreadsheet must stop at the preview with the
/// database still untouched.
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

  /// Lets the route, the future file read and the preview analysis resolve.
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

  /// Pumps the real navigator, so the screen under test comes from
  /// [onGenerateRoute] rather than from a hand-built widget.
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(database),
        ],
        child: const MaterialApp(onGenerateRoute: onGenerateRoute),
      ),
    );
    await settle(tester);
  }

  Future<void> pushNamed(WidgetTester tester, String route) async {
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pushNamed(route);
    await settle(tester);
  }

  Future<void> pushImportFile(WidgetTester tester) =>
      pushNamed(tester, AppRoutes.importFile);

  testWidgets('the import-sheet route offers both sources', (tester) async {
    expect(AppRoutes.importSheet, '/import-sheet');
    expect(AppRoutes.importFile, '/import-file');

    await pumpApp(tester);
    await pushNamed(tester, AppRoutes.importSheet);

    expect(tester.takeException(), isNull);
    expect(find.byType(ImportSpreadsheetScreen), findsOneWidget);
    expect(find.byType(BackupScreen), findsNothing,
        reason: 'picking a source happens before anything is read');
    expect(find.text('Import spreadsheet'), findsOneWidget);
    expect(find.text('Where should the rows come from?'), findsOneWidget);
    expect(find.text('Import from Google Sheets'), findsOneWidget);
    expect(find.text('Import from this device'), findsOneWidget);
    expect(
      picker.calls,
      0,
      reason: 'the chooser must not open a file picker on its own',
    );

    await unmount(tester);
  });

  testWidgets('choosing this device lands on the importer', (tester) async {
    await pumpApp(tester);
    await pushNamed(tester, AppRoutes.importSheet);

    await tester.tap(find.text('Import from this device'));
    await settle(tester);

    expect(tester.takeException(), isNull);
    // The chooser is still mounted underneath, just offstage - that is what
    // makes Back return to it rather than leaving the app.
    expect(
      find.byType(ImportSpreadsheetScreen, skipOffstage: false),
      findsOneWidget,
      reason: 'the chooser stays behind, so Back returns to it',
    );
    final screen = tester.widget<BackupScreen>(find.byType(BackupScreen));
    expect(screen.launch, BackupLaunch.importFile);

    expect(find.text('Import from file'), findsOneWidget);
    expect(find.text('Backup & restore'), findsNothing);
    expect(
      find.text('Export'),
      findsNothing,
      reason: 'the export side must not lead an import',
    );
    expect(find.text('Choose a file'), findsOneWidget);
    expect(find.text('No backup selected'), findsOneWidget);

    expect(picker.calls, 1, reason: 'the picker opens after the first frame');
    expect(
      picker.requestedExtensions.single,
      <String>['json', 'csv', 'xlsx', 'xls'],
      reason: 'the picker extensions must not change',
    );

    await unmount(tester);
  });

  testWidgets('a cancel leaves the importer on screen', (tester) async {
    await pumpApp(tester);
    await pushImportFile(tester);

    // The picker answered with nothing, so this is a cancel: the screen stays
    // exactly where it is, with the visible button as the only way back in.
    expect(find.byType(BackupScreen), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Choose a file'));
    await settle(tester);

    expect(picker.calls, 2, reason: 'the visible button retries the pick');
    expect(find.byType(BackupScreen), findsOneWidget);
    expect(find.text('Import from file'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('the regular backup screen is left exactly as it was',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(database),
        ],
        child: const MaterialApp(home: BackupScreen()),
      ),
    );
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Backup & restore'), findsOneWidget);
    expect(find.text('Export'), findsOneWidget);
    expect(find.text('Restore'), findsWidgets);
    expect(
      find.widgetWithText(OutlinedButton, 'Restore from file'),
      findsOneWidget,
    );
    expect(find.text('Import from file'), findsNothing);
    expect(find.text('Choose a file'), findsNothing);
    expect(picker.calls, 0, reason: 'nothing opens on its own in full mode');

    await unmount(tester);
  });

  testWidgets('a picked CSV stops at the preview with the data untouched',
      (tester) async {
    // Byte-order mark and CRLF, exactly what an Excel "CSV UTF-8" export
    // produces. The URI is not a local file, so the screen takes the bytes
    // straight from the picker instead of touching the disk - real file I/O
    // does not settle inside the test's fake-async zone.
    const csv = '\uFEFF'
        'Date,Time,Type,Amount,Category,Income source,Payment method,Event,Note\r\n'
        '2026-09-05,10:30,expense,1234.50,Food,,Cash,,Lunch with team\r\n'
        '2026-09-06,09:00,income,50000,,Salary,,,September salary\r\n';
    picker.responses.add(<PlatformFile>[
      _FakePlatformFile(
        name: 'transactions.csv',
        uri: Uri.parse('content://expenses/transactions.csv'),
        bytes: csv,
      ),
    ]);

    await pumpApp(tester);
    await pushImportFile(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Backup preview'), findsOneWidget);
    expect(find.text('transactions.csv'), findsOneWidget);
    expect(find.text('No backup selected'), findsNothing);
    expect(find.text('Reading the backup file...'), findsNothing);
    expect(find.text('Transactions'), findsOneWidget);
    expect(
      find.text('2'),
      findsOneWidget,
      reason: 'both CSV rows are in the preview count',
    );

    // The confirm block sits below the fold of the list, so it has to be
    // scrolled into view before it is built at all.
    final restoreFinder = find.widgetWithText(FilledButton, 'Restore');
    await tester.scrollUntilVisible(restoreFinder, 240);
    await settle(tester);

    final restore = tester.widget<FilledButton>(restoreFinder);
    expect(restore.onPressed, isNotNull, reason: 'the preview can be applied');

    final rows = await database.select(database.transactions).get();
    expect(
      rows,
      isEmpty,
      reason: 'import stops at the preview until the user confirms',
    );

    await unmount(tester);
  });

  testWidgets('an .xls file is refused without leaving the screen',
      (tester) async {
    // No usable local path here, so the screen falls back to the bytes the
    // picker hands back directly.
    picker.responses.add(<PlatformFile>[
      _FakePlatformFile(
        name: 'old.xls',
        uri: Uri.parse('content://expenses/old.xls'),
        bytes: 'Date,Amount\r\n2026-09-05,10\r\n',
      ),
    ]);

    await pumpApp(tester);
    await pushImportFile(tester);

    expect(find.textContaining('save it as .xlsx'), findsWidgets);
    expect(find.byType(BackupScreen), findsOneWidget);

    // The refusal is also a snackbar, which carries its own 4s timer.
    // Drain it so the tree can be unmounted without a pending-timer failure.
    for (var i = 0; i < 140; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }

    await unmount(tester);
  });
}

/// Stands in for the platform file picker: every call answers from
/// [responses], and an exhausted queue reads as "the user cancelled".
class _FakeFilePicker extends FilePickerPlatform {
  final List<List<PlatformFile>> responses = <List<PlatformFile>>[];
  final List<List<String>?> requestedExtensions = <List<String>?>[];
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
    requestedExtensions.add(allowedExtensions);
    if (responses.isEmpty) return const <PlatformFile>[];
    return responses.removeAt(0);
  }
}

/// A picked file backed by [bytes]: [uri] decides whether the screen reads a
/// real file off disk or asks the picker for the bytes themselves.
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
