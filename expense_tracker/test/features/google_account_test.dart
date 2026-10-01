import 'package:expense_tracker/core/errors/app_exception.dart';
import 'package:expense_tracker/services/google_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Switching Google accounts.
///
/// A real sign-in cannot happen in a host test - there is no Play Services to
/// ask - so what is pinned down here is the part that does not need it: the
/// pre-conditions, and that a misconfigured build fails *before* anything is
/// signed out. That ordering is the whole reason the guard is not simply left
/// inside [GoogleAuthService.signIn].
void main() {
  group('switchAccount', () {
    test('refuses a build with no ids before touching the session', () async {
      await expectLater(
        GoogleAuthService.switchAccount(configured: false),
        throwsA(
          isA<SheetsException>()
              .having((e) => e.needsSetup, 'needsSetup', isTrue)
              .having(
                (e) => e.message,
                'message',
                contains('Google Sheets setup'),
              ),
        ),
      );
    });

    test('fails with exactly the message signIn uses', () async {
      // Both go through the same guard, so a person told to fix setup is told
      // it the same way whichever entry point they happened to press.
      Object? signInError;
      Object? switchError;
      try {
        await GoogleAuthService.signIn(configured: false);
      } catch (error) {
        signInError = error;
      }
      try {
        await GoogleAuthService.switchAccount(configured: false);
      } catch (error) {
        switchError = error;
      }

      expect(signInError, isNotNull);
      expect(switchError, isNotNull);
      expect(
        (switchError as SheetsException).message,
        (signInError as SheetsException).message,
      );
      expect((switchError).needsSetup, isTrue);
    });
  });

  group('sign-in session', () {
    test('starts with nobody connected', () {
      expect(GoogleAuthService.isSignedIn, isFalse);
      expect(GoogleAuthService.signedInEmail, isNull,
          reason: 'no session is created until a person signs in');
    });

    test('signing out of an empty session is safe', () async {
      // The path switchAccount takes first must never throw, or a phone that
      // was never connected could not even reach the chooser.
      await expectLater(GoogleAuthService.signOut(), completes);
      expect(GoogleAuthService.signedInEmail, isNull);
    });
  });
}
