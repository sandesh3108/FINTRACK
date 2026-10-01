import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'default_data.dart';
import 'tables.dart';

part 'database.g.dart';

/// The generated row type for [Transactions].
///
/// Aliased so importing files never collide with a `Transaction` symbol that
/// another package may export.
typedef TxRow = Transaction;

/// The generated row type for [SpecialEvents], aliased away from the
/// `SpecialEvent` domain model used by the UI.
typedef EventRow = SpecialEvent;

/// The local, offline-first financial database.
///
/// Schema notes
/// ------------
/// * `amount` columns are **integers of minor units** (paise). Floating point
///   is never used for money, so totals cannot drift.
/// * `date` holds the calendar day (local midnight) and `time` holds `HH:mm`,
///   which keeps month/year reporting a simple range scan on an indexed column.
/// * Special events are a foreign key on the transaction, i.e. a *tag*. Event
///   totals are a filtered view of the same rows, so an event transaction is
///   counted exactly once in every aggregate.
///
/// Migrations are additive only: [onUpgrade] never drops a table, so user data
/// survives every upgrade.
@DriftDatabase(
  tables: [
    Categories,
    IncomeSources,
    PaymentMethods,
    SpecialEvents,
    Transactions,
    Settings,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Opens the on-device database in the platform documents directory.
  AppDatabase() : super(_openConnection());

  /// In-memory database for tests.
  AppDatabase.forTesting(super.executor);

  static QueryExecutor _openConnection() =>
      driftDatabase(name: 'expense_tracker');

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createIndexes();
          await _seedDefaults();
        },
        onUpgrade: (m, from, to) async {
          // Additive migrations only, executed in ascending step order.
          // Never delete or re-create existing tables here - user transactions
          // must survive every upgrade.
          if (from < 2) {
            // Accounts: every payment method gains an opening balance so the
            // app can show a remaining balance per account. Existing rows all
            // default to 0, i.e. "not set up yet".
            await m.addColumn(paymentMethods, paymentMethods.openingBalance);
            await _ensureAccountsExist();
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Fills in any of the four seeded accounts an upgrade has not produced yet.
  ///
  /// `_seedDefaults` only fills an entirely empty table, so a database created
  /// before the balance feature existed keeps whatever it was seeded with -
  /// which would leave the account it never heard of (BOI(Saving)) missing
  /// from the balances screen. This adds only what is absent and never renames
  /// or overwrites a row the user may already have used.
  Future<void> _ensureAccountsExist() async {
    for (final name in defaultPaymentMethods) {
      final existing = await (select(paymentMethods)
            ..where((m) => m.name.lower().equals(name.toLowerCase())))
          .get();
      if (existing.isEmpty) {
        await into(paymentMethods)
            .insert(PaymentMethodsCompanion.insert(name: name));
      }
    }
  }

  /// Indexes for the columns every report and search filters on.
  Future<void> _createIndexes() async {
    const statements = <String>[
      'CREATE INDEX idx_transactions_date ON transactions(date)',
      'CREATE INDEX idx_transactions_type_date ON transactions(type, date)',
      'CREATE INDEX idx_transactions_category ON transactions(category_id)',
      'CREATE INDEX idx_transactions_income_source ON transactions(income_source_id)',
      'CREATE INDEX idx_transactions_payment_method ON transactions(payment_method_id)',
      'CREATE INDEX idx_transactions_event ON transactions(special_event_id)',
      'CREATE INDEX idx_categories_name ON categories(name)',
      'CREATE INDEX idx_income_sources_name ON income_sources(name)',
      'CREATE INDEX idx_payment_methods_name ON payment_methods(name)',
      'CREATE INDEX idx_special_events_start ON special_events(start_date)',
    ];
    for (final statement in statements) {
      await customStatement(statement);
    }
  }

  /// Inserts the default categories, income sources and payment methods the
  /// first time the app runs. Safe to call again - it only fills empty tables.
  Future<void> _seedDefaults() async {
    await transaction(() async {
      if ((await select(categories).get()).isEmpty) {
        final now = DateTime.now();
        await batch((b) {
          b.insertAll(
            categories,
            [
              for (final name in defaultCategories)
                CategoriesCompanion.insert(
                  name: name,
                  isDefault: const Value(true),
                  createdAt: Value(now),
                  updatedAt: Value(now),
                ),
            ],
          );
        });
      }

      if ((await select(incomeSources).get()).isEmpty) {
        final now = DateTime.now();
        await batch((b) {
          b.insertAll(
            incomeSources,
            [
              for (final name in defaultIncomeSources)
                IncomeSourcesCompanion.insert(
                  name: name,
                  isDefault: const Value(true),
                  createdAt: Value(now),
                  updatedAt: Value(now),
                ),
            ],
          );
        });
      }

      if ((await select(paymentMethods).get()).isEmpty) {
        final now = DateTime.now();
        await batch((b) {
          b.insertAll(
            paymentMethods,
            [
              for (final name in defaultPaymentMethods)
                PaymentMethodsCompanion.insert(
                  name: name,
                  isDefault: const Value(true),
                  createdAt: Value(now),
                  updatedAt: Value(now),
                ),
            ],
          );
        });
      }
    });
  }
}
