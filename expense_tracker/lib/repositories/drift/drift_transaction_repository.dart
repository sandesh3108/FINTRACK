import 'package:drift/drift.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../database/database.dart';
import '../../shared/models/account_balance.dart';
import '../../shared/models/catalog_item.dart';
import '../../shared/models/group_total.dart';
import '../../shared/models/period_summary.dart';
import '../../shared/models/range_spec.dart';
import '../../shared/models/transaction_filter.dart';
import '../../shared/models/transaction_input.dart';
import '../../shared/models/tx_item.dart';
import '../../shared/models/tx_type.dart';
import '../../shared/models/validation.dart';
import '../transaction_repository.dart';

/// SQLite implementation of [TransactionRepository].
///
/// Every number the app shows comes from one of the aggregate queries below:
/// they run in SQL against indexed columns, so the dashboard stays fast with
/// thousands of rows and the UI never loads the whole ledger into memory.
class DriftTransactionRepository implements TransactionRepository {
  DriftTransactionRepository(this._db);

  final AppDatabase _db;

  // ---------------------------------------------------------------- reads

  @override
  Stream<List<TxItem>> watchTransactions(TransactionFilter filter) async* {
    final statement = await _filtered(filter);
    yield* statement.watch().asyncMap(_hydrate);
  }

  @override
  Future<List<TxItem>> getTransactions(TransactionFilter filter) async =>
      _hydrate(await (await _filtered(filter)).get());

  @override
  Future<int> countTransactions(TransactionFilter filter) async {
    final countExpr = countAll();
    final query = _db.selectOnly(_db.transactions)
      ..addColumns([countExpr])
      ..where(await _predicate(filter));
    final row = await query.getSingle();
    return row.read(countExpr) ?? 0;
  }

  @override
  Future<TxItem?> getById(int id) async {
    final row =
        await (_db.select(_db.transactions)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    final items = await _hydrate([row]);
    return items.isEmpty ? null : items.first;
  }

  Future<SimpleSelectStatement<$TransactionsTable, TxRow>> _filtered(
    TransactionFilter filter,
  ) async {
    final predicate = await _predicate(filter);
    final statement = _db.select(_db.transactions)
      ..where((_) => predicate)
      ..orderBy(_orderTerms(filter.sort))
      ..limit(filter.pageSize, offset: filter.page * filter.pageSize);
    return statement;
  }

  // --------------------------------------------------------------- writes

  @override
  Future<int> add(TransactionInput input) async {
    await _ensureValid(input);
    final now = DateTime.now();
    return _db.into(_db.transactions).insert(_companion(input, now, now));
  }

  @override
  Future<void> edit(int id, TransactionInput input) async {
    await _ensureValid(input);
    final changed = await (_db.update(_db.transactions)..where((t) => t.id.equals(id)))
        .write(_companion(input, null, DateTime.now()));
    if (changed == 0) {
      throw const ValidationException('This transaction no longer exists.');
    }
  }

  @override
  Future<void> remove(int id) async {
    await (_db.delete(_db.transactions)..where((t) => t.id.equals(id))).go();
  }

  @override
  Future<void> removeAll(List<int> ids) async {
    if (ids.isEmpty) return;
    await (_db.delete(_db.transactions)..where((t) => t.id.isIn(ids))).go();
  }

  @override
  Future<MergeReport> importTransactions(
    List<TransactionInput> inputs, {
    bool skipDuplicates = true,
  }) async {
    final existingKeys = skipDuplicates ? await _existingKeys() : <String>{};

    var inserted = 0;
    var skipped = 0;
    var invalid = 0;
    final errors = <String>[];
    final pending = <TransactionsCompanion>[];
    final batchKeys = <String>{};

    for (final input in inputs) {
      final problem = await _importCheck(input);
      if (problem != null) {
        invalid++;
        if (errors.length < 25) errors.add(problem);
        continue;
      }

      final key = _keyFor(input);
      if (existingKeys.contains(key) || batchKeys.contains(key)) {
        skipped++;
        continue;
      }
      batchKeys.add(key);
      final now = DateTime.now();
      pending.add(_companion(input, now, now));
      inserted++;
    }

    if (pending.isNotEmpty) {
      try {
        // One database transaction: if anything fails, the whole batch rolls
        // back and no partial import is left behind.
        await _db.transaction(() async {
          await _db.batch((batch) => batch.insertAll(_db.transactions, pending));
        });
      } on Exception catch (error) {
        throw DatabaseException(
          'Import failed, so no changes were saved.',
          technical: error.toString(),
        );
      }
    }

    return MergeReport(
      inserted: inserted,
      skippedDuplicates: skipped,
      invalid: invalid,
      errors: errors,
    );
  }

  // ------------------------------------------------------------ aggregates

  @override
  Future<PeriodSummary> summary(
    RangeSpec range, {
    int? specialEventId,
    bool includeEventRows = false,
  }) async {
    var incomeMinor = 0;
    var expenseMinor = 0;
    var incomeCount = 0;
    var expenseCount = 0;

    final sumExpr = _db.transactions.amount.sum();
    final countExpr = countAll();
    final typeExpr = _db.transactions.type;
    final grouped = _db.selectOnly(_db.transactions)
      ..addColumns([typeExpr, sumExpr, countExpr])
      ..where(_rangePredicate(
        range,
        specialEventId: specialEventId,
        includeEventRows: includeEventRows,
      ))
      ..groupBy([typeExpr]);

    for (final row in await grouped.get()) {
      final isIncome = row.read(typeExpr) == TxType.income.dbValue;
      final sum = row.read(sumExpr) ?? 0;
      final count = row.read(countExpr) ?? 0;
      if (isIncome) {
        incomeMinor = sum;
        incomeCount = count;
      } else {
        expenseMinor = sum;
        expenseCount = count;
      }
    }

    var maxExpenseMinor = 0;
    if (expenseCount > 0) {
      final maxExpr = _db.transactions.amount.max();
      final maxQuery = _db.selectOnly(_db.transactions)
        ..addColumns([maxExpr])
        ..where(_rangePredicate(
          range,
          type: TxType.expense,
          specialEventId: specialEventId,
          includeEventRows: includeEventRows,
        ));
      maxExpenseMinor = (await maxQuery.getSingle()).read(maxExpr) ?? 0;
    }

    int? topCategoryId;
    String? topCategoryName;
    if (expenseCount > 0) {
      final top = await totalsByCategory(
        range,
        type: TxType.expense,
        specialEventId: specialEventId,
        includeEventRows: includeEventRows,
      );
      if (top.isNotEmpty) {
        topCategoryId = top.first.id;
        topCategoryName = top.first.name;
      }
    }

    return PeriodSummary(
      start: range.start,
      end: range.end,
      incomeMinor: incomeMinor,
      expenseMinor: expenseMinor,
      incomeCount: incomeCount,
      expenseCount: expenseCount,
      maxExpenseMinor: maxExpenseMinor,
      topExpenseCategoryId: topCategoryId,
      topExpenseCategoryName: topCategoryName,
    );
  }

  @override
  Future<Map<int, PeriodSummary>> summariesByEvent(RangeSpec range) async {
    final eventId = _db.transactions.specialEventId;
    final query = _db.selectOnly(_db.transactions)
      ..addColumns([eventId])
      ..where(_rangePredicate(range, includeEventRows: true))
      ..groupBy([eventId]);

    final ids = <int>[];
    for (final row in await query.get()) {
      final id = row.read(eventId);
      if (id != null) ids.add(id);
    }
    if (ids.isEmpty) return const <int, PeriodSummary>{};

    // Reuse [summary] per event rather than duplicating its max/category
    // passes here: there are only a handful of events in any one range, and
    // this keeps a single definition of what an event total means.
    final result = <int, PeriodSummary>{};
    for (final id in ids) {
      result[id] = await summary(range, specialEventId: id);
    }
    return result;
  }

  @override
  Future<List<GroupTotal>> totalsByCategory(
    RangeSpec range, {
    TxType? type,
    int? specialEventId,
    bool includeEventRows = false,
  }) =>
      _groupTotals(
        range: range,
        groupColumn: _db.transactions.categoryId,
        lookup: _categoryCatalog,
        type: type,
        specialEventId: specialEventId,
        includeEventRows: includeEventRows,
        fallbackName: 'Uncategorized',
      );

  @override
  Future<List<GroupTotal>> totalsByPaymentMethod(
    RangeSpec range, {
    TxType? type,
    int? specialEventId,
    bool includeEventRows = false,
  }) =>
      _groupTotals(
        range: range,
        groupColumn: _db.transactions.paymentMethodId,
        lookup: _paymentMethodCatalog,
        type: type,
        specialEventId: specialEventId,
        includeEventRows: includeEventRows,
        fallbackName: 'Unknown',
      );

  @override
  Future<List<GroupTotal>> totalsByIncomeSource(
    RangeSpec range, {
    int? specialEventId,
    bool includeEventRows = false,
  }) =>
      _groupTotals(
        range: range,
        groupColumn: _db.transactions.incomeSourceId,
        lookup: _incomeSourceCatalog,
        type: TxType.income,
        specialEventId: specialEventId,
        includeEventRows: includeEventRows,
        fallbackName: 'Other',
      );

  @override
  Future<List<DayTotal>> dailyTotals(
    RangeSpec range, {
    int? specialEventId,
    bool includeEventRows = false,
  }) async {
    final sumExpr = _db.transactions.amount.sum();
    final countExpr = countAll();
    final dateExpr = _db.transactions.date;
    final typeExpr = _db.transactions.type;

    final query = _db.selectOnly(_db.transactions)
      ..addColumns([dateExpr, typeExpr, sumExpr, countExpr])
      ..where(_rangePredicate(
        range,
        specialEventId: specialEventId,
        includeEventRows: includeEventRows,
      ))
      ..groupBy([dateExpr, typeExpr]);

    final accumulator = <DateTime, _DayAccumulator>{};
    for (final row in await query.get()) {
      final day = row.read(dateExpr);
      if (day == null) continue;
      final acc = accumulator.putIfAbsent(day, _DayAccumulator.new);
      final total = row.read(sumExpr) ?? 0;
      final count = row.read(countExpr) ?? 0;
      acc.count += count;
      if (row.read(typeExpr) == TxType.income.dbValue) {
        acc.incomeMinor += total;
        acc.incomeCount += count;
      } else {
        acc.expenseMinor += total;
        acc.expenseCount += count;
      }
    }

    final days = accumulator.keys.toList()..sort();
    return [
      for (final day in days)
        DayTotal(
          day: day,
          expenseMinor: accumulator[day]!.expenseMinor,
          incomeMinor: accumulator[day]!.incomeMinor,
          count: accumulator[day]!.count,
        ),
    ];
  }

  @override
  Future<List<MonthTotal>> monthlyTotals(int year) async {
    final daily = await dailyTotals(RangeSpec.year(year));
    // List.filled would share a single accumulator across all twelve slots, so
    // every month would report the same numbers. Generate one per bucket.
    final buckets = List<_DayAccumulator>.generate(
      12,
      (_) => _DayAccumulator(),
      growable: false,
    );

    for (final day in daily) {
      final bucket = buckets[day.day.month - 1];
      bucket.incomeMinor += day.incomeMinor;
      bucket.expenseMinor += day.expenseMinor;
      bucket.count += day.count;
    }

    return [
      for (var month = 1; month <= 12; month++)
        MonthTotal(
          year: year,
          month: month,
          incomeMinor: buckets[month - 1].incomeMinor,
          expenseMinor: buckets[month - 1].expenseMinor,
          count: buckets[month - 1].count,
        ),
    ];
  }

  @override
  Future<List<AccountBalance>> accountBalances({bool activeOnly = false}) async {
    final methodQuery = _db.select(_db.paymentMethods);
    if (activeOnly) methodQuery.where((m) => m.isActive.equals(true));
    final methods = await methodQuery.get();
    if (methods.isEmpty) return const <AccountBalance>[];

    // One grouped scan over the whole ledger gives both directions per
    // account; the opening balance comes from the account row itself.
    final sumExpr = _db.transactions.amount.sum();
    final typeExpr = _db.transactions.type;
    final methodExpr = _db.transactions.paymentMethodId;
    final query = _db.selectOnly(_db.transactions)
      ..addColumns([methodExpr, typeExpr, sumExpr])
      ..groupBy([methodExpr, typeExpr]);

    final income = <int, int>{};
    final expense = <int, int>{};
    for (final row in await query.get()) {
      final id = row.read(methodExpr);
      if (id == null) continue; // unassigned rows belong to no account
      final total = row.read(sumExpr) ?? 0;
      if (row.read(typeExpr) == TxType.income.dbValue) {
        income[id] = total;
      } else {
        expense[id] = total;
      }
    }

    return [
      for (final method in methods)
        AccountBalance(
          paymentMethodId: method.id,
          name: method.name,
          openingMinor: method.openingBalance,
          incomeMinor: income[method.id] ?? 0,
          expenseMinor: expense[method.id] ?? 0,
          isActive: method.isActive,
        ),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  // ------------------------------------------------------- usage counters

  @override
  Future<Map<int, int>> usageCountsByCategory() =>
      _usageCounts(_db.transactions.categoryId);

  @override
  Future<Map<int, int>> usageCountsByIncomeSource() =>
      _usageCounts(_db.transactions.incomeSourceId);

  @override
  Future<Map<int, int>> usageCountsByPaymentMethod() =>
      _usageCounts(_db.transactions.paymentMethodId);

  @override
  Future<Map<int, int>> usageCountsByEvent() =>
      _usageCounts(_db.transactions.specialEventId);

  Future<Map<int, int>> _usageCounts(Expression<int> column) async {
    final countExpr = countAll();
    final query = _db.selectOnly(_db.transactions)
      ..addColumns([column, countExpr])
      ..where(column.isNotNull())
      ..groupBy([column]);

    final result = <int, int>{};
    for (final row in await query.get()) {
      final id = row.read(column);
      if (id == null) continue;
      result[id] = row.read(countExpr) ?? 0;
    }
    return result;
  }

  // ------------------------------------------------------------ internals

  /// Range + type + event predicate used by every aggregation.
  ///
  /// See the scope rule on [TransactionRepository.summary]: an explicit
  /// [specialEventId] wins; otherwise [includeEventRows] decides between
  /// regular rows only (the default) and every row in the range.
  Expression<bool> _rangePredicate(
    RangeSpec range, {
    TxType? type,
    int? specialEventId,
    bool includeEventRows = false,
  }) {
    var expression = _db.transactions.date.isBiggerOrEqualValue(range.start) &
        _db.transactions.date.isSmallerThanValue(range.end);
    if (type != null) {
      expression = expression & _db.transactions.type.equals(type.dbValue);
    }
    if (specialEventId != null) {
      expression = expression & _db.transactions.specialEventId.equals(specialEventId);
    } else if (!includeEventRows) {
      expression = expression & _db.transactions.specialEventId.isNull();
    }
    return expression;
  }

  /// Full filter predicate for the history screen.
  ///
  /// The ledger always shows every row, so this deliberately opts back into
  /// [includeEventRows]: a null filter event means "all", not "regular only".
  Future<Expression<bool>> _predicate(TransactionFilter filter) async {
    Expression<bool> expression = const Constant(true);

    if (filter.range != null) {
      expression = expression &
          _rangePredicate(
            filter.range!,
            type: filter.type,
            specialEventId: filter.specialEventId,
            includeEventRows: true,
          );
    } else {
      if (filter.type != null) {
        expression = expression & _db.transactions.type.equals(filter.type!.dbValue);
      }
      if (filter.specialEventId != null) {
        expression =
            expression & _db.transactions.specialEventId.equals(filter.specialEventId!);
      }
    }

    if (filter.categoryId != null) {
      expression = expression & _db.transactions.categoryId.equals(filter.categoryId!);
    }
    if (filter.incomeSourceId != null) {
      expression =
          expression & _db.transactions.incomeSourceId.equals(filter.incomeSourceId!);
    }
    if (filter.paymentMethodId != null) {
      expression =
          expression & _db.transactions.paymentMethodId.equals(filter.paymentMethodId!);
    }
    if (filter.minAmountMinor != null) {
      expression =
          expression & _db.transactions.amount.isBiggerOrEqualValue(filter.minAmountMinor!);
    }
    if (filter.maxAmountMinor != null) {
      expression =
          expression & _db.transactions.amount.isSmallerOrEqualValue(filter.maxAmountMinor!);
    }
    if (filter.hasSearch) {
      expression = expression & await _searchPredicate(filter.search);
    }

    return expression;
  }

  /// Matches note text, amount, type, and the *names* of category, income
  /// source, payment method and event. The name tables are small, so resolving
  /// their ids first keeps the transaction query on a single indexed scan.
  Future<Expression<bool>> _searchPredicate(String raw) async {
    final query = raw.trim().toLowerCase();
    if (query.isEmpty) return const Constant(true);

    // Strip LIKE wildcards so a user typing "50%" cannot widen the search.
    final sanitized = query.replaceAll(RegExp(r'[%_\\]'), '');
    final pattern = '%$sanitized%';

    Expression<bool>? expression;
    void match(Expression<bool> condition) {
      expression = expression == null ? condition : (expression! | condition);
    }

    match(_db.transactions.note.lower().like(pattern));

    final amount = parseImportedMoney(query);
    if (amount != null && amount > 0) {
      match(_db.transactions.amount.equals(amount));
    }

    final type = TxType.tryParse(query);
    if (type != null) {
      match(_db.transactions.type.equals(type.dbValue));
    }

    final categories = await _categoryIdsLike(pattern);
    final sources = await _incomeSourceIdsLike(pattern);
    final methods = await _paymentMethodIdsLike(pattern);
    final events = await _eventIdsLike(pattern);

    for (final id in categories) {
      match(_db.transactions.categoryId.equals(id));
    }
    for (final id in sources) {
      match(_db.transactions.incomeSourceId.equals(id));
    }
    for (final id in methods) {
      match(_db.transactions.paymentMethodId.equals(id));
    }
    for (final id in events) {
      match(_db.transactions.specialEventId.equals(id));
    }

    return expression ?? const Constant(true);
  }

  Future<List<int>> _categoryIdsLike(String pattern) async {
    final rows = await (_db.select(_db.categories)
          ..where((c) => c.name.lower().like(pattern)))
        .get();
    return [for (final row in rows) row.id];
  }

  Future<List<int>> _incomeSourceIdsLike(String pattern) async {
    final rows = await (_db.select(_db.incomeSources)
          ..where((s) => s.name.lower().like(pattern)))
        .get();
    return [for (final row in rows) row.id];
  }

  Future<List<int>> _paymentMethodIdsLike(String pattern) async {
    final rows = await (_db.select(_db.paymentMethods)
          ..where((m) => m.name.lower().like(pattern)))
        .get();
    return [for (final row in rows) row.id];
  }

  Future<List<int>> _eventIdsLike(String pattern) async {
    final rows = await (_db.select(_db.specialEvents)
          ..where((e) => e.name.lower().like(pattern)))
        .get();
    return [for (final row in rows) row.id];
  }

  /// Ordering clauses for `select()` statements, which expect a closure per
  /// term rather than a ready-made [OrderingTerm].
  List<OrderClauseGenerator<$TransactionsTable>> _orderTerms(TxSort sort) {
    return switch (sort) {
      TxSort.dateDesc => [
          (t) => OrderingTerm.desc(t.date),
          (t) => OrderingTerm.desc(t.time),
          (t) => OrderingTerm.desc(t.id),
        ],
      TxSort.dateAsc => [
          (t) => OrderingTerm.asc(t.date),
          (t) => OrderingTerm.asc(t.time),
          (t) => OrderingTerm.asc(t.id),
        ],
      TxSort.amountDesc => [
          (t) => OrderingTerm.desc(t.amount),
          (t) => OrderingTerm.desc(t.date),
          (t) => OrderingTerm.desc(t.time),
        ],
      TxSort.amountAsc => [
          (t) => OrderingTerm.asc(t.amount),
          (t) => OrderingTerm.desc(t.date),
          (t) => OrderingTerm.desc(t.time),
        ],
    };
  }

  Future<List<TxItem>> _hydrate(List<TxRow> rows) async {
    if (rows.isEmpty) return const [];

    final categoryRows = await _db.select(_db.categories).get();
    final sourceRows = await _db.select(_db.incomeSources).get();
    final methodRows = await _db.select(_db.paymentMethods).get();
    final eventRows = await _db.select(_db.specialEvents).get();

    final categoriesById = {for (final row in categoryRows) row.id: row};
    final sourcesById = {for (final row in sourceRows) row.id: row};
    final methodsById = {for (final row in methodRows) row.id: row};
    final eventsById = {for (final row in eventRows) row.id: row};

    return [
      for (final row in rows)
        TxItem(
          id: row.id,
          type: TxType.fromDb(row.type),
          amountMinor: row.amount,
          date: row.date,
          time: row.time,
          note: row.note,
          createdAt: row.createdAt,
          updatedAt: row.updatedAt,
          categoryId: row.categoryId,
          incomeSourceId: row.incomeSourceId,
          paymentMethodId: row.paymentMethodId,
          specialEventId: row.specialEventId,
          categoryName: categoriesById[row.categoryId]?.name,
          incomeSourceName: sourcesById[row.incomeSourceId]?.name,
          paymentMethodName: methodsById[row.paymentMethodId]?.name,
          specialEventName: eventsById[row.specialEventId]?.name,
          categoryArchived: row.categoryId != null &&
              !(categoriesById[row.categoryId]?.isActive ?? true),
          incomeSourceArchived: row.incomeSourceId != null &&
              !(sourcesById[row.incomeSourceId]?.isActive ?? true),
          paymentMethodArchived: row.paymentMethodId != null &&
              !(methodsById[row.paymentMethodId]?.isActive ?? true),
          specialEventArchived: row.specialEventId != null &&
              (eventsById[row.specialEventId]?.isArchived ?? false),
        ),
    ];
  }

  Future<List<GroupTotal>> _groupTotals({
    required RangeSpec range,
    required Expression<int> groupColumn,
    required Future<Map<int, CatalogItem>> Function() lookup,
    required TxType? type,
    required int? specialEventId,
    required bool includeEventRows,
    required String fallbackName,
  }) async {
    final sumExpr = _db.transactions.amount.sum();
    final countExpr = countAll();

    final query = _db.selectOnly(_db.transactions)
      ..addColumns([groupColumn, sumExpr, countExpr])
      ..where(_rangePredicate(
        range,
        type: type,
        specialEventId: specialEventId,
        includeEventRows: includeEventRows,
      ))
      ..groupBy([groupColumn]);

    final rows = await query.get();
    if (rows.isEmpty) return const [];

    final ids = <int>{};
    for (final row in rows) {
      final id = row.read(groupColumn);
      if (id != null) ids.add(id);
    }

    final catalog = ids.isEmpty ? <int, CatalogItem>{} : await lookup();

    final totals = <GroupTotal>[];
    for (final row in rows) {
      final id = row.read(groupColumn);
      final item = id == null ? null : catalog[id];
      totals.add(
        GroupTotal(
          id: id,
          name: item?.name ?? fallbackName,
          totalMinor: row.read(sumExpr) ?? 0,
          count: row.read(countExpr) ?? 0,
          isActive: item?.isActive ?? false,
        ),
      );
    }

    totals.sort((a, b) => b.totalMinor.compareTo(a.totalMinor));
    return totals;
  }

  Future<Map<int, CatalogItem>> _categoryCatalog() async {
    final rows = await _db.select(_db.categories).get();
    return {
      for (final row in rows)
        row.id: CatalogItem(
          id: row.id,
          name: row.name,
          isDefault: row.isDefault,
          isActive: row.isActive,
          createdAt: row.createdAt,
          updatedAt: row.updatedAt,
        ),
    };
  }

  Future<Map<int, CatalogItem>> _incomeSourceCatalog() async {
    final rows = await _db.select(_db.incomeSources).get();
    return {
      for (final row in rows)
        row.id: CatalogItem(
          id: row.id,
          name: row.name,
          isDefault: row.isDefault,
          isActive: row.isActive,
          createdAt: row.createdAt,
          updatedAt: row.updatedAt,
        ),
    };
  }

  Future<Map<int, CatalogItem>> _paymentMethodCatalog() async {
    final rows = await _db.select(_db.paymentMethods).get();
    return {
      for (final row in rows)
        row.id: CatalogItem(
          id: row.id,
          name: row.name,
          isDefault: row.isDefault,
          isActive: row.isActive,
          createdAt: row.createdAt,
          updatedAt: row.updatedAt,
        ),
    };
  }

  TransactionsCompanion _companion(
    TransactionInput input,
    DateTime? createdAt,
    DateTime updatedAt,
  ) {
    return TransactionsCompanion(
      type: Value(input.type.dbValue),
      amount: Value(input.amountMinor),
      date: Value(AppDates.day(input.date)),
      time: Value(input.time),
      categoryId: Value(input.categoryId),
      incomeSourceId: Value(input.incomeSourceId),
      paymentMethodId: Value(input.paymentMethodId),
      specialEventId: Value(input.specialEventId),
      note: Value(input.note),
      createdAt: createdAt == null ? const Value.absent() : Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  Future<void> _ensureValid(TransactionInput input) async {
    final result = TransactionRules.validate(
      input,
      categoryExists: await _categoryExists(input.categoryId),
      incomeSourceExists: await _incomeSourceExists(input.incomeSourceId),
      paymentMethodExists: await _paymentMethodExists(input.paymentMethodId),
    );
    if (!result.isValid) {
      throw ValidationException(
        result.message ?? 'This transaction could not be saved.',
        field: result.field,
      );
    }
  }

  /// Same validation as [_ensureValid] but returns a human-readable reason
  /// instead of throwing, so an import can count invalid rows and keep going.
  Future<String?> _importCheck(TransactionInput input) async {
    final result = TransactionRules.validate(
      input,
      categoryExists: await _categoryExists(input.categoryId),
      incomeSourceExists: await _incomeSourceExists(input.incomeSourceId),
      paymentMethodExists: await _paymentMethodExists(input.paymentMethodId),
    );
    return result.isValid ? null : (result.message ?? 'Invalid transaction.');
  }

  Future<bool> _categoryExists(int? id) async {
    if (id == null) return false;
    final row =
        await (_db.select(_db.categories)..where((c) => c.id.equals(id))).getSingleOrNull();
    return row != null;
  }

  Future<bool> _incomeSourceExists(int? id) async {
    if (id == null) return false;
    final row = await (_db.select(_db.incomeSources)..where((s) => s.id.equals(id)))
        .getSingleOrNull();
    return row != null;
  }

  Future<bool> _paymentMethodExists(int? id) async {
    if (id == null) return false;
    final row = await (_db.select(_db.paymentMethods)..where((m) => m.id.equals(id)))
        .getSingleOrNull();
    return row != null;
  }

  String _keyFor(TransactionInput input) => duplicateKeyByIds(
        date: AppDates.day(input.date),
        time: input.time,
        amountMinor: input.amountMinor,
        type: input.type,
        categoryId: input.categoryId,
        incomeSourceId: input.incomeSourceId,
        paymentMethodId: input.paymentMethodId,
        note: input.note,
      );

  Future<Set<String>> _existingKeys() async {
    final dateExpr = _db.transactions.date;
    final timeExpr = _db.transactions.time;
    final amountExpr = _db.transactions.amount;
    final typeExpr = _db.transactions.type;
    final categoryExpr = _db.transactions.categoryId;
    final sourceExpr = _db.transactions.incomeSourceId;
    final methodExpr = _db.transactions.paymentMethodId;
    final noteExpr = _db.transactions.note;

    final query = _db.selectOnly(_db.transactions)
      ..addColumns([
        dateExpr,
        timeExpr,
        amountExpr,
        typeExpr,
        categoryExpr,
        sourceExpr,
        methodExpr,
        noteExpr,
      ]);

    final keys = <String>{};
    for (final row in await query.get()) {
      final date = row.read(dateExpr);
      final time = row.read(timeExpr);
      final amount = row.read(amountExpr);
      final type = row.read(typeExpr);
      if (date == null || time == null || amount == null || type == null) continue;
      keys.add(
        duplicateKeyByIds(
          date: date,
          time: time,
          amountMinor: amount,
          type: TxType.fromDb(type),
          categoryId: row.read(categoryExpr),
          incomeSourceId: row.read(sourceExpr),
          paymentMethodId: row.read(methodExpr),
          note: row.read(noteExpr) ?? '',
        ),
      );
    }
    return keys;
  }
}

class _DayAccumulator {
  int incomeMinor = 0;
  int expenseMinor = 0;
  int incomeCount = 0;
  int expenseCount = 0;
  int count = 0;
}
