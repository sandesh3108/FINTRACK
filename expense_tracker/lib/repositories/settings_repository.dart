import '../../shared/models/app_settings.dart';

/// Durable, backup-able configuration.
///
/// Deliberately separate from the theme preferences: everything here travels
/// with a backup and restore, while transient UI state lives in
/// `shared_preferences`.
abstract class SettingsRepository {
  Future<AppSettings> load();

  /// Emits after every write so open screens stay in sync.
  Stream<AppSettings> watch();

  Future<void> save(AppSettings settings);

  /// Records the Google Sheet the user linked from inside the app.
  Future<void> linkSheet({
    required String spreadsheetId,
    required String title,
    required String accountEmail,
  });

  Future<void> unlinkSheet();

  Future<void> markSynced(DateTime when);
}
