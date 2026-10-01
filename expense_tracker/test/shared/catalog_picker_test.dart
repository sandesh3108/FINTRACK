import 'package:drift/native.dart';
import 'package:expense_tracker/database/database.dart';
import 'package:expense_tracker/repositories/providers.dart';
import 'package:expense_tracker/shared/models/catalog_item.dart';
import 'package:expense_tracker/shared/widgets/catalog_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers the escape hatch on the Add screen: "Other..." has to open a prompt,
/// insert the typed name into the catalog and hand the new id back to the
/// form, otherwise a user can only ever pick what the app shipped with.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;

  setUp(() => database = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => database.close());

  /// Gives the catalog stream and the `findOrCreate` future time to land.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> pumpPicker(
    WidgetTester tester,
    ValueChanged<int?> onChanged,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(database),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: CatalogPicker(
              kind: CatalogKind.category,
              label: 'Category',
              valueId: null,
              onChanged: onChanged,
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  /// Opens the list and picks [label], scrolling it when the item sits past
  /// the built window (the list is long and "Other..." is last).
  Future<void> choose(WidgetTester tester, String label) async {
    await tester.tap(find.byType(InputDecorator));
    await settle(tester);

    final item = find.text(label);
    if (item.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        item,
        60,
        scrollable: find.byType(Scrollable).last,
        maxScrolls: 40,
      );
      await settle(tester);
    }

    await tester.tap(item.last);
    await settle(tester);
  }

  testWidgets('Other... creates a new category and selects it',
      (tester) async {
    int? selected;
    await pumpPicker(tester, (id) => selected = id);

    await choose(tester, 'Other...');

    expect(
      find.text('New category'),
      findsOneWidget,
      reason: 'the prompt must name what is being created',
    );

    await tester.enterText(find.byType(TextField), 'Gym');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await settle(tester);

    final rows = await database.select(database.categories).get();
    expect(
      rows.map((row) => row.name),
      contains('Gym'),
      reason: 'the typed name has to reach the database',
    );
    expect(selected, isNotNull, reason: 'the form must receive a category id');

    final created = rows.singleWhere((row) => row.id == selected);
    expect(created.name, 'Gym');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('an empty prompt creates nothing and can be cancelled',
      (tester) async {
    int? selected;
    await pumpPicker(tester, (id) => selected = id);

    final before = await database.select(database.categories).get();

    await choose(tester, 'Other...');
    // The Add button ignores a blank name, so the prompt has to stay open
    // rather than silently adding an empty category.
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await settle(tester);

    expect(find.text('New category'), findsOneWidget);
    expect(
      (await database.select(database.categories).get()).length,
      before.length,
      reason: 'a blank name must not create an empty category',
    );
    expect(selected, isNull);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await settle(tester);

    expect(find.text('New category'), findsNothing);
    expect(
      (await database.select(database.categories).get()).length,
      before.length,
    );
    expect(selected, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('picking an existing category reports its id', (tester) async {
    int? selected;
    await pumpPicker(tester, (id) => selected = id);

    await choose(tester, 'Groceries');

    expect(selected, isNotNull);
    final row = await (database.select(database.categories)
          ..where((c) => c.id.equals(selected!)))
        .getSingle();
    expect(row.name, 'Groceries');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('typing filters the list down to matching categories',
      (tester) async {
    int? selected;
    await pumpPicker(tester, (id) => selected = id);

    await tester.tap(find.byType(InputDecorator));
    await settle(tester);

    await tester.enterText(find.byType(TextField), 'vehicle');
    await settle(tester);

    expect(find.text('Vehicle'), findsOneWidget);
    expect(find.text('Vehicle Maintenance'), findsOneWidget);
    expect(
      find.text('Groceries'),
      findsNothing,
      reason: 'a filtered list must hide everything that does not match',
    );

    await tester.tap(find.text('Vehicle Maintenance'));
    await settle(tester);

    expect(selected, isNotNull, reason: 'the filtered choice must be reported');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('a searched name with no match can be created from the list',
      (tester) async {
    int? selected;
    await pumpPicker(tester, (id) => selected = id);

    await tester.tap(find.byType(InputDecorator));
    await settle(tester);

    await tester.enterText(find.byType(TextField), 'Barber');
    await settle(tester);

    expect(find.text('No matches for "Barber"'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Add "Barber"'));
    await settle(tester);

    // The prompt opens pre-filled with what was typed, so "Add" creates it
    // without asking for the same word a second time.
    expect(find.text('New category'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Barber',
      reason: 'the searched-for name must be carried into the prompt',
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await settle(tester);

    final rows = await database.select(database.categories).get();
    expect(rows.map((row) => row.name), contains('Barber'));
    expect(selected, isNotNull, reason: 'the form must receive the new id');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });
}
