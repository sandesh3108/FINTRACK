import 'package:excel/excel.dart';
import 'package:expense_tracker/core/backup/backup_formats.dart';
import 'package:expense_tracker/core/errors/app_exception.dart';
import 'package:expense_tracker/repositories/backup_repository.dart';
import 'package:expense_tracker/shared/models/catalog_item.dart';
import 'package:expense_tracker/shared/models/transaction_filter.dart';
import 'package:expense_tracker/shared/models/transaction_input.dart';
import 'package:expense_tracker/shared/models/tx_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_harness.dart';

void main() {
  late TestHarness harness;

  setUp(() => harness = TestHarness());
  tearDown(() => harness.close());

  final day5 = DateTime(2026, 9, 5);
  final day6 = DateTime(2026, 9, 6);

  Future<int> addExpense(int amount, {DateTime? date, String category = 'Food'}) async {
    final categoryId =
        await harness.catalog.findOrCreate(CatalogKind.category, category);
    final paymentMethodId =
        await harness.catalog.findOrCreate(CatalogKind.paymentMethod, 'Cash');
    return harness.transactions.add(
      TransactionInput(
        type: TxType.expense,
        amountMinor: amount,
        date: date ?? day5,
        time: '10:00',
        categoryId: categoryId,
        paymentMethodId: paymentMethodId,
      ),
    );
  }

  Future<int> countAll() =>
      harness.transactions.countTransactions(const TransactionFilter());

  group('createBackup / preview', () {
    test('serialises every table and reports the contents without writing',
        () async {
      await addExpense(15000);
      await addExpense(25000, date: day6, category: 'Travel');
      final eventId = await harness.events.findOrCreate('Trip 2026');

      final json = await harness.backup.createBackupJson();
      final preview = harness.backup.preview(json);

      expect(preview.version, BackupRepository.formatVersion);
      expect(preview.transactions, 2);
      expect(preview.specialEvents, 1);
      expect(preview.categories, greaterThan(10));
      expect(preview.incomeSources, greaterThan(0));
      expect(preview.paymentMethods, greaterThan(0));
      expect(preview.hasSettings, isTrue);
      expect(preview.totalRows, greaterThan(preview.transactions));

      // Nothing was written by reading it.
      expect(await countAll(), 2);
      expect(await harness.events.getAll(), hasLength(1));
      expect(eventId, greaterThan(0));
    });

    test('produces human-readable, versioned JSON', () async {
      await addExpense(15000);
      final json = await harness.backup.createBackupJson();

      expect(json, contains(BackupRepository.documentType));
      expect(json, contains('"transactions"'));
      expect(json, isNot(contains('NaN')));
      expect(json, isNot(contains('Infinity')));
      expect(() => harness.backup.preview(json), returnsNormally);
    });
  });

  group('restore: merge', () {
    test('never duplicates rows that already exist', () async {
      await addExpense(15000);
      await addExpense(25000, date: day6);
      final json = await harness.backup.createBackupJson();

      final report = await harness.backup.restore(
        json,
        mode: BackupRestoreMode.merge,
      );

      expect(report.inserted, 0);
      expect(report.skippedDuplicates, 2);
      expect(report.invalid, 0);
      expect(await countAll(), 2, reason: 'merge must not double count');
    });

    test('adds rows the device is missing and leaves the rest alone', () async {
      await addExpense(15000);
      final keep = await addExpense(25000, date: day6);
      final json = await harness.backup.createBackupJson();

      await harness.transactions.remove(keep);
      expect(await countAll(), 1);

      final report = await harness.backup.restore(
        json,
        mode: BackupRestoreMode.merge,
      );

      expect(report.inserted, 1);
      expect(report.skippedDuplicates, 1);
      expect(await countAll(), 2);
    });

    test('never rewrites a row that already exists on the device', () async {
      final id = await addExpense(15000);
      final json = await harness.backup.createBackupJson();

      // Link the row to an event - a change the duplicate key deliberately
      // ignores, so the backup row is still "the same" transaction.
      final eventId = await harness.events.findOrCreate('Mumbai Trip');
      await harness.transactions.edit(
        id,
        TransactionInput(
          type: TxType.expense,
          amountMinor: 15000,
          date: day5,
          time: '10:00',
          categoryId:
              await harness.catalog.findOrCreate(CatalogKind.category, 'Food'),
          paymentMethodId: await harness.catalog
              .findOrCreate(CatalogKind.paymentMethod, 'Cash'),
          specialEventId: eventId,
        ),
      );

      final report = await harness.backup.restore(
        json,
        mode: BackupRestoreMode.merge,
      );

      expect(report.inserted, 0);
      expect(report.skippedDuplicates, 1);
      expect(await countAll(), 1);

      final row = await harness.transactions.getById(id);
      expect(row!.amountMinor, 15000);
      expect(
        row.specialEventId,
        eventId,
        reason: 'merge must never clear data that already exists',
      );
    });
  });

  group('restore: replace', () {
    test('wipes the device first, then reloads the backup', () async {
      await addExpense(15000);
      await addExpense(25000, date: day6);
      final json = await harness.backup.createBackupJson();

      await addExpense(99999, date: day6, category: 'NotInBackup');
      expect(await countAll(), 3);

      final report = await harness.backup.restore(
        json,
        mode: BackupRestoreMode.replace,
      );

      expect(report.inserted, 2);
      expect(await countAll(), 2, reason: 'rows absent from the backup go away');

      final rows = await harness.transactions
          .getTransactions(const TransactionFilter());
      expect(rows.map((r) => r.amountMinor), isNot(contains(99999)));

      // The catalog row that only existed on this device is gone too.
      final categories = await harness.catalog.getAll(CatalogKind.category);
      expect(categories.map((c) => c.name), isNot(contains('NotInBackup')));
    });

    test('restores catalog renames made before the backup was taken',
        () async {
      await addExpense(15000);
      final food = await harness.catalog.findOrCreate(CatalogKind.category, 'Food');
      await harness.catalog.rename(CatalogKind.category, food, 'Grub');

      final json = await harness.backup.createBackupJson();

      await harness.catalog.rename(CatalogKind.category, food, 'Renamed again');
      await harness.backup.restore(json, mode: BackupRestoreMode.replace);

      final categories = await harness.catalog.getAll(CatalogKind.category);
      expect(categories.map((c) => c.name), contains('Grub'));
      expect(categories.map((c) => c.name), isNot(contains('Renamed again')));
    });

    test('restores durable settings', () async {
      final settings = await harness.settings.load();
      await harness.settings.save(settings.copyWith(currencySymbol: '€'));
      final json = await harness.backup.createBackupJson();

      await harness.settings.save(settings.copyWith(currencySymbol: r'$'));
      expect((await harness.settings.load()).currencySymbol, r'$');

      await harness.backup.restore(json, mode: BackupRestoreMode.replace);
      expect((await harness.settings.load()).currencySymbol, '€');
    });
  });

  group('error handling', () {
    test('rejects malformed JSON instead of wiping data', () async {
      await addExpense(15000);

      expect(
        () => harness.backup.preview('{not json'),
        throwsA(isA<AppException>()),
      );
      await expectLater(
        harness.backup.restore('[]', mode: BackupRestoreMode.replace),
        throwsA(isA<AppException>()),
      );

      expect(await countAll(), 1, reason: 'a bad file must never destroy data');
    });

    test('rejects a document from an unknown future version', () async {
      await addExpense(15000);
      // createBackupJson pretty-prints, so there is a space after the colon.
      final json = await harness.backup
          .createBackupJson()
          .then((value) => value.replaceFirst('"version": 1', '"version": 99'));
      expect(json, contains('"version": 99'));

      expect(
        () => harness.backup.preview(json),
        throwsA(isA<AppException>()),
      );
      expect(await countAll(), 1);
    });
  });

  group('CSV / XLSX import', () {
    test('reads the standard nine columns and restores paise amounts',
        () async {
      // Byte-order mark and CRLF are exactly what an Excel "CSV UTF-8"
      // export produces.
      const text = '\uFEFF'
          'Date,Time,Type,Amount,Category,Income source,Payment method,Event,Note\r\n'
          '2026-09-05,10:30,expense,1234.50,Food,,Cash,,Lunch with team\r\n'
          '2026-09-06,09:00,income,50000,,Salary,,,September salary\r\n';

      final document = BackupFormats.fromCsv(text);
      expect(document['documentType'], BackupRepository.documentType);
      expect(document['version'], BackupRepository.formatVersion);

      final preview = harness.backup.previewDocument(document);
      expect(preview.transactions, 2);
      expect(preview.categories, 1);
      expect(preview.incomeSources, 1);
      expect(preview.paymentMethods, 1);
      expect(preview.specialEvents, 0);
      expect(preview.hasSettings, isFalse);

      final report = await harness.backup.restoreDocument(
        document,
        mode: BackupRestoreMode.merge,
      );
      expect(report.inserted, 2);
      expect(report.invalid, 0, reason: 'a valid row must pass validation');

      final rows =
          await harness.transactions.getTransactions(const TransactionFilter());
      expect(rows.map((r) => r.amountMinor).toSet(), {123450, 5000000});

      final lunch = rows.firstWhere((r) => r.note == 'Lunch with team');
      expect(lunch.amountMinor, 123450, reason: '1234.50 -> 123450 paise');
      expect(lunch.date, DateTime(2026, 9, 5));
      expect(lunch.time, '10:30');
      expect(lunch.type, TxType.expense);
      expect(lunch.categoryName, 'Food');
      expect(lunch.paymentMethodName, 'Cash');

      final salary = rows.firstWhere((r) => r.note == 'September salary');
      expect(salary.amountMinor, 5000000);
      expect(salary.type, TxType.income);
      expect(salary.incomeSourceName, 'Salary');

      // Restoring the same document again behaves like any backup merge.
      final again = await harness.backup.restoreDocument(
        document,
        mode: BackupRestoreMode.merge,
      );
      expect(again.inserted, 0);
      expect(again.skippedDuplicates, 2);
      expect(await countAll(), 2);
    });

    test('accepts currency symbols, thousands separators and day-first dates',
        () {
      const text = 'Date,Type,Amount,Category,Payment method\r\n'
          '05/09/2026,Expense,"₹1,234.50",Food,Cash\r\n'
          '06-09-2026,expense,Rs. 99.99,Food,Cash\r\n';

      final document = BackupFormats.fromCsv(text);
      final transactions = document['transactions'] as List;

      expect(transactions, hasLength(2));
      expect(
        transactions.map((row) => (row as Map<String, dynamic>)['amount']),
        unorderedEquals(<int>[123450, 9999]),
      );
      expect(
        transactions
            .map((row) => (row as Map<String, dynamic>)['date'])
            .toSet(),
        {'2026-09-05', '2026-09-06'},
      );
    });

    test('keeps a quoted note that contains a comma', () {
      const text = 'Date,Type,Amount,Category,Payment method,Note\r\n'
          '2026-09-05,expense,150,Food,Cash,"Dinner, drinks and dessert"\r\n';

      final document = BackupFormats.fromCsv(text);
      final row =
          (document['transactions'] as List).single as Map<String, dynamic>;

      expect(row['note'], 'Dinner, drinks and dessert');
      expect(row['amount'], 15000);
    });

    test('matches headers case-insensitively and tolerates missing columns',
        () {
      const text = 'DATE,Type,amount\r\n2026-09-05,Expense,10\r\n';

      final document = BackupFormats.fromCsv(text);
      final row =
          (document['transactions'] as List).single as Map<String, dynamic>;

      expect(row['type'], 'expense');
      expect(row['amount'], 1000);
      expect(row['time'], '00:00', reason: 'a blank time falls back');
      expect(row['category'], isNull);
      expect(row['note'], '');
      expect(document['categories'], isEmpty);

      expect(harness.backup.previewDocument(document).transactions, 1);
    });

    test('rejects malformed input with a message a user can act on', () {
      expect(
        () => BackupFormats.fromCsv('colour,amount\r\nred,5\r\n'),
        throwsA(
          isA<BackupFormatException>()
              .having((e) => e.message, 'message', contains('Date column')),
        ),
      );
      expect(
        () => BackupFormats.fromCsv('Date,Note\r\n2026-09-05,hello\r\n'),
        throwsA(
          isA<BackupFormatException>()
              .having((e) => e.message, 'message', contains('Amount column')),
        ),
      );
      expect(
        () => BackupFormats.fromCsv('   '),
        throwsA(isA<BackupFormatException>()),
      );
      expect(
        () => BackupFormats.fromCsv('Date,Amount\r\n'),
        throwsA(
          isA<BackupFormatException>()
              .having((e) => e.message, 'message', contains('rows')),
        ),
      );
    });

    test('round-trips an in-memory XLSX workbook', () async {
      final workbook = Excel.createExcel();
      final sheet = workbook.sheets.values.first;

      const headers = <String>[
        'Date',
        'Time',
        'Type',
        'Amount',
        'Category',
        'Income source',
        'Payment method',
        'Event',
        'Note',
      ];
      for (var c = 0; c < headers.length; c++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
            .value = TextCellValue(headers[c]);
      }

      // Row 1: every value typed in as text, the way a hand-filled sheet
      // arrives.
      const textRow = <String>[
        '2026-09-05',
        '10:30',
        'expense',
        '₹1,234.50',
        'Food',
        '',
        'Cash',
        '',
        'From a workbook',
      ];
      for (var c = 0; c < textRow.length; c++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 1))
            .value = TextCellValue(textRow[c]);
      }

      // Row 2: a date stored the way Excel really stores dates (a serial
      // number) and an amount stored as a raw number.
      final serial =
          DateTime(2026, 9, 6).difference(DateTime(1899, 12, 30)).inDays;
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2))
          .value = IntCellValue(serial);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 2))
          .value = TextCellValue('09:15');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 2))
          .value = TextCellValue('income');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 2))
          .value = DoubleCellValue(499.99);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 2))
          .value = TextCellValue('Freelance');

      final encoded = workbook.encode();
      expect(encoded, isNotNull);

      final document = BackupFormats.fromXlsx(encoded!);
      expect(harness.backup.previewDocument(document).transactions, 2);

      final transactions = document['transactions'] as List<Map<String, dynamic>>;

      final expense = transactions.firstWhere((r) => r['type'] == 'expense');
      expect(expense['amount'], 123450);
      expect(expense['date'], '2026-09-05');
      expect(expense['time'], '10:30');
      expect(expense['category'], 'Food');
      expect(expense['paymentMethod'], 'Cash');
      expect(expense['note'], 'From a workbook');

      final income = transactions.firstWhere((r) => r['type'] == 'income');
      expect(income['amount'], 49999, reason: '499.99 -> 49999 paise');
      expect(income['date'], '2026-09-06', reason: 'a serial-number date');
      expect(income['incomeSource'], 'Freelance');

      final report = await harness.backup.restoreDocument(
        document,
        mode: BackupRestoreMode.merge,
      );
      expect(report.inserted, 2);
      expect(report.invalid, 0);

      final rows =
          await harness.transactions.getTransactions(const TransactionFilter());
      expect(rows.map((r) => r.amountMinor).toSet(), {123450, 49999});
      expect(
        rows.map((r) => r.date).toSet(),
        {DateTime(2026, 9, 5), DateTime(2026, 9, 6)},
      );
    });

    test('refuses bytes that are not an .xlsx workbook', () {
      // A legacy .xls file is an OLE container, not a ZIP archive.
      expect(
        () => BackupFormats.fromXlsx(
          const [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1],
        ),
        throwsA(
          isA<BackupFormatException>()
              .having((e) => e.message, 'message', contains('.xlsx')),
        ),
      );
    });
  });

  group('account balances travel with a backup', () {
    Future<int> openingOf(String name) async {
      final rows = await harness.catalog.getAll(CatalogKind.paymentMethod);
      return rows.singleWhere((row) => row.name == name).openingBalanceMinor;
    }

    test('exports an opening balance, and only for payment methods', () async {
      final cash =
          await harness.catalog.findOrCreate(CatalogKind.paymentMethod, 'Cash');
      await harness.catalog
          .setOpeningBalance(CatalogKind.paymentMethod, cash, 500000);

      final document = await harness.backup.createBackup();

      final methods = document['paymentMethods'] as List<dynamic>;
      expect(methods, isNotEmpty);
      final cashRow = methods.firstWhere(
        (row) => row['name'] == 'Cash',
      ) as Map<String, dynamic>;
      expect(cashRow['openingBalance'], 500000);

      final categories = document['categories'] as List<dynamic>;
      expect(
        (categories.first as Map<String, dynamic>)
            .containsKey('openingBalance'),
        isFalse,
        reason: 'only accounts have a balance, so only they export one',
      );
    });

    test('a replace restore brings the saved balance back', () async {
      final cash =
          await harness.catalog.findOrCreate(CatalogKind.paymentMethod, 'Cash');
      await harness.catalog
          .setOpeningBalance(CatalogKind.paymentMethod, cash, 500000);
      final json = await harness.backup.createBackupJson();

      // The device has moved on since the backup was taken.
      await harness.catalog
          .setOpeningBalance(CatalogKind.paymentMethod, cash, 111111);
      expect(await openingOf('Cash'), 111111);

      await harness.backup.restore(json, mode: BackupRestoreMode.replace);

      expect(
        await openingOf('Cash'),
        500000,
        reason: 'a replace rebuilds the account exactly as it was saved',
      );
    });

    test('a merge never overwrites a balance the device already has', () async {
      final cash =
          await harness.catalog.findOrCreate(CatalogKind.paymentMethod, 'Cash');
      await harness.catalog
          .setOpeningBalance(CatalogKind.paymentMethod, cash, 500000);
      final json = await harness.backup.createBackupJson();

      await harness.catalog
          .setOpeningBalance(CatalogKind.paymentMethod, cash, 111111);

      await harness.backup.restore(json, mode: BackupRestoreMode.merge);

      expect(
        await openingOf('Cash'),
        111111,
        reason: 'a merge adds what is missing and changes nothing else',
      );
    });
  });
}
