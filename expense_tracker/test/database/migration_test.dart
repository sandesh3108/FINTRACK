import 'dart:io';

import 'package:drift/native.dart' show NativeDatabase;
import 'package:expense_tracker/database/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Proves the schema 1 -> 2 upgrade on a real file.
///
/// A database written before the balance feature existed has no
/// `opening_balance` column and was seeded with the older payment-method list,
/// so the migration has to add the column *and* backfill the account it never
/// heard of - without touching anything the user already recorded.
void main() {
  test('a schema 1 database gains the column, its accounts and keeps its data',
      () async {
    final dir = await Directory.systemTemp.createTemp('expense_migration');
    final file = File(p.join(dir.path, 'ledger.db'));

    try {
      // --- build a database shaped exactly as schema 1 left it ------------
      final before = AppDatabase.forTesting(NativeDatabase(file));
      // Touching a table runs onCreate for a brand-new file.
      await before.select(before.categories).get();
      await before
          .into(before.categories)
          .insert(CategoriesCompanion.insert(name: 'Travel'));

      await before.customStatement('PRAGMA foreign_keys = OFF');
      await before.customStatement('DROP TABLE payment_methods');
      await before.customStatement(
        'CREATE TABLE payment_methods ('
        'id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'name TEXT NOT NULL, '
        'is_default INTEGER NOT NULL DEFAULT 0, '
        'is_active INTEGER NOT NULL DEFAULT 1, '
        'created_at INTEGER NOT NULL DEFAULT (strftime(\'%s\', \'now\')), '
        'updated_at INTEGER NOT NULL DEFAULT (strftime(\'%s\', \'now\')))',
      );
      for (final name in const <String>['PhonePe', 'Google Pay', 'Cash', 'Other']) {
        await before.customStatement(
          'INSERT INTO payment_methods (name, created_at, updated_at) '
          'VALUES (?, 0, 0)',
          <Object>[name],
        );
      }
      await before.customStatement('PRAGMA user_version = 1');
      await before.close();

      // --- reopen it with the current schema ------------------------------
      final after = AppDatabase.forTesting(NativeDatabase(file));
      final methods = await after.select(after.paymentMethods).get();

      expect(
        methods.map((row) => row.name),
        containsAll(<String>['PhonePe', 'Google Pay', 'Cash', 'BOI(Saving)']),
        reason: 'every account the balance screen reports on must exist',
      );
      expect(
        methods.map((row) => row.name),
        contains('Other'),
        reason: 'a row the user already had must never be renamed away',
      );
      expect(
        methods.map((row) => row.openingBalance),
        everyElement(0),
        reason: 'upgraded accounts start as "not set up yet"',
      );

      final categories = await after.select(after.categories).get();
      expect(
        categories.map((row) => row.name),
        contains('Travel'),
        reason: 'an upgrade must never lose user data',
      );

      await after.close();
      // Let the sqlite handle go before the directory is removed.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    } finally {
      // Windows can hold the sqlite file briefly after close(), so the cleanup
      // retries rather than failing a test that proved what it set out to.
      var removed = false;
      for (var attempt = 0; attempt < 10 && !removed; attempt++) {
        try {
          await dir.delete(recursive: true);
          removed = true;
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    }
  });
}
