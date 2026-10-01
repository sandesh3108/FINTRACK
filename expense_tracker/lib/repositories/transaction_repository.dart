import 'package:expense_tracker/shared/models/account_balance.dart';
import 'package:expense_tracker/shared/models/group_total.dart';
import 'package:expense_tracker/shared/models/period_summary.dart';
import 'package:expense_tracker/shared/models/range_spec.dart';
import 'package:expense_tracker/shared/models/transaction_filter.dart';
import 'package:expense_tracker/shared/models/transaction_input.dart';
import 'package:expense_tracker/shared/models/tx_item.dart';
import 'package:expense_tracker/shared/models/tx_type.dart';
import 'package:expense_tracker/shared/models/validation.dart';

/// Contract for reading and writing the financial ledger.
///
/// The UI depends only on this interface. The production implementation reads
/// from the local SQLite database; a Google Sheets backed implementation can
/// be swapped in without touching a single widget, which is exactly the
/// repository boundary required by the specification.
abstract class TransactionRepository {
  // ------------------------------------------------------------- single row

  /// Live list for the history screen. Re-emits whenever transactions change.
  Stream<List<TxItem>> watchTransactions(TransactionFilter filter);

  Future<List<TxItem>> getTransactions(TransactionFilter filter);

  Future<int> countTransactions(TransactionFilter filter);

  Future<TxItem?> getById(int id);

  Future<int> add(TransactionInput input);

  Future<void> edit(int id, TransactionInput input);

  Future<void> remove(int id);

  Future<void> removeAll(List<int> ids);

  /// Inserts many rows inside a single database transaction.
  ///
  /// Anything already present (by duplicate key) is skipped rather than
  /// overwritten, and a failure rolls the whole batch back.
  Future<MergeReport> importTransactions(
    List<TransactionInput> inputs, {
    bool skipDuplicates = true,
  });

  // ------------------------------------------------------------ aggregates
  //
  // Scope rule: an aggregate sees rows from ONE of three views.
  //
  //   * `specialEventId` set  -> only that special event.
  //   * `specialEventId` null and `includeEventRows: false` (the default)
  //     -> regular bookkeeping only, i.e. `special_event_id IS NULL`.
  //   * `specialEventId` null and `includeEventRows: true`
  //     -> every row, event-tagged or not. This is the grand total.
  //
  // Special events are therefore never folded into the monthly figures; they
  // are reported separately and added back only where a grand total is asked
  // for. Every row still appears exactly once in any single view, so nothing
  // is ever double counted.

  /// Income / expense / balance / counts / largest spend for [range].
  ///
  /// Defaults to the regular (non-event) rows - see the scope rule above.
  Future<PeriodSummary> summary(
    RangeSpec range, {
    int? specialEventId,
    bool includeEventRows = false,
  });

  /// Income and expense for every special event with rows inside [range],
  /// keyed by event id. Empty when the range contains no event transactions.
  ///
  /// Lets a report render "monthly, event 1, event 2, …, grand total" from a
  /// single grouped query instead of one query per event.
  Future<Map<int, PeriodSummary>> summariesByEvent(RangeSpec range);

  Future<List<GroupTotal>> totalsByCategory(
    RangeSpec range, {
    TxType? type,
    int? specialEventId,
    bool includeEventRows = false,
  });

  Future<List<GroupTotal>> totalsByPaymentMethod(
    RangeSpec range, {
    TxType? type,
    int? specialEventId,
    bool includeEventRows = false,
  });

  Future<List<GroupTotal>> totalsByIncomeSource(
    RangeSpec range, {
    int? specialEventId,
    bool includeEventRows = false,
  });

  /// Chronological per-day income and expense inside [range].
  Future<List<DayTotal>> dailyTotals(
    RangeSpec range, {
    int? specialEventId,
    bool includeEventRows = false,
  });

  /// All twelve months of [year], zero-filled so charts have a stable x-axis.
  ///
  /// Regular rows only: special events belong to their own event report and
  /// are surfaced next to this by the grand-total breakdown.
  Future<List<MonthTotal>> monthlyTotals(int year);

  /// Remaining balance for every payment method ("account"), oldest activity
  /// included: opening balance + all income - all expenses, all time.
  ///
  /// Ordered by name so the accounts screen does not have to re-sort.
  Future<List<AccountBalance>> accountBalances({bool activeOnly = false});

  // ------------------------------------------------------- usage counters
  // Used by the management screens to show "used by N transactions" and to
  // guarantee that archiving a row never orphan or deletes history.

  Future<Map<int, int>> usageCountsByCategory();

  Future<Map<int, int>> usageCountsByIncomeSource();

  Future<Map<int, int>> usageCountsByPaymentMethod();

  Future<Map<int, int>> usageCountsByEvent();
}
