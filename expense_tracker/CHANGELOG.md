# Changelog

All notable changes to Expense Tracker are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Account balances.** Each payment method doubles as an account, seeded as
  PhonePe, Google Pay, Cash and BOI(Saving). Enter an opening balance once per
  account from *More → Accounts & balance* (or the strip at the top of the
  dashboard) and the remaining balance then derives itself: opening + income −
  expenses, over every transaction recorded against that account. Income gained a
  **Deposited to** field so salary can land in a specific account; balances appear
  on the dashboard, on their own screen, and travel with backups.
- Restore also reads **CSV** and **XLSX** files alongside JSON backups: headings
  are matched case-insensitively (extra columns are ignored, only Date and
  Amount are required), amounts land as integer paise, and a legacy `.xls` pick
  is refused with a hint to save as `.xlsx`.
- **Balance lock.** *More → Settings → Security* now offers *Protect account
  balances*: a numeric PIN, **digits only, 5 to 10 of them**, chosen when the
  feature is switched on. A salted SHA-256 of it is stored — never the PIN — and
  changing or removing it asks for the current one first. With it on, the
  Accounts screen renders nothing (not even the account names) until the PIN is
  accepted for the session, and the dashboard's account strip keeps the names
  while replacing each amount with dots. Unlocking is session-only and starts
  closed on every launch.
- **Google Sheets setup runs inside the app.** *More → Settings → Google Sheets
  setup* takes the Android client ID, Web client ID and project ID at runtime
  and stores them in the settings table, so finishing the Cloud Console wiring no
  longer means rebuilding. The page also carries the console click path and shows
  the package name plus this build's **signing SHA-1**, read live over a method
  channel, ready to copy into the OAuth client form — falling back to the
  documented value with a `keytool` hint when the platform cannot answer.
- **Import spreadsheet from the *More* tab.** *More → Data → Import spreadsheet*
  now opens a screen with exactly two choices — **Import from Google Sheets**
  (the existing Google flow, column mapping and preview included) and **Import
  from this device** (straight into the `.xlsx` / `.csv` picker) — so nobody has
  to work out which screen their file belongs in. Both run through the same
  decode → preview → duplicate-detection → confirm path as a restored file, and
  nothing is written before the preview is confirmed. The device path is also
  reachable on its own at `/import-file`.
- **Month-grid sheets import directly.** A spreadsheet laid out with months
  across the top, days down the left and `Things` / `Amount` pairs under each
  month is recognised on its own, because that layout has no `Date` / `Amount`
  heading for the ordinary reader to match. Rows are reshaped into dated
  transactions (integer paise, `Things` → category), and **each block below the
  table becomes a special event** — its heading is the name, its bracketed
  numbers (`Mumbai (8-9)`) give the event's days — while the monthly table stays
  event-free. The columns the sheet never had — **year, type, payment method**
  and, when there are blocks, the **month the event days fall in** — are asked
  **once** for the whole file in a single dialog that opens as soon as the file
  is understood; Cancel writes nothing and leaves the preview up to be asked
  again. Days that do not exist are left out and a description with no amount is
  counted in the preview instead of vanishing. A file that does not match falls
  back to ordinary heading matching, so existing exports import unchanged.
- **The name set in *Settings* is now the name everywhere.** Renaming the app
  used to change one row on the settings screen and nothing else; it now reaches
  the *Home* bar, the task switcher, the About card, the file shared from a
  report, the mail composed from *Contact*, the *More* header and the title
  offered when creating a spreadsheet. (The label under the icon on the phone's
  home screen is baked into the installed APK and cannot be changed at run time.)
- **A refresh button in the top-right corner** on *Home*, *Transactions*,
  *Reports* and *More*. The numbers on those screens now also re-derive
  themselves whenever a transaction is added, edited or deleted anywhere in the
  app, so a new entry no longer waits for the app to be closed and reopened.
- **Search inside the category picker.** Tapping *Category*, *Income source* or
  *Payment method* on a transaction opens a list that filters as you type rather
  than a dropdown that has to render all twenty-five shipped categories at once.
  Archived entries stay visible — they must remain selectable when editing
  history — the current choice is ticked, and a name that does not exist yet can
  be created straight from the search box, carried over into the prompt so it
  never has to be retyped. *Manage → Categories* already had its own search
  field and is unchanged.
- **Check connection** on the *Google Sheets* screen: runs the four things that
  can be wrong — OAuth client ids, signed-in account, access token, Sheets API —
  in order, stops at the first failure and prints exactly what to change.
- **Find my spreadsheet.** Deleting the app, reinstalling it or installing on a
  second phone wipes the local database, and with it the remembered spreadsheet
  id — the Sheets API can open a sheet by id but cannot list them, so nothing
  could work out *which* sheet to reopen. *Find my spreadsheet* now searches the
  connected account for spreadsheets it may see, and tapping one links it and
  reads its rows in the same motion, ready for the usual preview-and-confirm
  import. It asks for `…/auth/drive.readonly` for the length of that single call
  and never at sign-in, so a project that has not declared the scope still
  connects, exports and imports normally; if Google refuses it, the message says
  which scope to add.
- **Switch account** on the *Google Sheets* screen: signs out and straight back
  in, so Play Services shows its account chooser and a second Google account can
  be connected on the same phone. Backing out of the chooser is treated as
  "no change", not as an error.

### Changed

- **The app is now called FINTRACK.** The label rendered under the icon on the
  home screen, in the app drawer and in the recents list comes from
  `android/app/src/main/res/values/strings.xml`; the name used inside the app —
  the home bar, About, Contact, Reports, Settings, and the title offered when
  creating a spreadsheet — comes from `AppConfig.appName`. Both now default to
  **FINTRACK** and stay overridable with `--dart-define=APP_NAME=…`; *Settings*
  can still rename it per device, as before.
- **The account balances moved from Home to *More*.** Home is the screen you
  glance at; these are the figures the balance lock guards, so the *Your
  accounts* strip now sits on the *More* tab above *Manage*.
- **The balance lock now closes when you leave.** The Accounts screen is wrapped
  in a `PopScope` that clears the session flag on exit, so coming back — or
  handing the phone over — asks for the PIN again instead of staying open until
  the app restarts.

- **Special events no longer count toward the monthly figures.** Every report now
  offers three scopes: the regular rows (`special_event_id IS NULL`), one specific
  event, or everything. Reports render a *Total breakdown* card —
  *Monthly expenses*, one line per event, **Grand Total** — for expense and for
  income, and the yearly view does the same. The dashboard's balance card keeps
  the same rule and now says so when the period contains event activity. The
  history list is unaffected and still shows every row; a repository test asserts
  `monthly + events == grand total` exactly once.
- Google Sheets **export replaces the sheet instead of appending to it**, so
  exporting twice cannot duplicate the ledger and deleting a transaction removes
  it from the sheet. Rows stay sorted oldest date first.
- The Google sign-in gate moved from compile time to **runtime**:
  `GoogleAuthService.signIn` and `requireAccessToken` now take the answer to
  "are the ids set up" from the caller, which reads `AppSettings.hasGoogleConfig`
  — stored settings first, `--dart-define` as the fallback. The *Google Sheets*
  screen's "no client id" block was replaced by a button to the setup page.

### Fixed

- **Google Sheets answered HTTP 400 with *"could not complete the request"* on
  every call.** Two causes, both in how the range reached Google:

  1. The range was percent-encoded *before* being handed to `Uri.https`, which
     encodes its own path. `A1:I1000` became `A1%3AI1000`, the second pass turned
     that into `A1%253AI1000` on the wire, and Google decoded it back to the
     literal text `A1%3AI1000` — not a range, so it refused. Ranges are only ever
     `A-Z`, `0-9` and `:`, all legal in a path, so they now go through unwrapped.
  2. A fresh Google Sheet has exactly **1000 rows**, while the app asked for row
     1001 on every read and 1002 on every clear. Google rejects an out-of-grid
     range with 400 rather than trimming it. Every range is now clamped to the
     grid the sheet actually reports, and an export that needs more room grows
     the tab first (`updateSheetProperties`) instead of naming rows that do not
     exist yet.

  Column letters are also spelled base-26 rather than by offset, so column 27 is
  `AA` instead of `[`, and `values/update` now derives the range in its body and
  its URL from the same numbers so the two cannot disagree. *Check connection*
  no longer calls a healthy connection dead for answering 400 to its deliberately
  fake spreadsheet id — auth is evaluated before the body of a request, so 400 and
  404 both still prove the phone is online and the token was accepted. Failures
  that do reach the app now carry the method and path that produced them alongside
  Google's own wording.
- A Google sign-in failure no longer collapses into *"Could not sign in to
  Google. Check your connection and try again."*. Every refusal `google_sign_in`
  can produce — no network, no session, consent not granted, **failed recovery
  (the account is missing from the test-user list)**, a developer-error SHA-1 or
  package mismatch, missing Play Services, a rejected scope, a rate limit — is
  now translated into the sentence that names the actual cause, with Google's
  raw wording kept underneath it instead of being discarded.
- Migration 1 → 2 backfills `BOI(Saving)` on installs seeded before the balance
  feature existed, without renaming or overwriting anything the user already had.

## [1.0.0] — 2026-09-30

First release. A complete, offline-first expense and income tracker for Android.

### Added

**Recording**
- Quick expense / income entry with an auto-filled, editable date and time.
- Custom categories, income sources and payment methods, with inline creation
  ("Other…") from the form itself.
- Archive-not-delete for every catalog row and every special event: history keeps
  resolving its names, and deleting a row that is still in use is refused with an
  explanation of the archive alternative.
- Seeded default catalogs (categories, income sources, payment methods) on first run.

**Reading your data**
- Dashboard with a month selector, balance card, quick actions, five stat cards,
  a twelve-month chart, a category donut, a daily trend and recent transactions.
- Transaction history with debounced search, a full filter sheet (type, six date
  ranges, category / income source / payment method / event, min–max amount),
  four sort orders, day-grouped rows and page-based pagination.
- Seven report types: Monthly Summary, Category Breakdown, Income vs Expense,
  Payment Method Usage, Daily Spending, Special Event Summary and Yearly
  Comparison — each with charts, totals and a text/table alternative, and CSV
  export.
- 12 months of tracking with zero-filled gaps.

**Special events**
- Events are tags on transactions, so an event transaction is counted exactly
  once everywhere — verified by an explicit test.

**Data safety**
- JSON backup with **merge** (adds what the device is missing, never overwrites)
  and **replace** (wipes first, then restores) modes.
- A preview step that reports counts and duplicate detection before writing.
- Validation that rejects malformed and future-versioned files before any data
  is deleted.

**Optional Google Sheets**
- In-app connect: sign in, create a spreadsheet or link an existing one.
- Export transactions to the sheet.
- Flexible import: fetch → map columns → preview the first rows → see duplicate
  counts → import with duplicates skipped.
- Graceful setup screen when no OAuth client IDs were supplied at build time.

**Presentation**
- System / light / dark theme, six accent colours and Material You dynamic colour,
  all persisted.
- Indian digit grouping (`1,00,000`) as the default number format; the currency
  symbol is configurable at runtime.
- Empty, loading and retryable error states on every screen.
- Accessibility: tooltips on icon-only controls, ≥44 px targets, colour always
  paired with an icon or label, and chart data always duplicated as text.

**Engineering**
- Layered architecture: Presentation → State → Domain → Repositories → Storage,
  enforced by the analyzer (screens never import Drift).
- Money stored as integer paise end to end; no floating point on any money path.
- Riverpod 2 state management with value-equality family keys.
- 73 tests covering money maths, validation, query aggregates, pagination,
  archive-not-delete, event non-duplication, backup merge/replace and a widget
  smoke test of the real application root — all repository tests run against a
  real in-memory SQLite database.
- Branded adaptive launcher icon and Android 12+ splash screen.
- Release signing via a git-ignored `key.properties` + PKCS#12 keystore, with a
  debug-key fallback so a fresh clone still builds.

### Build configuration

- `android.builtInKotlin=true` in `android/gradle.properties`. On AGP 9 this is
  required, not cosmetic: with it `false`, AGP stops compiling Kotlin and
  `file_picker`'s Android module ships an empty AAR, failing
  `GeneratedPluginRegistrant.java` with `cannot find symbol FilePickerPlugin`.
- `file_picker` ≥ 13, `share_plus` ≥ 13 and `package_info_plus` ≥ 10. These are
  the first releases that guard `apply plugin: kotlin-android` behind
  `agpMajor < 9`; older ones apply it unconditionally and AGP 9 rejects that
  once built-in Kotlin is on. file_picker 13 is federated, so Android now comes
  from `android_file_picker`, which reads the `android.builtInKotlin` property
  itself. The three move together because they must agree on `win32` ^6.
- Fixed an Android 12+ resource error by dropping `android:postSplashScreenTheme`
  from `values-v31` and `values-night-v31`: the attribute was removed from the
  final Android 12 SDK and fails resource linking.

### Known limitations

- Google Sheets import reads a single sheet range; multi-sheet workbooks are not
  scanned.
- Import is limited to the first 1,000 rows per run (`AppConfig.maxImportRows`).
- Backup restore merges by content key, so two identical rows recorded on the
  same day with the same amount and note are treated as one.
- The release keystore is local to this machine; losing it means a future release
  must ship under a different application id.

[1.0.0]: https://github.com/sandeep/expense-tracker/releases/tag/v1.0.0
