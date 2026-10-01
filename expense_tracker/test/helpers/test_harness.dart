import 'package:drift/native.dart';
import 'package:expense_tracker/database/database.dart';
import 'package:expense_tracker/repositories/backup_repository.dart';
import 'package:expense_tracker/repositories/drift/drift_catalog_repository.dart';
import 'package:expense_tracker/repositories/drift/drift_event_repository.dart';
import 'package:expense_tracker/repositories/drift/drift_settings_repository.dart';
import 'package:expense_tracker/repositories/drift/drift_transaction_repository.dart';

/// Wires every repository against a throwaway in-memory database.
///
/// This is the same object graph [main] builds, minus the platform file
/// system, so tests exercise the real Drift queries rather than a mock.
class TestHarness {
  TestHarness()
      : db = AppDatabase.forTesting(NativeDatabase.memory()) {
    transactions = DriftTransactionRepository(db);
    catalog = DriftCatalogRepository(db, transactions);
    events = DriftEventRepository(db);
    settings = DriftSettingsRepository(db);
    backup = BackupRepository(
      transactions: transactions,
      catalog: catalog,
      events: events,
      settings: settings,
    );
  }

  final AppDatabase db;
  late final DriftTransactionRepository transactions;
  late final DriftCatalogRepository catalog;
  late final DriftEventRepository events;
  late final DriftSettingsRepository settings;
  late final BackupRepository backup;

  Future<void> close() => db.close();
}
