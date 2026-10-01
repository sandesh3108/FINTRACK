import 'package:flutter/material.dart';

import '../../shared/models/range_spec.dart';

/// The seven reports the specification requires, as one closed set.
///
/// Titles, icons and default ranges live here rather than being repeated in
/// the tab, the detail screen and any future deep link - so all three always
/// agree, and adding an eighth report is a single entry.
enum ReportType {
  monthly(
    'Monthly report',
    Icons.calendar_month_outlined,
    'Income, expense and balance for one month',
  ),
  yearly(
    'Yearly report',
    Icons.stacked_bar_chart_outlined,
    'Income and expense trend across twelve months',
  ),
  category(
    'Category report',
    Icons.donut_small_outlined,
    'How spending splits across categories',
  ),
  paymentMethod(
    'Payment method report',
    Icons.account_balance_wallet_outlined,
    'Cash, UPI, card and everything else',
  ),
  income(
    'Income report',
    Icons.trending_up_outlined,
    'Salary and every other income source',
  ),
  specialEvent(
    'Special event report',
    Icons.celebration_outlined,
    'A trip, a festival or a project',
  ),
  customRange(
    'Custom date range',
    Icons.date_range_outlined,
    'Any start and end date you choose',
  );

  const ReportType(this.title, this.icon, this.subtitle);

  /// Heading on the Reports tab and on the detail screen's AppBar.
  final String title;

  /// Leading icon on the Reports tab.
  final IconData icon;

  /// One-line explanation shown under [title].
  final String subtitle;

  /// Range used when the detail screen is opened without an explicit one, for
  /// example from a deep link or from the event screen.
  ///
  /// [ReportType.monthly] is the default because "show me a report" most
  /// often means "this month".
  RangeSpec fallbackRange() => switch (this) {
        ReportType.yearly => RangeSpec.thisYear(),
        ReportType.customRange => RangeSpec.days(
            DateTime.now().subtract(const Duration(days: 30)),
            DateTime.now(),
          ),
        ReportType.specialEvent => RangeSpec.thisYear(),
        _ => RangeSpec.thisMonth(),
      };

  /// The row used by the detail screen to pick a report over a chosen range.
  ///
  /// The event report is the only one that also needs an event id, so it is
  /// carried separately by the route arguments.
  String describe(RangeSpec range) => switch (this) {
        ReportType.category => 'Spending in ${range.label}',
        ReportType.paymentMethod => 'Payments in ${range.label}',
        ReportType.income => 'Income in ${range.label}',
        ReportType.customRange => range.label,
        _ => range.label,
      };
}
