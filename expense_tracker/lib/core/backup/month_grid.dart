/// Reading a *month grid* sheet: months across the top, days down the side.
///
/// The layout people keep for their own budgeting does not look like the
/// tidy one-row-per-transaction export this app writes. It looks like
///
/// ```text
///   Date/Months | Jan          | Feb          | ...
///               | Things|Amount| Things|Amount|
///   1           | rent  |  800 |        |      |
///   2           | hotel | 1200 |        |      |
///   ...
///   Totals      | 4,300 |      |  ...          |
///
///   Mumbai (8-9)
///               | Things | Amount       |
///   sweets      |  500
/// ```
///
/// [MonthGridReader.detect] recognises that shape and flattens it into
/// [GridEntry] rows. Anything it is not confident about returns `null`, so
/// the caller falls back to the ordinary column-matching reader and a file
/// that merely mentions a month or two is never half-imported.
///
/// The blocks *below* the main table each become a special event: their
/// heading (`Mumbai (8-9)`) is the event name and the parenthesised day
/// numbers give it a window. Rows in the main table carry no event, which is
/// what keeps them in the monthly totals.
///
/// Pure translation from cells to integer paise - no database, no widgets.
library;

import 'dart:math' as math;

import 'backup_formats.dart';

/// One row read out of a month grid.
class GridEntry {
  const GridEntry({
    required this.month,
    required this.day,
    required this.things,
    required this.amountMinor,
    this.eventName,
    this.eventEndDay,
  });

  /// Month of the column this came from (1-12), or `null` for a row in a
  /// block below the table, which names days but never a month.
  final int? month;

  /// Day of the month, 1-31.
  final int day;

  /// The `Things` cell - what was bought, who it was for. Becomes the
  /// category (or income source) of the transaction.
  final String things;

  /// Whole rupees * 100; never a float.
  final int amountMinor;

  /// Event this row belongs to, or `null` for a regular monthly row.
  final String? eventName;

  /// Last day of the event window when the heading gave a range
  /// (`Mumbai (8-9)`), otherwise `null`.
  final int? eventEndDay;

  bool get isEvent => eventName != null;
}

/// The result of recognising a month-grid sheet.
class MonthGrid {
  const MonthGrid({
    required this.entries,
    required this.monthCount,
    required this.blockNames,
    required this.skipped,
  });

  /// Every row found, main table first, then the event blocks.
  final List<GridEntry> entries;

  /// How many month columns were recognised - shown in the preview so a
  /// half-detected sheet is obvious before anything is written.
  final int monthCount;

  /// Event names in the order their blocks appear.
  final List<String> blockNames;

  /// Rows that had no readable amount, counted so the preview can say so
  /// instead of quietly dropping them.
  final int skipped;

  /// Rows that belong to the monthly table.
  Iterable<GridEntry> get regular => entries.where((e) => !e.isEvent);

  /// Rows that belong to a special event block.
  Iterable<GridEntry> get eventRows => entries.where((e) => e.isEvent);

  /// True when the file carried a main table at all - a file that only had
  /// blocks would still import, but deserves a different preview message.
  bool get hasRegular => regular.isNotEmpty;
}

/// Recognises and reads the month-grid layout.
class MonthGridReader {
  const MonthGridReader._();

  /// Month spellings people actually use, folded to letters only.
  static const Map<String, int> _months = <String, int>{
    'jan': 1,
    'january': 1,
    'feb': 2,
    'february': 2,
    'mar': 3,
    'march': 3,
    'apr': 4,
    'april': 4,
    'may': 5,
    'jun': 6,
    'june': 6,
    'jul': 7,
    'july': 7,
    'aug': 8,
    'august': 8,
    'sep': 9,
    'sept': 9,
    'september': 9,
    'oct': 10,
    'october': 10,
    'nov': 11,
    'november': 11,
    'dec': 12,
    'december': 12,
  };

  /// What the `Things` column might be called.
  static const Set<String> _things = <String>{
    'thing',
    'things',
    'item',
    'items',
    'description',
    'detail',
    'details',
    'particulars',
    'purpose',
    'head',
    'what',
    'name',
    'category',
    'note',
    'notes',
    'remark',
    'remarks',
  };

  /// What the `Amount` column might be called.
  static const Set<String> _amount = <String>{
    'amount',
    'amt',
    'cost',
    'price',
    'value',
    'rs',
    'rupees',
    'spend',
    'spent',
    'money',
    'total',
  };

  /// A row that ends a table rather than adding to it.
  static const Set<String> _totals = <String>{
    'total',
    'totals',
    'grandtotal',
    'sum',
    'monthlytotal',
  };

  /// How far down to look for the month header, and for each block's own
  /// Things / Amount header. Real sheets put both near the top of their
  /// section; a larger window only invites false positives.
  static const int _headerScanRows = 60;
  static const int _blockHeaderScanRows = 8;

  /// Fewest month columns worth calling a month grid.
  static const int _minMonthColumns = 4;

  /// Returns the rows of [rows] as a grid, or `null` when the file does not
  /// have this shape.
  ///
  /// Never throws: a file that cannot be read as a grid simply falls back to
  /// the standard reader, which explains its own failures.
  static MonthGrid? detect(List<List<Object?>> rows) {
    if (rows.isEmpty) return null;

    // ---------------------------------------------------------- the header
    var headerIndex = -1;
    var months = <int, int>{}; // column -> month number
    for (var r = 0; r < rows.length && r < _headerScanRows; r++) {
      final found = <int, int>{};
      for (var c = 0; c < rows[r].length; c++) {
        final month = _monthOf(rows[r][c]);
        if (month != null) found[c] = month;
      }
      if (found.length >= _minMonthColumns) {
        headerIndex = r;
        months = found;
        break;
      }
    }
    if (headerIndex < 0) return null;
    if (headerIndex + 1 >= rows.length) return null;

    // -------------------------------------------- Things / Amount per month
    final subHeader = rows[headerIndex + 1];
    final spans = _spans(months, rows[headerIndex].length, subHeader.length);
    final columns = <_GridColumns>[];
    for (final span in spans) {
      var things = -1;
      var amount = -1;
      for (var c = span.from; c <= span.to; c++) {
        final text = _cell(subHeader, c);
        if (text.isEmpty) continue;
        final folded = _fold(text);
        if (things < 0 && _things.contains(folded)) {
          things = c;
        } else if (amount < 0 && _amount.contains(folded)) {
          amount = c;
        }
      }
      if (things >= 0 && amount >= 0) {
        columns.add(
          _GridColumns(month: span.month, things: things, amount: amount),
        );
      }
    }
    if (columns.length < _minMonthColumns) return null;

    // ------------------------------------------------------------ day rows
    final dayColumn = _dayColumn(rows, headerIndex + 2);
    if (dayColumn < 0) return null;

    final entries = <GridEntry>[];
    var skipped = 0;
    var r = headerIndex + 2;
    for (; r < rows.length; r++) {
      final day = _dayOf(_value(rows[r], dayColumn));
      if (day == null) break; // Totals, a spacer, or the blocks below
      for (final column in columns) {
        final amount =
            BackupFormats.amountToMinor(_cell(rows[r], column.amount));
        if (amount == null) {
          if (_cell(rows[r], column.things).isNotEmpty) skipped++;
          continue;
        }
        entries.add(
          GridEntry(
            month: column.month,
            day: day,
            things: _cell(rows[r], column.things),
            amountMinor: amount,
          ),
        );
      }
    }
    final tableEnd = r;

    // -------------------------------------------------- the blocks below
    final (names: blockNames, skipped: blockSkipped) =
        _readBlocks(rows, tableEnd, entries);
    skipped += blockSkipped;

    if (entries.isEmpty) return null;

    return MonthGrid(
      entries: entries,
      monthCount: columns.length,
      blockNames: blockNames,
      skipped: skipped,
    );
  }

  // -------------------------------------------------------------- blocks

  /// Walks from [start] collecting `Heading` + `Things|Amount` sections.
  ///
  /// Each heading becomes an event; its day numbers come from the brackets
  /// in the heading, because a block names days and never a month. Returns
  /// the event names in order and how many of their rows had no amount.
  static ({List<String> names, int skipped}) _readBlocks(
    List<List<Object?>> rows,
    int start,
    List<GridEntry> entries,
  ) {
    final names = <String>[];
    var skipped = 0;
    var r = start;

    while (r < rows.length) {
      // A block heading is a row with exactly one populated cell.
      while (r < rows.length && _nonEmpty(rows[r]) != 1) {
        r++;
      }
      if (r >= rows.length) break;
      final heading = _firstText(rows[r]);
      r++;

      // The block's own Things / Amount header, a few rows down.
      var headerRow = -1;
      final limit = math.min(r + _blockHeaderScanRows, rows.length);
      for (var probe = r; probe < limit; probe++) {
        if (_isPairRow(rows[probe])) {
          headerRow = probe;
          break;
        }
        // A second heading before any header means this was not a block.
        if (probe > r && _nonEmpty(rows[probe]) == 1) break;
      }
      if (headerRow < 0) continue;

      final thingsColumn = _pairColumn(rows[headerRow], _things);
      final amountColumn = _pairColumn(rows[headerRow], _amount);
      if (thingsColumn < 0 && amountColumn < 0) continue;

      r = headerRow + 1;
      final label = _eventName(heading);
      final (startDay, endDay) = _eventDays(heading);
      var added = 0;

      while (r < rows.length) {
        final count = _nonEmpty(rows[r]);
        if (count == 0 || count == 1) break; // spacer, next heading, Total
        if (_totals.contains(_fold(_firstText(rows[r])))) break;

        final amount =
            BackupFormats.amountToMinor(_cell(rows[r], amountColumn));
        if (amount == null) {
          if (_cell(rows[r], thingsColumn).isNotEmpty) skipped++;
        } else {
          entries.add(
            GridEntry(
              month: null,
              day: startDay,
              things: _cell(rows[r], thingsColumn),
              amountMinor: amount,
              eventName: label,
              eventEndDay: endDay,
            ),
          );
          added++;
        }
        r++;
      }

      if (added > 0) names.add(label);
    }

    return (names: names, skipped: skipped);
  }

  // ------------------------------------------------------------- helpers

  /// Splits the month header row into one span per month: `Jan` sits at
  /// column 3 and `Feb` at 5, so January owns columns 3-4.
  static List<_Span> _spans(
    Map<int, int> months,
    int headerLength,
    int subHeaderLength,
  ) {
    final sorted = months.keys.toList()..sort();
    final width = math.max(headerLength, subHeaderLength);
    final spans = <_Span>[];
    for (var i = 0; i < sorted.length; i++) {
      final from = sorted[i];
      final to = i + 1 < sorted.length ? sorted[i + 1] - 1 : width - 1;
      if (to < from) continue;
      spans.add(_Span(month: months[from]!, from: from, to: to));
    }
    return spans;
  }

  /// Which of the first three columns holds the day numbers.
  ///
  /// Some sheets leave a margin column empty. Trying a couple of candidates
  /// and taking the one that behaves like a day counter is cheaper than
  /// guessing, and a file with no such column falls out as "not a grid".
  static int _dayColumn(List<List<Object?>> rows, int from) {
    var best = -1;
    var bestCount = 0;
    for (var c = 0; c < 3; c++) {
      var count = 0;
      for (var r = from; r < math.min(from + 12, rows.length); r++) {
        if (_dayOf(_value(rows[r], c)) != null) count++;
      }
      if (count > bestCount) {
        best = c;
        bestCount = count;
      }
    }
    return bestCount >= 3 ? best : -1;
  }

  /// `Mumbai (8-9)` -> `Mumbai`; an unbracketed heading is used as-is, and
  /// an empty one becomes `Event`, so no row is ever filed under nothing.
  static String _eventName(String heading) {
    final trimmed = heading.trim();
    final stripped =
        trimmed.replaceFirst(RegExp(r'\s*\([^)]*\)\s*$'), '').trim();
    return stripped.isEmpty ? (trimmed.isEmpty ? 'Event' : trimmed) : stripped;
  }

  /// `(14)` -> day 14, no end; `(8-9)` -> days 8 to 9; nothing recognisable
  /// -> day 1, which files the event at the start of the chosen month
  /// rather than dropping it.
  static (int, int?) _eventDays(String heading) {
    final match = RegExp(r'\((\d{1,2})(?:\s*[-–]\s*(\d{1,2}))?\)')
        .firstMatch(heading);
    if (match == null) return (1, null);

    final first = int.tryParse(match.group(1) ?? '');
    if (first == null || first < 1 || first > 31) return (1, null);

    final second = int.tryParse(match.group(2) ?? '');
    if (second == null || second < first || second > 31) return (first, null);
    return (first, second);
  }

  /// The month number of one header cell, or `null`.
  static int? _monthOf(Object? cell) {
    final folded = _fold(_text(cell));
    return folded.isEmpty ? null : _months[folded];
  }

  /// Reads one cell of one row as a day number, or `null`.
  ///
  /// Numeric cells come through as `1` or `1.0`; text cells may be `1.` or
  /// `01`. Anything outside 1-31 is not a day, which is also what stops a
  /// date column or an amount column being mistaken for one.
  static int? _dayOf(Object? cell) {
    if (cell == null) return null;
    if (cell is num) {
      final value = cell.toInt();
      return value >= 1 && value <= 31 ? value : null;
    }
    final text = _text(cell);
    if (text.isEmpty) return null;
    final value = double.tryParse(text.replaceAll(RegExp(r'[^\d.\-]'), ''));
    if (value == null || value.isNaN) return null;
    final day = value.round();
    return day >= 1 && day <= 31 ? day : null;
  }

  /// True when a row carries both halves of a Things / Amount pair.
  static bool _isPairRow(List<Object?> row) {
    var things = false;
    var amount = false;
    for (final cell in row) {
      final folded = _fold(_text(cell));
      if (folded.isEmpty) continue;
      if (_things.contains(folded)) things = true;
      if (_amount.contains(folded)) amount = true;
    }
    return things && amount;
  }

  /// Column of the first cell of [row] matching [words].
  static int _pairColumn(List<Object?> row, Set<String> words) {
    for (var c = 0; c < row.length; c++) {
      if (words.contains(_fold(_text(row[c])))) return c;
    }
    return -1;
  }

  static int _nonEmpty(List<Object?> row) {
    var count = 0;
    for (final cell in row) {
      if (_text(cell).isNotEmpty) count++;
    }
    return count;
  }

  static String _firstText(List<Object?> row) {
    for (final cell in row) {
      final text = _text(cell);
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  /// One cell as trimmed text.
  static String _text(Object? cell) =>
      cell == null ? '' : cell.toString().trim();

  /// One cell of [row], or `null` when the row is shorter than [column] -
  /// spreadsheets hand back ragged rows, so indexing has to be guarded.
  static Object? _value(List<Object?> row, int column) =>
      column < 0 || column >= row.length ? null : row[column];

  static String _cell(List<Object?> row, int column) =>
      _text(_value(row, column));

  /// Lower-case letters only, so `Things ` and `THINGS` and `Things:` all
  /// fold to `things`.
  static String _fold(String raw) =>
      raw.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
}

/// One month's share of the header row.
class _Span {
  const _Span({required this.month, required this.from, required this.to});

  final int month;
  final int from;
  final int to;
}

/// Where the Things and Amount columns of one month landed.
class _GridColumns {
  const _GridColumns({
    required this.month,
    required this.things,
    required this.amount,
  });

  final int month;
  final int things;
  final int amount;
}
