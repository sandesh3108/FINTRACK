import 'dart:convert';

import '../../core/errors/app_exception.dart';
import '../../core/utils/date_utils.dart';
import '../../shared/models/app_settings.dart';
import '../../shared/models/catalog_item.dart';
import '../../shared/models/special_event.dart';
import '../../shared/models/transaction_filter.dart';
import '../../shared/models/transaction_input.dart';
import '../../shared/models/tx_item.dart';
import '../../shared/models/tx_type.dart';
import '../../shared/models/validation.dart';
import '../core/backup/backup_formats.dart';
import 'catalog_repository.dart';
import 'event_repository.dart';
import 'settings_repository.dart';
import 'transaction_repository.dart';

/// How a restore should treat rows that already exist.
enum BackupRestoreMode {
  /// Default: add anything missing, leave existing rows untouched.
  merge,

  /// Wipe everything and reload the backup. Requires explicit confirmation.
  replace,
}

/// Result of reading a backup file before anything is written.
class BackupPreview {
  const BackupPreview({
    required this.version,
    required this.createdAt,
    required this.transactions,
    required this.categories,
    required this.incomeSources,
    required this.paymentMethods,
    required this.specialEvents,
    required this.hasSettings,
  });

  final int version;
  final String createdAt;
  final int transactions;
  final int categories;
  final int incomeSources;
  final int paymentMethods;
  final int specialEvents;
  final bool hasSettings;

  int get totalRows =>
      transactions + categories + incomeSources + paymentMethods + specialEvents;
}

/// Serialises the whole application state to a portable JSON document and
/// restores it again.
///
/// The format is versioned and human-readable so it can be parsed by other
/// tools if this app is ever replaced.
class BackupRepository {
  BackupRepository({
    required this.transactions,
    required this.catalog,
    required this.events,
    required this.settings,
  });

  /// Version of the document layout this build writes and understands.
  ///
  /// Declared in `core/backup` so the CSV and XLSX readers emit the same
  /// value without importing this repository.
  static const int formatVersion = backupFormatVersion;

  /// Marker every backup document carries, so files from other tools are
  /// rejected instead of half-restored.
  static const String documentType = backupDocumentType;

  final TransactionRepository transactions;
  final CatalogRepository catalog;
  final EventRepository events;
  final SettingsRepository settings;

  // ---------------------------------------------------------------- create

  /// Builds the complete backup document.
  ///
  /// Reads are deliberately done through the repositories so a future backend
  /// swap needs no change here.
  Future<Map<String, dynamic>> createBackup() async {
    final allTransactions = await transactions.getTransactions(
      const TransactionFilter(pageSize: 1000000),
    );

    final categories = await catalog.getAll(CatalogKind.category);
    final incomeSources = await catalog.getAll(CatalogKind.incomeSource);
    final paymentMethods = await catalog.getAll(CatalogKind.paymentMethod);
    final specialEvents = await events.getAll(includeArchived: true);
    final appSettings = await settings.load();

    return <String, dynamic>{
      'documentType': documentType,
      'version': formatVersion,
      'createdAt': DateTime.now().toIso8601String(),
      'app': 'expense_tracker',
      'settings': _settingsToJson(appSettings),
      'categories': [for (final item in categories) _catalogToJson(item)],
      'incomeSources': [for (final item in incomeSources) _catalogToJson(item)],
      'paymentMethods': [
        for (final item in paymentMethods)
          _catalogToJson(item, includeOpeningBalance: true),
      ],
      'specialEvents': [for (final event in specialEvents) _eventToJson(event)],
      'transactions': [for (final item in allTransactions) _transactionToJson(item)],
    };
  }

  /// Pretty-printed JSON ready to be written to a file or shared.
  Future<String> createBackupJson() async {
    final backup = await createBackup();
    return const JsonEncoder.withIndent('  ').convert(backup);
  }

  // ---------------------------------------------------------------- restore

  /// Validates the JSON text of a backup file without writing anything.
  BackupPreview preview(String json) => previewDocument(decodeDocument(json));

  /// Applies a backup described by JSON text.
  ///
  /// Catalog rows are resolved by name and created when missing, so a backup
  /// from a different device restores cleanly. Duplicate transactions are
  /// detected by the same key the importer uses and are never overwritten.
  Future<MergeReport> restore(
    String json, {
    required BackupRestoreMode mode,
  }) async =>
      restoreDocument(decodeDocument(json), mode: mode);

  /// Reads and validates the JSON text of a backup file.
  ///
  /// CSV and XLSX imports never come through here: they are turned into the
  /// same document shape by `BackupFormats` and handed straight to
  /// [previewDocument] / [restoreDocument].
  Map<String, dynamic> decodeDocument(String json) {
    Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (error) {
      throw AppException(
        'That file is not a valid backup.',
        technical: error.toString(),
      );
    }
    if (decoded is! Map) {
      throw const AppException('That file is not a valid backup.');
    }
    if (decoded['documentType'] != documentType) {
      throw const AppException(
        'That file was not created by this app.',
      );
    }
    return Map<String, dynamic>.from(decoded);
  }

  /// Validates a backup document without writing anything.
  BackupPreview previewDocument(Map<String, dynamic> document) {
    final version = _readInt(document['version']) ?? 0;
    if (version < 1 || version > formatVersion) {
      throw AppException(
        'This file was created by an unsupported version of the app.',
        technical: 'backup version $version',
      );
    }

    return BackupPreview(
      version: version,
      createdAt: document['createdAt']?.toString() ?? '',
      transactions: _length(document['transactions']),
      categories: _length(document['categories']),
      incomeSources: _length(document['incomeSources']),
      paymentMethods: _length(document['paymentMethods']),
      specialEvents: _length(document['specialEvents']),
      hasSettings: document['settings'] is Map,
    );
  }

  /// Applies a backup.
  ///
  /// Catalog rows are resolved by name and created when missing, so a backup
  /// from a different device restores cleanly. Duplicate transactions are
  /// detected by the same key the importer uses and are never overwritten.
  Future<MergeReport> restoreDocument(
    Map<String, dynamic> document, {
    required BackupRestoreMode mode,
  }) async {
    previewDocument(document);

    if (mode == BackupRestoreMode.replace) {
      // Order matters: transactions first (they reference the catalogs), then
      // the catalogs themselves, then everything is rebuilt from the backup.
      await transactions.removeAll(await _allTransactionIds());
      await catalog.clear(CatalogKind.category);
      await catalog.clear(CatalogKind.incomeSource);
      await catalog.clear(CatalogKind.paymentMethod);
      await events.clear();

      final names = await _ensureCatalog(document);
      final drafts = await _readTransactions(document, names);
      final report = await transactions.importTransactions(drafts, skipDuplicates: false);
      await _restoreSettings(document);
      return report;
    }

    final names = await _ensureCatalog(document);
    final drafts = await _readTransactions(document, names);
    final report = await transactions.importTransactions(drafts, skipDuplicates: true);
    await _restoreSettings(document);
    return report;
  }

  Future<void> _restoreSettings(Map<String, dynamic> document) async {
    final settingsMap = document['settings'];
    if (settingsMap is Map) {
      await settings.save(_settingsFromJson(settingsMap));
    }
  }

  Future<List<int>> _allTransactionIds() async {
    final rows = await transactions.getTransactions(
      const TransactionFilter(pageSize: 1000000),
    );
    return [for (final row in rows) row.id];
  }

  /// Creates any missing catalog rows / events and returns the name -> id maps
  /// needed to rebuild foreign keys.
  Future<_NameMaps> _ensureCatalog(
    Map<String, dynamic> document,
  ) async {
    final categoryEntries = _nameMap(document['categories']);
    final sourceEntries = _nameMap(document['incomeSources']);
    final methodEntries = _nameMap(document['paymentMethods']);
    final eventEntries = _nameMap(document['specialEvents']);

    final resolvedCategories = <String, int>{};
    for (final name in categoryEntries.keys) {
      resolvedCategories[name] = await catalog.findOrCreate(CatalogKind.category, name);
    }

    final resolvedSources = <String, int>{};
    for (final name in sourceEntries.keys) {
      resolvedSources[name] = await catalog.findOrCreate(CatalogKind.incomeSource, name);
    }

    // Taken before any row is created, so "was it me who made this?" is
    // answerable below.
    final existingMethodIds = <int>{
      for (final item in await catalog.getAll(CatalogKind.paymentMethod)) item.id,
    };

    final resolvedMethods = <String, int>{};
    for (final entry in methodEntries.entries) {
      final id = await catalog.findOrCreate(CatalogKind.paymentMethod, entry.key);
      resolvedMethods[entry.key] = id;

      // Carry an account's opening balance across only when this restore is
      // what created the row: a merge must never rewrite a balance the device
      // already has, while a replace has just cleared the table, so there
      // every account is new and gets its saved figure back.
      if (existingMethodIds.contains(id)) continue;
      final opening = _readInt(entry.value['openingBalance']);
      if (opening != null && opening != 0) {
        await catalog.setOpeningBalance(CatalogKind.paymentMethod, id, opening);
      }
    }

    final resolvedEvents = <String, int>{};
    for (final entry in eventEntries.entries) {
      final raw = entry.value;
      final start = DateTime.tryParse(raw['startDate']?.toString() ?? '') ?? DateTime.now();
      final end = DateTime.tryParse(raw['endDate']?.toString() ?? '');
      resolvedEvents[entry.key] = await events.findOrCreate(
        entry.key,
        startDate: start,
        endDate: end,
      );
    }

    return _NameMaps(
      categories: resolvedCategories,
      incomeSources: resolvedSources,
      paymentMethods: resolvedMethods,
      events: resolvedEvents,
    );
  }

  Future<List<TransactionInput>> _readTransactions(
    Map<String, dynamic> document,
    _NameMaps names,
  ) async {
    final raw = document['transactions'];
    if (raw is! List) return const [];

    final drafts = <TransactionInput>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final map = Map<String, dynamic>.from(entry);

      final amount = _readInt(map['amount']);
      final type = TxType.tryParse(map['type']?.toString());
      final date = DateTime.tryParse(map['date']?.toString() ?? '');
      final time = AppDates.tryParseTime(map['time']?.toString() ?? '') ??
          AppDates.timeFrom(DateTime.now());

      if (amount == null || amount <= 0 || type == null || date == null) continue;

      drafts.add(
        TransactionInput(
          type: type,
          amountMinor: amount,
          date: AppDates.day(date),
          time: time,
          categoryId: names.resolve(map['category']?.toString(), names.categories),
          incomeSourceId: names.resolve(map['incomeSource']?.toString(), names.incomeSources),
          paymentMethodId: names.resolve(map['paymentMethod']?.toString(), names.paymentMethods),
          specialEventId: names.resolve(map['specialEvent']?.toString(), names.events),
          note: map['note']?.toString() ?? '',
        ),
      );
    }
    return drafts;
  }

  // --------------------------------------------------------------- helpers

  Map<String, dynamic> _settingsToJson(AppSettings s) => {
        'currencySymbol': s.currencySymbol,
        'currencyCode': s.currencyCode,
        'defaultCategoryId': s.defaultCategoryId,
        'defaultPaymentMethodId': s.defaultPaymentMethodId,
        'googleSpreadsheetId': s.googleSpreadsheetId,
        'googleSpreadsheetTitle': s.googleSpreadsheetTitle,
        'googleAccountEmail': s.googleAccountEmail,
        'lastSyncAt': s.lastSyncAt?.toIso8601String(),
        'googleClientIdAndroid': s.googleClientIdAndroid,
        'googleClientIdWeb': s.googleClientIdWeb,
        'googleProjectId': s.googleProjectId,
        // A salted hash, never the PIN itself. It travels so a restored device
        // keeps the lock the user asked for instead of silently losing it -
        // and the file already holds the whole ledger in clear text anyway.
        'balancePinHash': s.balancePinHash,
        'balancePinSalt': s.balancePinSalt,
      };

  AppSettings _settingsFromJson(Map<dynamic, dynamic> map) => AppSettings(
        currencySymbol: map['currencySymbol']?.toString() ?? AppSettings().currencySymbol,
        currencyCode: map['currencyCode']?.toString() ?? AppSettings().currencyCode,
        defaultCategoryId: _readInt(map['defaultCategoryId']),
        defaultPaymentMethodId: _readInt(map['defaultPaymentMethodId']),
        googleSpreadsheetId: map['googleSpreadsheetId']?.toString() ?? '',
        googleSpreadsheetTitle: map['googleSpreadsheetTitle']?.toString() ?? '',
        googleAccountEmail: map['googleAccountEmail']?.toString() ?? '',
        lastSyncAt: DateTime.tryParse(map['lastSyncAt']?.toString() ?? ''),
        googleClientIdAndroid: map['googleClientIdAndroid']?.toString() ?? '',
        googleClientIdWeb: map['googleClientIdWeb']?.toString() ?? '',
        googleProjectId: map['googleProjectId']?.toString() ?? '',
        balancePinHash: map['balancePinHash']?.toString() ?? '',
        balancePinSalt: map['balancePinSalt']?.toString() ?? '',
      );

  Map<String, dynamic> _catalogToJson(
    CatalogItem item, {
    bool includeOpeningBalance = false,
  }) =>
      {
        'id': item.id,
        'name': item.name,
        'isDefault': item.isDefault,
        'isActive': item.isActive,
        'createdAt': item.createdAt.toIso8601String(),
        'updatedAt': item.updatedAt.toIso8601String(),
        // Only payment methods are accounts, so only they carry a balance.
        if (includeOpeningBalance) 'openingBalance': item.openingBalanceMinor,
      };

  Map<String, dynamic> _eventToJson(SpecialEvent event) => {
        'id': event.id,
        'name': event.name,
        'description': event.description,
        'startDate': AppDates.isoDay(event.startDate),
        'endDate': event.endDate == null ? null : AppDates.isoDay(event.endDate!),
        'isArchived': event.isArchived,
        'createdAt': event.createdAt.toIso8601String(),
        'updatedAt': event.updatedAt.toIso8601String(),
      };

  Map<String, dynamic> _transactionToJson(TxItem item) => <String, dynamic>{
        'id': item.id,
        'type': item.type.dbValue,
        'amount': item.amountMinor,
        'date': AppDates.isoDay(item.date),
        'time': item.time,
        'category': item.categoryName,
        'incomeSource': item.incomeSourceName,
        'paymentMethod': item.paymentMethodName,
        'specialEvent': item.specialEventName,
        'note': item.note,
        'createdAt': item.createdAt.toIso8601String(),
        'updatedAt': item.updatedAt.toIso8601String(),
      };

  Map<String, dynamic> _nameMap(dynamic raw) {
    if (raw is! List) return <String, dynamic>{};
    final result = <String, dynamic>{};
    for (final entry in raw) {
      if (entry is! Map) continue;
      final name = entry['name']?.toString().trim() ?? '';
      if (name.isEmpty) continue;
      result[name] = entry;
    }
    return result;
  }

  static int? _readInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }

  static int _length(dynamic value) => value is List ? value.length : 0;
}

class _NameMaps {
  const _NameMaps({
    required this.categories,
    required this.incomeSources,
    required this.paymentMethods,
    required this.events,
  });

  final Map<String, int> categories;
  final Map<String, int> incomeSources;
  final Map<String, int> paymentMethods;
  final Map<String, int> events;

  int? resolve(String? name, Map<String, int> map) {
    if (name == null || name.trim().isEmpty) return null;
    final normalized = name.trim().toLowerCase();
    for (final entry in map.entries) {
      if (entry.key.toLowerCase() == normalized) return entry.value;
    }
    return null;
  }
}
