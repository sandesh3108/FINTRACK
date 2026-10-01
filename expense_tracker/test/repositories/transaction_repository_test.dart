import 'package:expense_tracker/core/errors/app_exception.dart';
import 'package:expense_tracker/shared/models/catalog_item.dart';
import 'package:expense_tracker/shared/models/range_spec.dart';
import 'package:expense_tracker/shared/models/transaction_filter.dart';
import 'package:expense_tracker/shared/models/transaction_input.dart';
import 'package:expense_tracker/shared/models/tx_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_harness.dart';

void main() {
  late TestHarness harness;

  setUp(() => harness = TestHarness());
  tearDown(() => harness.close());

  final september = RangeSpec.month(2026, 9);
  final august = RangeSpec.month(2026, 8);
  final day5 = DateTime(2026, 9, 5);
  final day10 = DateTime(2026, 9, 10);
  final day10b = DateTime(2026, 9, 10);
  final day20 = DateTime(2026, 8, 20);

  Future<int> expense(
    int amount, {
    required DateTime date,
    String category = 'Food',
    String time = '10:00',
    String note = '',
  }) async {
    final categoryId =
        await harness.catalog.findOrCreate(CatalogKind.category, category);
    final paymentMethodId =
        await harness.catalog.findOrCreate(CatalogKind.paymentMethod, 'Cash');
    return harness.transactions.add(
      TransactionInput(
        type: TxType.expense,
        amountMinor: amount,
        date: date,
        time: time,
        categoryId: categoryId,
        paymentMethodId: paymentMethodId,
        note: note,
      ),
    );
  }

  Future<int> income(
    int amount, {
    required DateTime date,
    String source = 'Salary',
    String time = '09:00',
  }) async {
    final incomeSourceId =
        await harness.catalog.findOrCreate(CatalogKind.incomeSource, source);
    return harness.transactions.add(
      TransactionInput(
        type: TxType.income,
        amountMinor: amount,
        date: date,
        time: time,
        incomeSourceId: incomeSourceId,
      ),
    );
  }

  group('validation', () {
    test('rejects a zero or negative amount', () async {
      await expectLater(
        harness.transactions.add(
          TransactionInput(
            type: TxType.expense,
            amountMinor: 0,
            date: day5,
            time: '10:00',
            categoryId: 1,
            paymentMethodId: 1,
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('requires a category and payment method for expenses', () async {
      await expectLater(
        harness.transactions.add(
          TransactionInput(
            type: TxType.expense,
            amountMinor: 100,
            date: day5,
            time: '10:00',
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('requires an income source for income', () async {
      await expectLater(
        harness.transactions.add(
          TransactionInput(
            type: TxType.income,
            amountMinor: 100,
            date: day5,
            time: '10:00',
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects an unknown time', () async {
      final salary = await harness.catalog
          .findOrCreate(CatalogKind.incomeSource, 'Salary');
      await expectLater(
        harness.transactions.add(
          TransactionInput(
            type: TxType.income,
            amountMinor: 100,
            date: day5,
            time: '25',
            incomeSourceId: salary,
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('summary', () {
    test('separates income and expense inside the range', () async {
      await expense(50000, date: day5); // ₹500
      await income(200000, date: day10); // ₹2,000
      await expense(30000, date: day20); // different month, ignored

      final result = await harness.transactions.summary(september);

      expect(result.incomeMinor, 200000);
      expect(result.expenseMinor, 50000);
      expect(result.balanceMinor, 150000);
      expect(result.incomeCount, 1);
      expect(result.expenseCount, 1);
      expect(result.count, 2);
      expect(result.isEmpty, isFalse);
    });

    test('reports the largest expense and the top category', () async {
      await expense(10000, date: day5, category: 'Food');
      await expense(90000, date: day10, category: 'Travel');
      await expense(40000, date: day10b, category: 'Travel');
      await income(500000, date: day10);

      final result = await harness.transactions.summary(september);

      expect(result.maxExpenseMinor, 90000);
      expect(result.topExpenseCategoryName, 'Travel');
      expect(result.incomeCount, 1);
    });

    test('is empty for a range with no rows', () async {
      final result = await harness.transactions.summary(september);
      expect(result.isEmpty, isTrue);
      expect(result.count, 0);
      expect(result.balanceMinor, 0);
    });

    test('never spans the range boundary', () async {
      await expense(30000, date: day20); // 20 Aug
      expect((await harness.transactions.summary(september)).expenseMinor, 0);
      expect((await harness.transactions.summary(august)).expenseMinor, 30000);
    });
  });

  group('aggregates', () {
    test('totalsByCategory sums expenses only', () async {
      await expense(10000, date: day5, category: 'Food');
      await expense(15000, date: day10, category: 'Food');
      await expense(70000, date: day10, category: 'Travel');
      await income(99999, date: day10, source: 'Food'); // different table

      final totals =
          await harness.transactions.totalsByCategory(september, type: TxType.expense);

      final food = totals.firstWhere((t) => t.name == 'Food');
      final travel = totals.firstWhere((t) => t.name == 'Travel');

      expect(food.totalMinor, 25000);
      expect(food.count, 2);
      expect(travel.totalMinor, 70000);
      expect(travel.count, 1);
      expect(totals.length, 2, reason: 'income must not appear here');
      expect(
        totals.fold<int>(0, (a, b) => a + b.totalMinor),
        95000,
        reason: 'aggregate must equal the sum of its parts',
      );
    });

    test('totalsByPaymentMethod groups by method', () async {
      await expense(10000, date: day5);
      final upi = await harness.catalog.findOrCreate(
        CatalogKind.paymentMethod,
        'UPI',
      );
      await harness.transactions.add(
        TransactionInput(
          type: TxType.expense,
          amountMinor: 20000,
          date: day10,
          time: '11:00',
          categoryId: await harness.catalog
              .findOrCreate(CatalogKind.category, 'Shopping'),
          paymentMethodId: upi,
        ),
      );

      final totals = await harness.transactions.totalsByPaymentMethod(september);

      expect(totals, hasLength(2));
      expect(totals.firstWhere((t) => t.name == 'UPI').totalMinor, 20000);
      expect(totals.firstWhere((t) => t.name == 'Cash').totalMinor, 10000);
    });

    test('totalsByIncomeSource groups by source', () async {
      await income(100000, date: day5, source: 'Salary');
      await income(40000, date: day10, source: 'Salary');
      await income(25000, date: day10, source: 'Scholarship');
      await income(60000, date: day10, source: 'Friend');
      await expense(30000, date: day5); // expenses must not appear here

      final totals = await harness.transactions.totalsByIncomeSource(september);

      expect(totals, hasLength(3));
      expect(totals.firstWhere((t) => t.name == 'Salary').totalMinor, 140000);
      expect(
        totals.firstWhere((t) => t.name == 'Scholarship').totalMinor,
        25000,
      );
      expect(totals.firstWhere((t) => t.name == 'Friend').totalMinor, 60000);
      expect(
        totals.fold<int>(0, (a, b) => a + b.totalMinor),
        225000,
        reason: 'aggregate must equal the sum of its parts',
      );
    });

    test('dailyTotals groups rows by calendar day', () async {
      await expense(10000, date: day10, time: '01:00');
      await expense(20000, date: day10, time: '23:00');
      await income(50000, date: day10, time: '12:00');
      await expense(30000, date: day5);

      final days = await harness.transactions.dailyTotals(september);

      expect(days, hasLength(2));
      final tenth = days.firstWhere((d) => d.day.day == 10);
      expect(tenth.expenseMinor, 30000);
      expect(tenth.incomeMinor, 50000);
      expect(tenth.count, 3);
      expect(tenth.balanceMinor, 20000);

      final fifth = days.firstWhere((d) => d.day.day == 5);
      expect(fifth.expenseMinor, 30000);
      expect(fifth.incomeMinor, 0);
    });

    test('monthlyTotals returns twelve zero-filled months for the year',
        () async {
      await expense(40000, date: day5);
      await income(100000, date: day10);

      final months = await harness.transactions.monthlyTotals(2026);

      expect(months, hasLength(12));
      expect(months.first.month, 1);
      expect(months.last.month, 12);
      expect(months.every((m) => m.year == 2026), isTrue);

      final septemberTotals = months.firstWhere((m) => m.month == 9);
      expect(septemberTotals.expenseMinor, 40000);
      expect(septemberTotals.incomeMinor, 100000);
      expect(septemberTotals.count, 2);

      expect(months.where((m) => m.count == 0), hasLength(11),
          reason: 'September is the only month with data');
    });
  });

  group('special events', () {
    test('an event transaction is counted exactly once in every aggregate',
        () async {
      final eventId = await harness.events
          .findOrCreate('Mumbai Trip', startDate: DateTime(2026, 9, 1));

      // Two linked expenses plus one unlinked expense in the same month.
      await harness.transactions.add(
        TransactionInput(
          type: TxType.expense,
          amountMinor: 120000,
          date: day5,
          time: '08:00',
          categoryId:
              await harness.catalog.findOrCreate(CatalogKind.category, 'Travel'),
          paymentMethodId:
              await harness.catalog.findOrCreate(CatalogKind.paymentMethod, 'UPI'),
          specialEventId: eventId,
        ),
      );
      await harness.transactions.add(
        TransactionInput(
          type: TxType.expense,
          amountMinor: 80000,
          date: day10,
          time: '08:00',
          categoryId:
              await harness.catalog.findOrCreate(CatalogKind.category, 'Food'),
          paymentMethodId:
              await harness.catalog.findOrCreate(CatalogKind.paymentMethod, 'UPI'),
          specialEventId: eventId,
        ),
      );
      await expense(50000, date: day10b); // not part of the event

      final monthly = await harness.transactions.summary(september);
      final eventOnly = await harness.transactions.summary(
        september,
        specialEventId: eventId,
      );
      final grandTotal = await harness.transactions.summary(
        september,
        includeEventRows: true,
      );

      expect(eventOnly.expenseMinor, 200000);
      expect(eventOnly.count, 2);

      // The headline change: event rows never reach the monthly figure.
      expect(
        monthly.expenseMinor,
        50000,
        reason: 'special events must be kept out of the monthly total',
      );
      expect(
        grandTotal.expenseMinor,
        250000,
        reason: 'the grand total adds them back in',
      );

      expect(
        monthly.expenseMinor + eventOnly.expenseMinor,
        grandTotal.expenseMinor,
        reason: 'monthly + events must equal the grand total exactly once',
      );

      final byEvent =
          await harness.transactions.summariesByEvent(september);
      expect(byEvent.keys, [eventId]);
      expect(byEvent[eventId]!.expenseMinor, 200000);
      expect(byEvent[eventId]!.count, 2);

      // History keeps showing every row regardless of this split.
      final all = await harness.transactions.getTransactions(
        const TransactionFilter(range: null, sort: TxSort.dateAsc),
      );
      expect(all, hasLength(3));

      final event = await harness.events.byId(eventId);
      expect(event!.expenseMinor, 200000);
      expect(event.transactionCount, 2);
    });

    test('daily and category aggregates follow the same scope rule',
        () async {
      final eventId =
          await harness.events.findOrCreate('Birthday', startDate: day5);
      await harness.transactions.add(
        TransactionInput(
          type: TxType.expense,
          amountMinor: 60000,
          date: day5,
          time: '10:00',
          categoryId:
              await harness.catalog.findOrCreate(CatalogKind.category, 'Gifts'),
          paymentMethodId:
              await harness.catalog.findOrCreate(CatalogKind.paymentMethod, 'UPI'),
          specialEventId: eventId,
        ),
      );
      await expense(40000, date: day5, category: 'Food');

      final days = await harness.transactions.dailyTotals(september);
      expect(days.single.expenseMinor, 40000,
          reason: 'day totals must exclude the event row');

      final allDays = await harness.transactions.dailyTotals(
        september,
        includeEventRows: true,
      );
      expect(allDays.single.expenseMinor, 100000);

      final categories =
          await harness.transactions.totalsByCategory(september);
      expect(
        categories.map((c) => c.name),
        isNot(contains('Gifts')),
        reason: 'event spending must not appear in the regular breakdown',
      );

      final allCategories = await harness.transactions.totalsByCategory(
        september,
        includeEventRows: true,
      );
      expect(allCategories.map((c) => c.name), contains('Gifts'));
    });
  });

  group('search, filter, sort and pagination', () {
    setUp(() async {
      await expense(30000, date: day5, category: 'Food', note: 'Coffee with Sam');
      await expense(10000, date: day10, category: 'Travel', note: 'Auto ride');
      await expense(90000, date: day10b, category: 'Shopping', note: 'Shoes');
      await income(500000, date: day10, source: 'Salary');
    });

    test('filters by type', () async {
      final expenses = await harness.transactions.getTransactions(
        const TransactionFilter(type: TxType.expense),
      );
      expect(expenses, hasLength(3));
      expect(expenses.every((t) => t.isExpense), isTrue);

      final incomes = await harness.transactions.getTransactions(
        const TransactionFilter(type: TxType.income),
      );
      expect(incomes, hasLength(1));
      expect(incomes.single.amountMinor, 500000);
    });

    test('search matches the note and reports the count', () async {
      final results = await harness.transactions.getTransactions(
        const TransactionFilter(search: 'shoes'),
      );
      expect(results, hasLength(1));
      expect(results.single.note, 'Shoes');
      expect(
        await harness.transactions.countTransactions(
          const TransactionFilter(search: 'shoes'),
        ),
        1,
      );

      expect(
        await harness.transactions
            .getTransactions(const TransactionFilter(search: 'zzz')),
        isEmpty,
      );
    });

    test('sorts by amount and by date in both directions', () async {
      final desc = await harness.transactions.getTransactions(
        const TransactionFilter(sort: TxSort.amountDesc),
      );
      expect(desc.first.amountMinor, 500000);
      expect(desc.last.amountMinor, 10000);

      final asc = await harness.transactions.getTransactions(
        const TransactionFilter(sort: TxSort.amountAsc),
      );
      expect(asc.first.amountMinor, 10000);
      expect(asc.last.amountMinor, 500000);

      final oldest = await harness.transactions.getTransactions(
        const TransactionFilter(sort: TxSort.dateAsc),
      );
      expect(oldest.first.date, day5);
    });

    test('pages the result set without losing rows', () async {
      const size = 2;
      const first = TransactionFilter(pageSize: size, page: 0);
      const second = TransactionFilter(pageSize: size, page: 1);
      const third = TransactionFilter(pageSize: size, page: 2);

      final page0 = await harness.transactions.getTransactions(first);
      final page1 = await harness.transactions.getTransactions(second);
      final page2 = await harness.transactions.getTransactions(third);

      expect(page0, hasLength(2));
      expect(page1, hasLength(2));
      expect(page2, isEmpty, reason: 'four rows fit exactly in two pages');
      expect(await harness.transactions.countTransactions(first), 4);

      final ids = {...page0, ...page1, ...page2}.map((t) => t.id).toSet();
      expect(ids, hasLength(4), reason: 'pages must never overlap');
    });

    test('resolves display names onto each row', () async {
      final rows = await harness.transactions.getTransactions(
        const TransactionFilter(sort: TxSort.amountDesc),
      );
      final expenseRow = rows.firstWhere((t) => t.isExpense);
      expect(expenseRow.categoryName, isNotEmpty);
      expect(expenseRow.paymentMethodName, isNotEmpty);
      expect(expenseRow.primaryLabel, isNotEmpty);

      final incomeRow = rows.firstWhere((t) => t.isIncome);
      expect(incomeRow.incomeSourceName, 'Salary');
    });

    test('edits and deletes round trip', () async {
      final rows = await harness.transactions.getTransactions(
        const TransactionFilter(sort: TxSort.amountDesc),
      );
      final target = rows.last;

      await harness.transactions.edit(
        target.id,
        TransactionInput(
          type: target.type,
          amountMinor: 777777,
          date: target.date,
          time: target.time,
          categoryId: target.categoryId,
          incomeSourceId: target.incomeSourceId,
          paymentMethodId: target.paymentMethodId,
          note: 'edited',
        ),
      );

      final updated = await harness.transactions.getById(target.id);
      expect(updated!.amountMinor, 777777);
      expect(updated.note, 'edited');

      await harness.transactions.remove(target.id);
      expect(await harness.transactions.getById(target.id), isNull);
    });

    test('import skips duplicates by default and can be forced to insert',
        () async {
      final existing = await harness.transactions
          .getTransactions(const TransactionFilter());
      expect(existing, hasLength(4));

      final inputs = [for (final row in existing) row.toInput()];

      final report = await harness.transactions.importTransactions(inputs);
      expect(report.inserted, 0);
      expect(report.skippedDuplicates, 4);
      expect(report.invalid, 0);
      expect(
        await harness.transactions.countTransactions(const TransactionFilter()),
        4,
        reason: 'a merge must never create a second copy of the same row',
      );

      final forced =
          await harness.transactions.importTransactions(inputs, skipDuplicates: false);
      expect(forced.inserted, 4);
      expect(
        await harness.transactions.countTransactions(const TransactionFilter()),
        8,
      );
    });
  });

  group('account balances', () {
    test('opens at the typed balance and moves with every transaction',
        () async {
      final cash = await harness.catalog
          .findOrCreate(CatalogKind.paymentMethod, 'Cash');
      await harness.catalog
          .setOpeningBalance(CatalogKind.paymentMethod, cash, 500000); // ₹5,000

      await expense(20000, date: day5); // ₹200 out of Cash
      await harness.transactions.add(
        TransactionInput(
          type: TxType.income,
          amountMinor: 100000,
          date: day10,
          time: '09:00',
          incomeSourceId:
              await harness.catalog.findOrCreate(CatalogKind.incomeSource, 'Salary'),
          paymentMethodId: cash, // salary lands in the same account
        ),
      );

      final cashRow = (await harness.transactions.accountBalances())
          .singleWhere((row) => row.paymentMethodId == cash);

      expect(cashRow.openingMinor, 500000);
      expect(cashRow.incomeMinor, 100000);
      expect(cashRow.expenseMinor, 20000);
      expect(cashRow.remainingMinor, 580000);
      expect(cashRow.flowMinor, 80000);
      expect(cashRow.hasActivity, isTrue);
    });

    test('reports every payment method, untouched ones included', () async {
      final rows = await harness.transactions.accountBalances();

      expect(
        rows.map((row) => row.name),
        containsAll(<String>['PhonePe', 'Google Pay', 'Cash', 'BOI(Saving)']),
        reason: 'the four seeded accounts must always be listed',
      );
      expect(
        rows.where((row) => row.remainingMinor != 0),
        isEmpty,
        reason: 'a fresh account starts at zero',
      );
      expect(
        rows.map((row) => row.name).toList(),
        [...rows.map((row) => row.name)]
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
        reason: 'accounts come back sorted, so the screen does not re-sort',
      );
    });

    test('a negative balance is reported rather than clamped', () async {
      final credit = await harness.catalog
          .findOrCreate(CatalogKind.paymentMethod, 'Credit Card');
      await harness.catalog.setOpeningBalance(
          CatalogKind.paymentMethod, credit, 0);
      await harness.transactions.add(
        TransactionInput(
          type: TxType.expense,
          amountMinor: 75000,
          date: day5,
          time: '11:00',
          categoryId:
              await harness.catalog.findOrCreate(CatalogKind.category, 'Shopping'),
          paymentMethodId: credit,
        ),
      );

      final row = (await harness.transactions.accountBalances())
          .singleWhere((row) => row.paymentMethodId == credit);

      expect(row.remainingMinor, -75000);
      expect(row.hasActivity, isTrue);
    });

    test('opening balance only applies to payment methods', () async {
      final food = await harness.catalog.findOrCreate(CatalogKind.category, 'Food');
      await harness.catalog.setOpeningBalance(CatalogKind.category, food, 999999);

      final row = await harness.catalog.byId(CatalogKind.category, food);
      expect(row, isNotNull);
      expect(row!.openingBalanceMinor, 0,
          reason: 'categories are not accounts and gain no balance');
    });

    test('event transactions move the account balance too', () async {
      final eventId =
          await harness.events.findOrCreate('Mumbai Trip', startDate: day5);
      final cash = await harness.catalog
          .findOrCreate(CatalogKind.paymentMethod, 'Cash');
      await harness.catalog
          .setOpeningBalance(CatalogKind.paymentMethod, cash, 100000);

      await harness.transactions.add(
        TransactionInput(
          type: TxType.expense,
          amountMinor: 40000,
          date: day5,
          time: '10:00',
          categoryId:
              await harness.catalog.findOrCreate(CatalogKind.category, 'Travel'),
          paymentMethodId: cash,
          specialEventId: eventId,
        ),
      );

      final row = (await harness.transactions.accountBalances())
          .singleWhere((row) => row.paymentMethodId == cash);

      expect(
        row.remainingMinor,
        60000,
        reason: 'the account still paid for it, whatever the report calls it',
      );
    });
  });
}
