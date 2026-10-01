import 'package:flutter/services.dart';

/// Reads the SHA-1 fingerprint of the certificate that signed this install.
///
/// Google registers an Android OAuth client by package name + signing
/// certificate SHA-1, so the Google setup screen shows this value for pasting
/// into the Cloud Console instead of asking anyone to run `keytool`.
///
/// The value comes from the `expense_tracker/signing` channel implemented in
/// `MainActivity.kt`. Everything here is deliberately failure-proof: a missing
/// channel (widget tests, other platforms, a future refactor on the Kotlin
/// side) answers `null` rather than throwing, so the screen that asks for it
/// can always fall back to a documented placeholder.
class SigningFingerprint {
  const SigningFingerprint._();

  /// Channel implemented in `android/.../MainActivity.kt`.
  static const MethodChannel _channel =
      MethodChannel('expense_tracker/signing');

  /// Shown when the platform cannot answer, so the SHA-1 box is never empty.
  ///
  /// It is a placeholder rather than a claim: the setup screen tells the user
  /// to verify the real fingerprint with `keytool` whenever this value is the
  /// one being displayed.
  static const String fallback =
      'FA:A5:B3:31:B7:CA:FD:6E:FD:1D:71:96:20:B8:9C:DB:32:4F:FE:A1';

  /// The colon-separated uppercase SHA-1 of the signing certificate, or
  /// `null` when it could not be read.
  static Future<String?> read() async {
    try {
      final value = await _channel.invokeMethod<String>('getSha1');
      if (value == null || value.trim().isEmpty) return null;
      return value.trim();
    } catch (error) {
      // No handler registered (tests, non-Android hosts): treat it as
      // "unknown" and let the caller show the fallback.
      return null;
    }
  }
}
