import 'package:expense_tracker/shared/models/transaction_input.dart';
import 'package:expense_tracker/shared/models/tx_type.dart';

/// A transaction joined with the display names of everything it references.
///
/// This is the read model the UI works with - widgets never see Drift rows.
class TxItem {
  const TxItem({
    required this.id,
    required this.type,
    required this.amountMinor,
    required this.date,
    required this.time,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
    this.categoryId,
    this.incomeSourceId,
    this.paymentMethodId,
    this.specialEventId,
    this.categoryName,
    this.incomeSourceName,
    this.paymentMethodName,
    this.specialEventName,
    this.categoryArchived = false,
    this.paymentMethodArchived = false,
    this.incomeSourceArchived = false,
    this.specialEventArchived = false,
  });

  final int id;
  final TxType type;
  final int amountMinor;
  final DateTime date;
  final String time;
  final String note;
  final DateTime createdAt;
  final DateTime updatedAt;

  final int? categoryId;
  final int? incomeSourceId;
  final int? paymentMethodId;
  final int? specialEventId;

  final String? categoryName;
  final String? incomeSourceName;
  final String? paymentMethodName;
  final String? specialEventName;

  final bool categoryArchived;
  final bool paymentMethodArchived;
  final bool incomeSourceArchived;
  final bool specialEventArchived;

  /// Category for expenses, income source for income - what the list shows
  /// as the primary label.
  String get primaryLabel {
    if (type == TxType.expense) return categoryName ?? 'Uncategorized';
    return incomeSourceName ?? 'Other';
  }

  bool get isExpense => type == TxType.expense;

  bool get isIncome => type == TxType.income;

  bool get hasEvent => specialEventId != null;

  TransactionInput toInput() => TransactionInput(
        type: type,
        amountMinor: amountMinor,
        date: date,
        time: time,
        categoryId: categoryId,
        incomeSourceId: incomeSourceId,
        paymentMethodId: paymentMethodId,
        specialEventId: specialEventId,
        note: note,
      );

  TxItem copyWith({
    int? id,
    TxType? type,
    int? amountMinor,
    DateTime? date,
    String? time,
    String? note,
    int? categoryId,
    int? incomeSourceId,
    int? paymentMethodId,
    int? specialEventId,
    String? categoryName,
    String? incomeSourceName,
    String? paymentMethodName,
    String? specialEventName,
  }) {
    return TxItem(
      id: id ?? this.id,
      type: type ?? this.type,
      amountMinor: amountMinor ?? this.amountMinor,
      date: date ?? this.date,
      time: time ?? this.time,
      note: note ?? this.note,
      createdAt: createdAt,
      updatedAt: updatedAt,
      categoryId: categoryId ?? this.categoryId,
      incomeSourceId: incomeSourceId ?? this.incomeSourceId,
      paymentMethodId: paymentMethodId ?? this.paymentMethodId,
      specialEventId: specialEventId ?? this.specialEventId,
      categoryName: categoryName ?? this.categoryName,
      incomeSourceName: incomeSourceName ?? this.incomeSourceName,
      paymentMethodName: paymentMethodName ?? this.paymentMethodName,
      specialEventName: specialEventName ?? this.specialEventName,
      categoryArchived: categoryArchived,
      paymentMethodArchived: paymentMethodArchived,
      incomeSourceArchived: incomeSourceArchived,
      specialEventArchived: specialEventArchived,
    );
  }
}
