import 'package:expense_tracker/repositories/shared_preferences_ui_preferences.dart';
import 'package:expense_tracker/shared/models/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The selected appearance must survive the process being killed, so it lives
/// on disk rather than in widget state.
///
/// `setMockInitialValues` swaps the backing store *and* drops the cached
/// `SharedPreferences` instance, so the second `open()` genuinely re-reads the
/// preference store instead of handing back an in-memory copy - which is
/// exactly what happens when the app is launched again.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const desired = AppUiPreferences(
    themeMode: ThemeModeSetting.dark,
    accent: AccentColor.teal,
    dynamicColor: false,
    lastSelectedYear: 2024,
    lastSelectedMonth: 7,
  );

  test('a chosen appearance is written to the preference store', () async {
    SharedPreferences.setMockInitialValues({});

    final repository = await SharedPreferencesUiPreferencesRepository.open();
    await repository.save(desired);

    // Read the raw store, not the repository: this proves the values were
    // serialised rather than merely held in the object graph.
    final raw = await SharedPreferences.getInstance();
    expect(raw.getString('ui_theme_mode'), 'dark');
    expect(raw.getString('ui_accent_color'), 'teal');
    expect(raw.getBool('ui_dynamic_color'), isFalse);
    expect(raw.getInt('ui_last_selected_year'), 2024);
    expect(raw.getInt('ui_last_selected_month'), 7);
  });

  test('the appearance is restored on the next launch', () async {
    SharedPreferences.setMockInitialValues({});

    final firstLaunch = await SharedPreferencesUiPreferencesRepository.open();
    await firstLaunch.save(desired);

    // Simulate the app being killed and started again: keep only what the
    // first launch persisted, and give the process a clean preference cache.
    final persisted = await SharedPreferences.getInstance();
    SharedPreferences.setMockInitialValues({
      'ui_theme_mode': persisted.getString('ui_theme_mode')!,
      'ui_accent_color': persisted.getString('ui_accent_color')!,
      'ui_dynamic_color': persisted.getBool('ui_dynamic_color')!,
      'ui_last_selected_year': persisted.getInt('ui_last_selected_year')!,
      'ui_last_selected_month': persisted.getInt('ui_last_selected_month')!,
    });

    final secondLaunch = await SharedPreferencesUiPreferencesRepository.open();
    final restored = await secondLaunch.load();

    expect(restored.themeMode, ThemeModeSetting.dark);
    expect(restored.accent, AccentColor.teal);
    expect(restored.dynamicColor, isFalse);
    expect(restored.lastSelectedYear, 2024);
    expect(restored.lastSelectedMonth, 7);
  });

  test('an untouched store falls back to the system defaults', () async {
    SharedPreferences.setMockInitialValues({});

    final repository = await SharedPreferencesUiPreferencesRepository.open();
    final defaults = await repository.load();

    expect(defaults.themeMode, ThemeModeSetting.system);
    expect(defaults.accent, AccentColor.blue);
    expect(defaults.dynamicColor, isFalse);
    expect(defaults.lastSelectedYear, isNull);
    expect(defaults.lastSelectedMonth, isNull);
  });

  test('an unrecognised stored theme falls back instead of throwing', () async {
    // A value written by a future release, or a corrupted one, must not stop
    // the app from starting.
    SharedPreferences.setMockInitialValues({
      'ui_theme_mode': 'volumetric',
      'ui_accent_color': 'chartreuse',
    });

    final repository = await SharedPreferencesUiPreferencesRepository.open();
    final preferences = await repository.load();

    expect(preferences.themeMode, ThemeModeSetting.system);
    expect(preferences.accent, AccentColor.blue);
  });
}
