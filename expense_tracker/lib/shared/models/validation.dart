import 'package:expense_tracker/shared/models/catalog_item.dart';
import 'package:expense_tracker/shared/models/special_event.dart';
import 'package:expense_tracker/shared/models/transaction_input.dart';
import 'package:expense_tracker/shared/models/tx_item.dart';
import 'package:expense_tracker/shared/models/tx_type.dart';

/// Result of validating a [TransactionInput] before it reaches the database.
class ValidationResult {
  const ValidationResult.ok()
      : isValid = true,
        message = null,
        field = null;

  const ValidationResult.error(this.message, {this.field})
      : isValid = false;

  final bool isValid;
  final String? message;
  final String? field;

  @override
  String toString() => isValid ? 'ok' : 'error: $message';
}

/// Business rules from the specification, applied in one place so the form,
/// the importer and backup restore all agree.
class TransactionRules {
  const TransactionRules._();

  static ValidationResult validate(
    TransactionInput input, {
    required bool categoryExists,
    required bool incomeSourceExists,
    required bool paymentMethodExists,
  }) {
    if (input.amountMinor <= 0) {
      return const ValidationResult.error('Enter an amount greater than zero.',
          field: 'amount');
    }

    if (input.type != TxType.expense && input.type != TxType.income) {
      return const ValidationResult.error('Choose Expense or Income.',
          field: 'type');
    }

    if (input.type == TxType.expense) {
      if (input.categoryId == null) {
        return const ValidationResult.error('Choose a category for this expense.',
            field: 'category');
      }
      if (!categoryExists) {
        return const ValidationResult.error('That category no longer exists.',
            field: 'category');
      }
      if (input.paymentMethodId == null) {
        return const ValidationResult.error('Choose a payment method.',
            field: 'paymentMethod');
      }
      if (!paymentMethodExists) {
        return const ValidationResult.error('That payment method no longer exists.',
            field: 'paymentMethod');
      }
    }

    if (input.type == TxType.income) {
      if (input.incomeSourceId == null) {
        return const ValidationResult.error('Choose an income source.',
            field: 'incomeSource');
      }
      if (!incomeSourceExists) {
        return const ValidationResult.error('That income source no longer exists.',
            field: 'incomeSource');
      }
    }

    if (input.time.length != 5) {
      return const ValidationResult.error('Choose a valid time.', field: 'time');
    }

    return const ValidationResult.ok();
  }
}

/// Duplicate key used by import preview and backup merge.
///
/// Two rows are considered the same entry when they agree on every field a
/// person would consider "the same transaction".
String duplicateKey({
  required DateTime date,
  required String time,
  required int amountMinor,
  required TxType type,
  String category = '',
  String incomeSource = '',
  String paymentMethod = '',
  String note = '',
}) {
  return <String>[
    date.toIso8601String().substring(0, 10),
    time,
    amountMinor.toString(),
    type.dbValue,
    category.trim().toLowerCase(),
    incomeSource.trim().toLowerCase(),
    paymentMethod.trim().toLowerCase(),
    note.trim().toLowerCase(),
  ].join('|');
}

/// Duplicate key for a stored transaction, using its resolved display names.
String txItemDuplicateKey(TxItem item) => duplicateKey(
      date: item.date,
      time: item.time,
      amountMinor: item.amountMinor,
      type: item.type,
      category: item.categoryName ?? '',
      incomeSource: item.incomeSourceName ?? '',
      paymentMethod: item.paymentMethodName ?? '',
      note: item.note,
    );

/// Duplicate key for an input being imported, given the names its ids resolve
/// to.
String inputDuplicateKey(
  TransactionInput input, {
  String category = '',
  String incomeSource = '',
  String paymentMethod = '',
}) =>
    duplicateKey(
      date: input.date,
      time: input.time,
      amountMinor: input.amountMinor,
      type: input.type,
      category: category,
      incomeSource: incomeSource,
      paymentMethod: paymentMethod,
      note: input.note,
    );

/// Duplicate key built from the foreign-key ids actually stored in the row.
///
/// Used by backup merge and import, where names have already been resolved to
/// ids, so the comparison never depends on a later rename.
String duplicateKeyByIds({
  required DateTime date,
  required String time,
  required int amountMinor,
  required TxType type,
  required int? categoryId,
  required int? incomeSourceId,
  required int? paymentMethodId,
  required String note,
}) =>
    <String>[
      date.toIso8601String().substring(0, 10),
      time,
      amountMinor.toString(),
      type.dbValue,
      categoryId?.toString() ?? '',
      incomeSourceId?.toString() ?? '',
      paymentMethodId?.toString() ?? '',
      note.trim().toLowerCase(),
    ].join('|');

/// Outcome of a backup / import merge.
class MergeReport {
  const MergeReport({
    this.inserted = 0,
    this.skippedDuplicates = 0,
    this.invalid = 0,
    this.updated = 0,
    this.errors = const [],
  });

  final int inserted;
  final int skippedDuplicates;
  final int invalid;
  final int updated;
  final List<String> errors;

  int get total => inserted + skippedDuplicates + invalid + updated;

  bool get hasIssues => invalid > 0 || errors.isNotEmpty;

  MergeReport merge(MergeReport other) => MergeReport(
        inserted: inserted + other.inserted,
        skippedDuplicates: skippedDuplicates + other.skippedDuplicates,
        invalid: invalid + other.invalid,
        updated: updated + other.updated,
        errors: [...errors, ...other.errors],
      );
}

/// Catalog rows sorted the way every picker expects: active first, then
/// defaults, then alphabetical.
int compareCatalog(CatalogItem a, CatalogItem b) {
  if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
  if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

/// Events sorted newest-first, archived last.
int compareEvents(SpecialEvent a, SpecialEvent b) {
  if (a.isArchived != b.isArchived) return a.isArchived ? 1 : -1;
  return b.startDate.compareTo(a.startDate);
}
