# Expense Tracker Android App --- Automated Coding Agent Prompt

## 1. Role

You are an autonomous senior Android/Flutter engineer, software
architect, UI/UX designer, database engineer, QA engineer, and release
engineer.

Your task is to **design, implement, test, and package a complete
Android Expense Tracker application** from this specification.

Do not stop at generating a mockup or partial source code. The goal is a
**working Android project that can be built into a signed/release APK**.

When a requirement is ambiguous, choose the simplest production-ready
implementation that satisfies the intent, document the decision, and
continue. Do not repeatedly ask for approval for routine engineering
decisions.

------------------------------------------------------------------------

# 2. Project Goal

Build a personal finance application that replaces a manually maintained
monthly expense spreadsheet.

The application must allow the user to:

-   Record expenses quickly.
-   Record income.
-   Automatically record the current date and time.
-   Categorize expenses.
-   Track payment methods such as PhonePe, Google Pay, and Cash.
-   Create custom categories.
-   Track income sources such as Salary, From Home, Scholarship, Friend,
    and Other.
-   Track all 12 months.
-   View monthly totals.
-   View category-wise totals.
-   View payment-method totals.
-   View income totals.
-   View balance/savings.
-   Create separate Special Expense/Event groups such as Mumbai Trip,
    Pune Trip, Birthday, etc.
-   Import existing expense data from Google Sheets.
-   Export application data/reports to Google Sheets.
-   Work offline for normal tracking.
-   Provide backup and restore.
-   Provide dashboard and reports.
-   Allow theme customization.
-   Include Contact Us, About, Settings, and other standard pages.
-   Produce an installable Android APK.

The application should be simple enough for daily use while having a
clean architecture that allows future features to be added.

------------------------------------------------------------------------

# 3. Recommended Technology

Use the following stack unless there is a strong technical reason to
change it:

### Frontend / Android

-   Flutter
-   Dart
-   Material 3
-   Android target
-   Responsive mobile UI

### Local database

Use SQLite through a reliable Flutter database abstraction such as:

-   Drift, or
-   sqflite

Prefer **Drift** if it improves type safety and maintainability.

### State management

Use a clean, maintainable approach such as:

-   Riverpod

### Architecture

Use a layered architecture:

``` text
Presentation
    ↓
State Management
    ↓
Domain / Business Logic
    ↓
Repositories
    ↓
Local Database / External Services
```

Keep UI, business logic, database access, and external integrations
separated.

### Google Sheets

Use Google APIs / Google Sheets API for import and export.

Authentication should use Google's supported OAuth flow.

Do not hard-code credentials, API keys, client secrets, or tokens into
source code.

------------------------------------------------------------------------

# 4. Core Product Principle

The application must be **offline-first**.

Normal functionality must work without internet:

-   Add expense
-   Add income
-   Edit transaction
-   Delete transaction
-   Search transactions
-   Filter transactions
-   Dashboard
-   Monthly reports
-   Yearly reports
-   Category reports
-   Payment-method reports
-   Income reports
-   Special Expense/Event reports
-   Category management
-   Payment-method management
-   Income-source management
-   Theme settings
-   Backup creation
-   Backup restoration

Internet is required only for functionality that inherently needs
external services, especially:

-   Google Sheets import
-   Google Sheets export
-   Opening online contact links if configured

If the internet is unavailable, the app should continue working normally
and display a clear message only when an online feature is requested.

------------------------------------------------------------------------

# 5. Application Name

Use a configurable application name.

Default name:

**Expense Tracker**

Do not hard-code the name throughout the application.

Create a central application configuration so the name, package
information, support email, website, and other branding information can
be changed easily.

------------------------------------------------------------------------

# 6. Currency

Default currency:

**Indian Rupee (₹ / INR)**

All amounts must be stored safely using a decimal-safe representation.

Do not use floating-point arithmetic in a way that can introduce
monetary rounding errors.

Display amounts using Indian number formatting where appropriate.

Example:

``` text
₹1,250
₹12,500
₹1,25,000
```

------------------------------------------------------------------------

# 7. Main Navigation

Use a bottom navigation structure similar to:

``` text
Home
Transactions
Add
Reports
More
```

The Add button should be prominent.

Suggested navigation:

### Home

Dashboard.

### Transactions

Complete transaction history.

### Add

Quick Expense / Income entry.

### Reports

Monthly, yearly, category, payment, income, and event analysis.

### More

Settings, categories, payment methods, income sources, special events,
backup, Google Sheets, Contact Us, About, etc.

------------------------------------------------------------------------

# 8. Dashboard

Create a clean financial dashboard.

The dashboard should show the current month by default.

## Summary cards

Display:

-   Total Income
-   Total Expense
-   Balance
-   Today's Expense

Formula:

``` text
Balance = Total Income - Total Expense
```

## Additional statistics

Display:

-   This week's expense
-   This month's expense
-   This year's expense
-   Average daily spending
-   Number of transactions
-   Highest individual expense
-   Highest spending category

## Category summary

Show a category-wise breakdown.

Example:

``` text
Food              ₹3,200
Petrol            ₹2,100
Travel            ₹1,500
Shopping          ₹4,000
Medical             ₹500
Other             ₹1,200
```

Allow tapping a category to view its transactions.

## Payment method summary

Example:

``` text
PhonePe            ₹5,500
Google Pay         ₹4,000
Cash               ₹2,500
Other                ₹500
```

## Charts

Include useful charts such as:

-   Expense by category
-   Income vs expense
-   Monthly spending trend
-   Payment method distribution

Charts must remain readable on small screens.

Do not overload the dashboard with too many charts.

------------------------------------------------------------------------

# 9. Add Transaction

The most important workflow is:

``` text
Open App
→ Tap +
→ Expense
→ Enter Amount
→ Select Category
→ Select Payment Method
→ Save
```

The process should take only a few seconds.

------------------------------------------------------------------------

# 10. Expense Entry

Expense fields:

### Required

-   Amount
-   Category
-   Payment Method

### Automatically generated

-   Date
-   Time

Date and time should automatically use the current device date/time.

Allow the user to manually change date/time.

### Optional

-   Note/Description
-   Special Expense/Event

## Expense categories

Provide default categories including:

-   Food
-   Petrol/Fuel
-   Travel
-   Shopping
-   Groceries
-   Medical
-   Education
-   Mobile Recharge
-   Internet
-   Electricity
-   Rent
-   Entertainment
-   Vehicle
-   Vehicle Maintenance
-   Clothing
-   Personal
-   Restaurant
-   Snacks
-   Bills
-   Subscription
-   Gifts
-   Household
-   Fitness
-   Electronics
-   Other

The list must be editable.

------------------------------------------------------------------------

# 11. Custom Category System

The user must be able to create custom categories.

Example:

User selects:

``` text
Other
```

and enters:

``` text
Bike Service
```

The application must:

1.  Save the transaction as `Bike Service`.
2.  Add `Bike Service` to the reusable category list.
3.  Show `Bike Service` the next time an expense is entered.
4.  Allow the category to be edited later.

Provide category management:

-   Add category
-   Rename category
-   Delete/archive category
-   Search categories
-   View number of transactions using a category

Deleting a category must **not delete its transaction history**.

Use an archive/deactivate approach where appropriate.

------------------------------------------------------------------------

# 12. Payment Methods

Default payment methods:

-   PhonePe
-   Google Pay
-   Cash
-   Other

Allow users to add custom payment methods.

Examples:

-   Bank Transfer
-   Credit Card
-   Debit Card
-   UPI
-   Other

Payment methods must be manageable from Settings/More.

Track payment method totals.

------------------------------------------------------------------------

# 13. Income Entry

Allow switching between:

``` text
Expense
Income
```

Income fields:

-   Amount
-   Date
-   Time
-   Income Source
-   Note
-   Special Event/Event (optional)

Default income sources:

-   Salary
-   From Home
-   Scholarship
-   Friend
-   Other

Allow custom income sources.

If the user selects `Other` and types a new source, save it as a
reusable income source.

------------------------------------------------------------------------

# 14. Income Tracking

Show:

-   Total income
-   Monthly income
-   Yearly income
-   Income by source
-   Number of income transactions

Example:

``` text
Salary          ₹20,000
Scholarship     ₹10,000
From Home        ₹5,000
Friend           ₹2,000
Other            ₹1,000
```

------------------------------------------------------------------------

# 15. 12-Month Tracking

Provide a Yearly Overview screen.

Show all 12 months:

``` text
January
February
March
April
May
June
July
August
September
October
November
December
```

For every month show:

-   Total Income
-   Total Expense
-   Balance
-   Number of transactions

Example:

``` text
September 2026

Income:   ₹25,000
Expense:  ₹14,500
Balance:  ₹10,500
```

Allow tapping a month to open its detailed report.

------------------------------------------------------------------------

# 16. Category-Wise Totals

Provide a category analysis page.

For a selected month/year:

``` text
Food             ₹3,200
Petrol           ₹2,100
Travel           ₹1,500
Shopping         ₹4,000
Medical            ₹500
```

Allow:

-   Month selection
-   Year selection
-   Custom date range
-   Highest-to-lowest sorting
-   Lowest-to-highest sorting
-   Alphabetical sorting

Allow tapping a category to see all matching transactions.

------------------------------------------------------------------------

# 17. Payment-Method Analysis

Provide:

``` text
PhonePe
Google Pay
Cash
Other
```

Show totals by:

-   Month
-   Year
-   Custom date range

Example:

``` text
PhonePe       ₹5,500
Google Pay    ₹4,000
Cash          ₹2,500
Other           ₹500
```

------------------------------------------------------------------------

# 18. Special Expense / Event System

This is a critical feature.

The user currently maintains separate spreadsheet sections for things
such as:

-   Mumbai
-   Pune
-   Birthday
-   Trips
-   Other events

Implement a dedicated **Special Expenses / Events** system.

## Create Event

Example:

``` text
Event Name:
Mumbai Trip

Start Date:
10 September 2026

End Date:
15 September 2026

Description:
Mumbai trip expenses
```

A transaction can optionally be assigned to this event.

Example:

``` text
Bus             ₹500
Food            ₹800
Hotel         ₹1,500
Shopping      ₹1,200
Petrol          ₹600
```

Total:

``` text
₹4,600
```

## Event dashboard

Each event should show:

-   Total expense
-   Total income if applicable
-   Balance
-   Transaction count
-   Category breakdown
-   Payment-method breakdown
-   Date-wise breakdown

## Important accounting rule

An event transaction must NOT be added twice to overall expenses.

For example:

``` text
Petrol ₹500
Event: Mumbai Trip
```

The ₹500 is:

-   Included in Petrol total
-   Included in Mumbai Trip total
-   Included in September total

But it must be counted **only once** in the overall expense total.

The event is a grouping/tagging mechanism, not a second transaction.

------------------------------------------------------------------------

# 19. Transaction History

Create a complete transaction list.

Each row/card should show:

``` text
Date
Time
Expense/Income
Amount
Category / Income Source
Payment Method
Special Event
Note
```

Example:

``` text
30 Sep 2026 • 08:30 PM

Expense
₹250

Food
Google Pay
Mumbai Trip
```

Provide:

-   Search
-   Filter
-   Sort
-   Edit
-   Delete

Filters:

-   Date
-   Month
-   Year
-   Transaction type
-   Category
-   Income source
-   Payment method
-   Special event
-   Amount range

Search should work across:

-   Category
-   Description
-   Event
-   Payment method
-   Amount
-   Income source

------------------------------------------------------------------------

# 20. Quick Add

The Add screen should immediately show:

``` text
Expense
Income
```

The user should not need to navigate through multiple screens.

Remember recently used values where useful, but never make it difficult
to change them.

------------------------------------------------------------------------

# 21. Reports

Create a Reports section.

Reports:

1.  Monthly Report
2.  Yearly Report
3.  Category Report
4.  Payment Method Report
5.  Income Report
6.  Special Event Report
7.  Custom Date Range Report

Each report should show relevant totals and charts.

------------------------------------------------------------------------

# 22. Monthly Report

For a selected month:

``` text
September 2026

Total Income:   ₹25,000
Total Expense:  ₹14,500
Balance:        ₹10,500
```

Then:

-   Category breakdown
-   Payment method breakdown
-   Income source breakdown
-   Daily spending
-   Largest expense
-   Transaction count

------------------------------------------------------------------------

# 23. Yearly Report

Show:

-   Total yearly income
-   Total yearly expenses
-   Yearly balance
-   Monthly expense trend
-   Monthly income trend
-   Category totals
-   Payment-method totals
-   Income-source totals

Allow selecting any year.

------------------------------------------------------------------------

# 24. Search and Filters

Search should be fast and work offline.

Examples:

Search:

``` text
petrol
```

shows all petrol transactions.

Search:

``` text
Mumbai
```

shows transactions assigned to Mumbai Trip.

Filters should be combinable.

Example:

``` text
September
+
Expense
+
Petrol
+
Google Pay
```

------------------------------------------------------------------------

# 25. Google Sheets Import

Implement Google Sheets integration.

The user should be able to import their existing expense spreadsheet.

The current spreadsheet may contain month-wise sections and separate
special expense sections.

The import process should:

1.  Authenticate with Google.
2.  Allow the user to select a Google Sheet.
3.  Read available sheets/tabs.
4.  Detect or map columns/sections.
5.  Show a preview.
6.  Let the user confirm the mapping.
7.  Import transactions.
8.  Report results.

Possible fields:

-   Date
-   Time
-   Amount
-   Type
-   Category
-   Income Source
-   Payment Method
-   Special Event
-   Note

Because the old spreadsheet may not be normalized, build a flexible
import mapping interface rather than assuming one rigid format.

## Import preview

Show:

``` text
Detected transactions: 250
New transactions:       245
Possible duplicates:      3
Invalid rows:             2
```

Never overwrite existing transactions automatically.

Use duplicate detection based on a sensible combination of:

-   Date
-   Time
-   Amount
-   Type
-   Category
-   Payment method
-   Note

Allow the user to review conflicts before final import.

------------------------------------------------------------------------

# 26. Google Sheets Export

Provide:

**Export to Google Sheets**

Allow exporting:

-   All transactions
-   Current month
-   Selected month
-   Entire year
-   Category report
-   Payment report
-   Income report
-   Special Event report

Create a clean Google Sheets structure.

Suggested tabs:

``` text
Transactions
Monthly Summary
Category Summary
Payment Summary
Income Summary
Special Events
```

Transactions columns:

``` text
Transaction ID
Date
Time
Type
Amount
Category
Income Source
Payment Method
Special Event
Note
Created At
Updated At
```

Do not destroy or overwrite the user's original spreadsheet without
explicit confirmation.

------------------------------------------------------------------------

# 27. Backup and Restore

Provide:

``` text
Create Backup
Restore Backup
```

Use a portable JSON backup format.

The backup must include:

-   Transactions
-   Categories
-   Income sources
-   Payment methods
-   Special events
-   Application settings

Restore options:

``` text
Merge with existing data
Replace all existing data
```

Default to Merge.

Require confirmation before Replace All.

------------------------------------------------------------------------

# 28. Theme System

The application must allow the user to change the application theme.

Create:

### Appearance Settings

Options:

``` text
System Default
Light
Dark
```

Also provide an accent-color selector.

Possible accent colors can include:

-   Blue
-   Green
-   Purple
-   Orange
-   Red
-   Teal

The selected theme must persist after restarting the app.

Use Material 3 dynamic theming where appropriate.

Do not hard-code colors throughout widgets.

Use a centralized theme system.

------------------------------------------------------------------------

# 29. Settings Page

Create a comprehensive Settings screen.

Sections:

### Appearance

-   Theme
-   Light/Dark/System
-   Accent color
-   Dynamic color if supported

### Currency

-   INR ₹ by default

### Data

-   Backup
-   Restore
-   Export
-   Import

### Google Sheets

-   Connect account
-   Import
-   Export
-   Disconnect

### Transaction Settings

-   Default payment method
-   Default category if useful
-   Date/time preferences

### Security

If implemented:

-   App lock
-   PIN
-   Biometric authentication

Security features should be optional.

### About

-   App name
-   Version
-   Developer
-   License
-   Privacy information

### Contact Us

------------------------------------------------------------------------

# 30. Contact Us Page

Create a dedicated Contact Us page.

It should contain:

``` text
Contact Us

Have a question, suggestion, or found a problem?

Email:
[configured support email]

Website:
[configured website]

GitHub:
[configured GitHub URL]

Report a Bug
Send Feedback
```

Use configurable contact information.

Do not hard-code personal information directly into multiple screens.

The app should have a central configuration file for:

``` text
supportEmail
websiteUrl
githubUrl
developerName
appName
```

If an email application is available, tapping the email button should
open a mail composer.

If a website is configured, tapping it should open the browser.

If GitHub is configured, open the configured URL.

------------------------------------------------------------------------

# 31. About Page

Create:

``` text
About Expense Tracker
```

Show:

-   Application name
-   Version
-   Build number
-   Developer name
-   Description
-   Technology used
-   Privacy statement
-   Open-source licenses

Use the actual build version from the application configuration rather
than hard-coded text where possible.

------------------------------------------------------------------------

# 32. Privacy

The application should be privacy-focused.

Normal financial data must remain on the device.

Do not send financial data to external servers unless the user
explicitly uses an external feature such as Google Sheets.

Do not add analytics or tracking unless explicitly configured.

Clearly communicate that Google Sheets integration sends data to the
user's selected Google account/sheet.

------------------------------------------------------------------------

# 33. Google Sheets Data Model

There must be **no separate persistent financial database**.

Google Sheets is the source of truth.

## Transactions worksheet

```text
Transaction ID
Date
Time
Type
Amount
Category
Income Source
Payment Method
Special Event
Note
Created At
Updated At
```

## Categories worksheet

```text
Category ID
Category Name
Status
Created At
```

## Income Sources worksheet

```text
Source ID
Source Name
Status
Created At
```

## Payment Methods worksheet

```text
Payment Method ID
Payment Method Name
Status
Created At
```

## Special Events worksheet

```text
Event ID
Event Name
Description
Start Date
End Date
Status
Created At
```

## Report worksheets

```text
Monthly Summary
Category Summary
Payment Summary
Income Summary
Special Events Summary
```

Report worksheets are derived data only.

The `Transactions` worksheet is the authoritative financial source.

## Repository architecture

Use interfaces:

```text
TransactionRepository
CategoryRepository
IncomeSourceRepository
PaymentMethodRepository
SpecialEventRepository
```

Production implementations:

```text
TransactionRepository
        ↓
GoogleSheetsTransactionRepository
        ↓
Google Sheets API
```

Keep the UI independent from Google API implementation details.

# 34. Data Integrity

Important rules:

-   Amount must be greater than zero.
-   Amount must use safe monetary representation.
-   Type must be either Expense or Income.
-   Expense must have a category.
-   Income must have an income source.
-   Payment method is required for expenses.
-   Optional fields may be empty.
-   Deleted transactions must not appear in reports.
-   Archived categories must remain visible in historical transactions.
-   Archived payment methods must remain visible in historical
    transactions.
-   Archived events must remain visible in historical transactions.
-   Event transactions must never be double-counted.
-   Import operations must be transactional.
-   Failed imports must roll back safely.

------------------------------------------------------------------------

# 35. Empty States

Every screen should have a useful empty state.

Example:

``` text
No expenses yet.

Tap + to add your first expense.
```

For reports:

``` text
No transactions found for this period.
```

For events:

``` text
No special events created yet.
Create an event to track trips, birthdays, or other activities.
```

------------------------------------------------------------------------

# 36. Error Handling

Implement user-friendly error messages.

Do not expose raw stack traces to users.

Examples:

``` text
Unable to save transaction.
Please try again.
```

``` text
Google Sheets connection failed.
Check your internet connection and try again.
```

``` text
Import completed with some skipped rows.
Review the import summary.
```

Log useful technical information in debug builds.

Do not log sensitive financial data unnecessarily.

------------------------------------------------------------------------

# 37. Performance

The application should remain responsive with thousands of transactions.

Requirements:

-   Paginate or efficiently load long transaction lists.
-   Use database queries rather than loading everything into memory.
-   Add indexes for frequently searched fields.
-   Avoid recalculating the entire database unnecessarily.
-   Cache appropriate dashboard calculations if required.
-   Use asynchronous database operations.

The UI must never freeze while processing data.

------------------------------------------------------------------------

# 38. Accessibility and UX

Support:

-   Large readable text
-   Adequate contrast
-   Touch-friendly controls
-   Screen-reader labels where appropriate
-   Semantic buttons
-   Keyboard-safe forms
-   Proper form validation
-   Clear error states

Do not rely only on color to communicate Expense vs Income.

------------------------------------------------------------------------

# 39. Android Requirements

Configure:

-   Proper Android application ID/package name
-   App name
-   App icon
-   Splash screen
-   Minimum supported Android version appropriate for modern devices
-   Target latest stable Android SDK available in the build environment

Use a release-ready Android configuration.

The app must be installable as an APK.

------------------------------------------------------------------------

# 40. App Icon and Splash Screen

Create a simple professional finance-related app icon.

Suggested concept:

``` text
Wallet / ₹ / chart / expense tracking
```

Avoid overly complex artwork.

Create a clean splash screen with:

``` text
Expense Tracker
```

and the application icon.

------------------------------------------------------------------------

# 40A. Source-of-Truth Architecture

Financial data flow:

```text
Android App
    ↓
Google OAuth
    ↓
Google Sheets API
    ↓
User's Google Spreadsheet
    ↓
Transactions / Categories / Events / Reports
```

The app may use in-memory state for the current screen/session.

It may use local preferences for:

- Theme
- Accent color
- Last selected month
- UI preferences

However:

**Do NOT create a second persistent database containing the same financial transactions.**

Google Sheets remains authoritative.

A temporary memory cache is allowed for performance, but every financial mutation must synchronize to Google Sheets and stale cached data must be refreshed.

# 41. Project Structure

Use a maintainable structure similar to:

``` text
lib/
├── main.dart
├── app/
│   ├── app.dart
│   ├── routes.dart
│   └── theme/
│       ├── app_theme.dart
│       ├── theme_provider.dart
│       └── colors.dart
│
├── core/
│   ├── constants/
│   ├── utils/
│   ├── errors/
│   └── services/
│
├── database/
│   ├── database.dart
│   ├── tables/
│   └── migrations/
│
├── features/
│   ├── dashboard/
│   ├── transactions/
│   ├── reports/
│   ├── categories/
│   ├── income_sources/
│   ├── payment_methods/
│   ├── special_events/
│   ├── google_sheets/
│   ├── backup/
│   ├── settings/
│   ├── contact/
│   └── about/
│
└── shared/
    ├── widgets/
    ├── models/
    └── components/
```

Adjust the structure if needed, but maintain clear separation of
concerns.

------------------------------------------------------------------------

# 42. Code Quality

Follow:

-   Dart formatting
-   Effective Dart conventions
-   Strong typing
-   Null safety
-   SOLID principles where practical
-   Reusable widgets
-   Dependency injection where useful
-   Repository pattern
-   Clear naming
-   Small maintainable files
-   Meaningful comments only where needed

Do not generate one enormous file.

Do not put database logic directly into UI widgets.

Do not put business calculations directly into presentation code.

------------------------------------------------------------------------

# 43. Testing Requirements

Create automated tests for critical business logic.

At minimum test:

### Transaction calculations

``` text
Income = 10000
Expense = 3000
Balance = 7000
```

### Category totals

Multiple Food transactions must aggregate correctly.

### Monthly totals

Transactions from different months must not be mixed.

### Payment totals

PhonePe, Google Pay, Cash must aggregate independently.

### Event totals

Event transaction must appear in event total without being
double-counted globally.

### Income sources

Salary, Scholarship, Friend, etc. must aggregate correctly.

### Import

Duplicate transactions must be detected.

### Backup

Exported backup must restore the same data.

### Theme

Selected theme must persist after application restart.

------------------------------------------------------------------------

# 44. UI Testing

Test the main user journeys:

## Expense flow

``` text
Open app
→ Add
→ Expense
→ Amount
→ Category
→ Payment method
→ Save
→ Verify dashboard
```

## Income flow

``` text
Open app
→ Add
→ Income
→ Amount
→ Income source
→ Save
→ Verify balance
```

## Event flow

``` text
Create event
→ Add transaction
→ Assign event
→ Open event
→ Verify total
```

## Theme flow

``` text
Settings
→ Appearance
→ Dark
→ Restart app
→ Verify dark theme persists
```

## Backup flow

``` text
Create transactions
→ Backup
→ Clear/test environment
→ Restore
→ Verify data
```

------------------------------------------------------------------------

# 45. Google Sheets Integration Requirements

Do not fake Google Sheets integration.

If credentials/configuration are required, create a clearly documented
setup process.

Use:

-   OAuth
-   Google Sheets API
-   Secure token handling

Do not put secrets in:

``` text
GitHub
Source code
APK
Configuration committed to repository
```

Use environment/configuration mechanisms appropriate for Flutter.

If a complete Google API integration cannot be executed automatically
because credentials must be supplied by the developer, implement the
integration architecture and clearly document the exact remaining setup
steps.

------------------------------------------------------------------------

# 46. Importing the Existing Spreadsheet

The current spreadsheet has a structure similar to:

``` text
March
    Things | Amount

April
    Things | Amount

May
    Things | Amount

June
    Things | Amount

July
    Things | Amount

August
    Things | Amount

September
    Things | Amount

October
    Things | Amount
```

There are also separate sections for special expenses such as:

``` text
Mumbai
Birthday
Pune
Scholarship
Other special expenses
```

The import system must therefore be flexible.

Do not assume every row has a conventional database-style date column.

Provide a mapping/preview step when automatic parsing is uncertain.

------------------------------------------------------------------------

# 47. User Experience for Existing Data

The application should make migration from the spreadsheet easy.

The user should be able to:

``` text
Import Existing Data
        ↓
Preview
        ↓
Fix Mapping
        ↓
Detect Duplicates
        ↓
Confirm
        ↓
Import
```

Never silently discard data.

------------------------------------------------------------------------

# 48. Settings Persistence

Persist:

-   Theme
-   Accent color
-   Currency
-   Preferences
-   Last selected year/month where useful
-   Google Sheets connection state
-   Other app configuration

Use local storage/shared preferences for simple settings.

Use SQLite for structured data.

------------------------------------------------------------------------

# 49. Security

Implement sensible security without making the app difficult to use.

Never:

-   Store passwords in plain text.
-   Log OAuth tokens.
-   Commit API secrets.
-   Upload financial data without user action.

If app lock is implemented, use secure platform storage for
authentication-related secrets.

------------------------------------------------------------------------

# 50. Release Build

The final task is not complete until the project can produce an APK.

Run:

``` bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

If the environment supports it, also build:

``` bash
flutter build appbundle --release
```

Resolve all compilation errors and critical analyzer/test failures.

The release APK should be placed in a clearly documented output
directory.

Example:

``` text
build/app/outputs/flutter-apk/app-release.apk
```

Do not claim that an APK was successfully created unless the build
actually succeeds.

------------------------------------------------------------------------

# 51. Documentation

Create:

``` text
README.md
```

Include:

-   Project overview
-   Features
-   Technology stack
-   Requirements
-   Setup instructions
-   Development commands
-   Database information
-   Google Sheets setup
-   Android build instructions
-   APK location
-   Testing instructions
-   Configuration instructions
-   Troubleshooting
-   Release instructions

Also create:

``` text
ARCHITECTURE.md
```

Document:

-   Architecture
-   Database schema
-   Data flow
-   Google Sheets integration
-   State management
-   Important design decisions

Also create:

``` text
CHANGELOG.md
```

for release changes.

------------------------------------------------------------------------

# 52. Environment Configuration

Create an example configuration file such as:

```text
.env.example
```

Include placeholders/configuration documentation for:

```text
APP_NAME
SUPPORT_EMAIL
WEBSITE_URL
GITHUB_URL
GOOGLE_CLIENT_ID
GOOGLE_CLIENT_ID_ANDROID
GOOGLE_CLIENT_ID_WEB
GOOGLE_PROJECT_ID
```

Never commit actual secrets.

Do not put private Google service-account credentials inside the Android APK.

Use OAuth 2.0 for user-owned Google Sheets access.

Document Google Cloud Console configuration in `README.md`.

# 53. Development Workflow

Follow this implementation order:

## Phase 1 --- Project setup

-   Create Flutter project.
-   Configure Android.
-   Configure Material 3.
-   Configure themes.
-   Configure routing.
-   Configure state management.
-   Configure Google OAuth and the Google Sheets repository/service layer.

## Phase 2 --- Database

Implement:

-   Transactions
-   Categories
-   Income sources
-   Payment methods
-   Special events
-   Settings
-   Migrations

## Phase 3 --- Core transaction functionality

Implement:

-   Add expense
-   Add income
-   Edit
-   Delete
-   Search
-   Filters
-   Validation

## Phase 4 --- Dashboard

Implement:

-   Summary cards
-   Category totals
-   Payment totals
-   Income totals
-   Charts

## Phase 5 --- Reports

Implement:

-   Monthly
-   Yearly
-   Category
-   Payment
-   Income
-   Event
-   Custom date range

## Phase 6 --- Special Events

Implement complete event management.

## Phase 7 --- Settings and customization

Implement:

-   Theme
-   Accent color
-   Currency
-   Preferences
-   About
-   Contact Us

## Phase 8 --- Backup/restore

Implement safe local backup and restore.

## Phase 9 --- Google Sheets

Implement:

-   OAuth
-   Import
-   Mapping
-   Duplicate detection
-   Preview
-   Export

## Phase 10 --- Testing

Run unit, widget, integration, and manual workflow tests.

## Phase 11 --- Release

Build:

``` text
APK
AAB
```

where possible.

------------------------------------------------------------------------

# 54. Acceptance Criteria

The project is considered complete only when all of the following are
true:

### Core

-   [ ] Android app launches successfully.
-   [ ] Expense can be added.
-   [ ] Income can be added.
-   [ ] Date/time are automatically captured.
-   [ ] Date/time can be edited.
-   [ ] Categories work.
-   [ ] Custom categories work.
-   [ ] Payment methods work.
-   [ ] Custom payment methods work.
-   [ ] Income sources work.
-   [ ] Custom income sources work.
-   [ ] Transactions can be edited.
-   [ ] Transactions can be deleted.
-   [ ] Search works.
-   [ ] Filters work.

### Financial calculations

-   [ ] Monthly expense total works.
-   [ ] Monthly income total works.
-   [ ] Balance works.
-   [ ] Yearly total works.
-   [ ] Category totals work.
-   [ ] Payment-method totals work.
-   [ ] Income-source totals work.
-   [ ] Event totals work.
-   [ ] Event transactions are not double-counted.

### Special Events

-   [ ] Events can be created.
-   [ ] Transactions can be assigned to events.
-   [ ] Event totals work.
-   [ ] Event category breakdown works.
-   [ ] Event payment breakdown works.

### Dashboard

-   [ ] Dashboard works offline.
-   [ ] Current-month totals are correct.
-   [ ] Charts work.
-   [ ] Summary cards work.

### Theme

-   [ ] Light mode works.
-   [ ] Dark mode works.
-   [ ] System mode works.
-   [ ] Accent color works.
-   [ ] Theme persists after restart.

### Data

-   [ ] SQLite database works.
-   [ ] Backup works.
-   [ ] Restore works.
-   [ ] Existing data is protected during migration.

### Google Sheets

-   [ ] Google authentication is implemented.
-   [ ] Import is implemented.
-   [ ] Import preview works.
-   [ ] Duplicate detection works.
-   [ ] Export works.
-   [ ] Errors are handled.

### Pages

-   [ ] Home
-   [ ] Transactions
-   [ ] Add Transaction
-   [ ] Reports
-   [ ] Special Expenses
-   [ ] Categories
-   [ ] Payment Methods
-   [ ] Income Sources
-   [ ] Settings
-   [ ] Appearance
-   [ ] Contact Us
-   [ ] About

### Release

-   [ ] `flutter analyze` passes without critical issues.
-   [ ] Tests pass.
-   [ ] Release APK builds successfully.
-   [ ] APK can be installed on an Android device.
-   [ ] README is complete.
-   [ ] Architecture documentation is complete.

------------------------------------------------------------------------

# 55. Important Development Rules

1.  Do not create fake functionality just to make the UI appear
    complete.
2.  Do not use mock data in production screens unless clearly marked as
    sample data.
3.  Use real SQLite persistence.
4.  Do not lose transactions during migrations.
5.  Do not double-count special-event transactions.
6.  Do not store financial amounts using unsafe floating-point
    calculations.
7.  Do not hard-code theme colors throughout the UI.
8.  Do not hard-code support/contact information in multiple files.
9.  Do not hard-code API credentials.
10. Do not silently overwrite Google Sheets.
11. Always validate imported data.
12. Keep the app usable offline.
13. Keep the UI simple and fast.
14. Avoid unnecessary dependencies.
15. Avoid overengineering.
16. Keep business logic testable.
17. Do not mark a feature complete until it has been implemented and
    tested.
18. If an external credential is required, document the exact setup
    rather than pretending it works.
19. Fix build errors before declaring completion.
20. Build the actual APK at the end.

------------------------------------------------------------------------

# 56. Final Deliverables

At the end of the implementation, provide:

``` text
expense_tracker/
├── lib/
├── android/
├── test/
├── integration_test/
├── README.md
├── ARCHITECTURE.md
├── CHANGELOG.md
├── .env.example
└── ...
```

And produce:

``` text
app-release.apk
```

Also report:

-   Build status
-   Test status
-   APK path
-   Package name
-   Version
-   Known limitations
-   Any external configuration still required

The final application should be a functional, offline-first Android
expense tracker rather than a prototype.

------------------------------------------------------------------------

# 57. Final Product Vision

The final app should feel like a simple personal finance notebook that
has replaced the user's spreadsheet.

The primary daily interaction should be:

``` text
+ Add
   ↓
Expense / Income
   ↓
Amount
   ↓
Category / Income Source
   ↓
Payment Method
   ↓
Save
```

Everything else should happen automatically:

``` text
Monthly totals
Category totals
Payment totals
Income totals
Balance
Yearly totals
Charts
Reports
Special Event totals
```

The user should be able to open the app at any time and immediately
understand:

``` text
How much did I spend?
How much did I earn?
How much is left?
Where did I spend it?
How did I pay?
Which month/category/event cost the most?
```

The app should prioritize **speed, correctness, offline reliability,
data safety, customization, and maintainability**.
