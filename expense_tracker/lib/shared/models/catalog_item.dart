/// A row from one of the three "catalog" tables: expense categories, income
/// sources and payment methods. They share the same shape, so the management
/// screens can reuse one widget set.
class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.name,
    this.isDefault = false,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.usageCount = 0,
    this.openingBalanceMinor = 0,
  });

  final int id;
  final String name;

  /// Seeded rows shipped with the app; they can be renamed but are never
  /// removed, so defaults always exist for a fresh install.
  final bool isDefault;

  /// `false` means archived: hidden from pickers, still shown in history.
  final bool isActive;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Number of transactions referencing this row (all time).
  final int usageCount;

  /// Opening balance in minor units for a payment method ("account").
  ///
  /// Always `0` for categories and income sources - only accounts have one.
  final int openingBalanceMinor;

  CatalogItem copyWith({
    int? id,
    String? name,
    bool? isDefault,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? usageCount,
    int? openingBalanceMinor,
  }) {
    return CatalogItem(
      id: id ?? this.id,
      name: name ?? this.name,
      isDefault: isDefault ?? this.isDefault,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      usageCount: usageCount ?? this.usageCount,
      openingBalanceMinor: openingBalanceMinor ?? this.openingBalanceMinor,
    );
  }

  @override
  String toString() =>
      'CatalogItem($id, $name, active: $isActive, opening: $openingBalanceMinor)';

  @override
  bool operator ==(Object other) => other is CatalogItem && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Which catalog a [CatalogItem] belongs to - drives repository calls and
/// screen titles from a single enum.
enum CatalogKind {
  category('Categories', 'Category'),
  incomeSource('Income Sources', 'Income Source'),
  paymentMethod('Payment Methods', 'Payment Method');

  const CatalogKind(this.title, this.singular);

  final String title;
  final String singular;
}
