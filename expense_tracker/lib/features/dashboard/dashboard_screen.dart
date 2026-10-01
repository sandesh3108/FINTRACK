/// Home tab: a month-scoped overview of the ledger.
///
/// Every number rendered here comes from a repository call wrapped in one of
/// the private providers declared at the top of this file, and every provider
/// is displayed through [AsyncValueView], so loading, error, empty and data
/// states look the same on this screen as everywhere else in the app.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../app/state/app_identity.dart';
import '../../app/state/shell.dart';
import '../../app/state/ui_preferences.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../repositories/providers.dart';
import '../../shared/models/catalog_item.dart';
import '../../shared/models/group_total.dart';
import '../../shared/models/period_summary.dart';
import '../../shared/models/range_spec.dart';
import '../../shared/models/transaction_filter.dart';
import '../../shared/models/tx_item.dart';
import '../../shared/models/tx_type.dart';
import '../../shared/widgets/catalog_picker.dart';
import '../../shared/widgets/charts.dart';
import '../../shared/widgets/common.dart';
import 'transaction_list_tile.dart';

// -----------------------------------------------------------------------------
// Repository queries, one provider per read, all keyed by the visible period
// -----------------------------------------------------------------------------

/// Headline income / expense / balance / counts for the selected month.
///
/// The type is left to inference on purpose: `FutureProvider.family` is a
/// factory method, not a type, so the annotation would not resolve.
final _summaryProvider = FutureProvider.family<PeriodSummary, RangeSpec>(
  (ref, range) => ref.watch(transactionRepositoryProvider).summary(range),
);

/// Single largest expense of the month - its date captions the stat card.
final _largestExpenseProvider = FutureProvider.family<TxItem?, RangeSpec>(
  (ref, range) async {
    final rows = await ref.watch(transactionRepositoryProvider).getTransactions(
          TransactionFilter(
            range: range,
            type: TxType.expense,
            sort: TxSort.amountDesc,
            pageSize: 1,
          ),
        );
    return rows.isEmpty ? null : rows.first;
  },
);

/// Every special event with activity in the period, keyed by event id.
///
/// The dashboard needs only "are there any", because special events are kept
/// out of the monthly figures and reported on their own - this is what lets the
/// balance card say so instead of quietly showing a smaller number.
final _eventTotalsProvider =
    FutureProvider.family<Map<int, PeriodSummary>, RangeSpec>(
  (ref, range) =>
      ref.watch(transactionRepositoryProvider).summariesByEvent(range),
);

/// Expense totals grouped by category, for the donut chart.
final _categoryTotalsProvider =
    FutureProvider.family<List<GroupTotal>, RangeSpec>(
  (ref, range) => ref
      .watch(transactionRepositoryProvider)
      .totalsByCategory(range, type: TxType.expense),
);

/// Per-day income and expense inside the month, for the trend chart.
final _dailyTotalsProvider = FutureProvider.family<List<DayTotal>, RangeSpec>(
  (ref, range) => ref.watch(transactionRepositoryProvider).dailyTotals(range),
);

/// The five newest transactions of the month, newest first.
final _recentProvider = FutureProvider.family<List<TxItem>, RangeSpec>(
  (ref, range) => ref.watch(transactionRepositoryProvider).getTransactions(
        TransactionFilter(
          range: range,
          sort: TxSort.dateDesc,
          pageSize: 5,
        ),
      ),
);

/// Twelve zero-filled months of the year shown in the "at a glance" chart.
final _monthlyTotalsProvider = FutureProvider.family<List<MonthTotal>, int>(
  (ref, year) => ref.watch(transactionRepositoryProvider).monthlyTotals(year),
);

/// Whole-database row count: tells "an empty month" from "an empty app".
final FutureProvider<int> _totalTransactionsProvider = FutureProvider<int>(
  (ref) => ref
      .watch(transactionRepositoryProvider)
      .countTransactions(const TransactionFilter()),
);

// -----------------------------------------------------------------------------
// Refresh plumbing
// -----------------------------------------------------------------------------

/// Re-queries every dashboard read after the ledger (or a catalog label)
/// changed somewhere else in the app.
///
/// The providers are *invalidated* rather than watched on purpose: an
/// invalidation is a refresh, so [AsyncValueView] keeps the numbers that are
/// already on screen while the fresh queries run, instead of flashing a
/// spinner every time a row is edited.
void _refreshDashboard(WidgetRef ref) {
  ref.invalidate(_summaryProvider);
  ref.invalidate(_largestExpenseProvider);
  ref.invalidate(_categoryTotalsProvider);
  ref.invalidate(_dailyTotalsProvider);
  ref.invalidate(_recentProvider);
  ref.invalidate(_monthlyTotalsProvider);
  ref.invalidate(_totalTransactionsProvider);
  ref.invalidate(_eventTotalsProvider);
}

/// Subscribes the screen to every external change that affects its numbers.
///
/// Must be called from [DashboardScreen.build]: [WidgetRef.listen]
/// subscriptions registered during a build are dropped again on the next
/// rebuild, so the closures always see the period that is on screen.
void _listenForExternalChanges(WidgetRef ref) {
  ref.listen(ledgerRevisionProvider, (previous, next) {
    if (next.hasValue && next.valueOrNull != previous?.valueOrNull) {
      _refreshDashboard(ref);
    }
  });

  // Renaming or archiving a catalog row changes labels shown here but never
  // touches the transactions table, so those streams are watched separately.
  for (final kind in CatalogKind.values) {
    ref.listen(catalogListProvider(kind), (previous, next) {
      if (previous?.valueOrNull == null) return; // first snapshot, not a change
      _refreshDashboard(ref);
    });
  }
}

// -----------------------------------------------------------------------------
// Screen
// -----------------------------------------------------------------------------

/// The Home tab: period selector, balance, quick actions, statistics, charts
/// and the most recent transactions of the selected month.
class DashboardScreen extends ConsumerWidget {
  /// Creates the Home tab.
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final preferences = ref.watch(uiPreferencesProvider);
    final year = preferences.lastSelectedYear ?? now.year;
    final month = preferences.lastSelectedMonth ?? now.month;
    final range = RangeSpec.month(year, month);
    final isCurrentMonth = year == now.year && month == now.month;

    _listenForExternalChanges(ref);

    final summaryAsync = ref.watch(_summaryProvider(range));
    final largestExpenseAsync = ref.watch(_largestExpenseProvider(range));
    final categoryTotalsAsync = ref.watch(_categoryTotalsProvider(range));
    final dailyTotalsAsync = ref.watch(_dailyTotalsProvider(range));
    final recentAsync = ref.watch(_recentProvider(range));
    final monthsAsync = ref.watch(_monthlyTotalsProvider(year));
    final totalCountAsync = ref.watch(_totalTransactionsProvider);
    final eventsAsync = ref.watch(_eventTotalsProvider(range));

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(ref.watch(appNameProvider)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              _refreshDashboard(ref);
              showAppMessage(context, 'Refreshed');
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _periodSelector(
            context,
            ref,
            year: year,
            month: month,
            isCurrentMonth: isCurrentMonth,
          ),
          AsyncValueView<PeriodSummary>(
            value: summaryAsync,
            onRetry: () => ref.invalidate(_summaryProvider(range)),
            data: (summary) {
              // No activity in the period: offer the way forward instead of
              // rendering empty charts and zeroed statistics.
              if (summary.isEmpty) {
                return _emptyPeriod(
                  context,
                  ref,
                  countAsync: totalCountAsync,
                  range: range,
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // -------------------------------------------------- balance
                  _balanceCard(
                    context,
                    summary,
                    hasSpecialEvents:
                        eventsAsync.valueOrNull?.isNotEmpty ?? false,
                  ),
                  const SizedBox(height: 12),

                  // --------------------------------------------- quick actions
                  _quickActions(context, ref),
                  const SizedBox(height: 4),

                  // ---------------------------------------------------- stats
                  _statGrid(
                    context,
                    ref,
                    range: range,
                    summary: summary,
                    largestExpense: largestExpenseAsync.valueOrNull,
                  ),

                  // --------------------------------------------- yearly chart
                  const SectionHeader('This year at a glance'),
                  AsyncValueView<List<MonthTotal>>(
                    value: monthsAsync,
                    onRetry: () => ref.invalidate(_monthlyTotalsProvider),
                    data: (months) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        MonthlyIncomeExpenseChart(months: months),
                        const SizedBox(height: 12),
                        _chartLegend(context),
                      ],
                    ),
                  ),

                  // ----------------------------------------- category donut
                  const SectionHeader('Spending by category'),
                  AsyncValueView<List<GroupTotal>>(
                    value: categoryTotalsAsync,
                    onRetry: () =>
                        ref.invalidate(_categoryTotalsProvider(range)),
                    data: (totals) => CategoryDonutChart(
                      totals: totals,
                      centerLabel: 'Spent',
                      centerValueMinor: summary.expenseMinor,
                    ),
                  ),

                  // --------------------------------------------- daily trend
                  const SectionHeader('Daily trend'),
                  AsyncValueView<List<DayTotal>>(
                    value: dailyTotalsAsync,
                    onRetry: () => ref.invalidate(_dailyTotalsProvider(range)),
                    data: (days) => DailyTrendChart(days: days),
                  ),

                  // ---------------------------------------------- recent list
                  SectionHeader(
                    'Recent transactions',
                    trailing: TextButton(
                      onPressed: () => ref
                          .read(shellIndexProvider.notifier)
                          .select(ShellIndexController.transactions),
                      child: const Text('See all'),
                    ),
                  ),
                  AsyncValueView<List<TxItem>>(
                    value: recentAsync,
                    onRetry: () => ref.invalidate(_recentProvider(range)),
                    data: (items) => items.isEmpty
                        ? const EmptyState(
                            icon: Icons.receipt_long_rounded,
                            title: 'Nothing here yet',
                            message:
                                'Transactions recorded in this month will show up here.',
                            compact: true,
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final transaction in items)
                                TransactionListTile(
                                  transaction: transaction,
                                  onTap: () => Navigator.pushNamed(
                                    context,
                                    AppRoutes.editTransaction,
                                    arguments: EditTransactionArgs(transaction),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- widgets

  /// Previous / next arrows around the visible month, with a one-tap way back
  /// to the current month whenever the user has browsed away from it.

  Widget _periodSelector(
    BuildContext context,
    WidgetRef ref, {
    required int year,
    required int month,
    required bool isCurrentMonth,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    void goTo(int offset) {
      final target = AppDates.addMonths(DateTime(year, month, 1), offset);
      ref
          .read(uiPreferencesProvider.notifier)
          .rememberSelection(target.year, target.month);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous month',
            onPressed: () => goTo(-1),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  AppDates.monthYearLabel(year, month),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (isCurrentMonth)
                  Text(
                    'Current month',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  )
                else
                  ActionChip(
                    avatar: const Icon(Icons.today_rounded, size: 16),
                    label: const Text('This month'),
                    onPressed: () {
                      final today = DateTime.now();
                      ref
                          .read(uiPreferencesProvider.notifier)
                          .rememberSelection(today.year, today.month);
                    },
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Next month',
            onPressed: () => goTo(1),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }

  /// Headline card: balance, income and expense with icon + label pairs.
  Widget _balanceCard(
    BuildContext context,
    PeriodSummary summary, {
    required bool hasSpecialEvents,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Balance',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
                Text(
                  summary.isPositiveBalance ? 'Surplus' : 'Overspent',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: summary.isPositiveBalance
                        ? colors.primary
                        : colors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  summary.isPositiveBalance
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  color:
                      summary.isPositiveBalance ? colors.primary : colors.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: MoneyText(
                    summary.balanceMinor,
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _incomeExpenseCell(
                    context,
                    label: 'Income',
                    minor: summary.incomeMinor,
                    count: summary.incomeCount,
                    icon: Icons.trending_up_rounded,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _incomeExpenseCell(
                    context,
                    label: 'Expense',
                    minor: summary.expenseMinor,
                    count: summary.expenseCount,
                    icon: Icons.trending_down_rounded,
                    color: colors.error,
                  ),
                ),
              ],
            ),
            if (hasSpecialEvents) ...[
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.celebration_outlined,
                    size: 16,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Special-event entries are left out of these figures '
                      'and reported separately - see them broken down in '
                      'Reports.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// One half of the balance card: a coloured total with its icon and count.
  Widget _incomeExpenseCell(
    BuildContext context, {
    required String label,
    required int minor,
    required int count,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        MoneyText(
          minor,
          style: theme.textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          '$count ${count == 1 ? 'entry' : 'entries'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  /// Two equally sized buttons that jump to the Add tab.
  Widget _quickActions(BuildContext context, WidgetRef ref) {
    void openAddTab() =>
        ref.read(shellIndexProvider.notifier).select(ShellIndexController.add);

    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: openAddTab,
            icon: const Icon(Icons.trending_down_rounded),
            label: const Text('Add expense'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: openAddTab,
            icon: const Icon(Icons.trending_up_rounded),
            label: const Text('Add income'),
          ),
        ),
      ],
    );
  }

  /// Two-column grid of the period's headline statistics.
  Widget _statGrid(
    BuildContext context,
    WidgetRef ref, {
    required RangeSpec range,
    required PeriodSummary summary,
    TxItem? largestExpense,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final symbol = ref.watch(currencySymbolProvider);
    final topCategory = summary.topExpenseCategoryName;

    final cards = <Widget>[
      StatCard(
        label: 'Transactions',
        value: '${summary.count}',
        icon: Icons.receipt_long_rounded,
        accent: colors.primary,
        caption: range.label,
      ),
      StatCard(
        label: 'Income entries',
        value: '${summary.incomeCount}',
        icon: Icons.trending_up_rounded,
        accent: colors.primary,
        caption: 'Money in',
      ),
      StatCard(
        label: 'Expense entries',
        value: '${summary.expenseCount}',
        icon: Icons.trending_down_rounded,
        accent: colors.error,
        caption: 'Money out',
      ),
      StatCard(
        label: 'Largest expense',
        value: formatMinor(summary.maxExpenseMinor, symbol: symbol),
        icon: Icons.arrow_upward_rounded,
        accent: colors.error,
        // The date carries the month the largest expense belongs to.
        caption: largestExpense == null
            ? 'None this month'
            : AppDates.dateLabel(largestExpense.date),
      ),
      StatCard(
        label: 'Top category',
        value: topCategory ?? '-',
        icon: Icons.category_rounded,
        accent: colors.tertiary,
        caption: topCategory == null
            ? 'Nothing spent yet'
            : 'Biggest share of spending',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final cardWidth = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards) SizedBox(width: cardWidth, child: card),
          ],
        );
      },
    );
  }

  /// Text legend so the grouped bar chart is never colour-only.
  Widget _chartLegend(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    Widget swatch(Color color) => Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        swatch(colors.primary),
        const SizedBox(width: 6),
        Text('Income', style: theme.textTheme.labelMedium),
        const SizedBox(width: 24),
        swatch(colors.error),
        const SizedBox(width: 6),
        Text('Expense', style: theme.textTheme.labelMedium),
      ],
    );
  }

  /// Empty period: distinguishes "this month has nothing in it" from a brand
  /// new database that has never seen a transaction.
  Widget _emptyPeriod(
    BuildContext context,
    WidgetRef ref, {
    required AsyncValue<int> countAsync,
    required RangeSpec range,
  }) {
    return AsyncValueView<int>(
      value: countAsync,
      onRetry: () => ref.invalidate(_totalTransactionsProvider),
      data: (total) {
        final databaseIsEmpty = total == 0;
        return EmptyState(
          icon: databaseIsEmpty
              ? Icons.receipt_long_rounded
              : Icons.event_busy_rounded,
          title: databaseIsEmpty
              ? 'No transactions yet'
              : 'Nothing in ${range.label}',
          message: databaseIsEmpty
              ? 'Add your first expense or income and the balance, charts and '
                  'trends for the month will appear right here.'
              : 'No transactions were recorded in ${range.label}. Move to '
                  'another month or add one right now.',
          actionLabel: 'Add your first transaction',
          onAction: () => ref
              .read(shellIndexProvider.notifier)
              .select(ShellIndexController.add),
        );
      },
    );
  }
}
