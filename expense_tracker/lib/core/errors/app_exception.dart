/// Application-level exceptions.
///
/// Widgets catch [AppException] and show [message] to the user. Technical
/// detail stays in [technical] and is only written to debug logs, so raw stack
/// traces never reach the UI.
class AppException implements Exception {
  const AppException(this.message, {this.technical});

  /// Safe, user-facing message.
  final String message;

  /// Optional developer detail - never rendered in the UI.
  final String? technical;

  @override
  String toString() => message;
}

/// Raised when user input fails a business rule.
class ValidationException extends AppException {
  const ValidationException(super.message, {this.field});

  /// Identifier of the offending field so the form can highlight it.
  final String? field;
}

/// Raised when a local database operation fails.
class DatabaseException extends AppException {
  const DatabaseException(super.message, {super.technical});
}

/// Raised by Google Sheets / OAuth operations.
///
/// [needsSetup] marks errors caused by missing developer configuration so the
/// UI can offer setup instructions instead of a generic failure.
class SheetsException extends AppException {
  const SheetsException(super.message, {this.needsSetup = false, super.technical});

  final bool needsSetup;
}

/// Raised when the device has no connectivity and an online feature was used.
class OfflineException extends AppException {
  const OfflineException()
      : super(
          "You're offline. Google Sheets needs an internet connection - "
          'everything else keeps working without it.',
        );
}

/// Turns a caught error into text a person can act on.
///
/// Every screen funnels errors through this one function so the app speaks
/// with a single voice: [AppException] subclasses already carry a safe,
/// user-facing [AppException.message], and anything else (a platform failure,
/// malformed file, unexpected state) collapses to one reassuring line, so
/// stack traces, SQL and plugin internals never reach the UI.
///
/// ```dart
/// } catch (error) {
///   showAppMessage(context, friendlyMessage(error), error: true);
/// }
/// ```
String friendlyMessage(Object error) {
  if (error is AppException) return error.message;
  if (error is FormatException) {
    return 'That value could not be read. Check it and try again.';
  }
  if (error is TypeError) {
    return 'That file could not be read. It may be damaged or not a backup.';
  }
  return 'Something went wrong. Please try again.';
}
