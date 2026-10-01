import 'package:drift/drift.dart';

/// Expense categories.
///
/// Archived rows (`isActive == false`) stay visible on historical
/// transactions; they simply disappear from pickers.
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text().withLength(min: 1, max: 80)();

  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Income sources such as Salary, From Home, Scholarship.
class IncomeSources extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text().withLength(min: 1, max: 80)();

  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Payment methods such as PhonePe, Google Pay, Cash.
///
/// A payment method doubles as the user's *account*: the opening balance below
/// is what they type the first time they set the account up, and the app then
/// derives the remaining balance from every transaction recorded against it.
class PaymentMethods extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text().withLength(min: 1, max: 80)();

  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// Starting balance in minor units (paise), captured once per account.
  ///
  /// `0` means "not set up yet", which is indistinguishable from an account
  /// that genuinely started at zero - both are correct, so no sentinel is used.
  IntColumn get openingBalance =>
      integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Special expense / event groupings such as `Mumbai Trip` or `Birthday`.
class SpecialEvents extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text().withLength(min: 1, max: 120)();

  TextColumn get description => text().withDefault(const Constant(''))();

  DateTimeColumn get startDate => dateTime()();

  DateTimeColumn get endDate => dateTime().nullable()();

  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// The single financial ledger.
///
/// * `amount` is an integer of **minor units** (paise) - never a float.
/// * `date` is the calendar day (local midnight); `time` is `HH:mm`.
/// * Event membership is a foreign key, so an event transaction is a single
///   row that is simply *tagged* - it can never be counted twice.
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// `expense` or `income`.
  TextColumn get type => text()();

  /// Minor units (paise). Always > 0.
  IntColumn get amount => integer()();

  DateTimeColumn get date => dateTime()();

  /// `HH:mm`.
  TextColumn get time => text().withLength(min: 5, max: 5)();

  IntColumn get categoryId =>
      integer().nullable().references(Categories, #id, onDelete: KeyAction.setNull)();

  IntColumn get incomeSourceId =>
      integer().nullable().references(IncomeSources, #id, onDelete: KeyAction.setNull)();

  IntColumn get paymentMethodId =>
      integer().nullable().references(PaymentMethods, #id, onDelete: KeyAction.setNull)();

  IntColumn get specialEventId =>
      integer().nullable().references(SpecialEvents, #id, onDelete: KeyAction.setNull)();

  TextColumn get note => text().withDefault(const Constant(''))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Durable application configuration that travels with backups
/// (theme and other transient UI preferences live in `shared_preferences`).
class Settings extends Table {
  TextColumn get key => text()();

  TextColumn get value => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {key};
}
