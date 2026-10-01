/// Decimal-safe monetary helpers.
///
/// Every amount in the application is stored and manipulated as an **integer
/// of minor units** (paise: 1/100 of a rupee). Floating point arithmetic is
/// never used for money, so rounding errors cannot accumulate.
///
/// ```
/// 1 rupee    ->        1
/// 1,250      ->   125000
/// ₹12,500.50 ->  1250050
/// ```
library;

/// Number of minor units in one major unit (1 rupee = 100 paise).
const int moneyFactor = 100;

/// Parses user input into minor units.
///
/// Accepts the shapes people actually type: `1250`, `1,250`, `1250.5`,
/// `1250.50`, `₹1,250.50`, `1_250`.
///
/// Returns `null` when the value is empty, negative, zero, malformed or has
/// more than two decimal places.
int? parseMoneyToMinor(String input) {
  var cleaned = input.replaceAll(RegExp(r'[₹,\s_]'), '');
  if (cleaned.isEmpty) return null;

  if (cleaned.startsWith('-')) return null;
  if (cleaned.startsWith('+')) cleaned = cleaned.substring(1);
  if (cleaned.isEmpty) return null;

  final dot = cleaned.indexOf('.');
  String whole;
  String fraction;

  if (dot < 0) {
    whole = cleaned;
    // Seed the fraction so the digit check below passes for plain rupee
    // amounts (`1250`), which is how most numbers are typed.
    fraction = '0';
  } else {
    whole = cleaned.substring(0, dot);
    fraction = cleaned.substring(dot + 1);
    if (fraction.isEmpty) fraction = '0';
    // Reject 1.234 rather than silently truncating the user's number.
    if (fraction.length > 2) return null;
  }

  if (whole.isEmpty) whole = '0';
  if (!RegExp(r'^\d+$').hasMatch(whole)) return null;
  if (!RegExp(r'^\d+$').hasMatch(fraction)) return null;

  while (fraction.length < 2) {
    fraction = '${fraction}0';
  }

  final wholeValue = int.tryParse(whole);
  final fractionValue = int.tryParse(fraction);
  if (wholeValue == null || fractionValue == null) return null;
  if (wholeValue == 0 && fractionValue == 0) return null;

  return wholeValue * moneyFactor + fractionValue;
}

/// Groups a run of digits using the Indian numbering system
/// (`1,25,000` rather than `125,000`).
String groupDigitsIndian(String digits) {
  if (digits.length <= 3) return digits;

  final lastThree = digits.substring(digits.length - 3);
  final rest = digits.substring(0, digits.length - 3);

  final chunks = <String>[];
  for (var end = rest.length; end > 0; end -= 2) {
    final start = end - 2 < 0 ? 0 : end - 2;
    chunks.insert(0, rest.substring(start, end));
  }
  return '${chunks.join(',')},$lastThree';
}

/// Formats minor units as an Indian-formatted amount: `₹1,25,000`, `₹1,250.50`.
///
/// Negative values are rendered with a leading minus sign.
String formatMinor(
  int minor, {
  String symbol = '₹',
  bool showSymbol = true,
  bool forceDecimals = false,
}) {
  final isNegative = minor < 0;
  final absolute = minor.abs();
  final rupees = absolute ~/ moneyFactor;
  final paise = absolute % moneyFactor;

  final grouped = groupDigitsIndian(rupees.toString());
  final decimals = paise == 0
      ? (forceDecimals ? '.00' : '')
      : '.${paise.toString().padLeft(2, '0')}';

  final sign = isNegative ? '-' : '';
  final prefix = showSymbol ? symbol : '';
  return '$sign$prefix$grouped$decimals';
}

/// Compact amount for chart axes and tight spaces.
///
/// `12500000` -> `₹1.25Cr`, `125000` -> `₹1.25L`, `12500` -> `₹12.5k`.
///
/// Uses integer arithmetic only - even the abbreviation is computed from paise
/// with `~/` and `%`, so this file contains no floating point at all.
String formatMinorShort(int minor, {String symbol = '₹'}) {
  final rupees = minor.abs() ~/ moneyFactor;
  final sign = minor < 0 ? '-' : '';

  if (rupees >= 10000000) {
    return '$sign$symbol${_abbreviate(rupees, 10000000, 'Cr')}';
  }
  if (rupees >= 100000) {
    return '$sign$symbol${_abbreviate(rupees, 100000, 'L')}';
  }
  if (rupees >= 1000) {
    return '$sign$symbol${_abbreviate(rupees, 1000, 'k')}';
  }
  return '$sign$symbol${groupDigitsIndian(rupees.toString())}';
}

/// `[value] / [divisor]` rendered to at most two decimals, entirely in integers.
String _abbreviate(int value, int divisor, String suffix) {
  final hundredths = (value * 100) ~/ divisor;
  final whole = hundredths ~/ 100;
  final fraction = hundredths % 100;

  if (fraction == 0) return '$whole$suffix';
  if (fraction % 10 == 0) return '$whole.${fraction ~/ 10}$suffix';
  return '$whole.${fraction.toString().padLeft(2, '0')}$suffix';
}

/// Converts minor units back to a decimal string (`125050` -> `1250.50`).
///
/// Used by exports where a plain decimal number is required.
String minorToDecimalString(int minor) {
  final rupees = minor.abs() ~/ moneyFactor;
  final paise = minor.abs() % moneyFactor;
  final sign = minor < 0 ? '-' : '';
  return '$sign$rupees.${paise.toString().padLeft(2, '0')}';
}

/// Parses a decimal string (`1250.50`, `1,250`, `₹1250`) into minor units.
///
/// Unlike [parseMoneyToMinor] this is used for *imported* data and accepts
/// zero, because import previews need to report invalid rows rather than
/// silently drop them.
int? parseImportedMoney(String input) {
  var cleaned = input.replaceAll(RegExp(r'[₹,\s_₹]'), '').trim();
  if (cleaned.isEmpty) return null;
  if (cleaned.startsWith('-')) return null;
  if (cleaned.startsWith('+')) cleaned = cleaned.substring(1);

  final dot = cleaned.indexOf('.');
  String whole = dot < 0 ? cleaned : cleaned.substring(0, dot);
  String fraction = dot < 0 ? '00' : cleaned.substring(dot + 1);
  if (fraction.length > 2) return null;
  while (fraction.length < 2) {
    fraction = '${fraction}0';
  }
  if (whole.isEmpty) whole = '0';
  if (!RegExp(r'^\d+$').hasMatch(whole)) return null;
  if (!RegExp(r'^\d+$').hasMatch(fraction)) return null;

  final w = int.tryParse(whole);
  final f = int.tryParse(fraction);
  if (w == null || f == null) return null;
  return w * moneyFactor + f;
}
