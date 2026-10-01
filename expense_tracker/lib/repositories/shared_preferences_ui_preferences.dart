import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/models/app_settings.dart';

/// Transient UI preferences kept in `shared_preferences` so the very first
/// frame after launch already has the right theme - no flash of the wrong
/// colours while the database opens.
abstract class UiPreferencesRepository {
  Future<AppUiPreferences> load();

  Future<void> save(AppUiPreferences preferences);
}

/// `shared_preferences` implementation of [UiPreferencesRepository].
class SharedPreferencesUiPreferencesRepository implements UiPreferencesRepository {
  SharedPreferencesUiPreferencesRepository(this._prefs);

  final SharedPreferences _prefs;

  static const String _kThemeMode = 'ui_theme_mode';
  static const String _kAccent = 'ui_accent_color';
  static const String _kDynamicColor = 'ui_dynamic_color';
  static const String _kLastYear = 'ui_last_selected_year';
  static const String _kLastMonth = 'ui_last_selected_month';

  static Future<SharedPreferencesUiPreferencesRepository> open() async =>
      SharedPreferencesUiPreferencesRepository(await SharedPreferences.getInstance());

  @override
  Future<AppUiPreferences> load() async => AppUiPreferences(
        themeMode: _themeModeOf(_prefs.getString(_kThemeMode)),
        accent: AccentColor.fromName(_prefs.getString(_kAccent)),
        dynamicColor: _prefs.getBool(_kDynamicColor) ?? false,
        lastSelectedYear: _prefs.getInt(_kLastYear),
        lastSelectedMonth: _prefs.getInt(_kLastMonth),
      );

  @override
  Future<void> save(AppUiPreferences preferences) async {
    await _prefs.setString(_kThemeMode, preferences.themeMode.name);
    await _prefs.setString(_kAccent, preferences.accent.name);
    await _prefs.setBool(_kDynamicColor, preferences.dynamicColor);
    if (preferences.lastSelectedYear != null) {
      await _prefs.setInt(_kLastYear, preferences.lastSelectedYear!);
    }
    if (preferences.lastSelectedMonth != null) {
      await _prefs.setInt(_kLastMonth, preferences.lastSelectedMonth!);
    }
  }

  static ThemeModeSetting _themeModeOf(String? raw) {
    for (final mode in ThemeModeSetting.values) {
      if (mode.name == raw) return mode;
    }
    return ThemeModeSetting.system;
  }
}
