import 'package:expense_tracker/features/reports/report_definitions.dart';
import 'package:expense_tracker/features/reports/report_detail_screen.dart';
import 'package:expense_tracker/repositories/providers.dart';
import 'package:expense_tracker/shared/models/catalog_item.dart';
import 'package:expense_tracker/shared/models/range_spec.dart';
import 'package:expense_tracker/shared/models/transaction_input.dart';
import 'package:expense_tracker/shared/models/tx_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_harness.dart';

/// The headline requirement of the reporting change: spending recorded against
/// a special event must not leak into the monthly figure, must appear under
/// its own name, and must come back in the grand total - for expense and for
/// income alike.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestHarness harness;
  final september = RangeSpec.month(2026, 9);

  setUp(() => harness = TestHarness());
  tearDown(() => harness.close());

  Future<void> spend(
    int amount, {
    required String category,
    int? eventId,
  }) async {
    await harness.transactions.add(
      TransactionInput(
        type: TxType.expense,
        amountMinor: amount,
        date: DateTime(2026, 9, 5),
        time: '10:00',
        categoryId:
            await harness.catalog.findOrCreate(CatalogKind.category, category),
        paymentMethodId: await harness.catalog
            .findOrCreate(CatalogKind.paymentMethod, 'Cash'),
        specialEventId: eventId,
      ),
    );
  }

  Future<void> earn(
    int amount, {
    int? eventId,
  }) async {
    await harness.transactions.add(
      TransactionInput(
        type: TxType.income,
        amountMinor: amount,
        date: DateTime(2026, 9, 6),
        time: '09:00',
        incomeSourceId: await harness.catalog
            .findOrCreate(CatalogKind.incomeSource, 'Salary'),
        paymentMethodId: await harness.catalog
            .findOrCreate(CatalogKind.paymentMethod, 'Cash'),
        specialEventId: eventId,
      ),
    );
  }

  Future<void> pumpReport(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(harness.db),
        ],
        child: MaterialApp(
          home: ReportDetailScreen(
            title: 'September 2026',
            range: september,
            type: ReportType.monthly,
          ),
        ),
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

  testWidgets('separates monthly, each event and the grand total',
      (tester) async {
    final eventId = await harness.events
        .findOrCreate('Mumbai Trip', startDate: DateTime(2026, 9, 1));

    await spend(50000, category: 'Food'); // ₹500, regular
    await spend(120000, category: 'Travel', eventId: eventId); // ₹1,200 event
    await spend(80000, category: 'Food', eventId: eventId); // ₹800 event
    await earn(100000); // ₹1,000, regular
    await earn(40000, eventId: eventId); // ₹400 into the event

    await pumpReport(tester);

    expect(tester.takeException(), isNull, reason: 'the report must render');

    expect(find.text('Total breakdown'), findsOneWidget);
    expect(
      find.text('Monthly expenses'),
      findsOneWidget,
      reason: 'the regular rows are named separately',
    );
    expect(
      find.text('Mumbai Trip'),
      findsWidgets,
      reason: 'the event gets its own line',
    );
    expect(find.text('Monthly income'), findsOneWidget);

    // Every figure below is read from inside the breakdown card, so the
    // summary card's own numbers cannot satisfy the expectation by accident.
    final card = find.ancestor(
      of: find.text('Monthly expenses'),
      matching: find.byType(Card),
    );
    expect(card, findsOneWidget);

    Finder amount(String value) =>
        find.descendant(of: card, matching: find.text(value));

    // Expense: ₹500 regular, ₹500 + ₹1,200 + ₹800 = ₹2,500 with the event.
    expect(amount('₹500'), findsOneWidget);
    expect(amount('₹2,500'), findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('Grand Total')),
      findsNWidgets(2),
      reason: 'one grand total for expense and one for income',
    );
    // Income: ₹1,000 regular, ₹1,000 + ₹400 = ₹1,400 with the event.
    expect(amount('₹1,000'), findsOneWidget);
    expect(amount('₹1,400'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('stays hidden when the range holds no special events',
      (tester) async {
    await spend(50000, category: 'Food');
    await earn(100000);

    await pumpReport(tester);

    expect(tester.takeException(), isNull);
    expect(
      find.text('Total breakdown'),
      findsNothing,
      reason: 'there is nothing to separate, so the card must not appear',
    );

    await unmount(tester);
  });

  testWidgets('the event report keeps its own totals unsplit',
      (tester) async {
    final eventId = await harness.events
        .findOrCreate('Mumbai Trip', startDate: DateTime(2026, 9, 1));
    await spend(50000, category: 'Food');
    await spend(120000, category: 'Travel', eventId: eventId);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(harness.db),
        ],
        child: MaterialApp(
          home: ReportDetailScreen(
            title: 'Mumbai Trip',
            range: september,
            specialEventId: eventId,
            type: ReportType.specialEvent,
          ),
        ),
      ),
    );
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }

    expect(tester.takeException(), isNull);
    expect(
      find.text('Total breakdown'),
      findsNothing,
      reason: 'splitting one event against itself would just repeat it',
    );
    expect(find.text('Mumbai Trip'), findsWidgets);

    await unmount(tester);
  });
}
