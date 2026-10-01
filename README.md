# FINTRACK

An offline-first personal income and expense tracker for Android, built with Flutter.
The app is called **FINTRACK** — under the icon on the home screen, in the app
drawer and in the recents list — and the same name is used everywhere inside the
app. *Settings → App name* can still rename it per device.

Record a transaction in a couple of taps, keep categories, payment methods and income
sources the way *you* think about money, group rows into special events (a trip, a
festival, a project), and read seven different reports over a rolling twelve months.
Your data lives in SQLite on the device. Nothing leaves the phone unless you
explicitly export a backup or connect a Google Sheet.

**Highlights**

- Quick expense / income entry with an auto-filled, editable date and time
- Custom categories, payment methods and income sources — archive, never delete
  (history is always kept)
- **Account balances**: PhonePe, Google Pay, Cash and BOI(Saving) out of the box.
  Type each opening balance once; every transaction you record against an
  account updates the rest for you
- **Balance lock**: optional numeric PIN (digits only, 5–10) in front of the
  account figures. Turn it on in *More → Settings → Security*; the Accounts
  screen then shows nothing at all until you enter it, and **re-locks the instant
  you leave that screen**. The account strip keeps the names but replaces the
  amounts with dots while it is locked
- Special events with a strict *no double counting* rule: they never fold into the
  monthly figures, and every report separates **monthly / each event / grand total**
  for both expense and income
- Dashboard, history with search / filter / sort / pagination, and 7 report types.
  The **account balances live on the *More* tab**, not on Home — Home is the
  screen you glance at, and these are the figures the balance lock guards
- JSON backup with **merge** (never overwrites) and **replace** (wipes first) modes;
  restore also reads CSV and XLSX spreadsheets, and carries account balances with
  it — or start from *More → Data → Import spreadsheet*, which asks **where the
  rows are** (Google Sheets, or a file on this phone) and takes you there
- **Imports a spreadsheet you already keep yourself.** A sheet laid out as
  months across the top and days down the side — with party / trip blocks under
  the table — is recognised on its own: each block becomes a special event, the
  columns it never had (year, type, wallet) are asked **once** for the whole
  file, and a preview confirms before anything is written
- Optional Google Sheets connect → export (oldest date first) → flexible import with
  column mapping, preview and duplicate detection. Setup is entered **inside the
  app** (*Settings → Google Sheets setup*), so no rebuild is needed
- System / light / dark theme, six accent colours, Material You dynamic colour
- Decimal-safe money: every amount is an integer of paise, never a float
- Fully usable with no internet account and no build-time configuration

---

## Requirements

| Tool | Version used |
|---|---|
| Flutter (stable) | 3.47.5 (Dart 3.13.4) |
| Android SDK | API 36, build-tools 36.0.0 |
| JDK | Android Studio JBR 21 |

Any Flutter 3.x with Dart ≥ 3.5 will work; `pubspec.yaml` uses range constraints.

## Technology stack

| Concern | Choice | Why |
|---|---|---|
| UI | **Flutter 3.47 / Material 3** | one codebase, Android-native look, dynamic colour support |
| State | **Riverpod 2** | compile-time-safe dependencies, no build_runner, testable overrides |
| Local database | **Drift (SQLite)** via `drift_flutter` + `sqlite3_flutter_libs` | typed SQL, migrations, and the same code runs in host tests |
| Charts | **fl_chart** | Material 3 consistent axes, tooltips and legends |
| Money | **integer paise** | no floating point anywhere on a money path |
| OAuth | **google_sign_in** | platform account chooser, no client secret shipped |
| Prefs | **shared_preferences** | theme and accent readable before the first frame |
| Platform | `path_provider`, `file_picker`, `share_plus`, `url_launcher`, `package_info_plus` | Android share sheet, file import/export, contact links |

Every dependency is a stable release with a range constraint; there are no path,
git or vendored packages.

## Getting started

```sh
cd expense_tracker
flutter pub get
flutter run            # debug, with the app already installed or a device attached
```

> **Windows note.** If your shell cannot find `flutter`, put the SDK on `PATH`:
> ```sh
> export PATH="/c/flutter/bin:$PATH"
> ```

## Development commands

| Task | Command |
|---|---|
| Install dependencies | `flutter pub get` |
| Run in debug | `flutter run` |
| Static analysis (must be clean) | `flutter analyze` |
| Run all tests | `flutter test` |
| Run one file | `flutter test test/repositories/transaction_repository_test.dart` |
| Regenerate Drift code | `dart run build_runner build --delete-conflicting-outputs` |
| Release APK | `flutter build apk --release` |
| Release bundle (Play Store) | `flutter build appbundle --release` |
| Inspect the built APK | `flutter build apk --release --analyze-size` |
| Regenerate launcher icons | `python tools/generate_launcher_icons.py` |

## Database

The app uses **SQLite exclusively** — no cloud, no account, no sync daemon.

- **Engine:** [Drift](https://drift.simonbinder.eu) over a native SQLite
  connection opened by `drift_flutter` with `NativeDatabase.createInBackground`.
- **Location:** the platform databases directory
  (`/data/data/com.sandeep.expense_tracker/databases/`), so it survives app
  restarts and is included in Android's backup/restore.
- **Schema:** six tables — `transactions`, `categories`, `income_sources`,
  `payment_methods`, `special_events`, `settings`. See
  [`ARCHITECTURE.md`](ARCHITECTURE.md) for the column list.

```dart
// lib/database/database.dart
@DriftDatabase(tables: [Transactions, Categories, IncomeSources, PaymentMethods, SpecialEvents, Settings])
class AppDatabase extends _$AppDatabase { ... }
```

Key properties:

- **Amounts are `INTEGER` paise.** A ₹1,250.50 row is stored as `125050`.
- **Indexes** on `date`, `(type, date)` and every foreign key keep twelve-month
  reports as range scans.
- **`onCreate` seeds** a default catalog so a fresh install is immediately usable.
- **`onUpgrade` is additive only** — columns and tables are added, never dropped,
  so user data is never lost during migration. Schema 2 adds
  `payment_methods.opening_balance` (the account's starting balance) and backfills
  any seeded account an older install never had, renaming nothing.
- **Catalog rows are archived, never deleted**, so historical transactions always
  resolve their names.
- **A payment method is an account.** Picking one on a transaction — including
  *Deposited to* on income — is what moves money through it, so
  `remaining = opening + income - expenses` is derived, never typed twice.

To inspect the database on a connected device:

```sh
adb shell
run-as com.sandeep.expense_tracker
sqlite3 databases/expense_tracker.db "SELECT COUNT(*) FROM transactions;"
```

## Building a release APK

```sh
flutter build apk --release
```

The APK is written to:

```
build/app/outputs/flutter-apk/app-release.apk
```

### Signing

Release builds are signed with a local keystore that is **not** committed:

```
android/
├── key.properties        # alias + passwords (git-ignored)
└── upload-keystore.p12   # the key itself (git-ignored)
```

If either file is missing — for example on a fresh clone — Gradle falls back to the
debug key so `flutter build apk --release` still succeeds and produces a working
`app-release.apk`.

To create your own keystore (once, then keep a backup of it **and** the password):

```sh
keytool -genkeypair -v \
  -keystore android/upload-keystore.p12 -storetype PKCS12 \
  -keyalg RSA -keysize 3072 -validity 10000 -alias upload \
  -storepass YOUR_PASSWORD -keypass YOUR_PASSWORD \
  -dname "CN=Your Name, O=Your Org, C=IN"
```

Then write `android/key.properties`:

```properties
storePassword=YOUR_PASSWORD
keyPassword=YOUR_PASSWORD
keyAlias=upload
storeFile=upload-keystore.p12
storeType=pkcs12
```

> Losing the keystore means you can never update an installed app under the same
> signature again — ship a fresh package name instead.

### Build variants

```sh
flutter build apk --debug       # fast, unoptimised
flutter build apk --release     # optimised, tree-shaken, signed
flutter build appbundle --release   # for Google Play
```

## Configuration

Nothing is hard-coded. Branding, contact details and integration keys are read at
**build time** from `--dart-define` — see [` .env.example`](.env.example) for the
full list. Example:

```sh
flutter build apk --release \
  --dart-define=APP_NAME="My Budget" \
  --dart-define=SUPPORT_EMAIL="help@example.com" \
  --dart-define=CURRENCY_SYMBOL="₹" \
  --dart-define=GOOGLE_CLIENT_ID_ANDROID="xxxx.apps.googleusercontent.com" \
  --dart-define=GOOGLE_CLIENT_ID_WEB="yyyy.apps.googleusercontent.com"
```

All values have sensible defaults, so **no** `--dart-define` is required to build
and run the app. Values are declared exactly once, in
[`lib/core/config/app_config.dart`](lib/core/config/app_config.dart).

`APP_NAME` defaults to **FINTRACK** and drives the name shown *inside* the app.
The label under the launcher icon is a separate Android resource —
[`android/app/src/main/res/values/strings.xml`](android/app/src/main/res/values/strings.xml)
— which ships as `FINTRACK` too. Change both together if you rebrand.

The **currency symbol** itself can also be changed at runtime from *More →
Settings*; the value travels with the database and with backups. The three
**Google OAuth values are the same story**: they can be pasted into
*More → Settings → Google Sheets setup* at any time, and are stored in the
`settings` table instead of in the APK. Build-time values remain as a default
the screen starts from, for when one APK is shipped to several devices.

> Never put a client secret, service-account key or refresh token in this project.
> Android apps cannot keep secrets private — anything compiled into the APK is
> public. OAuth *client IDs* are not secrets; they are still supplied through
> `--dart-define` so they stay out of source control.

## Importing a spreadsheet you already keep

*More → Data → Import spreadsheet* opens a screen with exactly two choices:

1. **Import from Google Sheets** — goes to the Google Sheets screen, where you
   connect an account and either export this app's columns or import a sheet
   back, with a column-mapping step when the headings do not line up.
2. **Import from this device** — opens the file picker straight away for a
   `.xlsx` or `.csv` already on the phone. Nothing leaves the device.

Both stop at a preview and ask for a confirmation; rows already recorded are
counted as *skipped as duplicates* rather than written twice.

### Month-grid sheets

People's own budget sheets are usually **not** one row per transaction. They
look like this — months across the top, days down the left:

```text
Date/Months | Jan             | Feb
            | Things  | Amount| Things  | Amount
1           | rentina |  800  |         |
2           | hotel   |  450  | brother | 1200
...
Totals      | 4,300          | 1,200

Mumbai (8-9)
            | Things  | Amount
sweets      |  500
cake        |  600
```

That shape is detected on its own — it has no `Date` / `Amount` header row for
the ordinary reader to match, so it is tried first:

- Each cell's `Things` becomes the **category** (or income source) and its
  `Amount` becomes the amount, in integer paise.
- Each **block below the table** becomes a **special event**: the heading is
  the name (`Mumbai (8-9)` → *Mumbai*) and the bracketed numbers give the
  event's days. Rows in the main table carry no event, so they stay in the
  monthly figures.
- The sheet never states a year, whether a row is an expense or an income, or
  which wallet paid — and blocks name days but never a month. Those four are
  asked **once** for the whole file, in a single dialog that appears as soon
  as the file is understood. Cancel is always available and writes nothing.
- A row with a description and no amount is counted in the preview rather than
  silently dropped, and a day that does not exist (a 30th of February in a
  fixed 31-day grid) is left out.

If the file does not match the month-grid shape it falls back to ordinary
heading matching, so a normal export still imports exactly as before.

## Google Sheets (optional)

The app is offline-first by design. Google Sheets is only used when you press a
button on the *Google Sheets* screen.

1. In [Google Cloud Console](https://console.cloud.google.com/) create a project.
2. **APIs & Services → Library** → enable **Google Sheets API**. Enable the
   **Google Drive API** there as well — it is used only by *Find my spreadsheet*
   below, and everything else works without it.
3. **APIs & Services → OAuth consent screen** → configure it (External + *Add
   yourself as a test user* is enough while developing) and add these three
   scopes under **Scopes**, or Google answers the matching request with
   `invalid_scope`: `…/auth/spreadsheets`, `…/auth/userinfo.email`, and
   `…/auth/drive.readonly` (the last only for *Find my spreadsheet*).
4. **APIs & Services → Credentials → Create credentials → OAuth client ID**:
   - Application type **Android** → package name and SHA-1.
     You do not have to look these up: open **More → Settings → Google Sheets
     setup** in the app and both values are shown there ready to copy, with the
     SHA-1 read live from whatever signing key the installed build was signed
     with. (`keytool -list -v -keystore android/upload-keystore.p12 -storetype
     PKCS12 -storepass YOUR_PASSWORD -alias upload | grep SHA1` prints the same
     value if you would rather have it from the command line.)
   - Application type **Web application** → copy its client ID.

**Then, without rebuilding anything:** *More → Settings → Google Sheets setup* →
paste the Android and Web client IDs (and optionally the project ID) → **Save**.
The status line turns to *Configured* and the Google Sheets screen starts
offering **Connect Google account**. The ids are ordinary public identifiers and
are stored in the `settings` table, so they travel with a backup and are never
compiled into the APK.

The same three values can still be baked in at build time instead, if you are
shipping one APK to several devices:

```sh
flutter build apk --release \
  --dart-define=GOOGLE_CLIENT_ID_ANDROID="....apps.googleusercontent.com" \
  --dart-define=GOOGLE_CLIENT_ID_WEB="....apps.googleusercontent.com" \
  --dart-define=GOOGLE_PROJECT_ID="your-project"
```

If neither route is used the app still builds and runs; the *Google Sheets*
screen just points at the setup page instead of failing.

### When it will not connect

*Google Sheets* → **Check connection** runs the four things that can be wrong,
in order, and stops at the first one that fails:

| Step | What a failure means |
| --- | --- |
| OAuth client ids | Nothing was saved under *Google Sheets setup* and no `--dart-define` was baked in. |
| Google account | Nobody has signed in yet — tap **Connect Google account**. |
| Access token | Google refused to issue one: wrong SHA-1 or package name, missing Play Services, or consent not granted. |
| Google Sheets | The API is disabled, the account is not a test user, or the sheet is not shared with that account. |

Failures also print Google's own wording under the friendly sentence, so the
exact refusal can be read back instead of guessed at.

### Getting your data back on a new phone

Transactions live in SQLite on the device, and uninstalling the app deletes that
database. The Google Sheet does not — the sheet is the copy that survives.

1. Install the app and sign in under *Google Sheets* with the same Google
   account that was linked before.
2. If the sheet is already linked (its id travels inside a backup), press
   **Fetch sheet** and confirm the preview.
3. On a clean install, where nothing is linked, press **Find my spreadsheet**.
   It searches the account for spreadsheets it may see, newest first. Tapping
   one links it and reads its rows in the same motion, ready for the usual
   mapping → preview → confirm import. Nothing is written before the preview is
   confirmed, and rows that already exist are skipped rather than duplicated.

Pasting the sheet's link into *Paste a spreadsheet link* does the same job and
needs no extra permission, if you kept the link to hand.

### "This app has not completed the Google verification process"

This is Google, not the app. It means the OAuth consent screen is still in
**Testing** and the account you are signing in with is not on its test-user
list — or the app has been published but the requested scopes have not been
verified. Nothing in the APK can fix it; it is four clicks in the console.

1. Open the [Cloud Console](https://console.cloud.google.com/) and **select the
   project** whose ID you used (the one shown on the setup screen).
2. **APIs & Services → OAuth consent screen**.
3. Under **Audience** (older consoles: *Publishing status*) find **Test
   users** → **Add users** → type the Gmail address you sign in with →
   **Save**. Adding it here is what clears the block; publishing alone does not,
   while the status is still *Testing*.
4. On the same page, **Scopes → Add or remove scopes** — both of these must be
   listed, or sign-in fails with a different error:
   ```
   .../auth/spreadsheets
   .../auth/userinfo.email
   ```
5. **APIs & Services → Library → Google Sheets API** — confirm it says *API
   enabled*.

Sign out of the account in the app and connect again; the consent screen should
now simply ask for permission.

**Signing in with other people's accounts** works the same way: either add each
address as a test user, or press **Publish app** on the consent screen to move
it to *In production*. Be aware that `spreadsheets` is a *sensitive* scope —
once published, users outside your organisation may still see a verification
prompt unless the app has been through Google's verification. Staying in
*Testing* with a list of test users is the normal setup for an app you and a
few friends use.

**In the app:** *More → Google Sheets → Connect Google account* → create a new
spreadsheet or paste the URL of an existing one → **Export**. Export writes the
headings and every expense and income **oldest date first**, so the sheet reads
day by day; exporting again replaces the table rather than stacking a second copy
underneath it. **Import** walks you through fetching the sheet, mapping each column
to a field (Date, Amount, Type, Category, …), previewing the first rows, seeing how
many are duplicates, and then importing with duplicates skipped.

**More than one Google account:** once connected, the same card offers
**Switch account** next to *Sign out*. It signs out and immediately prompts
again, so Play Services shows its account chooser and a second person can
connect their own account on the same phone. Dismissing the chooser simply
leaves the app signed out.

If the ids were baked in at build time rather than pasted on the device, the
setup screen says **"Configured — ids supplied by this build"**; pasted ids say
**"ids saved on this device"**. Both open the same sign-in button.

## Testing

```sh
flutter test        # 188 tests
flutter analyze     # must report no issues
```

Repository tests run against a **real in-memory SQLite database**
(`NativeDatabase.memory()`), so the Drift queries, migrations, aggregates, backup
merge/replace and the archive-not-delete rules are all exercised end to end rather
than mocked. They cover every category the specification asks for: transaction
calculations, category / payment-method / income-source totals, monthly totals,
special-event totals including the no-double-counting rule, import duplicate
detection, backup round-trips and theme persistence across a restart.

On top of those:

- `test/database/migration_test.dart` rebuilds a real schema-1 file, reopens it
  with the current code and asserts the upgrade adds the opening-balance column,
  backfills the seeded accounts and loses nothing.
- `test/repositories/transaction_repository_test.dart` proves
  `monthly + events == grand total` exactly once, and that every account balance
  is `opening + income − expenses` including event spending.
- `test/services/google_drive_service_test.dart` and
  `google_sheets_service_test.dart` drive both Google services against a stubbed
  HTTP client: the Drive query Google would receive (mime type, `trashed`,
  title escaping), the reply parsed into sheet references, `probe()` treating a
  404 as proof the connection works, and each refusal mapped to the scope, API
  or test-user list it actually points at.
- `test/features/report_breakdown_test.dart` pumps a report and reads the
  *Monthly expenses / event / Grand Total* lines straight off the card, for
  expense and for income.
- `test/features/accounts_screen_test.dart` types an opening balance into the
  dialog and checks both the card and the stored paise value.
- `test/shared/catalog_picker_test.dart` drives the **Other...** escape hatch
  through the real dialog: the typed name reaches the database and the form gets
  the new id, while an empty prompt adds nothing.
- `test/core/month_grid_test.dart` feeds the month-grid reader a hand-built
  copy of the layout above and asserts what it produces — twelve month columns,
  paise not rupees, event names with their brackets stripped and their day
  numbers kept — plus the four shapes it must **refuse**: this app's own export,
  a two-month sheet, a grid with no day column and an empty file.
- `test/features/month_grid_import_test.dart` then runs that file end to end
  through the real navigator: recognised → asked once → previewed → confirmed →
  8 rows and 2 events in the database, with exactly the four monthly rows left
  outside every event. It also proves cancelling the dialog writes nothing and
  leaves the file ready to be asked again.

`test/app/app_smoke_test.dart` then pumps the real application root against that
database: it checks that all five tabs build without throwing, that the bottom
bar switches tabs, that an empty first run shows guidance, and that switching to
dark mode re-themes the tree. It unmounts the tree before the test ends, because
disposing the Riverpod scope makes Drift schedule stream-closing timers that
flutter_test would otherwise report as leaked.

> On Windows the tests need a SQLite library. The `sqlite3` Dart package builds it
> through its native-asset hook automatically; if loading fails, make sure
> `sqlite3.dll` is discoverable, e.g.
> `export PATH="$PATH:/c/Users/you/miniconda3/Library/bin"`.

## Project structure

```
lib/
├── core/            # config, security (balance PIN), money + date helpers,
│                    # error types, CSV/XLSX backup decoding, month-grid reader
├── shared/
│   ├── models/      # plain Dart value objects (TxItem, RangeSpec, filters…)
│   └── widgets/     # reusable UI: MoneyText, charts, form fields, pickers
├── database/        # Drift tables, schema, migration, default catalog data
├── repositories/    # interfaces + Drift implementations + JSON backup
├── app/             # theme, Riverpod state, routes, MaterialApp
└── features/        # screens, grouped by bottom-nav destination
    ├── shell/       # the 5-tab navigation shell
    ├── dashboard/   add/   transactions/   reports/
    └── more/        manage/ events/ settings/ backup/ contact/ about/
                     google_sheets/
```

See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the layering rules and data flow.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `flutter` not found on Windows | `export PATH="/c/flutter/bin:$PATH"` |
| `SDK location not found` | `android/local.properties` must contain `sdk.dir` and `flutter.sdk` |
| `app-release.apk` missing | read the Gradle error above it — a failed build never produces an APK |
| Tests fail to open SQLite | put `sqlite3.dll` on `PATH` (see *Testing*) |
| Sheets returns `invalid_grant` | token expired — tap *Connect Google account* again |
| Sheets returns 403 | enable the Sheets API and add your SHA-1 to the Android OAuth client |

### Gradle warnings you can ignore

- **`Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP):
  file_picker, package_info_plus, share_plus`** — Flutter detects this by
  searching those plugins' build files for the plugin id, so the warning fires
  even though each one now guards it with `if (agpMajor < 9)`. On AGP 9 nothing
  is applied; the warning is purely textual.
- **`Deprecated Gradle features were used … incompatible with Gradle 10`** —
  emitted by the plugins themselves, not by this project's Gradle scripts.

### `android.builtInKotlin=true` is load-bearing

`android/gradle.properties` sets `android.builtInKotlin=true` and that value
cannot be flipped to `false`. Both directions fail, for opposite reasons:

| Value | Result |
| --- | --- |
| `false` | AGP 9 stops compiling Kotlin. `file_picker`'s Android module emits **no compile task at all** and ships an empty AAR, so the build dies with `error: cannot find symbol FilePickerPlugin` in `GeneratedPluginRegistrant.java`. |
| `true` | Any plugin applying the Kotlin Gradle Plugin *unconditionally* fails configuration with `Failed to apply plugin 'kotlin-android'`. |

The version floors on `file_picker`, `share_plus` and `package_info_plus` in
`pubspec.yaml` keep those three in the second, correct camp — each guards KGP
behind `if (agpMajor < 9)`. `android_file_picker` (file_picker 13 is federated,
so Android lives in its own package) goes further and reads the
`android.builtInKotlin` property itself. Bump the three together; they also have
to agree on `win32` ^6.

Keeping `id("kotlin-android")` out of `app/build.gradle.kts` is the same rule
from the app's side: Flutter's built-in Kotlin provides the `kotlin { }` block.

## Privacy

Your financial data stays on your device. There is no analytics, advertising or
crash-reporting SDK. Google Sheets sync sends data only to the Google account and
spreadsheet you choose, and only when you press the button.

*Protect account balances* keeps a salted hash of your PIN, never the PIN itself.
It guards against someone reading the figures on an unlocked phone — it is not
encryption, and a backup file already contains your ledger in clear text.

## License

MIT — see [`CHANGELOG.md`](CHANGELOG.md) for release notes.
