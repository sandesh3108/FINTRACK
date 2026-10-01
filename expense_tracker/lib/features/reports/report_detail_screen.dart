import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/state/app_identity.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../repositories/providers.dart';
import '../../shared/models/group_total.dart';
import '../../shared/models/period_summary.dart';
import '../../shared/models/range_spec.dart';
import '../../shared/models/special_event.dart';
import '../../shared/models/transaction_filter.dart';
import '../../shared/models/tx_item.dart';
import '../../shared/models/tx_type.dart';
import '../../shared/widgets/charts.dart';
import '../../shared/widgets/common.dart';
import 'report_definitions.dart';

/// Everything one report needs to answer, as a single value-equality key so
/// Riverpod families cache each combination separately.
class _Scope {
  const _Scope(this.range, [this.eventId]);

  final RangeSpec range;
  final int? eventId;

  @override
  bool operator ==(Object other) =>
      other is _Scope && other.range == range && other.eventId == eventId;

  @override
  int get hashCode => Object.hash(range, eventId);
}

final _summaryProvider = FutureProvider.family<PeriodSummary, _Scope>(
  (ref, scope) => ref
      .watch(transactionRepositoryProvider)
      .summary(scope.range, specialEventId: scope.eventId),
);

final _categoryProvider = FutureProvider.family<List<GroupTotal>, _Scope>(
  (ref, scope) => ref.watch(transactionRepositoryProvider).totalsByCategory(
        scope.range,
        type: TxType.expense,
        specialEventId: scope.eventId,
      ),
);

final _paymentProvider = FutureProvider.family<List<GroupTotal>, _Scope>(
  (ref, scope) =>
      ref.watch(transactionRepositoryProvider).totalsByPaymentMethod(
            scope.range,
            type: TxType.expense,
            specialEventId: scope.eventId,
          ),
);

final _incomeSourceProvider = FutureProvider.family<List<GroupTotal>, _Scope>(
  (ref, scope) =>
      ref.watch(transactionRepositoryProvider).totalsByIncomeSource(
            scope.range,
            specialEventId: scope.eventId,
          ),
);

final _dailyProvider = FutureProvider.family<List<DayTotal>, _Scope>(
  (ref, scope) => ref
      .watch(transactionRepositoryProvider)
      .dailyTotals(scope.range, specialEventId: scope.eventId),
);

/// Every special event that has rows in the range, resolved to its own name
/// so the breakdown can label each one.
final _breakdownProvider =
    FutureProvider.family<List<_BreakdownRow>, _Scope>((ref, scope) async {
  // Both watched before the first await: watching after an `await` is not
  // allowed inside a Riverpod provider body.
  final transactions = ref.watch(transactionRepositoryProvider);
  final events = ref.watch(eventRepositoryProvider);

  final perEvent = await transactions.summariesByEvent(scope.range);
  if (perEvent.isEmpty) return const <_BreakdownRow>[];

  final names = {
    for (final event in await events.getAll(includeArchived: true))
      event.id: event.name,
  };
  return [
    for (final entry in perEvent.entries)
      _BreakdownRow(
        names[entry.key] ?? 'Special event',
        entry.value,
      ),
  ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
});

/// Everything in the range, event rows included - the figure the breakdown
/// adds up to.
final _grandTotalProvider = FutureProvider.family<PeriodSummary, _Scope>(
  (ref, scope) => ref
      .watch(transactionRepositoryProvider)
      .summary(scope.range, includeEventRows: true),
);

/// One row of the per-event half of the breakdown table.
class _BreakdownRow {
  const _BreakdownRow(this.label, this.summary);

  final String label;
  final PeriodSummary summary;
}

final _monthlyProvider = FutureProvider.family<List<MonthTotal>, int>(
  (ref, year) => ref.watch(transactionRepositoryProvider).monthlyTotals(year),
);

final _rowsProvider = FutureProvider.family<List<TxItem>, _Scope>(
  (ref, scope) => ref.watch(transactionRepositoryProvider).getTransactions(
        TransactionFilter(
          range: scope.range,
          specialEventId: scope.eventId,
          sort: TxSort.dateAsc,
          page: 0,
          pageSize: 1000000,
        ),
      ),
);

final _eventProvider = FutureProvider.family<SpecialEvent?, int>(
  (ref, id) => ref.watch(eventRepositoryProvider).byId(id),
);

/// Renders one of the seven reports.
///
/// The same screen serves every report type: it always leads with the headline
/// numbers for the range, then adds the sections that report type calls for.
/// Inference is only needed when the route carries no [type] - the event
/// screen, for example, simply passes an event id.
class ReportDetailScreen extends ConsumerStatefulWidget {
  const ReportDetailScreen({
    super.key,
    required this.title,
    this.range,
    this.specialEventId,
    this.type,
  });

  /// Heading used when [type] is null.
  final String title;

  /// Period to report on; `null` falls back to the type's default range.
  final RangeSpec? range;

  /// Restricts every figure to one special event when set.
  final int? specialEventId;

  /// Which of the seven reports this is. Inferred from [specialEventId]
  /// when omitted.
  final ReportType? type;

  @override
  ConsumerState<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends ConsumerState<ReportDetailScreen> {
  bool _exporting = false;

  ReportType get _type => widget.type ??
      (widget.specialEventId != null
          ? ReportType.specialEvent
          : ReportType.monthly);

  RangeSpec get _range => widget.range ?? _type.fallbackRange();

  _Scope get _scope => _Scope(_range, widget.specialEventId);

  @override
  Widget build(BuildContext context) {
    final type = _type;
    final range = _range;
    final scope = _scope;

    // Watched unconditionally: these are small indexed queries over a range,
    // and doing so keeps every section independent and re-fetchable.
    final summary = ref.watch(_summaryProvider(scope));
    final categories = ref.watch(_categoryProvider(scope));
    final payments = ref.watch(_paymentProvider(scope));
    final incomeSources = ref.watch(_incomeSourceProvider(scope));
    final days = ref.watch(_dailyProvider(scope));
    final months = ref.watch(_monthlyProvider(range.start.year));

    // These are futures, not streams, so without this the screen would keep
    // whatever was computed the first time it opened. Watching the ledger
    // revision re-runs them whenever a transaction is added, edited or deleted
    // anywhere in the app - which is what makes a new row appear without
    // closing and reopening the app.
    ref.listen(ledgerRevisionProvider, (previous, next) {
      if (next.hasValue && next.valueOrNull != previous?.valueOrNull) {
        ref.invalidate(_summaryProvider);
        ref.invalidate(_categoryProvider);
        ref.invalidate(_paymentProvider);
        ref.invalidate(_incomeSourceProvider);
        ref.invalidate(_dailyProvider);
        ref.invalidate(_breakdownProvider);
        ref.invalidate(_grandTotalProvider);
        ref.invalidate(_monthlyProvider);
        ref.invalidate(_rowsProvider);
        ref.invalidate(_eventProvider);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(type.title),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(_summaryProvider);
              ref.invalidate(_categoryProvider);
              ref.invalidate(_paymentProvider);
              ref.invalidate(_incomeSourceProvider);
              ref.invalidate(_dailyProvider);
              ref.invalidate(_breakdownProvider);
              ref.invalidate(_grandTotalProvider);
              ref.invalidate(_monthlyProvider);
              ref.invalidate(_rowsProvider);
              ref.invalidate(_eventProvider);
              showAppMessage(context, 'Refreshed');
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Share as CSV',
            onPressed: _exporting ? null : () => _exportCsv(range, scope),
            icon: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _ScopeHeader(type: type, range: range),
          if (widget.specialEventId != null)
            _EventHeader(eventId: widget.specialEventId!),
          _SummaryCard(summary: summary),
          // The event report already *is* one event, so splitting it again
          // would just repeat the same figures.
          if (type != ReportType.specialEvent) _TotalBreakdown(scope: scope),
          ..._sections(
            type: type,
            summary: summary,
            categories: categories,
            payments: payments,
            incomeSources: incomeSources,
            days: days,
            months: months,
          ),
        ],
      ),
    );
  }

  /// The report body, ordered so the headline number comes before the detail
  /// that explains it.
  List<Widget> _sections({
    required ReportType type,
    required AsyncValue<PeriodSummary> summary,
    required AsyncValue<List<GroupTotal>> categories,
    required AsyncValue<List<GroupTotal>> payments,
    required AsyncValue<List<GroupTotal>> incomeSources,
    required AsyncValue<List<DayTotal>> days,
    required AsyncValue<List<MonthTotal>> months,
  }) {
    switch (type) {
      case ReportType.yearly:
        return [
          _ChartSection(
            title: 'Month by month',
            child: _Async<List<MonthTotal>>(
              value: months,
              emptyMessage: 'Nothing was recorded in this year yet.',
              data: (rows) =>
                  MonthlyIncomeExpenseChart(months: rows),
            ),
          ),
          _categoryBreakdown(categories),
          _paymentBreakdown(payments),
          _incomeBreakdown(incomeSources),
        ];

      case ReportType.category:
        return [
          _ChartSection(
            title: 'Where it went',
            child: _Async<List<GroupTotal>>(
              value: categories,
              emptyMessage: 'No expenses in this range yet.',
              data: (rows) => CategoryDonutChart(totals: rows),
            ),
          ),
          _categoryBreakdown(categories),
          _paymentBreakdown(payments),
        ];

      case ReportType.paymentMethod:
        return [
          _ChartSection(
            title: 'How you paid',
            child: _Async<List<GroupTotal>>(
              value: payments,
              emptyMessage: 'No expenses in this range yet.',
              data: (rows) => RankBars(totals: rows),
            ),
          ),
          _paymentBreakdown(payments),
          _categoryBreakdown(categories),
        ];

      case ReportType.income:
        return [
          _ChartSection(
            title: 'Where it came from',
            child: _Async<List<GroupTotal>>(
              value: incomeSources,
              emptyMessage: 'No income in this range yet.',
              data: (rows) => RankBars(totals: rows),
            ),
          ),
          _incomeBreakdown(incomeSources),
        ];

      case ReportType.specialEvent:
        return [
          _categoryBreakdown(categories),
          _paymentBreakdown(payments),
          _incomeBreakdown(incomeSources),
          _dailyBreakdown(days),
        ];

      case ReportType.monthly:
      case ReportType.customRange:
        return [
          _dailyBreakdown(days),
          _categoryBreakdown(categories),
          _paymentBreakdown(payments),
          _incomeBreakdown(incomeSources),
        ];
    }
  }

  Widget _dailyBreakdown(AsyncValue<List<DayTotal>> days) => _ChartSection(
        title: 'Spending by day',
        child: _Async<List<DayTotal>>(
          value: days,
          emptyMessage: 'Nothing was recorded in this range yet.',
          data: (rows) => DailySpendingBars(days: rows),
        ),
      );

  Widget _categoryBreakdown(AsyncValue<List<GroupTotal>> categories) =>
      _ChartSection(
        title: 'By category',
        child: _Async<List<GroupTotal>>(
          value: categories,
          emptyMessage: 'No expenses in this range yet.',
          data: (rows) => RankBars(totals: rows),
        ),
      );

  Widget _paymentBreakdown(AsyncValue<List<GroupTotal>> payments) =>
      _ChartSection(
        title: 'By payment method',
        child: _Async<List<GroupTotal>>(
          value: payments,
          emptyMessage: 'No expenses in this range yet.',
          data: (rows) => RankBars(totals: rows),
        ),
      );

  Widget _incomeBreakdown(AsyncValue<List<GroupTotal>> incomeSources) =>
      _ChartSection(
        title: 'By income source',
        child: _Async<List<GroupTotal>>(
          value: incomeSources,
          emptyMessage: 'No income in this range yet.',
          data: (rows) => RankBars(totals: rows),
        ),
      );

  /// Writes every row in the report range to a temporary CSV and opens the
  /// Android share sheet.
  Future<void> _exportCsv(RangeSpec range, _Scope scope) async {
    setState(() => _exporting = true);
    try {
      final rows = await ref.read(_rowsProvider(scope).future);
      final csv = _buildCsv(type: _type, range: range, rows: rows);

      final directory = await getTemporaryDirectory();
      final name =
          'expense-report-${_type.name}-${AppDates.isoDay(DateTime.now())}.csv';
      final file = File(p.join(directory.path, name));
      await file.writeAsString(csv, flush: true);

      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          title: '${_type.title} — ${range.label}',
          text: 'Generated by ${ref.read(appNameProvider)}',
        ),
      );
      if (mounted) showAppMessage(context, 'Report exported');
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, friendlyMessage(error), error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Builds the CSV document: a small header block, then one row per
  /// transaction with amounts as decimal strings.
  String _buildCsv({
    required ReportType type,
    required RangeSpec range,
    required List<TxItem> rows,
  }) {
    final buffer = StringBuffer()
      ..writeln('Report,${_csv(type.title)}')
      ..writeln('Range,${_csv(range.label)}')
      ..writeln('From,${AppDates.isoDay(range.start)}')
      ..writeln('To,${AppDates.isoDay(range.end.subtract(const Duration(days: 1)))}')
      ..writeln('Generated,${AppDates.isoTimestamp(DateTime.now())}')
      ..writeln('Transactions,${rows.length}')
      ..writeln()
      ..writeln('Date,Time,Type,Amount,Category,Income source,'
          'Payment method,Event,Note');

    for (final row in rows) {
      buffer.writeln([
        AppDates.isoDay(row.date),
        row.time,
        row.type.name,
        minorToDecimalString(row.amountMinor),
        row.categoryName ?? '',
        row.incomeSourceName ?? '',
        row.paymentMethodName ?? '',
        row.specialEventName ?? '',
        row.note,
      ].map(_csv).join(','));
    }

    return buffer.toString();
  }

  /// Quotes a CSV field when it could otherwise be misread as several.
  static String _csv(String value) {
    if (!value.contains(',') &&
        !value.contains('"') &&
        !value.contains('\n') &&
        !value.contains('\r')) {
      return value;
    }
    return '"${value.replaceAll('"', '""')}"';
  }
}

/// The period being reported on, shown above every figure.
class _ScopeHeader extends StatelessWidget {
  const _ScopeHeader({required this.type, required this.range});

  final ReportType type;
  final RangeSpec range;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(type.title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 2),
          Text(
            type.describe(range),
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

/// Event name and window for the special event report.
class _EventHeader extends ConsumerWidget {
  const _EventHeader({required this.eventId});

  final int eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = ref.watch(_eventProvider(eventId));
    final value = event.valueOrNull;
    if (value == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.celebration_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(value.name, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${value.dateRangeLabel} · ${value.transactionCount} '
              'transaction${value.transactionCount == 1 ? '' : 's'}',
              style: theme.textTheme.bodySmall,
            ),
            if (value.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(value.description, style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}

/// Income / expense / balance for the range - the first thing every report
/// should answer.
/// Splits a period into regular monthly figures, one row per special event,
/// and a grand total that adds them back together - for expense and income.
///
/// Renders nothing when the range holds no special-event transactions, since
/// the summary card above is then already the whole story.
class _TotalBreakdown extends ConsumerWidget {
  const _TotalBreakdown({required this.scope});

  final _Scope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final eventRows = ref.watch(_breakdownProvider(scope)).valueOrNull;
    if (eventRows == null || eventRows.isEmpty) {
      return const SizedBox.shrink();
    }
    final monthly = ref.watch(_summaryProvider(scope)).valueOrNull;
    final grand = ref.watch(_grandTotalProvider(scope)).valueOrNull;
    if (monthly == null || grand == null) return const SizedBox.shrink();

    Widget line(String label, int minor, {bool total = false}) {
      final style = total
          ? theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)
          : theme.textTheme.bodyMedium;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label, style: style)),
            MoneyText(minor, style: style),
          ],
        ),
      );
    }

    Widget group({
      required String title,
      required IconData icon,
      required String regularLabel,
      required int Function(PeriodSummary period) of,
    }) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 6),
            line(regularLabel, of(monthly)),
            for (final row in eventRows) line(row.label, of(row.summary)),
            const SizedBox(height: 4),
            line('Grand Total', of(grand), total: true),
          ],
        );

    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total breakdown', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Special events are kept out of the monthly figures and listed '
              'separately; the grand total adds them back in.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            group(
              title: 'Expense',
              icon: Icons.trending_down_rounded,
              regularLabel: 'Monthly expenses',
              of: (period) => period.expenseMinor,
            ),
            const Divider(height: 28),
            group(
              title: 'Income',
              icon: Icons.trending_up_rounded,
              regularLabel: 'Monthly income',
              of: (period) => period.incomeMinor,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends ConsumerWidget {
  const _SummaryCard({required this.summary});

  final AsyncValue<PeriodSummary> summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // The user can rename the currency at runtime, so read it rather than
    // assuming the build-time default.
    final symbol = ref.watch(currencySymbolProvider);

    return AsyncValueView<PeriodSummary>(
      value: summary,
      loadingLabel: 'Totaling the period…',
      data: (data) {
        if (data.isEmpty) {
          return const EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'Nothing recorded',
            message:
                'There are no transactions in this range, so there is nothing '
                'to report yet.',
          );
        }
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Totals', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _Figure(
                        label: 'Income',
                        icon: Icons.trending_up_rounded,
                        minor: data.incomeMinor,
                        count: data.incomeCount,
                      ),
                    ),
                    Expanded(
                      child: _Figure(
                        label: 'Expense',
                        icon: Icons.trending_down_rounded,
                        minor: data.expenseMinor,
                        count: data.expenseCount,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 20,
                      color: data.isPositiveBalance
                          ? theme.colorScheme.primary
                          : theme.colorScheme.error,
                      semanticLabel: 'Balance',
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Balance', style: theme.textTheme.bodyLarge),
                    ),
                    MoneyText(
                      data.balanceMinor,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: data.isPositiveBalance
                            ? null
                            : theme.colorScheme.error,
                      ),
                    ),
                  ],
                ),
                if (data.maxExpenseMinor > 0) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Largest expense: '
                    '${formatMinor(data.maxExpenseMinor, symbol: symbol)}'
                    '${data.topExpenseCategoryName == null
                        ? ''
                        : ' · ${data.topExpenseCategoryName}'}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One income/expense figure in the summary card.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.icon,
    required this.minor,
    required this.count,
  });

  final String label;
  final IconData icon;
  final int minor;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text(label, style: theme.textTheme.labelLarge),
          ],
        ),
        const SizedBox(height: 4),
        MoneyText(minor, style: theme.textTheme.titleLarge),
        Text('$count', style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// A titled block holding one chart or table.
class _ChartSection extends StatelessWidget {
  const _ChartSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [SectionHeader(title), child, const SizedBox(height: 8)],
    );
  }
}

/// Renders a loaded value, or the empty state when nothing was recorded.
///
/// A failure surfaces through [AsyncValueView]'s error path rather than
/// blanking the report, so one broken query never hides the rest.
class _Async<T extends List<Object?>> extends StatelessWidget {
  const _Async({required this.value, required this.data, required this.emptyMessage});

  final AsyncValue<T> value;
  final Widget Function(T rows) data;
  final String emptyMessage;

  Widget _empty() => EmptyState(
        icon: Icons.bar_chart_rounded,
        title: 'Nothing to show',
        message: emptyMessage,
        compact: true,
      );

  @override
  Widget build(BuildContext context) {
    return AsyncValueView<T>(
      value: value,
      data: (rows) => rows.isEmpty ? _empty() : data(rows),
    );
  }
}
