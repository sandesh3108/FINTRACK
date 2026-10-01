import 'package:drift/drift.dart';

import '../../database/database.dart';
import '../../shared/models/app_settings.dart';
import '../settings_repository.dart';

/// SQLite implementation of [SettingsRepository] backed by key/value rows.
class DriftSettingsRepository implements SettingsRepository {
  DriftSettingsRepository(this._db);

  final AppDatabase _db;

  static const String _kCurrencySymbol = 'currency_symbol';
  static const String _kCurrencyCode = 'currency_code';
  static const String _kDefaultPaymentMethod = 'default_payment_method_id';
  static const String _kDefaultCategory = 'default_category_id';
  static const String _kSheetId = 'google_spreadsheet_id';
  static const String _kSheetTitle = 'google_spreadsheet_title';
  static const String _kSheetEmail = 'google_account_email';
  static const String _kLastSync = 'google_last_sync';
  static const String _kGoogleAndroidId = 'google_client_id_android';
  static const String _kGoogleWebId = 'google_client_id_web';
  static const String _kGoogleProjectId = 'google_project_id';
  static const String _kBalancePinHash = 'balance_pin_hash';
  static const String _kBalancePinSalt = 'balance_pin_salt';

  @override
  Future<AppSettings> load() async {
    final rows = await _db.select(_db.settings).get();
    final values = {for (final row in rows) row.key: row.value};
    return _fromMap(values);
  }

  @override
  Stream<AppSettings> watch() => _db.select(_db.settings).watch().map(
        (rows) => _fromMap({for (final row in rows) row.key: row.value}),
      );

  @override
  Future<void> save(AppSettings settings) => _putAll(_toMap(settings));

  @override
  Future<void> linkSheet({
    required String spreadsheetId,
    required String title,
    required String accountEmail,
  }) =>
      _putAll({
        _kSheetId: spreadsheetId,
        _kSheetTitle: title,
        _kSheetEmail: accountEmail,
      });

  @override
  Future<void> unlinkSheet() => _putAll({
        _kSheetId: '',
        _kSheetTitle: '',
        _kSheetEmail: '',
        _kLastSync: '',
      });

  @override
  Future<void> markSynced(DateTime when) => _put(_kLastSync, when.toIso8601String());

  Map<String, String> _toMap(AppSettings s) => {
        _kCurrencySymbol: s.currencySymbol,
        _kCurrencyCode: s.currencyCode,
        _kDefaultPaymentMethod: s.defaultPaymentMethodId?.toString() ?? '',
        _kDefaultCategory: s.defaultCategoryId?.toString() ?? '',
        _kSheetId: s.googleSpreadsheetId,
        _kSheetTitle: s.googleSpreadsheetTitle,
        _kSheetEmail: s.googleAccountEmail,
        _kLastSync: s.lastSyncAt?.toIso8601String() ?? '',
        _kGoogleAndroidId: s.googleClientIdAndroid,
        _kGoogleWebId: s.googleClientIdWeb,
        _kGoogleProjectId: s.googleProjectId,
        _kBalancePinHash: s.balancePinHash,
        _kBalancePinSalt: s.balancePinSalt,
      };

  AppSettings _fromMap(Map<String, String> values) => AppSettings(
        currencySymbol: values[_kCurrencySymbol] ?? AppSettings().currencySymbol,
        currencyCode: values[_kCurrencyCode] ?? AppSettings().currencyCode,
        defaultPaymentMethodId: _toInt(values[_kDefaultPaymentMethod]),
        defaultCategoryId: _toInt(values[_kDefaultCategory]),
        googleSpreadsheetId: values[_kSheetId] ?? '',
        googleSpreadsheetTitle: values[_kSheetTitle] ?? '',
        googleAccountEmail: values[_kSheetEmail] ?? '',
        lastSyncAt: DateTime.tryParse(values[_kLastSync] ?? ''),
        googleClientIdAndroid: values[_kGoogleAndroidId] ?? '',
        googleClientIdWeb: values[_kGoogleWebId] ?? '',
        googleProjectId: values[_kGoogleProjectId] ?? '',
        balancePinHash: values[_kBalancePinHash] ?? '',
        balancePinSalt: values[_kBalancePinSalt] ?? '',
      );

  static int? _toInt(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    return int.tryParse(raw.trim());
  }

  Future<void> _putAll(Map<String, String> values) async {
    for (final entry in values.entries) {
      await _put(entry.key, entry.value);
    }
  }

  Future<void> _put(String key, String value) async {
    await _db.into(_db.settings).insert(
          SettingsCompanion.insert(key: key, value: Value(value)),
          mode: InsertMode.insertOrReplace,
        );
  }
}
