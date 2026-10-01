import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../repositories/providers.dart';
import '../../shared/models/group_total.dart';
import 'common.dart';

// -----------------------------------------------------------------------------
// Chart palette helpers
// -----------------------------------------------------------------------------

/// Colour for a group by its position in the palette so the same category
/// keeps the same colour across every chart on a screen.
Color colorForIndex(ColorScheme scheme, int index) {
  final palette = _paletteFor(scheme);
  return palette[index % palette.length];
}

List<Color> _paletteFor(ColorScheme scheme) => <Color>[
      scheme.primary,
      scheme.tertiary,
      scheme.secondary,
      const Color(0xFF00897B),
      const Color(0xFFF9A825),
      const Color(0xFFD84315),
      const Color(0xFF5E35B1),
      const Color(0xFF0277BD),
      const Color(0xFF7CB342),
      const Color(0xFFAD1457),
    ];

/// Rounds an axis maximum up to a readable amount in *paise* so ticks land on
/// round currency values.
double axisMaxPaise(int maximumMinor) {
  if (maximumMinor <= 0) return 100000; // ₹1,000
  const steps = <int>[10000, 25000, 50000, 100000, 250000, 500000, 1000000];
  for (final step in steps) {
    if (maximumMinor <= step * 4) {
      final divisions = (maximumMinor / step).ceil();
      return (divisions * step).toDouble();
    }
  }
  // Fall back to the nearest crore of paise (₹10,00,000).
  const crore = 100000000;
  return ((maximumMinor ~/ crore) + 1) * crore.toDouble();
}

// -----------------------------------------------------------------------------
// Category donut
// -----------------------------------------------------------------------------

/// Donut chart of a grouped breakdown (categories, payment methods, sources).
///
/// The centre shows the period total, and a legend below repeats every value
/// as text so the data is never colour-only - required for accessibility.
class CategoryDonutChart extends ConsumerStatefulWidget {
  const CategoryDonutChart({
    super.key,
    required this.totals,
    this.centerLabel = 'Total',
    this.centerValueMinor,
    this.emptyMessage = 'Nothing recorded for this period yet.',
  });

  final List<GroupTotal> totals;
  final String centerLabel;
  final int? centerValueMinor;
  final String emptyMessage;

  @override
  ConsumerState<CategoryDonutChart> createState() => _CategoryDonutChartState();
}

class _CategoryDonutChartState extends ConsumerState<CategoryDonutChart> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final symbol = ref.watch(currencySymbolProvider);
    final totals = widget.totals;

    if (totals.isEmpty) {
      return EmptyState(
        icon: Icons.donut_small_rounded,
        title: 'No data yet',
        message: widget.emptyMessage,
        compact: true,
      );
    }

    final sum = totals.fold<int>(0, (acc, item) => acc + item.totalMinor);
    final highlighted = _selected == null ? null : totals[_selected!];

    return Column(
      children: [
        SizedBox(
          height: 200,
          child: PieChart(
            PieChartData(
              centerSpaceRadius: 52,
              sectionsSpace: 2,
              startDegreeOffset: -90,
              sections: [
                for (var i = 0; i < totals.length; i++)
                  PieChartSectionData(
                    value: totals[i].totalMinor.toDouble(),
                    color: colorForIndex(colors, i),
                    radius: _selected == i ? 46 : 40,
                    showTitle: false,
                  ),
              ],
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  if (event is FlTapUpEvent || event is FlPanEndEvent) {
                    final section = response?.touchedSection?.touchedSectionIndex;
                    setState(() {
                      _selected = (section == null || section == _selected) ? null : section;
                    });
                  }
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                highlighted?.name ?? widget.centerLabel,
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: colors.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              highlighted == null
                  ? MoneyText(
                      widget.centerValueMinor ?? sum,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    )
                  : MoneyText(
                      highlighted.totalMinor,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorForIndex(
                          colors,
                          totals.indexOf(highlighted),
                        ),
                      ),
                    ),
              if (highlighted != null)
                Text(
                  _percent(highlighted.totalMinor, sum),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (var i = 0; i < totals.length; i++)
              _LegendChip(
                color: colorForIndex(colors, i),
                label: totals[i].name,
                value: totals[i].totalMinor,
                share: _percent(totals[i].totalMinor, sum),
                selected: _selected == i,
                symbol: symbol,
                onTap: () => setState(() {
                  _selected = _selected == i ? null : i;
                }),
              ),
          ],
        ),
      ],
    );
  }

  static String _percent(int part, int total) {
    if (total <= 0) return '0%';
    final ratio = ((part * 1000) ~/ total) / 10;
    if (ratio >= 99.95) return '100%';
    if (ratio <= 0.05) return '0%';
    return ratio.toStringAsFixed(ratio < 10 ? 1 : 0).replaceFirst('.0', '');
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({
    required this.color,
    required this.label,
    required this.value,
    required this.share,
    required this.selected,
    required this.symbol,
    required this.onTap,
  });

  final Color color;
  final String label;
  final int value;
  final String share;
  final bool selected;
  final String symbol;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              '$label ${formatMinor(value, symbol: symbol)} ($share)',
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Monthly income vs expense bars
// -----------------------------------------------------------------------------

/// Grouped bar chart comparing income and expense for each month of a year.
class MonthlyIncomeExpenseChart extends ConsumerWidget {
  const MonthlyIncomeExpenseChart({super.key, required this.months, this.spotMonths});

  /// Twelve months (zero-filled) produced by `TransactionRepository.monthlyTotals`.
  final List<MonthTotal> months;

  /// Restricts the x-axis to months that actually have data, so a year with
  /// two months of history is not dominated by empty space.
  final Set<int>? spotMonths;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final symbol = ref.watch(currencySymbolProvider);

    final visible = months
        .where((m) => spotMonths == null || spotMonths!.contains(m.month))
        .toList();

    final maxima = visible
        .expand((m) => <int>[m.incomeMinor, m.expenseMinor])
        .fold<int>(0, (a, b) => a > b ? a : b);
    final maxY = axisMaxPaise(maxima);

    if (visible.every((m) => m.count == 0)) {
      return const EmptyState(
        icon: Icons.bar_chart_rounded,
        title: 'No data yet',
        message: 'Add transactions to see your monthly income and expenses.',
        compact: true,
      );
    }

    return SizedBox(
      height: 240,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY / 4,
            getDrawingHorizontalLine: (value) => FlLine(
              color: colors.outlineVariant.withValues(alpha: 0.5),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (group) => colors.surfaceContainerHigh,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final month = visible[group.x];
                final label = rodIndex == 0 ? 'Income' : 'Expense';
                return BarTooltipItem(
                  '${AppDates.monthShort(month.month)}\n'
                  '$label ${formatMinor(rod.toY.round(), symbol: symbol)}',
                  theme.textTheme.labelSmall!.copyWith(color: colors.onSurface),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 54,
                interval: maxY / 4,
                getTitlesWidget: (value, meta) => Text(
                  formatMinorShort(value.round(), symbol: symbol),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= visible.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      AppDates.monthShort(visible[index].month),
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < visible.length; i++)
              BarChartGroupData(
                x: i,
                barsSpace: 4,
                barRods: [
                  BarChartRodData(
                    toY: visible[i].incomeMinor.toDouble(),
                    color: colors.primary,
                    width: 8,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3),
                    ),
                  ),
                  BarChartRodData(
                    toY: visible[i].expenseMinor.toDouble(),
                    color: colors.error,
                    width: 8,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Daily trend
// -----------------------------------------------------------------------------

/// Line chart of the daily balance / expense trend inside one period.
class DailyTrendChart extends ConsumerWidget {
  const DailyTrendChart({
    super.key,
    required this.days,
    this.includeIncome = true,
    this.emptyMessage = 'Add transactions to see your daily trend.',
  });

  final List<DayTotal> days;
  final bool includeIncome;
  final String emptyMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final symbol = ref.watch(currencySymbolProvider);

    if (days.isEmpty) {
      return EmptyState(
        icon: Icons.show_chart_rounded,
        title: 'No data yet',
        message: emptyMessage,
        compact: true,
      );
    }

    final maxima = days
        .expand((d) => <int>[d.expenseMinor, d.incomeMinor])
        .fold<int>(0, (a, b) => a > b ? a : b);
    final maxY = axisMaxPaise(maxima);

    final expenseSpots = <FlSpot>[
      for (var i = 0; i < days.length; i++)
        FlSpot(i.toDouble(), days[i].expenseMinor.toDouble()),
    ];
    final incomeSpots = <FlSpot>[
      for (var i = 0; i < days.length; i++)
        FlSpot(i.toDouble(), days[i].incomeMinor.toDouble()),
    ];

    return SizedBox(
      height: 240,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY,
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (spot) => colors.surfaceContainerHigh,
              getTooltipItems: (spots) => [
                for (final spot in spots)
                  LineTooltipItem(
                    '${AppDates.dateLabel(days[spot.x.toInt()].day)}\n'
                    '${spot.barIndex == 0 ? 'Expense' : 'Income'} '
                    '${formatMinor(spot.y.round(), symbol: symbol)}',
                    theme.textTheme.labelSmall!.copyWith(color: colors.onSurface),
                  ),
              ],
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY / 4,
            getDrawingHorizontalLine: (value) => FlLine(
              color: colors.outlineVariant.withValues(alpha: 0.5),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            show: true,
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 54,
                interval: maxY / 4,
                getTitlesWidget: (value, meta) => Text(
                  formatMinorShort(value.round(), symbol: symbol),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                interval: (days.length - 1).clamp(1, 1e9).toDouble() / 6,
                getTitlesWidget: (value, meta) {
                  final index = value.round();
                  if (index < 0 || index >= days.length) {
                    return const SizedBox.shrink();
                  }
                  if (days.length > 1 &&
                      index % ((days.length / 7).ceil().clamp(1, 1000)) != 0) {
                    return const SizedBox.shrink();
                  }
                  final day = days[index].day;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${day.day} ${AppDates.monthShort(day.month)}',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: expenseSpots,
              isCurved: true,
              color: colors.error,
              barWidth: 3,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: colors.error.withValues(alpha: 0.12),
              ),
            ),
            if (includeIncome)
              LineChartBarData(
                spots: incomeSpots,
                isCurved: true,
                color: colors.primary,
                barWidth: 3,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: colors.primary.withValues(alpha: 0.10),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Daily spending bars
// -----------------------------------------------------------------------------

/// Vertical bars for one series per day - used by the daily spending report.
class DailySpendingBars extends ConsumerWidget {
  const DailySpendingBars({
    super.key,
    required this.days,
    this.color,
    this.emptyMessage = 'Nothing was recorded for this period.',
    this.tapable = false,
    this.onTapDay,
  });

  final List<DayTotal> days;
  final Color? color;
  final String emptyMessage;
  final bool tapable;
  final ValueChanged<DayTotal>? onTapDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final symbol = ref.watch(currencySymbolProvider);
    final barColor = color ?? colors.primary;

    if (days.isEmpty) {
      return EmptyState(
        icon: Icons.calendar_view_day_rounded,
        title: 'No data yet',
        message: emptyMessage,
        compact: true,
      );
    }

    final maxima =
        days.fold<int>(0, (a, b) => a > b.expenseMinor ? a : b.expenseMinor);
    final maxY = axisMaxPaise(maxima);

    return SizedBox(
      height: 240,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY / 4,
            getDrawingHorizontalLine: (value) => FlLine(
              color: colors.outlineVariant.withValues(alpha: 0.5),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (group) => colors.surfaceContainerHigh,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final day = days[group.x];
                return BarTooltipItem(
                  '${AppDates.dateLabel(day.day)}\n'
                  '${formatMinor(day.expenseMinor, symbol: symbol)}'
                  '${day.count > 0 ? ' · ${day.count} tx' : ''}',
                  theme.textTheme.labelSmall!.copyWith(color: colors.onSurface),
                );
              },
            ),
            touchCallback: (event, response) {
              if (!tapable || onTapDay == null) return;
              if (event is FlTapUpEvent) {
                final index = response?.spot?.touchedBarGroupIndex;
                if (index != null && index >= 0 && index < days.length) {
                  onTapDay!(days[index]);
                }
              }
            },
          ),
          titlesData: FlTitlesData(
            show: true,
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 54,
                interval: maxY / 4,
                getTitlesWidget: (value, meta) => Text(
                  formatMinorShort(value.round(), symbol: symbol),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= days.length) {
                    return const SizedBox.shrink();
                  }
                  if (days.length > 10 && index % ((days.length / 8).ceil()) != 0) {
                    return const SizedBox.shrink();
                  }
                  final day = days[index].day;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${day.day}',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < days.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: days[i].expenseMinor.toDouble(),
                    color: days[i].expenseMinor == 0
                        ? colors.outlineVariant.withValues(alpha: 0.4)
                        : barColor,
                    width: days.length > 20 ? 6 : 14,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Horizontal ranking bars (no chart library needed)
// -----------------------------------------------------------------------------

/// Horizontal proportional bars for a ranked list (payment methods, income
/// sources, categories). Uses plain layout rather than a chart library so it
/// stays readable with 25+ entries.
class RankBars extends ConsumerWidget {
  const RankBars({
    super.key,
    required this.totals,
    this.tint,
    this.emptyMessage = 'Nothing recorded for this period yet.',
    this.maxRows = 12,
    this.showPercent = true,
  });

  final List<GroupTotal> totals;
  final Color? tint;
  final String emptyMessage;
  final int maxRows;
  final bool showPercent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final symbol = ref.watch(currencySymbolProvider);

    if (totals.isEmpty) {
      return EmptyState(
        icon: Icons.format_list_numbered_rounded,
        title: 'No data yet',
        message: emptyMessage,
        compact: true,
      );
    }

    final sum = totals.fold<int>(0, (acc, item) => acc + item.totalMinor);
    final rows = totals.take(maxRows).toList();

    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Semantics(
              label:
                  '${rows[i].name}, ${formatMinor(rows[i].totalMinor, symbol: symbol)}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: tint ?? colorForIndex(colors, i),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          rows[i].name,
                          style: theme.textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (showPercent && sum > 0)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Text(
                            '${(rows[i].totalMinor * 1000 ~/ sum) / 10}%',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      MoneyText(
                        rows[i].totalMinor,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: sum == 0 ? 0 : rows[i].totalMinor / sum,
                      minHeight: 6,
                      backgroundColor: colors.surfaceContainerHighest,
                      color: tint ?? colorForIndex(colors, i),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (totals.length > maxRows)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '+ ${totals.length - maxRows} more',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Month-over-month comparison
// -----------------------------------------------------------------------------

/// Side-by-side bars for two periods (this month vs last month, this year vs
/// last year).
class ComparisonBars extends ConsumerWidget {
  const ComparisonBars({
    super.key,
    required this.entries,
    this.emptyMessage = 'Not enough data to compare yet.',
  });

  /// Label, this-period total, previous-period total.
  final List<ComparisonEntry> entries;
  final String emptyMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final symbol = ref.watch(currencySymbolProvider);

    final maxima = entries
        .expand((e) => <int>[e.currentMinor, e.previousMinor])
        .fold<int>(0, (a, b) => a > b ? a : b);

    if (maxima == 0) {
      return EmptyState(
        icon: Icons.compare_arrows_rounded,
        title: 'No data yet',
        message: emptyMessage,
        compact: true,
      );
    }

    return Column(
      children: [
        Row(
          children: [
            AppBadge(label: 'Current', color: colors.primary),
            const SizedBox(width: 12),
            AppBadge(label: 'Previous', color: colors.onSurfaceVariant),
          ],
        ),
        const SizedBox(height: 14),
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Semantics(
              label:
                  '${entry.label}: current ${formatMinor(entry.currentMinor, symbol: symbol)}, '
                  'previous ${formatMinor(entry.previousMinor, symbol: symbol)}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.label, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  _bar(
                    context,
                    value: entry.currentMinor,
                    maxima: maxima,
                    color: colors.primary,
                    label: 'Current',
                  ),
                  const SizedBox(height: 6),
                  _bar(
                    context,
                    value: entry.previousMinor,
                    maxima: maxima,
                    color: colors.onSurfaceVariant.withValues(alpha: 0.5),
                    label: 'Previous',
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _bar(
    BuildContext context, {
    required int value,
    required int maxima,
    required Color color,
    required String label,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          flex: 70,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: maxima == 0 ? 0 : value / maxima,
              minHeight: 10,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 92,
          child: MoneyText(
            value,
            align: TextAlign.right,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// One row of a [ComparisonBars].
class ComparisonEntry {
  const ComparisonEntry({
    required this.label,
    required this.currentMinor,
    required this.previousMinor,
  });

  final String label;
  final int currentMinor;
  final int previousMinor;
}

// -----------------------------------------------------------------------------
// Summary table
// -----------------------------------------------------------------------------

/// Accessible text alternative for a chart: a plain table of values.
class TotalsTable extends ConsumerWidget {
  const TotalsTable({super.key, required this.rows, this.title});

  /// Label, amount, optional transaction count.
  final List<TotalsTableRow> rows;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              title!,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          rows[i].label,
                          style: theme.textTheme.bodyMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (rows[i].count != null) ...[
                        Text(
                          '${rows[i].count} tx',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      MoneyText(
                        rows[i].amountMinor,
                        align: TextAlign.right,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class TotalsTableRow {
  const TotalsTableRow(this.label, this.amountMinor, {this.count});

  final String label;
  final int amountMinor;
  final int? count;
}
