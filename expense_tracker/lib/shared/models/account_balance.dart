/// One account's position: where it started, what has flowed through it and
/// what is left.
///
/// A "account" here is a payment method - PhonePe, Google Pay, Cash and
/// BOI(Saving) out of the box - so picking a payment method on a transaction
/// is what moves money in or out of it.
///
/// Every amount is an integer of minor units (paise). There is no floating
/// point anywhere on this path, so the balance cannot drift.
class AccountBalance {
  const AccountBalance({
    required this.paymentMethodId,
    required this.name,
    required this.openingMinor,
    required this.incomeMinor,
    required this.expenseMinor,
    this.isActive = true,
  });

  /// Id of the payment method this balance belongs to.
  final int paymentMethodId;

  final String name;

  /// What the account started at, set once by the user in minor units.
  final int openingMinor;

  /// All income ever recorded against this account.
  final int incomeMinor;

  /// All expenses ever recorded against this account.
  final int expenseMinor;

  /// Archived accounts keep their history but drop out of the picker.
  final bool isActive;

  /// Opening balance plus income, minus expenses.
  int get remainingMinor => openingMinor + incomeMinor - expenseMinor;

  /// Net movement since the opening balance, ignoring the balance itself.
  int get flowMinor => incomeMinor - expenseMinor;

  /// `false` until anything has been recorded against the account, which is
  /// how the UI knows to invite the user to enter an opening balance.
  bool get hasActivity => incomeMinor != 0 || expenseMinor != 0;

  @override
  bool operator ==(Object other) =>
      other is AccountBalance && other.paymentMethodId == paymentMethodId;

  @override
  int get hashCode => paymentMethodId.hashCode;

  @override
  String toString() =>
      'AccountBalance($paymentMethodId, $name, remaining: $remainingMinor)';
}
