import 'package:drift/drift.dart';

import '../../core/errors/app_exception.dart';
import '../../database/database.dart';
import '../../shared/models/catalog_item.dart';
import '../../shared/models/validation.dart';
import '../catalog_repository.dart';
import '../transaction_repository.dart';

/// SQLite implementation of [CatalogRepository].
///
/// The three tables share a shape but drift types them separately, so each
/// operation dispatches to three small, fully typed helpers rather than
/// fighting generics.
class DriftCatalogRepository implements CatalogRepository {
  DriftCatalogRepository(this._db, this._transactions);

  final AppDatabase _db;
  final TransactionRepository _transactions;

  // ------------------------------------------------------------------ read

  @override
  Stream<List<CatalogItem>> watch(CatalogKind kind, {bool activeOnly = false}) {
    switch (kind) {
      case CatalogKind.category:
        final query = _db.select(_db.categories);
        if (activeOnly) query.where((c) => c.isActive.equals(true));
        return query.watch().map((rows) => _sort(rows.map(_categoryItem)));
      case CatalogKind.incomeSource:
        final query = _db.select(_db.incomeSources);
        if (activeOnly) query.where((s) => s.isActive.equals(true));
        return query.watch().map((rows) => _sort(rows.map(_sourceItem)));
      case CatalogKind.paymentMethod:
        final query = _db.select(_db.paymentMethods);
        if (activeOnly) query.where((m) => m.isActive.equals(true));
        return query.watch().map((rows) => _sort(rows.map(_methodItem)));
    }
  }

  @override
  Future<List<CatalogItem>> getAll(CatalogKind kind, {bool activeOnly = false}) async {
    switch (kind) {
      case CatalogKind.category:
        final query = _db.select(_db.categories);
        if (activeOnly) query.where((c) => c.isActive.equals(true));
        return _sort((await query.get()).map(_categoryItem));
      case CatalogKind.incomeSource:
        final query = _db.select(_db.incomeSources);
        if (activeOnly) query.where((s) => s.isActive.equals(true));
        return _sort((await query.get()).map(_sourceItem));
      case CatalogKind.paymentMethod:
        final query = _db.select(_db.paymentMethods);
        if (activeOnly) query.where((m) => m.isActive.equals(true));
        return _sort((await query.get()).map(_methodItem));
    }
  }

  @override
  Future<CatalogItem?> byId(CatalogKind kind, int id) async {
    final items = await getAll(kind);
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  // ---------------------------------------------------------------- create

  @override
  Future<int> findOrCreate(CatalogKind kind, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ValidationException('Enter a ${kind.singular.toLowerCase()} name.');
    }

    final existing = await _findIdByName(kind, trimmed);
    if (existing != null) return existing;

    switch (kind) {
      case CatalogKind.category:
        return _db.into(_db.categories).insert(
              CategoriesCompanion.insert(name: trimmed),
            );
      case CatalogKind.incomeSource:
        return _db.into(_db.incomeSources).insert(
              IncomeSourcesCompanion.insert(name: trimmed),
            );
      case CatalogKind.paymentMethod:
        return _db.into(_db.paymentMethods).insert(
              PaymentMethodsCompanion.insert(name: trimmed),
            );
    }
  }

  @override
  Future<void> rename(CatalogKind kind, int id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ValidationException('Enter a ${kind.singular.toLowerCase()} name.');
    }

    final duplicate = await _findIdByName(kind, trimmed);
    if (duplicate != null && duplicate != id) {
      throw ValidationException(
        'A ${kind.singular.toLowerCase()} named "$trimmed" already exists.',
      );
    }

    final now = DateTime.now();
    final int changed;
    switch (kind) {
      case CatalogKind.category:
        changed = await (_db.update(_db.categories)..where((c) => c.id.equals(id))).write(
          CategoriesCompanion(name: Value(trimmed), updatedAt: Value(now)),
        );
      case CatalogKind.incomeSource:
        changed = await (_db.update(_db.incomeSources)..where((s) => s.id.equals(id))).write(
          IncomeSourcesCompanion(name: Value(trimmed), updatedAt: Value(now)),
        );
      case CatalogKind.paymentMethod:
        changed = await (_db.update(_db.paymentMethods)..where((m) => m.id.equals(id))).write(
          PaymentMethodsCompanion(name: Value(trimmed), updatedAt: Value(now)),
        );
    }

    if (changed == 0) {
      throw ValidationException('This ${kind.singular.toLowerCase()} no longer exists.');
    }
  }

  @override
  Future<void> setOpeningBalance(CatalogKind kind, int id, int minor) async {
    // Only payment methods are accounts, so anything else is deliberately a
    // no-op rather than an error.
    if (kind != CatalogKind.paymentMethod) return;

    final changed =
        await (_db.update(_db.paymentMethods)..where((m) => m.id.equals(id))).write(
      PaymentMethodsCompanion(
        openingBalance: Value(minor),
        updatedAt: Value(DateTime.now()),
      ),
    );
    if (changed == 0) {
      throw ValidationException('This payment method no longer exists.');
    }
  }

  // --------------------------------------------------------------- archive

  @override
  Future<void> setActive(CatalogKind kind, int id, bool active) async {
    final now = DateTime.now();
    switch (kind) {
      case CatalogKind.category:
        await (_db.update(_db.categories)..where((c) => c.id.equals(id))).write(
          CategoriesCompanion(isActive: Value(active), updatedAt: Value(now)),
        );
      case CatalogKind.incomeSource:
        await (_db.update(_db.incomeSources)..where((s) => s.id.equals(id))).write(
          IncomeSourcesCompanion(isActive: Value(active), updatedAt: Value(now)),
        );
      case CatalogKind.paymentMethod:
        await (_db.update(_db.paymentMethods)..where((m) => m.id.equals(id))).write(
          PaymentMethodsCompanion(isActive: Value(active), updatedAt: Value(now)),
        );
    }
  }

  @override
  Future<void> delete(CatalogKind kind, int id) async {
    final usage = await _usage(kind);
    final count = usage[id] ?? 0;
    if (count > 0) {
      throw ValidationException(
        'This ${kind.singular.toLowerCase()} is used by $count transaction(s), so it cannot '
        'be deleted. Archive it instead - history is always kept.',
      );
    }

    switch (kind) {
      case CatalogKind.category:
        await (_db.delete(_db.categories)..where((c) => c.id.equals(id))).go();
      case CatalogKind.incomeSource:
        await (_db.delete(_db.incomeSources)..where((s) => s.id.equals(id))).go();
      case CatalogKind.paymentMethod:
        await (_db.delete(_db.paymentMethods)..where((m) => m.id.equals(id))).go();
    }
  }

  @override
  Future<void> clear(CatalogKind kind) async {
    switch (kind) {
      case CatalogKind.category:
        await _db.delete(_db.categories).go();
      case CatalogKind.incomeSource:
        await _db.delete(_db.incomeSources).go();
      case CatalogKind.paymentMethod:
        await _db.delete(_db.paymentMethods).go();
    }
  }

  // -------------------------------------------------------------- internals

  Future<Map<int, int>> _usage(CatalogKind kind) => switch (kind) {
        CatalogKind.category => _transactions.usageCountsByCategory(),
        CatalogKind.incomeSource => _transactions.usageCountsByIncomeSource(),
        CatalogKind.paymentMethod => _transactions.usageCountsByPaymentMethod(),
      };

  Future<int?> _findIdByName(CatalogKind kind, String name) async {
    final lower = name.toLowerCase();
    switch (kind) {
      case CatalogKind.category:
        final rows =
            await (_db.select(_db.categories)..where((c) => c.name.lower().equals(lower))).get();
        return rows.isEmpty ? null : rows.first.id;
      case CatalogKind.incomeSource:
        final rows =
            await (_db.select(_db.incomeSources)..where((s) => s.name.lower().equals(lower))).get();
        return rows.isEmpty ? null : rows.first.id;
      case CatalogKind.paymentMethod:
        final rows =
            await (_db.select(_db.paymentMethods)..where((m) => m.name.lower().equals(lower))).get();
        return rows.isEmpty ? null : rows.first.id;
    }
  }

  static CatalogItem _categoryItem(Category row) => CatalogItem(
        id: row.id,
        name: row.name,
        isDefault: row.isDefault,
        isActive: row.isActive,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      );

  static CatalogItem _sourceItem(IncomeSource row) => CatalogItem(
        id: row.id,
        name: row.name,
        isDefault: row.isDefault,
        isActive: row.isActive,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      );

  static CatalogItem _methodItem(PaymentMethod row) => CatalogItem(
        id: row.id,
        name: row.name,
        isDefault: row.isDefault,
        isActive: row.isActive,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        openingBalanceMinor: row.openingBalance,
      );

  static List<CatalogItem> _sort(Iterable<CatalogItem> items) =>
      (items.toList()..sort(compareCatalog));
}
