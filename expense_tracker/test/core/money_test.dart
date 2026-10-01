import 'package:expense_tracker/core/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('groupDigitsIndian', () {
    test('leaves short numbers alone', () {
      expect(groupDigitsIndian('0'), '0');
      expect(groupDigitsIndian('123'), '123');
    });

    test('groups the first three from the right, then in pairs', () {
      expect(groupDigitsIndian('1000'), '1,000');
      expect(groupDigitsIndian('12345'), '12,345');
      expect(groupDigitsIndian('1234567'), '12,34,567');
      expect(groupDigitsIndian('100000'), '1,00,000');
      expect(groupDigitsIndian('10000000'), '1,00,00,000');
    });
  });

  group('parseMoneyToMinor', () {
    test('parses whole and fractional rupees into paise', () {
      expect(parseMoneyToMinor('1'), 100);
      expect(parseMoneyToMinor('1250'), 125000);
      expect(parseMoneyToMinor('1250.5'), 125050);
      expect(parseMoneyToMinor('1250.50'), 125050);
      expect(parseMoneyToMinor('0.01'), 1);
    });

    test('tolerates grouping, symbol and separator noise', () {
      expect(parseMoneyToMinor('1,250'), 125000);
      expect(parseMoneyToMinor('₹1,250.50'), 125050);
      expect(parseMoneyToMinor('1_250'), 125000);
      expect(parseMoneyToMinor(' 42 '), 4200);
      expect(parseMoneyToMinor('+42'), 4200);
    });

    test('rejects empty, zero, negative and malformed input', () {
      expect(parseMoneyToMinor(''), isNull);
      expect(parseMoneyToMinor('   '), isNull);
      expect(parseMoneyToMinor('0'), isNull);
      expect(parseMoneyToMinor('0.00'), isNull);
      expect(parseMoneyToMinor('-5'), isNull);
      expect(parseMoneyToMinor('-1.50'), isNull);
      expect(parseMoneyToMinor('1.234'), isNull);
      expect(parseMoneyToMinor('abc'), isNull);
      expect(parseMoneyToMinor('12.'), 1200);
      expect(parseMoneyToMinor('.5'), 50);
      expect(parseMoneyToMinor('1,2,3'), 12300);
    });

    test('never loses precision on large values', () {
      expect(parseMoneyToMinor('999999999.99'), 99999999999);
      expect(parseMoneyToMinor('1000000000'), 100000000000);
    });
  });

  group('formatMinor', () {
    test('renders Indian grouping', () {
      expect(formatMinor(0), '₹0');
      expect(formatMinor(100), '₹1');
      expect(formatMinor(125000), '₹1,250');
      expect(formatMinor(125050), '₹1,250.50');
      expect(formatMinor(10000000), '₹1,00,000');
      expect(formatMinor(1000000000), '₹1,00,00,000');
    });

    test('renders negative balances with the sign outside the symbol', () {
      expect(formatMinor(-125050), '-₹1,250.50');
      expect(formatMinor(-100), '-₹1');
    });

    test('honours showSymbol and forceDecimals', () {
      expect(formatMinor(125000, showSymbol: false), '1,250');
      expect(formatMinor(125000, forceDecimals: true), '₹1,250.00');
      expect(formatMinor(125050, forceDecimals: true), '₹1,250.50');
      expect(formatMinor(125000, symbol: '\$'), '\$1,250');
    });

    test('round-trips through parseMoneyToMinor', () {
      for (final minor in <int>[1, 99, 100, 12345678, 1000000000, -5555]) {
        final text = formatMinor(minor, showSymbol: false);
        final parsed = parseMoneyToMinor(text);
        if (minor > 0) {
          expect(parsed, minor, reason: 'round trip failed for $minor');
        }
      }
    });
  });

  group('formatMinorShort', () {
    test('abbreviates at k, lakh and crore boundaries', () {
      expect(formatMinorShort(0), '₹0');
      expect(formatMinorShort(100), '₹1');
      expect(formatMinorShort(12500), '₹125');
      // 1,250 rupees crosses the k threshold -> 1.25k
      expect(formatMinorShort(125000), '₹1.25k');
      expect(formatMinorShort(1000000), '₹10k');
      expect(formatMinorShort(1250000), '₹12.5k');
      expect(formatMinorShort(12500000), '₹1.25L');
      expect(formatMinorShort(1250000000), '₹1.25Cr');
      expect(formatMinorShort(-12500000), '-₹1.25L');
    });
  });

  group('minorToDecimalString', () {
    test('always emits two decimals', () {
      expect(minorToDecimalString(125050), '1250.50');
      expect(minorToDecimalString(125000), '1250.00');
      expect(minorToDecimalString(0), '0.00');
      expect(minorToDecimalString(50), '0.50');
      expect(minorToDecimalString(-50), '-0.50');
    });

    test('is the inverse of parseMoneyToMinor', () {
      const minor = 987654321;
      expect(parseMoneyToMinor(minorToDecimalString(minor)), minor);
    });
  });

  group('parseImportedMoney', () {
    test('accepts zero so import previews can report it', () {
      expect(parseImportedMoney('0'), 0);
      expect(parseImportedMoney('0.00'), 0);
    });

    test('parses grouped decimals', () {
      expect(parseImportedMoney('1,250'), 125000);
      expect(parseImportedMoney('1250.5'), 125050);
      expect(parseImportedMoney('₹1,250.50'), 125050);
    });

    test('rejects negatives and over-precise values', () {
      expect(parseImportedMoney('-1'), isNull);
      expect(parseImportedMoney('1.999'), isNull);
      expect(parseImportedMoney('abc'), isNull);
      expect(parseImportedMoney(''), isNull);
    });
  });
}
