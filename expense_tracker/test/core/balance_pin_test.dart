import 'package:expense_tracker/core/security/balance_pin.dart';
import 'package:flutter_test/flutter_test.dart';

/// The spec pins down this PIN exactly: **numeric only, minimum 5 digits,
/// maximum 10**. These tests are the enforcement of that sentence, plus the
/// storage rules that keep the PIN itself out of the database.
void main() {
  group('format rules', () {
    test('accepts the shortest allowed PIN', () {
      expect(BalancePin.validate('12345'), isNull);
    });

    test('accepts the longest allowed PIN', () {
      expect(BalancePin.validate('1234567890'), isNull);
    });

    test('accepts every length in between', () {
      for (var length = BalancePin.minLength;
          length <= BalancePin.maxLength;
          length++) {
        expect(
          BalancePin.validate('7' * length),
          isNull,
          reason: '$length digits must be allowed',
        );
      }
    });

    test('rejects one digit too few', () {
      expect(
        BalancePin.validate('1234'),
        contains('${BalancePin.minLength} digits'),
      );
    });

    test('rejects one digit too many', () {
      expect(
        BalancePin.validate('12345678901'),
        contains('${BalancePin.maxLength} digits'),
      );
    });

    test('rejects anything that is not a digit', () {
      for (final value in const <String>[
        'abcde',
        '12ab5',
        '12 45',
        '1234-',
        '+12345',
        '12.455',
        '1234\n',
        '١٢٣٤٥', // Arabic-Indic digits are not 0-9
      ]) {
        expect(
          BalancePin.validate(value),
          isNotNull,
          reason: '"$value" must not pass as a PIN',
        );
      }
    });

    test('rejects an empty or whitespace-only entry', () {
      expect(BalancePin.validate(''), isNotNull);
      expect(BalancePin.validate('   '), isNotNull);
    });

    test('keeps a leading zero rather than trimming it away', () {
      expect(
        BalancePin.validate('01234'),
        isNull,
        reason: 'the PIN is a string, so 01234 must not become 1234',
      );
      expect(BalancePin.hash('01234', 'salt'), isNot(BalancePin.hash('1234', 'salt')));
    });

    test('ignores padding around an otherwise valid PIN', () {
      expect(BalancePin.validate('  12345  '), isNull);
    });
  });

  group('storage', () {
    test('a salt is hex, long enough, and never repeats', () {
      final salts = <String>{};
      for (var i = 0; i < 50; i++) {
        final salt = BalancePin.newSalt();
        expect(salt, hasLength(BalancePin.saltBytes * 2));
        expect(RegExp(r'^[0-9a-f]+$').hasMatch(salt), isTrue);
        salts.add(salt);
      }
      expect(salts, hasLength(50), reason: 'two installs must not collide');
    });

    test('the digest never contains the PIN', () {
      const pin = '48291';
      final digest = BalancePin.hash(pin, BalancePin.newSalt());
      expect(digest, isNot(contains(pin)));
      expect(digest, hasLength(64)); // sha256
    });

    test('the same PIN under two salts produces two digests', () {
      final first = BalancePin.hash('48291', BalancePin.newSalt());
      final second = BalancePin.hash('48291', BalancePin.newSalt());
      expect(first, isNot(second), reason: 'the salt is what hides repeats');
    });

    test('a PIN verifies against its own digest', () {
      final salt = BalancePin.newSalt();
      final digest = BalancePin.hash('48291', salt);
      expect(BalancePin.matches('48291', digest, salt), isTrue);
    });

    test('the wrong PIN does not verify', () {
      final salt = BalancePin.newSalt();
      final digest = BalancePin.hash('48291', salt);
      expect(BalancePin.matches('48292', digest, salt), isFalse);
      expect(BalancePin.matches('48291', digest, 'other-salt'), isFalse);
    });

    test('an unset lock can never be opened', () {
      expect(BalancePin.matches('12345', '', ''), isFalse);
      expect(BalancePin.matches('12345', 'deadbeef', ''), isFalse);
      expect(BalancePin.matches('12345', '', 'salt'), isFalse);
    });

    test('a malformed PIN is refused even when it matches a stored digest', () {
      // Guards the case where a bad value was written by something other than
      // the dialog - length must still be enforced at the point of entry.
      final salt = BalancePin.newSalt();
      expect(BalancePin.matches('1234', BalancePin.hash('1234', salt), salt),
          isFalse);
    });
  });
}
