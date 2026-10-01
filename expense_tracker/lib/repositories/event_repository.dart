import '../../shared/models/special_event.dart';

/// Special expense / event groupings such as `Mumbai Trip` or `Birthday`.
abstract class EventRepository {
  Stream<List<SpecialEvent>> watchAll({bool includeArchived = false});

  Future<List<SpecialEvent>> getAll({bool includeArchived = false});

  Future<SpecialEvent?> byId(int id);

  Future<int> create(SpecialEventDraft draft);

  Future<void> update(int id, SpecialEventDraft draft);

  Future<void> setArchived(int id, bool archived);

  /// Only allowed when no transaction references the event.
  Future<void> delete(int id);

  /// Used by importers: returns an existing event with the same name, or
  /// creates one.
  Future<int> findOrCreate(String name, {DateTime? startDate, DateTime? endDate});

  /// Removes every event. Only used by "replace all data" restore after
  /// transactions have been cleared.
  Future<void> clear();
}
