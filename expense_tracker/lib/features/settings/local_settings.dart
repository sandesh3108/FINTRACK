import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../shared/models/tx_type.dart';

/// Device-local preferences that belong to no other store.
///
/// Durable financial configuration lives in `AppSettings` (SQLite) and the
/// transient UI state (theme, accent, dynamic colour) lives in
/// `UiPreferencesController`. The app name and the transaction type shown when
/// the Add tab opens are presentation defaults for this device only, so they
/// are kept in `shared_preferences` exactly like the rest of the transient UI
/// state - they never travel inside a backup.
class LocalSettings {
  /// Creates a snapshot of the device-local preferences.
  const LocalSettings({
    this.appName = AppConfig.appName,
    this.defaultTransactionType = TxType.expense,
  });

  /// Name shown for the app. Falls back to the build-time [AppConfig.appName].
  final String appName;

  /// Transaction type pre-selected when the Add tab opens.
  final TxType defaultTransactionType;

  /// Returns a copy with the given fields replaced.
  LocalSettings copyWith({
    String? appName,
    TxType? defaultTransactionType,
  }) {
    return LocalSettings(
      appName: appName ?? this.appName,
      defaultTransactionType:
          defaultTransactionType ?? this.defaultTransactionType,
    );
  }
}

/// Loads and persists [LocalSettings].
///
/// Writes are optimistic: the new value is published first, then written to
/// `shared_preferences`, so the UI never waits on disk to feel instant.
class LocalSettingsController extends AsyncNotifier<LocalSettings> {
  static const String _kAppName = 'settings_app_name';
  static const String _kDefaultType = 'settings_default_transaction_type';

  @override
  Future<LocalSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    final storedName = prefs.getString(_kAppName)?.trim();
    return LocalSettings(
      appName: (storedName == null || storedName.isEmpty)
          ? AppConfig.appName
          : storedName,
      defaultTransactionType: _typeOf(prefs.getString(_kDefaultType)),
    );
  }

  /// Renames the app on this device.
  Future<void> setAppName(String value) =>
      _persist(_current.copyWith(appName: value));

  /// Chooses the transaction type the Add tab should start with.
  Future<void> setDefaultTransactionType(TxType value) => _persist(
      _current.copyWith(defaultTransactionType: value));

  /// Restores both values to the shipped defaults.
  Future<void> reset() => _persist(const LocalSettings());

  /// The last loaded value, or the defaults while the first read is running.
  LocalSettings get _current => state.valueOrNull ?? const LocalSettings();

  Future<void> _persist(LocalSettings next) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAppName, next.appName);
    await prefs.setString(_kDefaultType, next.defaultTransactionType.name);
    state = AsyncValue.data(next);
  }

  static TxType _typeOf(String? raw) {
    for (final type in TxType.values) {
      if (type.name == raw) return type;
    }
    return TxType.expense;
  }
}

/// Live device-local preferences (app name, starting transaction type).
final AsyncNotifierProvider<LocalSettingsController, LocalSettings>
    localSettingsProvider =
    AsyncNotifierProvider<LocalSettingsController, LocalSettings>(
  LocalSettingsController.new,
);
