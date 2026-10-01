import 'package:drift/drift.dart';

import '../../core/errors/app_exception.dart';
import '../../database/database.dart' hide SpecialEvent;
import '../../shared/models/special_event.dart';
import '../../shared/models/tx_type.dart';
import '../../shared/models/validation.dart';
import '../event_repository.dart';

/// SQLite implementation of [EventRepository].
class DriftEventRepository implements EventRepository {
  DriftEventRepository(this._db);

  final AppDatabase _db;

  // ------------------------------------------------------------ aggregates
  //
  // An event is a *tag* on transactions, so its totals are always derived
  // from the `transactions` table and never stored twice. These three
  // expressions are projected onto a LEFT JOIN, so an event with no linked
  // transactions still yields exactly one row reporting zeros.
  //
  // Two deliberate choices:
  //   * `COUNT(transactions.id)` rather than `COUNT(*)`: a left join produces
  //     one row with NULLs for an empty event, which `COUNT(*)` would call 1.
  //   * `CASE` rather than `SUM(...) FILTER (WHERE ...)`: SQLite only gained
  //     FILTER in 3.30 (Android 13); CASE works everywhere.

  late final Expression<int> _eventCount = _db.transactions.id.count();

  late final Expression<int> _eventExpense = _caseOfType(TxType.expense).sum();

  late final Expression<int> _eventIncome = _caseOfType(TxType.income).sum();

  /// `CASE WHEN type = <type> THEN amount ELSE 0 END`
  Expression<int> _caseOfType(TxType type) => CaseWhenExpression<int>(
        cases: [
          CaseWhen(
            _db.transactions.type.equals(type.dbValue),
            then: _db.transactions.amount,
          ),
        ],
        orElse: const Constant(0),
      );

  /// Builds the event query with [expressions] columns attached.
  JoinedSelectStatement<dynamic, dynamic> _query({
    bool includeArchived = false,
    int? id,
  }) {
    final query = _db.select(_db.specialEvents).join([
      leftOuterJoin(
        _db.transactions,
        _db.transactions.specialEventId.equalsExp(_db.specialEvents.id),
        useColumns: false,
      ),
    ]);

    final predicates = <Expression<bool>>[
      if (id != null) _db.specialEvents.id.equals(id),
      if (!includeArchived) _db.specialEvents.isArchived.equals(false),
    ];
    if (predicates.isNotEmpty) {
      query.where(predicates.reduce((a, b) => a & b));
    }

    query.addColumns([_eventCount, _eventExpense, _eventIncome]);
    // Group on every event column so the base fields stay legal projections
    // beside the aggregates on any SQLite version.
    query.groupBy([
      _db.specialEvents.id,
      _db.specialEvents.name,
      _db.specialEvents.description,
      _db.specialEvents.startDate,
      _db.specialEvents.endDate,
      _db.specialEvents.isArchived,
      _db.specialEvents.createdAt,
      _db.specialEvents.updatedAt,
    ]);
    return query;
  }

  @override
  Stream<List<SpecialEvent>> watchAll({bool includeArchived = false}) =>
      _query(includeArchived: includeArchived).watch().map(_mapAll);

  @override
  Future<List<SpecialEvent>> getAll({bool includeArchived = false}) async =>
      _mapAll(await _query(includeArchived: includeArchived).get());

  @override
  Future<SpecialEvent?> byId(int id) async {
    // Archived events must still be readable so the form can edit them.
    final rows = await _query(includeArchived: true, id: id).get();
    return rows.isEmpty ? null : _map(rows.first);
  }

  @override
  Future<int> create(SpecialEventDraft draft) async {
    _validate(draft);
    return _db.into(_db.specialEvents).insert(
          SpecialEventsCompanion.insert(
            name: draft.name.trim(),
            startDate: draft.startDate,
            endDate: Value(draft.endDate),
            description: Value(draft.description.trim()),
          ),
        );
  }

  @override
  Future<void> update(int id, SpecialEventDraft draft) async {
    _validate(draft);
    final changed = await (_db.update(_db.specialEvents)..where((e) => e.id.equals(id))).write(
      SpecialEventsCompanion(
        name: Value(draft.name.trim()),
        startDate: Value(draft.startDate),
        endDate: Value(draft.endDate),
        description: Value(draft.description.trim()),
        updatedAt: Value(DateTime.now()),
      ),
    );
    if (changed == 0) {
      throw const ValidationException('This event no longer exists.');
    }
  }

  @override
  Future<void> setArchived(int id, bool archived) async {
    await (_db.update(_db.specialEvents)..where((e) => e.id.equals(id))).write(
      SpecialEventsCompanion(isArchived: Value(archived), updatedAt: Value(DateTime.now())),
    );
  }

  @override
  Future<void> delete(int id) async {
    final used = await (_db.select(_db.specialEvents)
          ..where((e) => e.id.equals(id)))
        .getSingleOrNull();
    if (used == null) return;

    final referencing = await (_db.select(_db.transactions)
          ..where((t) => t.specialEventId.equals(id)))
        .get();
    if (referencing.isNotEmpty) {
      throw ValidationException(
        'This event is used by ${referencing.length} transaction(s), so it cannot be '
        'deleted. Archive it instead - history is always kept.',
      );
    }
    await (_db.delete(_db.specialEvents)..where((e) => e.id.equals(id))).go();
  }

  @override
  Future<int> findOrCreate(String name, {DateTime? startDate, DateTime? endDate}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException('Enter an event name.');
    }
    final lower = trimmed.toLowerCase();
    final existing =
        await (_db.select(_db.specialEvents)..where((e) => e.name.lower().equals(lower)))
            .getSingleOrNull();
    if (existing != null) return existing.id;

    return _db.into(_db.specialEvents).insert(
          SpecialEventsCompanion.insert(
            name: trimmed,
            startDate: startDate ?? DateTime.now(),
            endDate: Value(endDate),
          ),
        );
  }

  @override
  Future<void> clear() async {
    await _db.delete(_db.specialEvents).go();
  }

  void _validate(SpecialEventDraft draft) {
    if (draft.name.trim().isEmpty) {
      throw const ValidationException('Enter an event name.', field: 'name');
    }
    final end = draft.endDate;
    if (end != null && end.isBefore(draft.startDate)) {
      throw const ValidationException(
        'The end date cannot be before the start date.',
        field: 'endDate',
      );
    }
  }

  List<SpecialEvent> _mapAll(List<TypedResult> rows) {
    final mapped = rows.map(_map).toList();
    mapped.sort(compareEvents);
    return mapped;
  }

  /// Reads the event row plus its three aggregate columns off a joined result.
  ///
  /// The aggregates are `late final` fields, so the instances read here are
  /// the same ones passed to `addColumns`.
  SpecialEvent _map(TypedResult row) {
    final event = row.readTable(_db.specialEvents);
    return SpecialEvent(
      id: event.id,
      name: event.name,
      description: event.description,
      startDate: event.startDate,
      endDate: event.endDate,
      isArchived: event.isArchived,
      createdAt: event.createdAt,
      updatedAt: event.updatedAt,
      transactionCount: row.read(_eventCount) ?? 0,
      expenseMinor: row.read(_eventExpense) ?? 0,
      incomeMinor: row.read(_eventIncome) ?? 0,
    );
  }
}
