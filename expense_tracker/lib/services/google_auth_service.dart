import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';

import '../core/config/app_config.dart';
import '../core/errors/app_exception.dart';

/// The signed-in Google identity, reduced to the four fields the app uses.
///
/// Nothing here exposes a token to widgets; only the Sheets service sees it.
class GoogleAccount {
  const GoogleAccount({
    required this.email,
    required this.id,
    required this.displayName,
    required this.accessToken,
  });

  final String email;
  final String id;
  final String? displayName;
  final String accessToken;
}

/// Thin wrapper around `google_sign_in`.
///
/// Keeping the client in one place means the app owns a single sign-in session
/// for the whole process: the account chooser appears once, and `signOut`
/// actually revokes it because it targets the same instance that signed in.
///
/// The service never builds an OAuth URL by hand and never stores a refresh
/// token of its own - `google_sign_in` handles the platform credential store.
class GoogleAuthService {
  GoogleAuthService._();

  static final GoogleSignIn _client =
      GoogleSignIn(scopes: AppConfig.googleScopes);

  static GoogleSignInAccount? _account;

  /// Email of the connected account, or `null` when nobody is signed in.
  static String? get signedInEmail => _account?.email;

  static bool get isSignedIn => _account != null;

  /// Starts the interactive sign-in flow.
  ///
  /// [configured] is the runtime answer to "are the OAuth client ids set up":
  /// the values saved under *Settings → Google Sheets setup*, or the
  /// build-time `--dart-define` fallback when settings have not loaded. The
  /// caller reads it from the settings provider, so the gate can be opened or
  /// closed without rebuilding the app.
  ///
  /// Returns `null` when the user backs out of the account chooser, which is
  /// not an error. Throws [SheetsException] when setup is missing or Google
  /// refuses the request.
  /// Throws the "set me up first" message when [configured] is false.
  ///
  /// Returns normally when it is true, so callers can write
  /// `if (!configured) _requireConfigured(configured);` and fail *before*
  /// disturbing a session that already works. Factored out so [signIn] and
  /// [switchAccount] say exactly the same thing.
  static void _requireConfigured(bool configured) {
    if (configured) return;
    throw const SheetsException(
      'Google sign-in has not been set up yet. Open Settings → Google '
      'Sheets setup and paste your OAuth client ids.',
      needsSetup: true,
    );
  }

  static Future<GoogleAccount?> signIn({required bool configured}) async {
    if (!configured) _requireConfigured(configured);

    try {
      final account = await _client.signIn();
      if (account == null) return null; // the user closed the chooser

      final auth = await account.authentication;
      final token = auth.accessToken;
      if (token == null || token.isEmpty) {
        throw const SheetsException(
          'Google signed you in but did not hand back an access token. '
          'Sign out and try again.',
        );
      }

      _account = account;
      return GoogleAccount(
        email: account.email,
        id: account.id,
        displayName: account.displayName,
        accessToken: token,
      );
    } on SheetsException {
      rethrow;
    } catch (error) {
      throw _signInFailure(error);
    }
  }

  /// Turns a failure from `google_sign_in` into one sentence that names the
  /// actual cause.
  ///
  /// The plugin reports every Google refusal as a [PlatformException] with a
  /// short fixed code, and the Android side puts Google's own wording in
  /// [PlatformException.message]. Without this mapping the screen can only say
  /// "something went wrong", which is precisely what a person cannot act on -
  /// and this is the one place where the difference between "your SHA-1 does
  /// not match" and "you are offline" actually matters.
  static SheetsException _signInFailure(Object error) {
    final detail = error is PlatformException
        ? '${error.code}${error.message == null ? '' : ': ${error.message}'}'
        : error.toString();

    if (error is PlatformException) {
      switch (error.code) {
        case 'network_error':
          return SheetsException(
            'No internet connection. Google sign-in needs the network - '
            'everything else in the app keeps working offline.',
            technical: detail,
          );
        case 'sign_in_required':
          return SheetsException(
            'Google has no session on this device yet. Tap Connect Google '
            'account to start one.',
            technical: detail,
          );
        case 'sign_in_canceled':
          return SheetsException(
            'Sign-in was cancelled before it finished.',
            technical: detail,
          );
        case 'user_recoverable_auth':
          return SheetsException(
            'Google still needs your permission to read spreadsheets. Tap '
            'Connect Google account and accept the consent screen.',
            technical: detail,
          );
        case 'failed_to_recover_auth':
          return SheetsException(
            'Google asked for permission and it was not granted. That almost '
            'always means the account is not on the app\'s test-user list: '
            'open Google Cloud Console → OAuth consent screen → Test users, '
            'add your address, save, then try again.',
            technical: detail,
          );
        default:
          return SheetsException(_describeGoogleError(error.message ?? detail),
              technical: detail);
      }
    }

    return SheetsException(
      'Could not sign in to Google. Check your connection and try again.',
      technical: detail,
    );
  }

  /// Reads Google's own wording, when there is any, and says what to change.
  ///
  /// Returns the raw message as a last resort: an unfamiliar refusal is still
  /// more useful than a blank sentence, because it can be searched or pasted
  /// into a bug report.
  static String _describeGoogleError(String message) {
    final lower = message.toLowerCase();

    const consoleFix =
        'Open Google Cloud Console → APIs & Services → Credentials and make '
        'sure the Android OAuth client lists package com.sandeep.expense_tracker '
        'and this build\'s SHA-1 fingerprint (Google Sheets setup shows the '
        'fingerprint this build signs with).';

    if (lower.contains('developer_error') ||
        lower.contains('unregistered') ||
        lower.contains('invalid_client') ||
        lower.contains('10:')) {
      return 'Google does not recognise this install as the app it is '
          'authorising. $consoleFix';
    }
    if (lower.contains('play services') ||
        lower.contains('service_missing') ||
        lower.contains('service_disabled') ||
        lower.contains('api_not_connected')) {
      return 'Google Play Services is missing or out of date on this phone. '
          'Update it from the Play Store, then try again.';
    }
    if (lower.contains('network') ||
        lower.contains('unreachable') ||
        lower.contains('timeout') ||
        lower.contains('unable to resolve host')) {
      return 'Google could not be reached. Check the internet connection and '
          'try again.';
    }
    if (lower.contains('invalid_scope') || lower.contains('scope')) {
      return 'Google rejected a permission this app asked for. In Google Cloud '
          'Console → OAuth consent screen → Scopes, add '
          'https://www.googleapis.com/auth/spreadsheets, '
          'https://www.googleapis.com/auth/userinfo.email and '
          'https://www.googleapis.com/auth/drive.readonly, then save.';
    }
    if (lower.contains('permission denied') ||
        lower.contains('insufficient') ||
        lower.contains('access_denied')) {
      return 'Google refused the request. Enable the Google Sheets API under '
          'APIs & Services → Library, and add your address under OAuth '
          'consent screen → Test users.';
    }
    if (lower.contains('429') || lower.contains('rate limit')) {
      return 'Google is limiting how often this app may talk to it. Wait a '
          'minute and try again.';
    }
    return 'Could not sign in to Google: $message';
  }

  /// Connects a *different* Google account than the one already signed in.
  ///
  /// `google_sign_in` hands back an already-authorised account without
  /// asking, so on a phone carrying several Google accounts there would
  /// otherwise be no way to pick another one. Signing out first is what makes
  /// Play Services show its chooser.
  ///
  /// Returns `null` when the chooser is dismissed - a normal outcome, not an
  /// error. The previous session is already gone by then, so the caller is
  /// left disconnected rather than still connected as before; that is the
  /// honest result of asking to change account and not finishing.
  static Future<GoogleAccount?> switchAccount({
    required bool configured,
  }) async {
    // Fail before touching anything: a build with no ids must not sign the
    // user out of an account that was already working.
    if (!configured) _requireConfigured(configured);

    await signOut();
    return signIn(configured: configured);
  }

  /// A currently valid access token, re-authenticating when needed.
  ///
  /// Tokens expire roughly hourly, so every API call goes through here rather
  /// than caching one in a widget. [configured] carries the same meaning as in
  /// [signIn].
  static Future<String> requireAccessToken({required bool configured}) async {
    final existing = _account;
    if (existing != null) {
      try {
        final auth = await existing.authentication;
        final token = auth.accessToken;
        if (token != null && token.isNotEmpty) return token;
      } catch (error) {
        // The stored token could not be refreshed; drop it and sign in again.
        _account = null;
      }
    }

    final signed = await signIn(configured: configured);
    if (signed == null) {
      throw const SheetsException(
        'Sign in to Google to read or write a spreadsheet.',
      );
    }
    return signed.accessToken;
  }

  /// An access token that may also read Drive, used for one job: finding the
  /// spreadsheet this app wrote on another device or before a reinstall.
  ///
  /// The everyday client asks for Sheets only, so this widens the platform's
  /// scope list for the length of one call and puts it back afterwards. Each
  /// `GoogleSignIn` instance re-runs the plugin's `init` on first use, which
  /// is what lets a throwaway instance choose the scopes a token is minted
  /// for; [signInSilently] performs that re-init without ever showing UI, and
  /// the consent prompt - if Drive has not been granted yet - comes from
  /// Google's own token recovery, not from us.
  ///
  /// Restoring the narrow list in a `finally` matters: without it a single
  /// failed search would leave every later sign-in asking for Drive, turning
  /// an optional feature into a prerequisite for the whole Google integration.
  static Future<String> requireDiscoveryToken({required bool configured}) async {
    _requireConfigured(configured);
    // The session has to exist first; this token is minted for it, not for a
    // fresh sign-in, so the chooser is never shown twice.
    await requireAccessToken(configured: configured);

    final wide = GoogleSignIn(scopes: const <String>[
      ...AppConfig.googleScopes,
      AppConfig.googleDriveScope,
    ]);
    try {
      await wide.signInSilently();
      final account = _account;
      if (account == null) {
        throw const SheetsException('Sign in to Google first.');
      }
      final token = (await account.authentication).accessToken;
      if (token == null || token.isEmpty) {
        throw const SheetsException(
          'Google did not hand back an access token for Drive. Sign out and '
          'sign in again.',
        );
      }
      return token;
    } on SheetsException {
      rethrow;
    } catch (error) {
      throw _signInFailure(error);
    } finally {
      await _restoreEverydayScopes();
    }
  }

  /// Puts the plugin's scope list back to what sign-in and Sheets need.
  ///
  /// Best effort on purpose: the worst outcome of a failed restore is that a
  /// later sign-in asks for one extra permission, never that the current
  /// session stops working.
  static Future<void> _restoreEverydayScopes() async {
    try {
      await GoogleSignIn(scopes: AppConfig.googleScopes).signInSilently();
    } catch (_) {
      // Ignore - the signed-in session and its token are already in hand.
    }
  }

  /// Ends the local session. Always succeeds locally, even offline, so a user
  /// can always disconnect their account from the device.
  static Future<void> signOut() async {
    try {
      await _client.signOut();
    } catch (error) {
      // The local session must be cleared even if Google is unreachable.
    } finally {
      _account = null;
    }
  }

  /// Revokes the grant at Google as well as clearing the local session.
  static Future<void> disconnect() async {
    try {
      await _client.disconnect();
    } catch (error) {
      // Revocation is best effort; the local session is cleared regardless.
    } finally {
      _account = null;
    }
  }
}
