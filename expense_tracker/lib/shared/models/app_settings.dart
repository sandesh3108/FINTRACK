import 'package:expense_tracker/core/config/app_config.dart';

/// Theme mode requested by the user.
enum ThemeModeSetting {
  system('System default'),
  light('Light'),
  dark('Dark');

  const ThemeModeSetting(this.label);

  final String label;
}

/// Accent / seed colour choices for the Material 3 colour scheme.
enum AccentColor {
  blue('Blue', 0xFF1565C0),
  green('Green', 0xFF2E7D32),
  purple('Purple', 0xFF6A1B9A),
  orange('Orange', 0xFFEF6C00),
  red('Red', 0xFFC62828),
  teal('Teal', 0xFF00695C);

  const AccentColor(this.label, this.argb);

  final String label;

  /// 32-bit ARGB value, declared as an int so the model stays widget-free.
  final int argb;

  static AccentColor fromName(String? name) => AccentColor.values.firstWhere(
        (c) => c.name == name,
        orElse: () => AccentColor.blue,
      );
}

/// Application configuration persisted across launches.
///
/// Split into two stores on purpose:
///
/// * [AppUiPreferences] - transient UI state (theme, accent, last selection)
///   kept in `shared_preferences` so the very first frame already has the
///   right theme.
/// * [AppSettings] - durable configuration (defaults, currency, Google Sheet
///   link) stored in SQLite so it travels with backup and restore.
class AppUiPreferences {
  const AppUiPreferences({
    this.themeMode = ThemeModeSetting.system,
    this.accent = AccentColor.blue,
    this.dynamicColor = false,
    this.lastSelectedYear,
    this.lastSelectedMonth,
  });

  final ThemeModeSetting themeMode;
  final AccentColor accent;
  final bool dynamicColor;

  /// Remembered so reports reopen where the user left off.
  final int? lastSelectedYear;
  final int? lastSelectedMonth;

  AppUiPreferences copyWith({
    ThemeModeSetting? themeMode,
    AccentColor? accent,
    bool? dynamicColor,
    int? lastSelectedYear,
    int? lastSelectedMonth,
  }) {
    return AppUiPreferences(
      themeMode: themeMode ?? this.themeMode,
      accent: accent ?? this.accent,
      dynamicColor: dynamicColor ?? this.dynamicColor,
      lastSelectedYear: lastSelectedYear ?? this.lastSelectedYear,
      lastSelectedMonth: lastSelectedMonth ?? this.lastSelectedMonth,
    );
  }
}

/// Durable, backup-able configuration.
class AppSettings {
  const AppSettings({
    this.currencySymbol = AppConfig.currencySymbol,
    this.currencyCode = AppConfig.currencyCode,
    this.defaultPaymentMethodId,
    this.defaultCategoryId,
    this.googleSpreadsheetId = '',
    this.googleSpreadsheetTitle = '',
    this.googleAccountEmail = '',
    this.lastSyncAt,
    this.googleClientIdAndroid = '',
    this.googleClientIdWeb = '',
    this.googleProjectId = '',
    this.balancePinHash = '',
    this.balancePinSalt = '',
  });

  final String currencySymbol;
  final String currencyCode;

  /// Pre-selected values on the Add screen. Always overridable per entry.
  final int? defaultPaymentMethodId;
  final int? defaultCategoryId;

  /// Linked Google Sheet, when the user connected one in-app.
  final String googleSpreadsheetId;
  final String googleSpreadsheetTitle;
  final String googleAccountEmail;
  final DateTime? lastSyncAt;

  // -------------------------------------------------- Google OAuth, runtime
  // Client ids entered on the Google Sheets setup screen, so a person can
  // finish the Cloud Console wiring without ever rebuilding the app. They are
  // public identifiers (they ship inside every installed APK), never secrets.
  final String googleClientIdAndroid;
  final String googleClientIdWeb;
  final String googleProjectId;

  /// True when sign-in is allowed: either the ids typed into Settings or the
  /// ones baked into this build with `--dart-define`.
  bool get hasGoogleConfig =>
      googleClientIdAndroid.isNotEmpty ||
      googleClientIdWeb.isNotEmpty ||
      AppConfig.hasGoogleCredentials;

  // ------------------------------------------------------------ balance PIN
  // Salted SHA-256 of the numeric PIN, plus its per-install salt. Never the
  // PIN itself. This guards a glance at the balances, not the database - the
  // backup file already contains the whole ledger in clear text.
  final String balancePinHash;
  final String balancePinSalt;

  /// True when the account balances must be unlocked with the PIN first.
  bool get hasBalanceLock => balancePinHash.isNotEmpty && balancePinSalt.isNotEmpty;

  bool get hasLinkedSheet => googleSpreadsheetId.isNotEmpty;

  AppSettings copyWith({
    String? currencySymbol,
    String? currencyCode,
    int? defaultPaymentMethodId,
    int? defaultCategoryId,
    String? googleSpreadsheetId,
    String? googleSpreadsheetTitle,
    String? googleAccountEmail,
    DateTime? lastSyncAt,
    String? googleClientIdAndroid,
    String? googleClientIdWeb,
    String? googleProjectId,
    String? balancePinHash,
    String? balancePinSalt,
    bool clearDefaultPaymentMethod = false,
    bool clearDefaultCategory = false,
    bool clearSheet = false,
    bool clearSync = false,
    bool clearGoogleConfig = false,
    bool clearBalanceLock = false,
  }) {
    return AppSettings(
      currencySymbol: currencySymbol ?? this.currencySymbol,
      currencyCode: currencyCode ?? this.currencyCode,
      defaultPaymentMethodId: clearDefaultPaymentMethod
          ? null
          : (defaultPaymentMethodId ?? this.defaultPaymentMethodId),
      defaultCategoryId:
          clearDefaultCategory ? null : (defaultCategoryId ?? this.defaultCategoryId),
      googleSpreadsheetId: clearSheet ? '' : (googleSpreadsheetId ?? this.googleSpreadsheetId),
      googleSpreadsheetTitle:
          clearSheet ? '' : (googleSpreadsheetTitle ?? this.googleSpreadsheetTitle),
      googleAccountEmail: clearSheet ? '' : (googleAccountEmail ?? this.googleAccountEmail),
      lastSyncAt: clearSync ? null : (lastSyncAt ?? this.lastSyncAt),
      googleClientIdAndroid: clearGoogleConfig
          ? ''
          : (googleClientIdAndroid ?? this.googleClientIdAndroid),
      googleClientIdWeb:
          clearGoogleConfig ? '' : (googleClientIdWeb ?? this.googleClientIdWeb),
      googleProjectId:
          clearGoogleConfig ? '' : (googleProjectId ?? this.googleProjectId),
      balancePinHash:
          clearBalanceLock ? '' : (balancePinHash ?? this.balancePinHash),
      balancePinSalt: clearBalanceLock ? '' : (balancePinSalt ?? this.balancePinSalt),
    );
  }
}
