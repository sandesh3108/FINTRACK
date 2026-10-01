import '../../shared/models/catalog_item.dart';

/// CRUD for the three lookup lists: expense categories, income sources and
/// payment methods.
///
/// Archiving via [setActive] (`false`) is the supported way to "delete" a row:
/// it disappears from pickers but every historical transaction keeps its name,
/// which is what the specification requires.
///
/// The UI depends only on this interface, so a Google Sheets backed
/// implementation can be substituted without touching any widget.
abstract class CatalogRepository {
  /// Live list for the management screens.
  Stream<List<CatalogItem>> watch(CatalogKind kind, {bool activeOnly = false});

  Future<List<CatalogItem>> getAll(CatalogKind kind, {bool activeOnly = false});

  Future<CatalogItem?> byId(CatalogKind kind, int id);

  /// Case-insensitive lookup that creates the row when it does not exist.
  ///
  /// Powers the "Other -> type a new value" flow on the Add screen and every
  /// importer.
  Future<int> findOrCreate(CatalogKind kind, String name);

  Future<void> rename(CatalogKind kind, int id, String name);

  /// Sets the opening balance (minor units) of a payment method / account.
  ///
  /// A no-op for [CatalogKind.category] and [CatalogKind.incomeSource], which
  /// have no balance, so callers never have to guard. Negative values are
  /// allowed: an account can start in debt (a credit card, for example).
  Future<void> setOpeningBalance(CatalogKind kind, int id, int minor);

  /// `false` archives the row, `true` restores it.
  Future<void> setActive(CatalogKind kind, int id, bool active);

  /// Permanently removes a row. Throws when transactions still reference it so
  /// history is never orphaned - callers should archive instead.
  Future<void> delete(CatalogKind kind, int id);

  /// Removes every row of this kind.
  ///
  /// Only used by "replace all data" restore, after transactions have already
  /// been cleared, so it can never orphan history.
  Future<void> clear(CatalogKind kind);
}
