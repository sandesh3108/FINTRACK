import 'package:expense_tracker/core/utils/money.dart';
import 'package:expense_tracker/shared/models/range_spec.dart';
import 'package:expense_tracker/shared/models/tx_type.dart';

/// Sort options for the transaction list.
enum TxSort {
  dateDesc,
  dateAsc,
  amountDesc,
  amountAsc;

  String get label => switch (this) {
        TxSort.dateDesc => 'Newest first',
        TxSort.dateAsc => 'Oldest first',
        TxSort.amountDesc => 'Highest amount',
        TxSort.amountAsc => 'Lowest amount',
      };
}

/// A combinable query for the transaction history screen.
///
/// Every field is optional; an empty filter returns everything.
class TransactionFilter {
  const TransactionFilter({
    this.search = '',
    this.type,
    this.range,
    this.categoryId,
    this.incomeSourceId,
    this.paymentMethodId,
    this.specialEventId,
    this.minAmountMinor,
    this.maxAmountMinor,
    this.sort = TxSort.dateDesc,
    this.page = 0,
    this.pageSize = 30,
  });

  /// Free-text search across note, amount, category, income source,
  /// payment method and event names.
  final String search;

  final TxType? type;

  /// `null` means "all dates".
  final RangeSpec? range;

  final int? categoryId;
  final int? incomeSourceId;
  final int? paymentMethodId;
  final int? specialEventId;

  final int? minAmountMinor;
  final int? maxAmountMinor;

  final TxSort sort;

  /// Zero-based page index used for pagination.
  final int page;

  final int pageSize;

  bool get hasSearch => search.trim().isNotEmpty;

  bool get isEmpty =>
      !hasSearch &&
      type == null &&
      range == null &&
      categoryId == null &&
      incomeSourceId == null &&
      paymentMethodId == null &&
      specialEventId == null &&
      minAmountMinor == null &&
      maxAmountMinor == null;

  /// Number of individual constraints currently applied (shown as a badge).
  int get activeCount {
    var n = 0;
    if (hasSearch) n++;
    if (type != null) n++;
    if (range != null) n++;
    if (categoryId != null) n++;
    if (incomeSourceId != null) n++;
    if (paymentMethodId != null) n++;
    if (specialEventId != null) n++;
    if (minAmountMinor != null || maxAmountMinor != null) n++;
    return n;
  }

  TransactionFilter copyWith({
    String? search,
    TxType? type,
    RangeSpec? range,
    int? categoryId,
    int? incomeSourceId,
    int? paymentMethodId,
    int? specialEventId,
    int? minAmountMinor,
    int? maxAmountMinor,
    TxSort? sort,
    int? page,
    int? pageSize,
    bool clearType = false,
    bool clearRange = false,
    bool clearCategory = false,
    bool clearIncomeSource = false,
    bool clearPaymentMethod = false,
    bool clearEvent = false,
    bool clearAmountRange = false,
    bool resetPage = true,
  }) {
    return TransactionFilter(
      search: search ?? this.search,
      type: clearType ? null : (type ?? this.type),
      range: clearRange ? null : (range ?? this.range),
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      incomeSourceId: clearIncomeSource ? null : (incomeSourceId ?? this.incomeSourceId),
      paymentMethodId: clearPaymentMethod ? null : (paymentMethodId ?? this.paymentMethodId),
      specialEventId: clearEvent ? null : (specialEventId ?? this.specialEventId),
      minAmountMinor: clearAmountRange ? null : (minAmountMinor ?? this.minAmountMinor),
      maxAmountMinor: clearAmountRange ? null : (maxAmountMinor ?? this.maxAmountMinor),
      sort: sort ?? this.sort,
      page: resetPage ? 0 : (page ?? this.page),
      pageSize: pageSize ?? this.pageSize,
    );
  }

  TransactionFilter clearAll() => const TransactionFilter();

  /// Short human description of the active filters, used for the empty state.
  String describe() {
    final parts = <String>[];
    if (type != null) parts.add(type!.label);
    if (range != null) parts.add(range!.label);
    if (categoryId != null) parts.add('a category');
    if (incomeSourceId != null) parts.add('an income source');
    if (paymentMethodId != null) parts.add('a payment method');
    if (specialEventId != null) parts.add('an event');
    if (minAmountMinor != null || maxAmountMinor != null) {
      final low = minAmountMinor == null ? '' : formatMinor(minAmountMinor!);
      final high = maxAmountMinor == null ? '' : formatMinor(maxAmountMinor!);
      parts.add('$low-$high');
    }
    if (hasSearch) parts.add('"${search.trim()}"');
    return parts.join(', ');
  }

  /// Value equality so the filter can be used as a Riverpod family key:
  /// an unchanged filter must not re-subscribe the query stream.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TransactionFilter &&
          other.search == search &&
          other.type == type &&
          other.range == range &&
          other.categoryId == categoryId &&
          other.incomeSourceId == incomeSourceId &&
          other.paymentMethodId == paymentMethodId &&
          other.specialEventId == specialEventId &&
          other.minAmountMinor == minAmountMinor &&
          other.maxAmountMinor == maxAmountMinor &&
          other.sort == sort &&
          other.page == page &&
          other.pageSize == pageSize);

  @override
  int get hashCode => Object.hash(
        search,
        type,
        range,
        categoryId,
        incomeSourceId,
        paymentMethodId,
        specialEventId,
        minAmountMinor,
        maxAmountMinor,
        sort,
        page,
        pageSize,
      );
}
