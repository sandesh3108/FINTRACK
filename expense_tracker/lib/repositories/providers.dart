import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../database/database.dart';
import '../shared/models/account_balance.dart';
import '../shared/models/app_settings.dart';
import '../shared/models/transaction_filter.dart';
import 'backup_repository.dart';
import 'catalog_repository.dart';
import 'drift/drift_catalog_repository.dart';
import 'drift/drift_event_repository.dart';
import 'drift/drift_settings_repository.dart';
import 'drift/drift_transaction_repository.dart';
import 'event_repository.dart';
import 'settings_repository.dart';
import 'transaction_repository.dart';

/// The application database.
///
/// Overridden in [main] with a real connection; tests override it with an
/// in-memory database.
final Provider<AppDatabase> appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw StateError('appDatabaseProvider must be overridden before use.');
});

/// Live configuration (currency, defaults, linked Google Sheet).
///
/// Streams from SQLite, so every screen updating a setting refreshes all the
/// others automatically.
final StreamProvider<AppSettings> settingsProvider =
    StreamProvider<AppSettings>((ref) => ref.watch(settingsRepositoryProvider).watch());

/// Symbol used by [MoneyText] and exports. Falls back to the build-time
/// default until the database has been read.
final Provider<String> currencySymbolProvider = Provider<String>((ref) {
  final settings = ref.watch(settingsProvider).valueOrNull;
  return (settings?.currencySymbol.isNotEmpty ?? false)
      ? settings!.currencySymbol
      : AppConfig.currencySymbol;
});

final Provider<TransactionRepository> transactionRepositoryProvider =
    Provider<TransactionRepository>((ref) {
  return DriftTransactionRepository(ref.watch(appDatabaseProvider));
});

/// Emits a new value whenever any transaction is added, edited, deleted or
/// restored from a backup.
///
/// This is the one place that can watch the whole ledger, so it is shared by
/// every screen that needs to re-derive numbers from it: an edit made in the
/// pushed editor, an entry saved on the Add tab and a restore from backup all
/// reach the same stream. The first emission is the query's own snapshot and
/// is skipped - only later emissions represent a change.
final StreamProvider<int> ledgerRevisionProvider = StreamProvider<int>(
  (ref) async* {
    final repository = ref.watch(transactionRepositoryProvider);
    var revision = 0;
    var first = true;
    await for (final _ in repository.watchTransactions(
      const TransactionFilter(pageSize: 1),
    )) {
      if (first) {
        first = false;
        continue;
      }
      revision += 1;
      yield revision;
    }
  },
);

final Provider<CatalogRepository> catalogRepositoryProvider =
    Provider<CatalogRepository>((ref) {
  return DriftCatalogRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(transactionRepositoryProvider),
  );
});

/// Remaining balance for every payment method (account).
///
/// Refreshed through [ledgerRevisionProvider] by the screens that show it, so
/// it always reflects the latest transaction without polling.
final FutureProvider<List<AccountBalance>> accountBalancesProvider =
    FutureProvider<List<AccountBalance>>(
  (ref) => ref.watch(transactionRepositoryProvider).accountBalances(),
);

/// Whether the account balances are currently revealed.
///
/// Deliberately *not* part of [AppSettings]: unlocking is an action, not a
/// preference, so it starts locked on every launch and is never written to
/// disk. Settings only stores the PIN itself; this holds the answer to "has
/// this session typed it yet".
///
/// Screens that hide money keep this provider beside the amounts it guards -
/// both are invalidated and rebuilt together, so a lock can never be shown
/// while its numbers sit one frame away.
final StateProvider<bool> balanceUnlockedProvider =
    StateProvider<bool>((ref) => false);

final Provider<EventRepository> eventRepositoryProvider =
    Provider<EventRepository>((ref) {
  return DriftEventRepository(ref.watch(appDatabaseProvider));
});

final Provider<SettingsRepository> settingsRepositoryProvider =
    Provider<SettingsRepository>((ref) {
  return DriftSettingsRepository(ref.watch(appDatabaseProvider));
});

final Provider<BackupRepository> backupRepositoryProvider =
    Provider<BackupRepository>((ref) {
  return BackupRepository(
    transactions: ref.watch(transactionRepositoryProvider),
    catalog: ref.watch(catalogRepositoryProvider),
    events: ref.watch(eventRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
  );
});
