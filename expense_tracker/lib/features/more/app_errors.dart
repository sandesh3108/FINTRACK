// Re-export kept so the feature screens that were written against the build
// contract keep working.
//
// friendlyMessage now lives with the rest of the error types in
// core/errors/app_exception.dart, which is the canonical import. This file
// only forwards the one symbol; importing both libraries is safe because
// they resolve to the same declaration.
export '../../core/errors/app_exception.dart' show friendlyMessage;
