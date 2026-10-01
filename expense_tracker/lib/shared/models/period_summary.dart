/// Headline numbers for a date range.
///
/// All amounts are minor units (paise).
class PeriodSummary {
  const PeriodSummary({
    required this.start,
    required this.end,
    this.incomeMinor = 0,
    this.expenseMinor = 0,
    this.incomeCount = 0,
    this.expenseCount = 0,
    this.maxExpenseMinor = 0,
    this.topExpenseCategoryId,
    this.topExpenseCategoryName,
  });

  final DateTime start;
  final DateTime end;
  final int incomeMinor;
  final int expenseMinor;
  final int incomeCount;
  final int expenseCount;

  /// Largest single expense in the range (`0` when there are none).
  final int maxExpenseMinor;

  final int? topExpenseCategoryId;
  final String? topExpenseCategoryName;

  /// `Balance = Total Income - Total Expense`
  int get balanceMinor => incomeMinor - expenseMinor;

  int get count => incomeCount + expenseCount;

  bool get isEmpty => count == 0;

  bool get isPositiveBalance => balanceMinor >= 0;

  PeriodSummary copyWith({
    int? incomeMinor,
    int? expenseMinor,
    int? incomeCount,
    int? expenseCount,
    int? maxExpenseMinor,
    int? Function()? topExpenseCategoryId,
    String? Function()? topExpenseCategoryName,
  }) {
    return PeriodSummary(
      start: start,
      end: end,
      incomeMinor: incomeMinor ?? this.incomeMinor,
      expenseMinor: expenseMinor ?? this.expenseMinor,
      incomeCount: incomeCount ?? this.incomeCount,
      expenseCount: expenseCount ?? this.expenseCount,
      maxExpenseMinor: maxExpenseMinor ?? this.maxExpenseMinor,
      topExpenseCategoryId: topExpenseCategoryId != null
          ? topExpenseCategoryId()
          : this.topExpenseCategoryId,
      topExpenseCategoryName: topExpenseCategoryName != null
          ? topExpenseCategoryName()
          : this.topExpenseCategoryName,
    );
  }
}
