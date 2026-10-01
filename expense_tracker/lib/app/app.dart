import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/models/app_settings.dart';
import 'routes.dart';
import 'state/app_identity.dart';
import 'state/ui_preferences.dart';
import 'theme/app_theme.dart';

/// Root widget: builds the [MaterialApp] from the persisted theme preferences.
///
/// Theme mode, accent colour and Material You support are all read from
/// [uiPreferencesProvider], so changing them on the Settings screen re-themes
/// the whole app instantly and the choice survives a restart.
class ExpenseApp extends ConsumerWidget {
  const ExpenseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(uiPreferencesProvider);

    final themeMode = switch (preferences.themeMode) {
      ThemeModeSetting.system => ThemeMode.system,
      ThemeModeSetting.light => ThemeMode.light,
      ThemeModeSetting.dark => ThemeMode.dark,
    };

    // Material You only exists on Android 12+; the builder returns null
    // elsewhere and we fall back to the seed colour.
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return MaterialApp(
          title: ref.watch(appNameProvider),
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(
            brightness: Brightness.light,
            accent: preferences.accent,
            useDynamicColor: preferences.dynamicColor,
            dynamicScheme: lightDynamic,
          ),
          darkTheme: AppTheme.build(
            brightness: Brightness.dark,
            accent: preferences.accent,
            useDynamicColor: preferences.dynamicColor,
            dynamicScheme: darkDynamic,
          ),
          themeMode: themeMode,
          locale: const Locale('en', 'IN'),
          supportedLocales: const <Locale>[
            Locale('en', 'IN'),
            Locale('en'),
          ],
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          onGenerateRoute: onGenerateRoute,
          restorationScopeId: 'expense_tracker',
        );
      },
    );
  }
}
