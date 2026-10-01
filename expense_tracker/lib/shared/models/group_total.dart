/// One row of a grouped total: a category, payment method, income source,
/// day or month.
class GroupTotal {
  const GroupTotal({
    this.id,
    required this.name,
    required this.totalMinor,
    required this.count,
    this.isActive = true,
  });

  /// Underlying row id (`null` when the group is "uncategorised").
  final int? id;

  final String name;

  /// Sum in minor units.
  final int totalMinor;

  /// Number of transactions in the group.
  final int count;

  /// Archived rows still show in history but are dimmed in management screens.
  final bool isActive;

  @override
  String toString() => 'GroupTotal($name: $totalMinor x$count)';
}

/// Daily income / expense pair used by the "daily spending" report.
class DayTotal {
  const DayTotal({
    required this.day,
    required this.expenseMinor,
    required this.incomeMinor,
    required this.count,
  });

  final DateTime day;
  final int expenseMinor;
  final int incomeMinor;
  final int count;

  int get balanceMinor => incomeMinor - expenseMinor;
}

/// Monthly income / expense pair used by yearly reports and trends.
class MonthTotal {
  const MonthTotal({
    required this.year,
    required this.month,
    required this.incomeMinor,
    required this.expenseMinor,
    required this.count,
  });

  final int year;
  final int month;
  final int incomeMinor;
  final int expenseMinor;
  final int count;

  int get balanceMinor => incomeMinor - expenseMinor;
}
