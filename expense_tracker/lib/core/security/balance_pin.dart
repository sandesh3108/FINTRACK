import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// The numeric PIN that guards the account balances.
///
/// Rules, from the specification: **digits only, 5 to 10 of them**. Short
/// enough to type at a keypad, long enough that a shoulder-surfing guess is
/// not worth taking. The PIN is kept as a string end to end so a leading zero
/// survives - `01234` must not silently become `1234`.
///
/// What this buys, honestly: it stops someone picking up an unlocked phone and
/// reading your balances. It is **not** encryption. The stored value is a
/// salted SHA-256 of a numeric PIN, and a determined attacker with the file
/// can search that space - but the same backup file already contains the
/// entire ledger in clear text, so the PIN adds no exposure of its own.
class BalancePin {
  const BalancePin._();

  /// Shortest acceptable PIN.
  static const int minLength = 5;

  /// Longest acceptable PIN.
  static const int maxLength = 10;

  /// Bytes of entropy in a new salt. Long enough that two installs holding the
  /// same PIN never produce the same hash.
  static const int saltBytes = 16;

  /// Returns a message explaining why [value] is unusable, or `null` if it is
  /// fine. The message is written to be shown verbatim in a dialog.
  static String? validate(String value) {
    final raw = value.trim();

    if (raw.isEmpty) return 'Enter a PIN.';

    if (RegExp(r'[^0-9]').hasMatch(raw)) {
      return 'Digits only - no letters, spaces or symbols.';
    }
    if (raw.length < minLength) {
      return 'A PIN needs at least $minLength digits.';
    }
    if (raw.length > maxLength) {
      return 'A PIN can be at most $maxLength digits.';
    }
    return null;
  }

  /// Fresh random salt, as lowercase hex.
  static String newSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(saltBytes, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Salted digest of [pin]. The result is what gets persisted - the PIN
  /// itself never reaches storage.
  static String hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  /// Whether [pin] is the one that produced [hash] under [salt].
  ///
  /// A salt or hash that has never been set always fails, so an unset lock
  /// can never be opened by typing anything.
  static bool matches(String pin, String hash, String salt) {
    if (hash.isEmpty || salt.isEmpty) return false;
    if (validate(pin) != null) return false;
    return BalancePin.hash(pin, salt) == hash;
  }
}
