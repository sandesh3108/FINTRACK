/// Central application configuration.
///
/// Branding, contact and integration values are declared exactly once, here.
/// Every screen reads them from this class - nothing is hard-coded in widgets.
///
/// Values can be overridden at build time with `--dart-define`, for example:
///
/// ```sh
/// flutter build apk --release \
///   --dart-define=APP_NAME="My Budget" \
///   --dart-define=SUPPORT_EMAIL="help@example.com"
/// ```
///
/// Secrets (client secrets, service-account keys, refresh tokens) must never be
/// added here: they would be compiled into the publicly distributed APK.
class AppConfig {
  const AppConfig._();

  // ---------------------------------------------------------------- branding
  static const String appName = String.fromEnvironment(
    'APP_NAME',
    defaultValue: 'FINTRACK',
  );

  /// The Android application id, mirrored for display and documentation.
  ///
  /// The value actually baked into the APK is set once in
  /// `android/app/build.gradle.kts`; change both together.
  static const String packageName = String.fromEnvironment(
    'PACKAGE_NAME',
    defaultValue: 'com.sandeep.expense_tracker',
  );

  static const String developerName = String.fromEnvironment(
    'DEVELOPER_NAME',
    defaultValue: 'FINTRACK',
  );

  static const String description =
      'A simple, offline-first personal finance notebook that replaces a '
      'monthly expense spreadsheet. Record expenses and income in seconds, '
      'categorise them, group them into special events, and see exactly where '
      'your money goes.';

  static const String privacyStatement =
      'Your financial data stays on this device. Nothing is uploaded, tracked '
      'or shared unless you explicitly use an online feature such as Google '
      'Sheets sync. The app contains no analytics, advertising or crash '
      'reporting SDKs. Google Sheets sync only sends data to the Google '
      'account and spreadsheet that you choose.';

  static const String technologySummary =
      'Flutter · Dart · Material 3 · SQLite (Drift) · Riverpod · Google Sheets API';

  static const String licenseName = 'MIT License';

  // --------------------------------------------------------------- contact
  /// Empty value means "not configured" - the UI hides the entry.
  static const String supportEmail = String.fromEnvironment(
    'SUPPORT_EMAIL',
    defaultValue: '',
  );

  static const String websiteUrl = String.fromEnvironment(
    'WEBSITE_URL',
    defaultValue: '',
  );

  static const String githubUrl = String.fromEnvironment(
    'GITHUB_URL',
    defaultValue: '',
  );

  // ------------------------------------------------------------- currency
  static const String currencySymbol = String.fromEnvironment(
    'CURRENCY_SYMBOL',
    defaultValue: '₹',
  );

  static const String currencyCode = String.fromEnvironment(
    'CURRENCY_CODE',
    defaultValue: 'INR',
  );

  // ------------------------------------------------------------- Google OAuth
  // Public OAuth client IDs. Not secrets, but supplied at build time so they
  // stay out of source control.
  static const String googleProjectId = String.fromEnvironment(
    'GOOGLE_PROJECT_ID',
    defaultValue: '',
  );

  static const String googleClientIdAndroid = String.fromEnvironment(
    'GOOGLE_CLIENT_ID_ANDROID',
    defaultValue: '',
  );

  static const String googleClientIdWeb = String.fromEnvironment(
    'GOOGLE_CLIENT_ID_WEB',
    defaultValue: '',
  );

  static const String googleClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
    defaultValue: '',
  );

  /// Resolves the web/installed client ID to use for the OAuth flow.
  static String get effectiveGoogleClientId =>
      googleClientIdWeb.isNotEmpty ? googleClientIdWeb : googleClientId;

  /// True when the developer supplied Google credentials at build time.
  ///
  /// Google Sheets screens use this to show the exact setup steps instead of
  /// failing with an opaque error.
  static bool get hasGoogleCredentials =>
      googleClientIdAndroid.isNotEmpty || effectiveGoogleClientId.isNotEmpty;

  // -------------------------------------------------------------- Sheets I/O

  /// Scopes requested at sign-in.
  ///
  /// Deliberately narrow: read/write the spreadsheet the user links, plus the
  /// account's email so Settings can show which account is connected. No mail,
  /// drive-wide or profile scope is requested.
  static const List<String> googleScopes = <String>[
    'https://www.googleapis.com/auth/spreadsheets',
    'https://www.googleapis.com/auth/userinfo.email',
  ];

  /// The one extra scope used to *find* a spreadsheet written earlier.
  ///
  /// Deliberately kept out of [googleScopes]: asking for it at sign-in would
  /// make the everyday "Connect Google account" fail on a project that has not
  /// declared it, which would break the feature everybody uses to reach the
  /// feature only they need. It is requested for the length of one call by
  /// *Find my spreadsheet*, which explains what to switch on if Google refuses.
  static const String googleDriveScope =
      'https://www.googleapis.com/auth/drive.readonly';

  /// Column headings written by the exporter and matched by the importer.
  ///
  /// Declaring them once guarantees a sheet this app wrote can always be read
  /// back by this app, and gives the importer sensible default mappings for
  /// any sheet that used them.
  static const List<String> sheetColumns = <String>[
    'Date',
    'Time',
    'Type',
    'Amount',
    'Category',
    'Income source',
    'Payment method',
    'Event',
    'Note',
  ];

  /// 1-based row holding [sheetColumns]; everything below is data.
  static const int sheetHeaderRow = 1;

  /// Upper bound on rows fetched in one import, so a very large sheet cannot
  /// stall the UI. Additional rows are reported rather than silently dropped.
  static const int maxImportRows = 1000;

  /// Title of the tab the exporter writes to.
  static const String sheetTabName = 'Transactions';
}
