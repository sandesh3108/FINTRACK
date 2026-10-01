/// A special expense / event grouping such as `Mumbai Trip` or `Birthday`.
///
/// Events are pure *tags*: an assigned transaction is counted once globally
/// and once for the event, never twice.
class SpecialEvent {
  const SpecialEvent({
    required this.id,
    required this.name,
    this.description = '',
    required this.startDate,
    this.endDate,
    this.isArchived = false,
    required this.createdAt,
    required this.updatedAt,
    this.transactionCount = 0,
    this.expenseMinor = 0,
    this.incomeMinor = 0,
  });

  final int id;
  final String name;
  final String description;

  /// First day of the event window.
  final DateTime startDate;

  /// Optional last day; `null` for open-ended events.
  final DateTime? endDate;

  /// Archived events disappear from pickers but stay on old transactions.
  final bool isArchived;

  final DateTime createdAt;
  final DateTime updatedAt;

  // ------------------------------------------------------------ aggregates
  final int transactionCount;
  final int expenseMinor;
  final int incomeMinor;

  int get balanceMinor => incomeMinor - expenseMinor;

  bool get isOngoing => endDate == null;

  String get dateRangeLabel {
    if (endDate == null) return _format(startDate);
    if (startDate.year == endDate!.year &&
        startDate.month == endDate!.month &&
        startDate.day == endDate!.day) {
      return _format(startDate);
    }
    return '${_format(startDate)} - ${_format(endDate!)}';
  }

  static String _format(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  SpecialEvent copyWith({
    int? id,
    String? name,
    String? description,
    DateTime? startDate,
    DateTime? endDate,
    bool? isArchived,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? transactionCount,
    int? expenseMinor,
    int? incomeMinor,
    bool clearEndDate = false,
  }) {
    return SpecialEvent(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      startDate: startDate ?? this.startDate,
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      transactionCount: transactionCount ?? this.transactionCount,
      expenseMinor: expenseMinor ?? this.expenseMinor,
      incomeMinor: incomeMinor ?? this.incomeMinor,
    );
  }

  @override
  String toString() => 'SpecialEvent($id, $name)';

  @override
  bool operator ==(Object other) => other is SpecialEvent && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Values captured by the event create/edit form.
class SpecialEventDraft {
  const SpecialEventDraft({
    required this.name,
    this.description = '',
    required this.startDate,
    this.endDate,
  });

  final String name;
  final String description;
  final DateTime startDate;
  final DateTime? endDate;
}
