import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/state/ui_preferences.dart';
import 'database/database.dart';
import 'repositories/providers.dart';
import 'repositories/shared_preferences_ui_preferences.dart';

/// Application entry point.
///
/// Everything that must exist before the first frame - the SQLite connection
/// and the persisted theme preferences - is opened here, then injected through
/// Riverpod overrides. No widget ever reaches for a global.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final preferences = await SharedPreferencesUiPreferencesRepository.open();
  final initialPreferences = await preferences.load();
  final database = AppDatabase();

  runApp(
    ProviderScope(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(database),
        uiPreferencesRepositoryProvider.overrideWithValue(preferences),
        uiPreferencesInitialProvider.overrideWithValue(initialPreferences),
      ],
      child: const ExpenseApp(),
    ),
  );
}
