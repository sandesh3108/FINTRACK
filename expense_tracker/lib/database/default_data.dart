/// Rows seeded into a brand new database.
///
/// Everything here is editable and archivable from the app; these are only
/// the starting values described in the specification.
library;

/// Expense categories shipped with a fresh install.
const List<String> defaultCategories = <String>[
  'Food',
  'Petrol/Fuel',
  'Travel',
  'Shopping',
  'Groceries',
  'Medical',
  'Education',
  'Mobile Recharge',
  'Internet',
  'Electricity',
  'Rent',
  'Entertainment',
  'Vehicle',
  'Vehicle Maintenance',
  'Clothing',
  'Personal',
  'Restaurant',
  'Snacks',
  'Bills',
  'Subscription',
  'Gifts',
  'Household',
  'Fitness',
  'Electronics',
  'Other',
];

/// Income sources shipped with a fresh install.
const List<String> defaultIncomeSources = <String>[
  'Salary',
  'From Home',
  'Scholarship',
  'Friend',
  'Other',
];

/// Payment methods shipped with a fresh install.
///
/// These double as the four *accounts* the balance feature reports on, so the
/// names are deliberate rather than illustrative. New ones can still be added
/// from the transaction form's "Other..." option or the manage screen.
const List<String> defaultPaymentMethods = <String>[
  'PhonePe',
  'Google Pay',
  'Cash',
  'BOI(Saving)',
];

/// Seed inserted before the first frame so the Add screen is never empty.
class SeedData {
  const SeedData._();

  static const String defaultThemeMode = 'system';
  static const String defaultAccent = 'blue';
}
