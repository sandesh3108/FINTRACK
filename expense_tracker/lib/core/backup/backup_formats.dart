/// Reading transactions out of the two spreadsheet formats people actually
/// share: CSV text and `.xlsx` workbooks.
///
/// Both readers return the same backup document `createBackup()` writes, so
/// the restore path never needs to know which file the user picked: one
/// document shape, one preview, one merge.
///
/// Nothing here touches the database or the UI - it is a pure translation
/// from cells to integer paise and calendar dates.
library;

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

import '../config/app_config.dart';
import '../errors/app_exception.dart';
import '../utils/date_utils.dart';
import '../utils/money.dart';

/// Marker written into every backup document so files from other tools are
/// rejected instead of half-restored.
const String backupDocumentType = 'expense_tracker_backup';

/// Version of the document layout this build writes and understands.
const int backupFormatVersion = 1;

/// Raised when a picked file cannot be read as transactions.
///
/// The [message] is written for the person holding the file, so screens show
/// it unchanged instead of a library error nobody can act on.
class BackupFormatException extends AppException {
  const BackupFormatException(super.message, {super.technical});
}

/// The columns this app understands when reading a file, in
/// [AppConfig.sheetColumns] order, so a file this app wrote always reads back
/// and near-miss headings still map to the right field.
enum _Field {
  date,
  time,
  type,
  amount,
  category,
  incomeSource,
  paymentMethod,
  event,
  note;

  /// Heading the file is expected to carry, straight from the shared config.
  String get label => AppConfig.sheetColumns[index];
}

/// Header spellings that mean the same thing as a field.
///
/// People name columns slightly differently, so matching only the exact label
/// would force everyone to rename their file first.
const Map<_Field, List<String>> _aliases = <_Field, List<String>>{
  _Field.date: <String>['date', 'day', 'transaction date'],
  _Field.time: <String>['time', 'at'],
  _Field.type: <String>['type', 'kind', 'income or expense'],
  _Field.amount: <String>['amount', 'value', 'amt', 'total'],
  _Field.category: <String>['category', 'head', 'expense category'],
  _Field.incomeSource: <String>['income source', 'source', 'salary source'],
  _Field.paymentMethod: <String>['payment method', 'payment', 'method', 'paid by'],
  _Field.event: <String>['event', 'special event', 'occasion'],
  _Field.note: <String>['note', 'notes', 'description', 'remarks', 'details'],
};

/// Converts CSV text or XLSX bytes into the backup document the repository
/// restores.
///
/// Pure functions: no database, no widgets, and no money ever leaves integer
/// paise.
class BackupFormats {
  const BackupFormats._();

  // ------------------------------------------------------------------ read

  /// Reads CSV [source] into a backup document.
  ///
  /// Quoted fields, CRLF line endings and a byte-order mark are all handled.
  /// Columns are matched against [AppConfig.sheetColumns] case-insensitively;
  /// extra columns are ignored and missing ones fall back to sensible
  /// defaults. Only `Date` and `Amount` are required.
  static Map<String, dynamic> fromCsv(String source) => _fromRows(
        csvRows(source),
        label: 'That CSV',
      );

  /// Reads CSV [source] into raw rows, without looking at the headings.
  ///
  /// Exposed separately from [fromCsv] because the month-grid reader has to
  /// look at the *shape* of a file - months across the top - and would be
  /// rejected by heading matching before it ever got the chance. Callers that
  /// want transactions call [fromCsv]; callers that want to decide which
  /// reader to use call this first.
  ///
  /// Quoted fields, CRLF line endings and a byte-order mark are all handled.
  static List<List<Object?>> csvRows(String source) {
    // Excel writes a byte-order mark in front of the first heading. Strip it
    // up front so header matching never sees it.
    final text = source.startsWith('\uFEFF') ? source.substring(1) : source;
    if (text.trim().isEmpty) {
      throw const BackupFormatException('That CSV file is empty.');
    }

    final List<List<dynamic>> rows;
    try {
      // fieldDelimiter is left null so the decoder auto-detects `,`, `;`,
      // tab or `|` - spreadsheets export all four.
      rows = const CsvDecoder().convert(text);
    } catch (error) {
      throw BackupFormatException(
        'That CSV file could not be read.',
        technical: error.toString(),
      );
    }

    return <List<Object?>>[
      for (final row in rows) <Object?>[for (final cell in row) cell],
    ];
  }

  /// Reads the first worksheet of an XLSX [bytes] into a backup document.
  ///
  /// Excel may hand a date over as a real date value, as a serial number or
  /// as formatted text - all three are read. The legacy `.xls` format is a
  /// different binary container, so it is refused with a hint instead of a
  /// ZIP error.
  static Map<String, dynamic> fromXlsx(List<int> bytes) =>
      _fromRows(xlsxRows(bytes), label: 'That spreadsheet');

  /// Reads the first worksheet of an XLSX [bytes] into raw rows, without
  /// looking at the headings - see [csvRows] for why this exists.
  ///
  /// The legacy `.xls` format is a different binary container, so it is
  /// refused with a hint instead of a ZIP error.
  static List<List<Object?>> xlsxRows(List<int> bytes) {
    // ZIP archives (and therefore workbooks) start with the letters PK.
    if (bytes.length < 2 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
      throw const BackupFormatException(
        'That file is not an .xlsx workbook. Re-save the spreadsheet as '
        '.xlsx and try again.',
      );
    }

    final Excel workbook;
    try {
      workbook = Excel.decodeBytes(bytes);
    } catch (error) {
      throw BackupFormatException(
        'That workbook could not be opened. Re-save the spreadsheet as '
        '.xlsx and try again.',
        technical: error.toString(),
      );
    }

    final sheets = workbook.sheets;
    if (sheets.isEmpty) {
      throw const BackupFormatException('That workbook has no worksheets.');
    }

    final sheet = sheets.values.first;
    final rowCount = sheet.maxRows;
    final columnCount = sheet.maxColumns;
    final rows = <List<Object?>>[];
    try {
      for (var r = 0; r < rowCount; r++) {
        final row = <Object?>[];
        for (var c = 0; c < columnCount; c++) {
          row.add(
            sheet
                .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
                .value,
          );
        }
        rows.add(row);
      }
    } catch (error) {
      throw BackupFormatException(
        'That workbook could not be read.',
        technical: error.toString(),
      );
    }

    return rows;
  }

  // --------------------------------------------------------------- parsing

  /// Validates the header of [rows] and turns the body into a document in the
  /// exact shape `createBackup()` writes, so preview and restore treat a
  /// spreadsheet exactly like a JSON backup.
  ///
  /// [label] opens every message (`That CSV`, `That spreadsheet`) so the
  /// wording stays actionable.
  static Map<String, dynamic> _fromRows(
    List<List<Object?>> rows, {
    required String label,
  }) {
    final headerIndex = rows.indexWhere(_hasContent);
    if (headerIndex < 0) throw BackupFormatException('$label is empty.');

    final columns = _mapColumns(rows[headerIndex]);
    if (columns[_Field.date]! < 0) {
      throw BackupFormatException('$label has no recognisable Date column.');
    }
    if (columns[_Field.amount]! < 0) {
      throw BackupFormatException('$label has no recognisable Amount column.');
    }

    final body = <List<Object?>>[
      for (var i = headerIndex + 1; i < rows.length; i++)
        if (_hasContent(rows[i])) rows[i],
    ];
    if (body.isEmpty) {
      throw BackupFormatException('$label has no rows below its header.');
    }

    final now = DateTime.now().toIso8601String();
    final categories = <String>{};
    final incomeSources = <String>{};
    final paymentMethods = <String>{};
    final events = <String, DateTime>{};
    final transactions = <Map<String, dynamic>>[];

    for (final row in body) {
      final date = AppDates.tryParseDate(_dateCell(row, columns[_Field.date]!));
      if (date == null) continue;

      final amountText = _textCell(row, columns[_Field.amount]!);
      final amount = _amountToMinor(amountText);
      if (amount == null || amount <= 0) continue;

      final timeText = _textCell(row, columns[_Field.time]!);
      final time = AppDates.tryParseTime(timeText) ?? '00:00';

      final category = _textCell(row, columns[_Field.category]!);
      final incomeSource = _textCell(row, columns[_Field.incomeSource]!);
      final paymentMethod = _textCell(row, columns[_Field.paymentMethod]!);
      final event = _textCell(row, columns[_Field.event]!);
      final note = _textCell(row, columns[_Field.note]!);

      if (category.isNotEmpty) categories.add(category);
      if (incomeSource.isNotEmpty) incomeSources.add(incomeSource);
      if (paymentMethod.isNotEmpty) paymentMethods.add(paymentMethod);
      if (event.isNotEmpty) {
        final seen = events[event];
        if (seen == null || date.isBefore(seen)) events[event] = date;
      }

      transactions.add(<String, dynamic>{
        // No `id`: these rows do not exist yet. Restore reads only the keys
        // below, and the catalog lists it needs to resolve the names.
        'type': _typeOf(
          _textCell(row, columns[_Field.type]!),
          category: category,
          incomeSource: incomeSource,
        ),
        'amount': amount,
        'date': AppDates.isoDay(date),
        'time': time,
        'category': category.isEmpty ? null : category,
        'incomeSource': incomeSource.isEmpty ? null : incomeSource,
        'paymentMethod': paymentMethod.isEmpty ? null : paymentMethod,
        'specialEvent': event.isEmpty ? null : event,
        'note': note,
        'createdAt': now,
        'updatedAt': now,
      });
    }

    if (transactions.isEmpty) {
      throw const BackupFormatException(
        'None of the rows in that file could be read. Check the Date and '
        'Amount columns.',
      );
    }

    return _document(
      transactions: transactions,
      categories: categories,
      incomeSources: incomeSources,
      paymentMethods: paymentMethods,
      events: events,
      createdAt: now,
    );
  }

  /// Assembles the document `createBackup()` would have written.
  ///
  /// Catalog rows are derived from the names on the transactions, because
  /// restore creates whatever is missing with `findOrCreate`: a CSV that
  /// says "Food" has to list it exactly like a JSON backup does, or the row
  /// would restore without a category.
  static Map<String, dynamic> _document({
    required List<Map<String, dynamic>> transactions,
    required Set<String> categories,
    required Set<String> incomeSources,
    required Set<String> paymentMethods,
    required Map<String, DateTime> events,
    required String createdAt,
  }) =>
      <String, dynamic>{
        'documentType': backupDocumentType,
        'version': backupFormatVersion,
        'createdAt': createdAt,
        'app': 'expense_tracker',
        'categories': [
          for (final name in categories) <String, dynamic>{'name': name},
        ],
        'incomeSources': [
          for (final name in incomeSources) <String, dynamic>{'name': name},
        ],
        'paymentMethods': [
          for (final name in paymentMethods) <String, dynamic>{'name': name},
        ],
        'specialEvents': [
          for (final entry in events.entries)
            <String, dynamic>{
              'name': entry.key,
              'startDate': AppDates.isoDay(entry.value),
              'endDate': null,
            },
        ],
        'transactions': transactions,
      };

  /// Index of each field's column in the header row, or -1 when the file
  /// simply does not carry it. Matching ignores case and also accepts the
  /// common aliases.
  static Map<_Field, int> _mapColumns(List<Object?> header) {
    final columns = <_Field, int>{};
    for (final field in _Field.values) {
      var index = -1;
      for (var i = 0; i < header.length && index < 0; i++) {
        final cell = _text(header[i]).toLowerCase();
        if (cell.isEmpty) continue;
        if (cell == field.label.toLowerCase() ||
            (_aliases[field]?.contains(cell) ?? false)) {
          index = i;
        }
      }
      columns[field] = index;
    }
    return columns;
  }

  /// True when at least one cell carries text - blank spacer rows are
  /// skipped wherever they appear.
  static bool _hasContent(List<Object?> row) =>
      row.any((cell) => _text(cell).isNotEmpty);

  /// One cell as trimmed text. Excel cell values render themselves to text
  /// (a text cell keeps its plain string, a date cell renders ISO), so one
  /// rule covers both readers.
  static String _text(Object? cell) =>
      cell == null ? '' : cell.toString().trim();

  /// Column [column] of [row] as text; a missing column reads as empty.
  static String _textCell(List<Object?> row, int column) =>
      column < 0 || column >= row.length ? '' : _text(row[column]);

  /// The Date column as text `AppDates.tryParseDate` understands.
  ///
  /// A cell typed as a date or a date-time is read directly; a bare number
  /// is an Excel serial (days since 30 Dec 1899); anything else is treated
  /// as formatted text.
  static String _dateCell(List<Object?> row, int column) {
    if (column < 0 || column >= row.length) return '';
    final cell = row[column];
    if (cell is DateCellValue) return AppDates.isoDay(cell.asDateTimeLocal());
    if (cell is DateTimeCellValue) {
      return AppDates.isoDay(cell.asDateTimeLocal());
    }
    if (cell is IntCellValue) return _serialDay(cell.value);
    if (cell is DoubleCellValue) return _serialDay(cell.value);
    return _text(cell);
  }

  /// Excel serial number -> `yyyy-MM-dd`. Values outside the serial range
  /// come back as text so the row is skipped rather than misdated.
  static String _serialDay(num serial) {
    if (serial < 1 || serial > 2958465) return serial.toString();
    return AppDates.isoDay(
      DateTime(1899, 12, 30).add(Duration(days: serial.floor())),
    );
  }

  /// The same reading the Google Sheets importer does: income / expense in
  /// any case, and when the column is blank an income source on the row
  /// means income. Returns the value stored in the backup document.
  static String _typeOf(
    String raw, {
    required String category,
    required String incomeSource,
  }) {
    final typeText = raw.toLowerCase();
    if (typeText.contains('incom')) return 'income';
    if (typeText.isNotEmpty && typeText.contains('exp')) return 'expense';
    return incomeSource.isNotEmpty && category.isEmpty ? 'income' : 'expense';
  }

  /// `1234`, `1,234.50`, `₹1,234.50` or `Rs. 1234.5` -> `123450` paise.
  ///
  /// The entry point other readers use, so every file path agrees on what a
  /// number in a cell means. See [_amountToMinor] for the rules.
  static int? amountToMinor(String raw) => _amountToMinor(raw);

  /// `1234`, `1,234.50`, `₹1,234.50` or `Rs. 1234.5` -> `123450` paise.
  ///
  /// Currency words and symbols are decoration, so they are stripped before
  /// the shared money parser sees the number. More than two decimals are
  /// rounded half-up rather than rejected, because spreadsheets happily
  /// store `1234.567`.
  static int? _amountToMinor(String raw) {
    var cleaned = raw.trim();
    if (cleaned.isEmpty) return null;
    cleaned = cleaned.replaceAll(
      RegExp(r'(?:rs\.?|inr|[$₹€£¥])', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(RegExp(r'[,\s_]'), '');
    cleaned = _roundToTwoDecimals(cleaned);
    return cleaned.isEmpty ? null : parseImportedMoney(cleaned);
  }

  /// Rounds the decimal string to two places using integer maths only, so
  /// money never touches a float.
  static String _roundToTwoDecimals(String value) {
    final dot = value.indexOf('.');
    if (dot < 0 || value.length - dot - 1 <= 2) return value;

    var whole = value.substring(0, dot);
    final fraction = value.substring(dot + 1);
    var cents = int.tryParse(fraction.substring(0, 2));
    if (cents == null) return value;

    // Half-up: the third decimal decides, everything after it is noise.
    if (fraction.codeUnitAt(2) >= 0x35) {
      cents += 1;
      if (cents > 99) {
        cents = 0;
        final rupees = int.tryParse(whole);
        if (rupees != null) whole = '${rupees + 1}';
      }
    }
    return '$whole.${cents.toString().padLeft(2, '0')}';
  }
}
