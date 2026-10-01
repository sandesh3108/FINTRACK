import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/shared_preferences_ui_preferences.dart';
import '../../shared/models/app_settings.dart';

/// Repository for the transient UI preferences (theme, accent, last selection).
final Provider<UiPreferencesRepository> uiPreferencesRepositoryProvider =
    Provider<UiPreferencesRepository>((ref) {
  throw StateError('uiPreferencesRepositoryProvider must be overridden before use.');
});

/// Values read from disk before the first frame, so the app never flashes the
/// wrong theme while the database opens.
final Provider<AppUiPreferences> uiPreferencesInitialProvider =
    Provider<AppUiPreferences>((ref) => const AppUiPreferences());

/// Holds and persists the user's UI preferences.
///
/// Theme and accent are applied by watching this provider at the root of the
/// widget tree; every change is written back immediately so it survives a
/// restart.
class UiPreferencesController extends Notifier<AppUiPreferences> {
  @override
  AppUiPreferences build() => ref.read(uiPreferencesInitialProvider);

  Future<void> _persist(AppUiPreferences next) async {
    state = next;
    try {
      await ref.read(uiPreferencesRepositoryProvider).save(next);
    } on Exception {
      // A failed preference write must never block the UI; the in-memory value
      // is still correct for this session.
    }
  }

  Future<void> setThemeMode(ThemeModeSetting mode) =>
      _persist(state.copyWith(themeMode: mode));

  Future<void> setAccent(AccentColor accent) => _persist(state.copyWith(accent: accent));

  Future<void> setDynamicColor(bool enabled) =>
      _persist(state.copyWith(dynamicColor: enabled));

  Future<void> rememberSelection(int year, int month) =>
      _persist(state.copyWith(lastSelectedYear: year, lastSelectedMonth: month));
}

/// Watched by [ExpenseApp] and by the settings screen.
final NotifierProvider<UiPreferencesController, AppUiPreferences> uiPreferencesProvider =
    NotifierProvider<UiPreferencesController, AppUiPreferences>(
  UiPreferencesController.new,
);
