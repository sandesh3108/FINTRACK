/// Date and time helpers shared by the UI and the repository layer.
library;

import 'package:intl/intl.dart';

class AppDates {
  const AppDates._();

  static const List<String> monthNames = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static const List<String> monthShortNames = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// Strips the time component so day boundaries are always local midnight.
  static DateTime day(DateTime value) => DateTime(value.year, value.month, value.day);

  /// First instant of the month containing [value].
  static DateTime firstOfMonth(DateTime value) => DateTime(value.year, value.month, 1);

  /// First instant of the month after the one containing [value].
  static DateTime firstOfNextMonth(DateTime value) => DateTime(value.year, value.month + 1, 1);

  /// First instant of the year containing [value].
  static DateTime firstOfYear(DateTime value) => DateTime(value.year, 1, 1);

  static int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

  /// Adds [months] calendar months, clamping the day to the target month length.
  static DateTime addMonths(DateTime value, int months) {
    final targetMonth = value.month + months;
    final year = value.year + ((targetMonth - 1) ~/ 12);
    final normalizedMonth = ((targetMonth - 1) % 12 + 12) % 12 + 1;
    final day = value.day > daysInMonth(year, normalizedMonth)
        ? daysInMonth(year, normalizedMonth)
        : value.day;
    return DateTime(year, normalizedMonth, day);
  }

  /// Monday-start week containing [value].
  static DateTime startOfWeek(DateTime value) {
    final d = day(value);
    return d.subtract(Duration(days: d.weekday - DateTime.monday));
  }

  /// Local midnight of "today".
  static DateTime today() => day(DateTime.now());

  static String monthName(int month) => monthNames[month - 1];

  static String monthShort(int month) => monthShortNames[month - 1];

  /// `30 Sep 2026`
  static String dateLabel(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')} ${monthShort(value.month)} ${value.year}';

  /// `September 2026`
  static String monthYearLabel(int year, int month) => '${monthName(month)} $year';

  /// `HH:mm` from a [DateTime].
  static String timeFrom(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  /// `08:30 PM` from a stored `HH:mm` string. Tolerates `8:30`, `20:30`, `20:30:00`.
  static String timeLabel(String? time) {
    if (time == null || time.trim().isEmpty) return '';
    final parts = time.trim().split(':');
    final hour = int.tryParse(parts[0]);
    final minute = parts.length > 1 ? int.tryParse(parts[1]) : 0;
    if (hour == null || minute == null) return time;
    final period = hour >= 12 ? 'PM' : 'AM';
    final twelve = hour % 12 == 0 ? 12 : hour % 12;
    return '$twelve:${minute.toString().padLeft(2, '0')} $period';
  }

  /// `30 Sep 2026 • 08:30 PM`
  static String dateTimeLabel(DateTime date, String? time) =>
      '${dateLabel(date)} • ${timeLabel(time)}';

  /// Normalises free-form imported text into a calendar day.
  ///
  /// Understands `2026-09-30`, `30/09/2026`, `30-09-2026`, `30 September 2026`,
  /// `Sep 30, 2026` and `30 Sep 2026`. Returns `null` when unparseable.
  static DateTime? tryParseDate(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return null;

    // ISO first: 2026-09-30
    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(raw);
    if (iso != null) return _build(iso, order: 'ymd');

    // 30/09/2026 or 30-09-2026
    final dmy = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$').firstMatch(raw);
    if (dmy != null) return _build(dmy, order: 'dmy');

    // 09/30/2026 (month first) - only when the first part exceeds 12 it is
    // unambiguous, otherwise we prefer day-first (Indian spreadsheets).
    final mdy = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$').firstMatch(raw);
    if (mdy != null) {
      final first = int.parse(mdy.group(1)!);
      final second = int.parse(mdy.group(2)!);
      if (first > 12 && second <= 12) return _build(mdy, order: 'mdy');
    }

    // 30 September 2026 / September 30, 2026 / Sep 30 2026
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return day(parsed);

    final cleaned = raw.replaceAll(RegExp(r'[,]+'), ' ').replaceAll(RegExp(r'\s+'), ' ');
    final tokens = cleaned.split(' ');
    if (tokens.length < 3) return null;

    int? year;
    int? month;
    int? dom;
    for (final token in tokens) {
      if (RegExp(r'^\d{4}$').hasMatch(token)) {
        year = int.parse(token);
      } else if (RegExp(r'^\d{1,2}$').hasMatch(token) && month != null) {
        dom = int.tryParse(token);
      } else if (RegExp(r'^\d{1,2}$').hasMatch(token)) {
        dom = int.tryParse(token);
      } else {
        month = monthIndex(token);
      }
    }
    if (year == null || month == null || dom == null) return null;
    if (month < 1 || month > 12 || dom < 1 || dom > daysInMonth(year, month)) return null;
    return DateTime(year, month, dom);
  }

  static DateTime? _build(RegExpMatch match, {required String order}) {
    int a, b, c;
    if (order == 'ymd') {
      a = int.parse(match.group(1)!);
      b = int.parse(match.group(2)!);
      c = int.parse(match.group(3)!);
      return _safe(a, b, c);
    }
    if (order == 'dmy') {
      a = int.parse(match.group(3)!);
      b = int.parse(match.group(2)!);
      c = int.parse(match.group(1)!);
      return _safe(a, b, c);
    }
    a = int.parse(match.group(3)!);
    b = int.parse(match.group(1)!);
    c = int.parse(match.group(2)!);
    return _safe(a, b, c);
  }

  static DateTime? _safe(int year, int month, int day) {
    if (month < 1 || month > 12) return null;
    if (day < 1 || day > daysInMonth(year, month)) return null;
    return DateTime(year, month, day);
  }

  /// Month number for a textual month name, or `null`.
  static int? monthIndex(String name) {
    final lower = name.trim().toLowerCase();
    if (lower.isEmpty) return null;
    for (var i = 0; i < monthNames.length; i++) {
      final full = monthNames[i].toLowerCase();
      final short = monthShortNames[i].toLowerCase();
      if (lower == full || lower == short || full.startsWith(lower) && lower.length >= 3) {
        return i + 1;
      }
    }
    return null;
  }

  /// Normalises free-form imported text into `HH:mm`.
  ///
  /// Understands `08:30 PM`, `20:30`, `8:30`, `08:30:00`. Returns `null` when
  /// the value is not a time.
  static String? tryParseTime(String input) {
    final raw = input.trim().toUpperCase();
    if (raw.isEmpty) return null;

    final match = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?\s*(AM|PM)?$').firstMatch(raw);
    if (match == null) return null;

    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final period = match.group(3);

    if (minute > 59) return null;
    if (period == 'PM' && hour < 12) hour += 12;
    if (period == 'AM' && hour == 12) hour = 0;
    if (hour > 23) return null;

    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  /// `yyyy-MM-dd` - the stable wire format used by exports and backups.
  static String isoDay(DateTime value) => DateFormat('yyyy-MM-dd').format(value);

  /// `yyyy-MM-dd HH:mm` - used for `created_at` / `updated_at` columns in exports.
  static String isoTimestamp(DateTime value) => DateFormat('yyyy-MM-dd HH:mm:ss').format(value);
}
