import 'package:expense_tracker/core/errors/app_exception.dart';
import 'package:expense_tracker/shared/models/catalog_item.dart';
import 'package:expense_tracker/shared/models/special_event.dart';
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

  Future<void> addExpense({
    String category = 'Food',
    String paymentMethod = 'Cash',
  }) async {
    final categoryId =
        await harness.catalog.findOrCreate(CatalogKind.category, category);
    final paymentMethodId =
        await harness.catalog.findOrCreate(CatalogKind.paymentMethod, paymentMethod);
    await harness.transactions.add(
      TransactionInput(
        type: TxType.expense,
        amountMinor: 15000,
        date: day5,
        time: '10:00',
        categoryId: categoryId,
        paymentMethodId: paymentMethodId,
      ),
    );
  }

  group('CatalogRepository', () {
    test('seeds sensible defaults on a fresh database', () async {
      final categories = await harness.catalog.getAll(CatalogKind.category);
      final sources = await harness.catalog.getAll(CatalogKind.incomeSource);
      final methods = await harness.catalog.getAll(CatalogKind.paymentMethod);

      expect(categories.length, greaterThan(10));
      expect(sources.map((c) => c.name), contains('Salary'));
      expect(methods.map((c) => c.name), containsAll(<String>['Cash', 'PhonePe']));
      expect(categories.every((c) => c.isActive), isTrue);
    });

    test('findOrCreate returns the same row for the same name', () async {
      final first =
          await harness.catalog.findOrCreate(CatalogKind.category, 'Gym');
      final second =
          await harness.catalog.findOrCreate(CatalogKind.category, 'Gym');
      final differentlyCased =
          await harness.catalog.findOrCreate(CatalogKind.category, '  gym ');

      expect(second, first);
      expect(differentlyCased, first);

      final all = await harness.catalog.getAll(CatalogKind.category);
      expect(all.where((c) => c.name.toLowerCase() == 'gym'), hasLength(1));
    });

    test('rename updates the row in place', () async {
      final id = await harness.catalog.findOrCreate(CatalogKind.category, 'Old');
      await harness.catalog.rename(CatalogKind.category, id, 'New');

      final renamed = await harness.catalog.byId(CatalogKind.category, id);
      expect(renamed!.name, 'New');
      expect(renamed.id, id, reason: 'renaming must not change history links');
    });

    test('archiving hides a row from active lookups but keeps the data',
        () async {
      await addExpense(category: 'Legacy');
      final id = await harness.catalog.findOrCreate(CatalogKind.category, 'Legacy');

      await harness.catalog.setActive(CatalogKind.category, id, false);

      final active = await harness.catalog.getAll(CatalogKind.category,
          activeOnly: true);
      expect(active.map((c) => c.id), isNot(contains(id)));

      final all = await harness.catalog.getAll(CatalogKind.category);
      expect(all.map((c) => c.id), contains(id));
      expect(all.firstWhere((c) => c.id == id).isActive, isFalse);

      // Still selectable when editing the old transaction.
      final linked = await harness.catalog.byId(CatalogKind.category, id);
      expect(linked, isNotNull);
    });

    test('refuses to delete a row that history depends on', () async {
      await addExpense(category: 'Food');
      final food = await harness.catalog.findOrCreate(CatalogKind.category, 'Food');

      await expectLater(
        harness.catalog.delete(CatalogKind.category, food),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message.toLowerCase(),
            'message',
            allOf(contains('archive'), contains('history')),
          ),
        ),
      );

      expect(await harness.catalog.byId(CatalogKind.category, food), isNotNull,
          reason: 'the row must survive the failed delete');
    });

    test('deletes a row that nothing references', () async {
      final id =
          await harness.catalog.findOrCreate(CatalogKind.category, 'Never used');
      await harness.catalog.delete(CatalogKind.category, id);
      expect(await harness.catalog.byId(CatalogKind.category, id), isNull);
    });

    test('reports how many transactions use each row', () async {
      await addExpense(category: 'Food');
      await addExpense(category: 'Food');
      await addExpense(category: 'Travel');

      final counts = await harness.transactions.usageCountsByCategory();
      final food = await harness.catalog.findOrCreate(CatalogKind.category, 'Food');
      final travel =
          await harness.catalog.findOrCreate(CatalogKind.category, 'Travel');

      expect(counts[food], 2);
      expect(counts[travel], 1);
    });
  });

  group('EventRepository', () {
    test('creates and reads an event', () async {
      final id = await harness.events.create(
        SpecialEventDraft(
          name: 'Mumbai Trip',
          description: 'Four days out',
          startDate: DateTime(2026, 9, 1),
        ),
      );

      final event = await harness.events.byId(id);
      expect(event!.name, 'Mumbai Trip');
      expect(event.description, 'Four days out');
      expect(event.startDate, DateTime(2026, 9, 1));
      expect(event.isArchived, isFalse);
      expect(event.transactionCount, 0);
      expect(event.dateRangeLabel, isNotEmpty);
    });

    test('findOrCreate is idempotent by name', () async {
      final first = await harness.events.findOrCreate('Diwali 2026');
      final second = await harness.events.findOrCreate('diwali 2026');
      expect(second, first);
      expect(await harness.events.getAll(), hasLength(1));
    });

    test('updates an event', () async {
      final id = await harness.events
          .findOrCreate('Trip', startDate: DateTime(2026, 9, 1));
      await harness.events.update(
        id,
        SpecialEventDraft(
          name: 'Trip (renamed)',
          description: '',
          startDate: DateTime(2026, 9, 2),
        ),
      );

      final updated = await harness.events.byId(id);
      expect(updated!.name, 'Trip (renamed)');
      expect(updated.startDate, DateTime(2026, 9, 2));
    });

    test('archiving keeps the event and its linked transactions', () async {
      final id = await harness.events.findOrCreate('Old Trip');
      final category =
          await harness.catalog.findOrCreate(CatalogKind.category, 'Travel');
      final method =
          await harness.catalog.findOrCreate(CatalogKind.paymentMethod, 'UPI');

      await harness.transactions.add(
        TransactionInput(
          type: TxType.expense,
          amountMinor: 42000,
          date: day5,
          time: '12:00',
          categoryId: category,
          paymentMethodId: method,
          specialEventId: id,
        ),
      );

      await harness.events.setArchived(id, true);

      expect(await harness.events.getAll(includeArchived: false), isEmpty);
      final archived = await harness.events.getAll(includeArchived: true);
      expect(archived, hasLength(1));
      expect(archived.single.isArchived, isTrue);
      expect(archived.single.transactionCount, 1);
      expect(archived.single.expenseMinor, 42000);

      // The transaction keeps its link after archiving.
      final rows = await harness.transactions
          .getTransactions(const TransactionFilter());
      expect(rows, hasLength(1));
      expect(rows.single.specialEventId, id);
      expect(rows.single.specialEventName, 'Old Trip');
    });

    test('refuses to delete an event that transactions reference', () async {
      final id = await harness.events.findOrCreate('Booked Trip');
      final category =
          await harness.catalog.findOrCreate(CatalogKind.category, 'Travel');
      final method =
          await harness.catalog.findOrCreate(CatalogKind.paymentMethod, 'UPI');

      await harness.transactions.add(
        TransactionInput(
          type: TxType.expense,
          amountMinor: 10000,
          date: day5,
          time: '12:00',
          categoryId: category,
          paymentMethodId: method,
          specialEventId: id,
        ),
      );

      await expectLater(
        harness.events.delete(id),
        throwsA(isA<ValidationException>()),
      );
      expect(await harness.events.byId(id), isNotNull);
    });

    test('deletes an unused event', () async {
      final id = await harness.events.findOrCreate('Empty event');
      await harness.events.delete(id);
      expect(await harness.events.byId(id), isNull);
    });
  });
}
