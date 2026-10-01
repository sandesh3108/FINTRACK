import 'package:expense_tracker/core/backup/month_grid.dart';
import 'package:flutter_test/flutter_test.dart';

/// The month-grid reader.
///
/// The layout under test is the one people keep for themselves: months across
/// the top, each split into Things / Amount, days down the left, a Totals row
/// at the bottom, and separate blocks below the table for parties and trips.
void main() {
  /// Builds a 12-month sheet of that shape.
  ///
  /// Month headings sit at odd columns (1, 3, 5 ...) so each one owns a pair
  /// of sub-columns, which is how a merged header comes back from Excel.
  List<List<Object?>> buildSheet() {
    const months = <String>[
      'Jan', 'Feb', 'March', 'April', 'May', 'June',
      'July', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final width = 1 + months.length * 2;
    final rows = <List<Object?>>[];

    final header = List<Object?>.filled(width, null);
    header[0] = 'Date/Months';
    for (var i = 0; i < months.length; i++) {
      header[1 + i * 2] = months[i];
    }
    rows.add(header);

    final subHeader = List<Object?>.filled(width, null);
    for (var i = 0; i < months.length; i++) {
      subHeader[1 + i * 2] = 'Things';
      subHeader[2 + i * 2] = 'Amount';
    }
    rows.add(subHeader);

    void addDay(int day, Map<int, (String, Object?)> spend) {
      final row = List<Object?>.filled(width, null);
      row[0] = day;
      spend.forEach((month, value) {
        row[1 + month * 2] = value.$1;
        row[2 + month * 2] = value.$2;
      });
      rows.add(row);
    }

    addDay(1, {0: ('rentina', 800), 1: ('brother', 1200)});
    addDay(2, {0: ('hotel chatpati', 450), 11: ('gift', 300)});
    // A description with no amount beside it: readable, but not money.
    addDay(3, {0: ('pending', null)});
    addDay(4, {0: ('travel', 250)});

    final totals = List<Object?>.filled(width, null);
    totals[0] = 'Totals';
    totals[1] = '1500';
    rows.add(totals);

    rows.add(List<Object?>.filled(width, null)); // spacer

    // An event block: heading, its own Things / Amount header, rows, total.
    rows.add(<Object?>['Mumbai (8-9)']);
    rows.add(<Object?>[null, 'Things', 'Amount']);
    rows.add(<Object?>[null, 'sweets', 500]);
    rows.add(<Object?>[null, 'cake', 600]);
    rows.add(<Object?>[null, 'Total', 1100]);

    rows.add(List<Object?>.filled(width, null));

    rows.add(<Object?>['Birthday (14)']);
    rows.add(<Object?>['Things', 'Amount']);
    rows.add(<Object?>['flowers', 200]);
    rows.add(<Object?>['decorations', 100]);

    return rows;
  }

  group('month grid', () {
    test('reads the month columns, the day rows and the money', () {
      final grid = MonthGridReader.detect(buildSheet());

      expect(grid, isNotNull);
      expect(grid!.monthCount, 12, reason: 'all twelve month columns');

      final regular = grid.regular.toList();
      expect(regular, hasLength(5));

      final jan1 = regular.firstWhere((e) => e.month == 1 && e.day == 1);
      expect(jan1.things, 'rentina');
      expect(jan1.amountMinor, 80000, reason: 'rupees become paise');
      expect(jan1.eventName, isNull,
          reason: 'the monthly table must stay out of the event totals');

      final feb1 = regular.firstWhere((e) => e.month == 2 && e.day == 1);
      expect(feb1.things, 'brother');
      expect(feb1.amountMinor, 120000);

      // Days 2, 3 and 4 all belong to January; only the day-4 travel row has
      // money in it, so 1 (Jan), 1 (Feb), 2 (Jan), 4 (Jan) survive - day 3
      // had no amount at all.
      expect(
        regular.where((e) => e.day == 3),
        isEmpty,
        reason: 'a row with no amount is not a transaction',
      );
      expect(regular.last.month, 1);
      expect(regular.last.day, 4);
      expect(regular.last.amountMinor, 25000);
    });

    test('turns each block below the table into an event', () {
      final grid = MonthGridReader.detect(buildSheet())!;

      expect(grid.blockNames, <String>['Mumbai', 'Birthday'],
          reason: 'the brackets hold the dates, not the name');

      final eventRows = grid.eventRows.toList();
      expect(eventRows, hasLength(4));
      expect(eventRows.every((e) => e.isEvent), isTrue);

      final mumbai = eventRows.where((e) => e.eventName == 'Mumbai').toList();
      expect(mumbai, hasLength(2));
      expect(mumbai.first.day, 8, reason: 'from Mumbai (8-9)');
      expect(mumbai.first.eventEndDay, 9);
      expect(mumbai.map((e) => e.things), <String>['sweets', 'cake']);
      expect(mumbai.map((e) => e.amountMinor), <int>[50000, 60000]);
      expect(mumbai.first.month, isNull,
          reason: 'a block names days but never a month');

      final birthday =
          eventRows.where((e) => e.eventName == 'Birthday').toList();
      expect(birthday, hasLength(2));
      expect(birthday.first.day, 14);
      expect(birthday.first.eventEndDay, isNull, reason: '(14) is one day');
      expect(birthday.map((e) => e.amountMinor), <int>[20000, 10000]);
    });

    test('counts a row it could not read instead of losing it', () {
      final grid = MonthGridReader.detect(buildSheet())!;
      expect(grid.skipped, 1, reason: 'day 3 had a Things cell, no amount');
    });
  });

  group('files that are not month grids', () {
    test('this app\'s own export is left to the ordinary reader', () {
      final rows = <List<Object?>>[
        <Object?>['Date', 'Type', 'Amount', 'Category'],
        <Object?>['2026-01-05', 'expense', '120.00', 'Food'],
        <Object?>['2026-01-06', 'income', '5000.00', 'Salary'],
      ];
      expect(MonthGridReader.detect(rows), isNull);
    });

    test('two months is not enough to claim the shape', () {
      final rows = <List<Object?>>[
        <Object?>['Date/Months', 'Jan', null, 'Feb', null],
        <Object?>[null, 'Things', 'Amount', 'Things', 'Amount'],
        <Object?>[1, 'rent', 800, null, null],
      ];
      expect(MonthGridReader.detect(rows), isNull);
    });

    test('a sheet with months but no day column is refused', () {
      final rows = <List<Object?>>[
        <Object?>[null, 'Jan', null, 'Feb', null, 'March', null, 'April'],
        <Object?>[null, 'Things', 'Amount', 'Things', 'Amount',
          'Things', 'Amount', 'Things', 'Amount'],
        <Object?>[null, 'rent', 800, null, null, null, null, null, null],
      ];
      expect(MonthGridReader.detect(rows), isNull);
    });

    test('an empty sheet is refused rather than throwing', () {
      expect(MonthGridReader.detect(const <List<Object?>>[]), isNull);
      expect(MonthGridReader.detect(<List<Object?>>[const <Object?>[]]), isNull);
    });
  });
}
