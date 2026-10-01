import 'package:expense_tracker/shared/models/tx_type.dart';

/// The values captured by the Add / Edit form and by importers.
///
/// Kept free of database types so the UI never depends on Drift.
class TransactionInput {
  const TransactionInput({
    required this.type,
    required this.amountMinor,
    required this.date,
    required this.time,
    this.categoryId,
    this.incomeSourceId,
    this.paymentMethodId,
    this.specialEventId,
    this.note = '',
  });

  final TxType type;

  /// Always greater than zero, in minor units (paise).
  final int amountMinor;

  /// Calendar day (local midnight).
  final DateTime date;

  /// `HH:mm`.
  final String time;

  final int? categoryId;
  final int? incomeSourceId;
  final int? paymentMethodId;
  final int? specialEventId;
  final String note;

  TransactionInput copyWith({
    TxType? type,
    int? amountMinor,
    DateTime? date,
    String? time,
    int? categoryId,
    int? incomeSourceId,
    int? paymentMethodId,
    int? specialEventId,
    String? note,
    bool clearCategory = false,
    bool clearIncomeSource = false,
    bool clearPaymentMethod = false,
    bool clearEvent = false,
  }) {
    return TransactionInput(
      type: type ?? this.type,
      amountMinor: amountMinor ?? this.amountMinor,
      date: date ?? this.date,
      time: time ?? this.time,
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      incomeSourceId: clearIncomeSource ? null : (incomeSourceId ?? this.incomeSourceId),
      paymentMethodId: clearPaymentMethod ? null : (paymentMethodId ?? this.paymentMethodId),
      specialEventId: clearEvent ? null : (specialEventId ?? this.specialEventId),
      note: note ?? this.note,
    );
  }

  @override
  String toString() =>
      'TransactionInput(${type.name} $amountMinor ${date.year}-${date.month}-${date.day} $time)';
}
