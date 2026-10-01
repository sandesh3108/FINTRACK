# Architecture

How the pieces fit together, and the rules that keep them fitting.

---

## 1. Layers

```
┌─────────────────────────────────────────────────────────────────┐
│  Presentation      lib/features/**  ·  lib/shared/widgets/**    │
│                    Widgets, screens, local Stream/Future        │
│                    Providers that turn repository reads into    │
│                    AsyncValue views.                            │
├─────────────────────────────────────────────────────────────────┤
│  State             lib/app/state/**  ·  Riverpod                │
│                    shellIndexProvider, uiPreferencesProvider,   │
│                    the repository providers.                   │
├─────────────────────────────────────────────────────────────────┤
│  Domain            lib/shared/models/**  ·  lib/core/**         │
│                    Value objects, validation rules, money and   │
│                    date maths, error types, AppConfig.          │
│                    Plain Dart — no Flutter, no Drift.           │
├─────────────────────────────────────────────────────────────────┤
│  Repositories      lib/repositories/*.dart       (interfaces)  │
│                    lib/repositories/drift/**     (implementation)│
│                    lib/repositories/backup_repository.dart      │
├─────────────────────────────────────────────────────────────────┤
│  Storage           lib/database/**               Drift → SQLite │
│                    lib/services/**               HTTP / OAuth   │
└─────────────────────────────────────────────────────────────────┘
```

**The dependency arrow only points down.** A screen may import a repository
*interface*, a model, a shared widget and a provider — never `lib/database/**`,
never `package:drift`. `flutter analyze` is the enforcement mechanism; there is no
hidden coupling through globals.

### Interfaces first

Every repository is declared as an abstract class in
`lib/repositories/<name>_repository.dart` and implemented in
`lib/repositories/drift/`. This costs one small file each and buys three things:

- screens depend on a contract, not on SQL;
- tests can drive the real Drift implementation against an in-memory database;
- a future backend (a different file format, a sync service) only needs a new
  implementation of the same interface.

---

## 2. Money is an integer

**Every monetary value in the app is an `int` of minor units (paise).** There is no
`double` on any money path — not in the schema, not in a model, not on a chart axis.

```
1 rupee      →        1
₹1,250       →   125000
₹1,250.50    →   125050
```

- **Storage:** `transactions.amount INTEGER` — one column, no floats to drift.
- **Parsing:** `parseMoneyToMinor(String) → int?` (returns `null` for anything it
  cannot represent exactly; more than two decimals is rejected, not truncated).
- **Display:** `formatMinor` / `formatMinorShort` — both pure integer maths, with
  Indian digit grouping (`1,00,000`).
- **Charts:** plot paise directly. `axisMaxPaise` rounds an axis ceiling up in
  paise, so the tick labels are formatted from integers too.
- **Averages / shares:** `~/` and `%`, never `/`.

The one place a ratio exists it is used *only* to pick an abbreviation and is
computed as `(value * 100) ~/ divisor` → `whole`, `fraction` — still integers.

`formatMinor` round-trips through `parseMoneyToMinor`; `money_test.dart` asserts it.

---

## 3. Database

Drift (SQLite) with six tables:

| Table | Purpose |
|---|---|
| `categories` | expense categories |
| `income_sources` | salary, freelance, … |
| `payment_methods` | cash, UPI, card, … |
| `special_events` | named groupings with an optional date window |
| `transactions` | the ledger |
| `settings` | durable configuration that travels with backups |

```sql
transactions(
  id, type, amount, date, time, note,
  category_id, income_source_id, payment_method_id, special_event_id,
  created_at, updated_at
)
```

- `date` is local **midnight** of the calendar day and `time` is `HH:mm`, so a
  month report is an indexed range scan rather than a string parse.
- Every column a report filters on has an index (`idx_transactions_date`,
  `idx_transactions_type_date`, and one per foreign key).
- Catalog rows are **archived, never deleted**, so historical transactions keep
  resolving their names. `CatalogRepository.delete` / `EventRepository.delete`
  throw a `ValidationException` that says so when rows are still referenced.
- `onCreate` seeds a sensible default catalog (categories, sources, methods) and
  the four seeded accounts — PhonePe, Google Pay, Cash, BOI(Saving).
- `onUpgrade` is additive only: columns and tables are added, never dropped, so
  user data survives every upgrade. Migration 1 → 2 adds
  `payment_methods.opening_balance` and backfills any account an older install
  was never seeded with, renaming nothing.

### A payment method is an account

Choosing a payment method on a transaction — including the **Deposited to** field
income gained — is what moves money through that account, so the balance shown on
*More → Accounts & balance* is derived rather than entered:

```
remaining = opening_balance + Σ income − Σ expenses
```

All three terms are plain column scans over `transactions` grouped by
`payment_method_id`, in integer paise. Negative balances are reported, not
clamped, and event spending is included: the account still paid for it whatever
the reports call it. See `DriftTransactionRepository.accountBalances`.

### Special events do not double count

An event is a **foreign key on the transaction — a tag, not a copy**. Every
aggregate therefore picks a scope from one predicate:

```dart
summary(range, specialEventId: id)     // rows in range AND tagged with id
summary(range)                          // rows in range, special_event_id IS NULL
summary(range, includeEventRows: true)  // every row in range
```

The three are exhaustive and disjoint, so `monthly + Σ events == grand total`
holds exactly — `transaction_repository_test.dart` asserts it for every aggregate,
not just the summary. `summariesByEvent(range)` returns the middle scope once per
event, which is what the report breakdown card renders as *Monthly expenses /
one line per event / Grand Total*. The history ledger passes
`includeEventRows: true` because it is a list of rows, not a total, and must keep
showing everything.

Account balances deliberately ignore this rule — they always use every row.

---

## 4. State management (Riverpod 2)

Three kinds of provider, all explicit:

| Kind | Example | Notes |
|---|---|---|
| **Binding** | `transactionRepositoryProvider` | one instance of each repository |
| **Reactive read** | `settingsProvider` (`StreamProvider<AppSettings>`) | a table, exposed as a stream |
| **Screen-local** | `txListProvider` (family over `TransactionFilter`) | declared at the top of the screen that owns it |

Screen-local providers are deliberately *file-private*. They name exactly one
repository read, so a screen's data needs are visible in its first 40 lines.

`TransactionFilter` and `RangeSpec` implement value equality specifically so they
can be **family keys**: an unchanged filter does not re-subscribe the query.

**Shell tab index** lives in `shellIndexProvider`, not in widget state, so the
"Add" quick action on the dashboard and the bottom navigation bar agree. Tab
destinations use `_TabRedirect`, which sets the index and pops to the first route
instead of stacking a second shell on the navigator.

**Preferences are split on purpose:**

- `shared_preferences` → *transient UI state*: theme mode, accent, dynamic colour,
  last selected year/month. Never in a backup.
- SQLite `settings` → *durable configuration*: currency symbol, defaults, linked
  spreadsheet, the Google OAuth ids typed into Settings, and the balance PIN's
  salted hash (never the PIN). It travels with a backup.

One provider is deliberately *neither* store: `balanceUnlockedProvider` is a
`StateProvider<bool>` starting at `false` on every launch. Whether the balances
have been unlocked this session is an action, not a preference, so writing it
down would defeat the lock it guards. It is cleared again by the Accounts
screen's `PopScope` on exit, and is short-lived by construction: the flag means
"somebody typed the PIN, very recently". It sits beside `accountBalancesProvider`
in `lib/repositories/providers.dart` so the lock and the money it protects are
invalidated as one unit.

### Balance lock

*Protect account balances* (Settings → Security) puts a numeric PIN in front of
the account figures. The rules are the specification's, enforced in
`lib/core/security/balance_pin.dart` and nowhere else: **digits only, 5 to 10
of them**, checked by `BalancePin.validate` and rendered by the shared
`showPinDialog` — a formatter strips non-digits while typing, the validator
catches length, so a caller cannot forget either.

What is stored is `BalancePin.hash(pin, salt)` plus the salt, as strings in the
`settings` table; the PIN itself is never written. `AppSettings.hasBalanceLock`
requires *both* halves, so a half-written lock reports as off rather than as a
door nobody can open.

Two screens watch it, and neither leaks:

- **Accounts** refuses to render anything — names included — until the PIN is
  accepted. `hasBalanceLock && !unlocked` is computed in `build`, so there is no
  frame where the amounts exist behind a padlock. It is wrapped in a `PopScope`
  that clears the session flag the moment the route pops, so *visible only after
  the password* holds even if the phone is handed straight to someone else —
  leaving the section is what re-locks it, not a timer.
- **More** carries the account strip (it moved off Home, the screen you only
  glance at) and keeps the account names while replacing each amount with `••••`
  and a lock icon, because knowing which wallets you have is not the secret.

Unlocking is deliberately not persisted and has no lockout counter: this stops
someone reading a borrowed phone, and a phone that unlocked for you already had
your data anyway. Turning the lock off or changing it asks for the current PIN
first, so an unattended Settings screen cannot silently remove it.

---

## 5. Routing

`lib/app/routes.dart` owns the table (`AppRoutes`) and the argument objects
(`EditTransactionArgs`, `ReportDetailArgs`, `ManageCatalogArgs`, `EventFormArgs`).
Pushing a named route keeps a single source of truth for signatures, and the
argument classes make the required data compile-time visible.

The shell (`HomeShell`) is an `IndexedStack` of five const tab widgets, each with
its own `Scaffold` + `AppBar`, so a tab behaves exactly like a pushed route for the
status bar and scroll-under-app-bar.

Import has two entry points on purpose: **`/import-sheet`** is a chooser that
asks *where the rows are* (Google Sheets, or a file on this phone) and only
routes, while **`/import-file`** is the device reader itself — the backup screen
in import mode, which reaches for the picker on the first frame. Keeping them
apart means the choice is explicit and neither path has to know about the other.

---

## 6. Errors

`AppException` and its subclasses (`ValidationException`, `DatabaseException`,
`SheetsException`, `OfflineException`) carry a **safe, user-facing message**;
anything unexpected is collapsed by

```dart
String friendlyMessage(Object error)
```

which is the only function allowed to turn a caught error into UI text. Stack
traces, SQL and plugin internals never reach the user. Every screen shows a
retryable error state rather than dying silently.

---

## 7. Theming and accessibility

- All colour comes from `Theme.of(context).colorScheme` — there is not a single
  hard-coded colour in `lib/features/**`. Charts use `colorForIndex(colorScheme, i)`.
- Material 3 throughout, with dynamic colour (Material You) as an opt-in.
- Icon-only controls carry a `tooltip` or `Semantics`.
- Colour is never the only signal: income/expense pair their colour with an icon
  and a label; archived rows get an icon and italic text, not just a hue.
- Charts are always accompanied by a table or text list of the same numbers.

---

## 8. Backup

`BackupRepository` exports one self-describing JSON document (format version 1)
containing settings, all four catalogs, events and transactions.

| Mode | Behaviour |
|---|---|
| **Merge** | adds rows the device does not have; **never** overwrites a row that already exists. Duplicates are found by `duplicateKey` (date + time + amount + type + names + note), so a rename on either side still matches. |
| **Replace** | deletes transactions → clears catalogs → rebuilds from the file, then restores settings. |

`preview()` reads a file and reports counts **without writing anything**, so the
UI can show the user what will happen first. A malformed or future-versioned file
is rejected before anything is deleted.

### Two readers, one screen

A picked file goes down one of two paths, decided by shape rather than by
extension:

| Reader | Recognises | Entry |
|---|---|---|
| `BackupFormats.fromCsv` / `fromXlsx` | a `Date` + `Amount` header row | `csvRows` / `xlsxRows` hand the raw rows to the grid reader first |
| `MonthGridReader.detect` | months across the top, `Things`/`Amount` pairs under each, days down the left | reshapes the cells into `GridEntry` rows |

Detection runs **first** because the month grid has no header row for heading
matching to find — it would be rejected before anyone could see what was inside.
Anything short of four month columns, a `Things`/`Amount` pair per month and a
day counter returns `null`, so an ordinary export is never half-imported.

Each block below the table becomes a special event: the heading is the name
(`Mumbai (8-9)` → *Mumbai*), the bracketed numbers give its days, and its rows
get a `specialEventId`. Main-table rows get none, which is exactly the rule in
§3 — the monthly figures stay clean and the grand total picks everything up.

What the grid cannot know (year, type, wallet, and the month its blocks fall in)
is asked **once** by `showImportDefaultsDialog`, before any name is resolved —
`findOrCreate` writes as it goes, so nothing may run until the person has
confirmed. `ImportDefaults` then stamps every row, `_readyRows` drops calendar
days that do not exist, and the batch lands through the same
`importTransactions` merge every other path uses.

---

## 9. Google Sheets

Sheets sits *behind* the same repository boundary: `google_auth_service.dart`
wraps `google_sign_in`, `google_sheets_service.dart` wraps the REST API. The UI
never builds a URL or holds a token.

Credentials come from **two places, checked in order**:

1. `AppSettings.googleClientIdAndroid` / `googleClientIdWeb` — pasted into
   *Settings → Google Sheets setup*, stored in the `settings` table.
2. `AppConfig.googleClientIdAndroid` — the `--dart-define` fallback, for builds
   that want to ship pre-configured.

Either is enough: `AppSettings.hasGoogleConfig` is the single gate the UI reads,
so finishing setup on the device no longer requires a rebuild. Android still
validates sign-in purely by **package name + signing-cert SHA-1** against the
Cloud Console's Android client — the setup screen computes that SHA-1 at
runtime over a method channel and offers it ready to paste, because it is the
one value a person cannot guess and the one most often entered wrong.

The setup screen shows **how to configure it** instead of throwing. Import is
four explicit steps — fetch → map columns → preview → import — with duplicates
flagged before anything is written.

---

## 10. Testing

```
test/
├── core/money_test.dart                    decimal safety, grouping, round-trips
├── helpers/test_harness.dart               real repositories on NativeDatabase.memory()
├── database/database_smoke_test.dart       schema creation + seeding
└── repositories/
    ├── transaction_repository_test.dart    filters, sort, paging, aggregates, events
    ├── catalog_and_event_repository_test.dart  archive-not-delete, rename, usage counts
    └── backup_repository_test.dart         preview, merge, replace, error paths
```

Repository tests use a **real in-memory SQLite database**, not mocks — the harness
builds the same object graph `main` does. That is why the aggregate, migration and
backup rules are genuinely verified rather than assumed.

Widget tests are intentionally limited: screens are thin, and the logic they would
assert on already lives in layers that are tested directly.

---

## 11. Extension points

| To add… | Do this |
|---|---|
| a report | add a `ReportDefinition` in `report_definitions.dart` — the tab and detail screens pick it up automatically |
| a field on transactions | add the column, bump `schemaVersion`, add an **additive** `onUpgrade` step, extend `TransactionInput` + `TxItem` |
| a backend | implement the repository interface; nothing above it changes |
| a chart type | add a widget to `lib/shared/widgets/charts.dart` taking models, not providers |

## 12. Naming and refreshing

`appNameProvider` in `lib/app/state/app_identity.dart` derives the name the app
should call itself from `localSettingsProvider`, falling back to the
compile-time `AppConfig.appName`. Every screen that names the app reads it, so a
rename reaches the Home bar, the task switcher, About, the shared report file
and the composed mail at once — `AppConfig.appName` itself cannot change, being
`String.fromEnvironment`.

Screens holding **one-shot** queries — reports, report detail, the *More*
summary, catalog usage counts — listen to `ledgerRevisionProvider`, the single
stream that only emits when a transaction actually changed, and invalidate
themselves from it. Stream-backed screens re-emit on their own. Each of those
app bars also carries a refresh button as the manual counterpart, for the moment
when "did that land?" needs answering now rather than at the next change.
