import 'package:expense_tracker/core/utils/date_utils.dart';

/// An inclusive-start / exclusive-end span of days used by every report,
/// dashboard card and aggregation query.
class RangeSpec {
  const RangeSpec({
    required this.start,
    required this.end,
    required this.label,
  });

  /// First instant included in the range (local midnight).
  final DateTime start;

  /// First instant *excluded* from the range (local midnight).
  final DateTime end;

  /// Human label, e.g. `September 2026` or `2026`.
  final String label;

  int get dayCount {
    var days = end.difference(start).inDays;
    if (days <= 0) days = 1;
    return days;
  }

  bool contains(DateTime value) {
    final d = AppDates.day(value);
    return !d.isBefore(start) && d.isBefore(end);
  }

  /// The single calendar day containing [value].
  factory RangeSpec.day(DateTime value) {
    final d = AppDates.day(value);
    return RangeSpec(start: d, end: d.add(const Duration(days: 1)), label: AppDates.dateLabel(d));
  }

  factory RangeSpec.month(int year, int month) {
    final start = DateTime(year, month, 1);
    return RangeSpec(
      start: start,
      end: DateTime(year, month + 1, 1),
      label: AppDates.monthYearLabel(year, month),
    );
  }

  factory RangeSpec.year(int year) => RangeSpec(
        start: DateTime(year, 1, 1),
        end: DateTime(year + 1, 1, 1),
        label: '$year',
      );

  factory RangeSpec.today() => RangeSpec.day(DateTime.now());

  factory RangeSpec.thisWeek() {
    final start = AppDates.startOfWeek(DateTime.now());
    return RangeSpec(
      start: start,
      end: start.add(const Duration(days: 7)),
      label: 'This week',
    );
  }

  factory RangeSpec.thisMonth() {
    final now = DateTime.now();
    return RangeSpec.month(now.year, now.month);
  }

  factory RangeSpec.thisYear() => RangeSpec.year(DateTime.now().year);

  /// Inclusive of both [start] and [endInclusive].
  factory RangeSpec.days(DateTime start, DateTime endInclusive) {
    final s = AppDates.day(start);
    final e = AppDates.day(endInclusive).add(const Duration(days: 1));
    if (e.isBefore(s)) {
      return RangeSpec(start: s, end: s.add(const Duration(days: 1)), label: AppDates.dateLabel(s));
    }
    return RangeSpec(
      start: s,
      end: e,
      label: s == AppDates.day(endInclusive)
          ? AppDates.dateLabel(s)
          : '${AppDates.dateLabel(s)} - ${AppDates.dateLabel(AppDates.day(endInclusive))}',
    );
  }

  RangeSpec previousMonth() {
    final previous = AppDates.addMonths(start, -1);
    return RangeSpec.month(previous.year, previous.month);
  }

  RangeSpec nextMonth() {
    final next = AppDates.addMonths(start, 1);
    return RangeSpec.month(next.year, next.month);
  }

  RangeSpec previousYear() => RangeSpec.year(start.year - 1);

  RangeSpec nextYear() => RangeSpec.year(start.year + 1);

  @override
  bool operator ==(Object other) =>
      other is RangeSpec && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'RangeSpec($start -> $end, $label)';
}
