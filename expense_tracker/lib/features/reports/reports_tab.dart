import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../app/state/ui_preferences.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/date_utils.dart';
import '../../repositories/providers.dart';
import '../../shared/models/period_summary.dart';
import '../../shared/models/range_spec.dart';
import '../../shared/widgets/catalog_picker.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/form_fields.dart';
import 'report_definitions.dart';

/// Which granularity the range picker on the Reports tab is showing.
enum _RangeScope { month, year, custom }

/// Live headline numbers for whatever range the picker is currently showing.
final _summaryProvider = FutureProvider.family<PeriodSummary, RangeSpec>(
  (ref, range) => ref.watch(transactionRepositoryProvider).summary(range),
);

/// The Reports tab: pick a period, then pick one of the seven reports.
///
/// The chosen month and year are written back to the UI preferences, so the
/// tab reopens where the user left off after a restart.
class ReportsTab extends ConsumerStatefulWidget {
  const ReportsTab({super.key});

  @override
  ConsumerState<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends ConsumerState<ReportsTab> {
  _RangeScope _scope = _RangeScope.month;
  int _year = DateTime.now().year;
  int _month = DateTime.now().month;
  DateTime _customStart = DateTime.now().subtract(const Duration(days: 30));
  DateTime _customEnd = DateTime.now();
  String? _failure;

  @override
  void initState() {
    super.initState();
    // Reopen on the period the user was last looking at.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final preferences = ref.read(uiPreferencesProvider);
      setState(() {
        _year = preferences.lastSelectedYear ?? _year;
        _month = preferences.lastSelectedMonth ?? _month;
      });
    });
  }

  RangeSpec get _range => switch (_scope) {
        _RangeScope.month => RangeSpec.month(_year, _month),
        _RangeScope.year => RangeSpec.year(_year),
        _RangeScope.custom => RangeSpec.days(_customStart, _customEnd),
      };

  String get _rangeLabel => switch (_scope) {
        _RangeScope.month => AppDates.monthYearLabel(_year, _month),
        _RangeScope.year => '$_year',
        _RangeScope.custom => '${AppDates.dateLabel(_customStart)} – '
            '${AppDates.dateLabel(_customEnd)}',
      };

  /// Remembers the selected month/year so the tab reopens in the same place.
  void _remember() {
    ref.read(uiPreferencesProvider.notifier).rememberSelection(_year, _month);
  }

  void _shift(int delta) {
    setState(() {
      if (_scope == _RangeScope.month) {
        final moved = DateTime(_year, _month + delta, 1);
        _year = moved.year;
        _month = moved.month;
      } else if (_scope == _RangeScope.year) {
        _year += delta;
      }
    });
    if (_scope != _RangeScope.custom) _remember();
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(_summaryProvider(_range));

    // These are futures, not streams, so without this the screen would keep
    // whatever was computed the first time it opened. Watching the ledger
    // revision re-runs them whenever a transaction is added, edited or deleted
    // anywhere in the app - which is what makes a new row appear without
    // closing and reopening the app.
    ref.listen(ledgerRevisionProvider, (previous, next) {
      if (next.hasValue && next.valueOrNull != previous?.valueOrNull) {
        ref.invalidate(_summaryProvider);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(_summaryProvider);
              showAppMessage(context, 'Refreshed');
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _buildRangePicker(context),
          const SizedBox(height: 12),
          _buildSummary(summary),
          if (_failure != null) ...[
            const SizedBox(height: 12),
            _buildFailure(context),
          ],
          const SizedBox(height: 8),
          SectionHeader('Reports'),
          for (final type in ReportType.values)
            _ReportTile(
              type: type,
              rangeLabel: _rangeLabel,
              onTap: () => _open(type),
            ),
        ],
      ),
    );
  }

  Widget _buildRangePicker(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<_RangeScope>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: _RangeScope.month,
                  label: Text('Month'),
                  icon: Icon(Icons.calendar_today_outlined),
                ),
                ButtonSegment(
                  value: _RangeScope.year,
                  label: Text('Year'),
                  icon: Icon(Icons.calendar_view_month_outlined),
                ),
                ButtonSegment(
                  value: _RangeScope.custom,
                  label: Text('Custom'),
                  icon: Icon(Icons.date_range_outlined),
                ),
              ],
              selected: {_scope},
              onSelectionChanged: (next) => setState(() {
                _scope = next.first;
                _failure = null;
              }),
            ),
            const SizedBox(height: 16),
            if (_scope == _RangeScope.custom)
              Column(
                children: [
                  DateField(
                    label: 'From',
                    value: _customStart,
                    onChanged: (value) => setState(() {
                      _customStart = value;
                      if (_customEnd.isBefore(value)) _customEnd = value;
                    }),
                  ),
                  const SizedBox(height: 12),
                  DateField(
                    label: 'To',
                    value: _customEnd,
                    errorText: _customEnd.isBefore(_customStart)
                        ? 'The end date cannot be before the start date.'
                        : null,
                    onChanged: (value) => setState(() => _customEnd = value),
                  ),
                ],
              )
            else
              Row(
                children: [
                  IconButton.outlined(
                    tooltip: _scope == _RangeScope.month
                        ? 'Previous month'
                        : 'Previous year',
                    onPressed: () => _shift(-1),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _rangeLabel,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton.outlined(
                    tooltip: _scope == _RangeScope.month
                        ? 'Next month'
                        : 'Next year',
                    onPressed: () => _shift(1),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(AsyncValue<PeriodSummary> summary) {
    return AsyncValueView<PeriodSummary>(
      value: summary,
      loadingLabel: 'Totaling the period…',
      onRetry: () => ref.invalidate(_summaryProvider(_range)),
      data: (data) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Totals for $_rangeLabel',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _TotalRow(
                label: 'Income',
                minor: data.incomeMinor,
                icon: Icons.trending_up_rounded,
              ),
              _TotalRow(
                label: 'Expense',
                minor: data.expenseMinor,
                icon: Icons.trending_down_rounded,
              ),
              const Divider(height: 24),
              _TotalRow(
                label: 'Balance',
                minor: data.balanceMinor,
                icon: Icons.account_balance_wallet_outlined,
                emphasise: true,
              ),
              const SizedBox(height: 4),
              Text(
                '${data.count} transaction${data.count == 1 ? '' : 's'}'
                ' · ${data.incomeCount} income · ${data.expenseCount} expense',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFailure(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_failure!, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => setState(() => _failure = null),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the chosen report.
  ///
  /// Six of the seven need nothing but the range; the event report first asks
  /// which event, because an event report without an event is meaningless.
  Future<void> _open(ReportType type) async {
    _failure = null;
    if (type == ReportType.specialEvent) {
      final eventId = await _pickEvent();
      if (eventId == null || !mounted) return;
      await _push(type, eventId: eventId);
      return;
    }
    await _push(type);
  }

  Future<void> _push(ReportType type, {int? eventId}) async {
    try {
      final range = _range;
      await Navigator.of(context).pushNamed(
        AppRoutes.reportDetail,
        arguments: ReportDetailArgs(
          title: type.title,
          range: range,
          type: type,
          specialEventId: eventId,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _failure = friendlyMessage(error));
    }
  }

  /// Asks which event to report on. Returns `null` when the user cancels.
  Future<int?> _pickEvent() async {
    var selected = SpecialEventPicker.noneValue;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Special event report'),
          content: SizedBox(
            width: 360,
            child: SpecialEventPicker(
              label: 'Event',
              valueId: selected,
              onChanged: (value) => setDialogState(
                () => selected = value ?? SpecialEventPicker.noneValue,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Open report'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || selected <= 0) return null;
    return selected;
  }
}

/// One row of the headline totals card.
class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.minor,
    required this.icon,
    this.emphasise = false,
  });

  final String label;
  final int minor;
  final IconData icon;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isNegative = minor < 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: isNegative ? scheme.error : scheme.primary,
            semanticLabel: label,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: theme.textTheme.bodyLarge),
          ),
          MoneyText(
            minor,
            style: emphasise
                ? theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isNegative ? scheme.error : null,
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

/// A tappable entry for one of the seven reports.
class _ReportTile extends StatelessWidget {
  const _ReportTile({
    required this.type,
    required this.rangeLabel,
    required this.onTap,
  });

  final ReportType type;
  final String rangeLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.secondaryContainer,
          foregroundColor: theme.colorScheme.onSecondaryContainer,
          child: Icon(type.icon, size: 22),
        ),
        title: Text(type.title),
        subtitle: Text(type.subtitle),
        trailing: Text(
          rangeLabel,
          style: theme.textTheme.labelMedium
              ?.copyWith(color: theme.colorScheme.outline),
          textAlign: TextAlign.end,
        ),
        onTap: onTap,
      ),
    );
  }
}
