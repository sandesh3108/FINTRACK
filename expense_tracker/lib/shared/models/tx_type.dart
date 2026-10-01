/// The two kinds of money movement the app records.
enum TxType {
  expense,
  income;

  /// Value stored in the `type` column.
  String get dbValue => name;

  String get label => this == TxType.expense ? 'Expense' : 'Income';

  static TxType fromDb(String value) =>
      value.toLowerCase() == 'income' ? TxType.income : TxType.expense;

  static TxType? tryParse(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final normalized = value.trim().toLowerCase();
    if (normalized == 'income' || normalized == 'credit' || normalized == 'in') {
      return TxType.income;
    }
    if (normalized == 'expense' ||
        normalized == 'expenses' ||
        normalized == 'debit' ||
        normalized == 'spent' ||
        normalized == 'out') {
      return TxType.expense;
    }
    return null;
  }
}
