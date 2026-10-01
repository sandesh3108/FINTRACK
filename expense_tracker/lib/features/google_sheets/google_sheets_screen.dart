import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/routes.dart';
import '../../app/state/app_identity.dart';
import '../../core/config/app_config.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../repositories/providers.dart';
import '../../services/google_auth_service.dart';
import '../../services/google_drive_service.dart';
import '../../services/google_sheets_service.dart';
import '../../shared/models/app_settings.dart';
import '../../shared/models/catalog_item.dart';
import '../../shared/models/transaction_filter.dart';
import '../../shared/models/transaction_input.dart';
import '../../shared/models/tx_item.dart';
import '../../shared/models/tx_type.dart';
import '../../shared/models/validation.dart';
import '../../shared/widgets/common.dart';

/// The columns this app understands when reading a sheet.
enum _Field {
  date('Date'),
  time('Time'),
  type('Type'),
  amount('Amount'),
  category('Category'),
  incomeSource('Income source'),
  paymentMethod('Payment method'),
  event('Event'),
  note('Note');

  const _Field(this.label);
  final String label;
}

/// Header spellings that mean the same thing as a [_Field].
///
/// People name columns slightly differently, so matching only the exact label
/// would force everyone to rename their sheet first.
const Map<_Field, List<String>> _aliases = <_Field, List<String>>{
  _Field.date: <String>['date', 'day', 'transaction date'],
  _Field.time: <String>['time', 'at'],
  _Field.type: <String>['type', 'kind', 'income or expense'],
  _Field.amount: <String>['amount', 'value', 'amt', 'total'],
  _Field.category: <String>['category', 'head', 'expense category'],
  _Field.incomeSource: <String>['income source', 'source', 'salary source'],
  _Field.paymentMethod: <String>['payment method', 'payment', 'method', 'paid by'],
  _Field.event: <String>['event', 'special event', 'occasion'],
  _Field.note: <String>['note', 'notes', 'description', 'remarks', 'details'],
};

/// One sheet row after parsing: either a usable input, or the reason it is not
/// usable.
class _Candidate {
  const _Candidate.ok({
    required this.input,
    this.category = '',
    this.incomeSource = '',
    this.paymentMethod = '',
    this.event = '',
  }) : problem = null;

  const _Candidate.skipped(this.problem)
      : input = null,
        category = '',
        incomeSource = '',
        paymentMethod = '',
        event = '';

  final TransactionInput? input;
  final String? problem;
  final String category;
  final String incomeSource;
  final String paymentMethod;
  final String event;

  bool get isOk => input != null;
}

/// Connects the app to Google, links a spreadsheet, and moves rows both ways.
///
/// The whole feature is opt-in: nothing here runs unless the user presses a
/// button, and the import is a four-step flow (fetch → map → preview →
/// import) so a wrong mapping is visible before anything is written.
/// One line of the *Check connection* report.
///
/// Kept as a value rather than built in the widget so the whole report can be
/// assembled in one pass and rendered in the order the steps were run.
class _Check {
  const _Check(this.label, this.ok, this.detail);

  /// What is being verified.
  final String label;

  /// Whether it passed.
  final bool ok;

  /// The evidence, or the fix when [ok] is false.
  final String detail;
}

class GoogleSheetsScreen extends ConsumerStatefulWidget {
  const GoogleSheetsScreen({super.key});

  @override
  ConsumerState<GoogleSheetsScreen> createState() => _GoogleSheetsScreenState();
}

class _GoogleSheetsScreenState extends ConsumerState<GoogleSheetsScreen> {
  final TextEditingController _linkController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Seeded from the renameable name rather than a literal, so a new sheet
    // is offered under whatever the app currently calls itself.
    _titleController.text = ref.read(appNameProvider);
  }

  /// Label of the operation currently running, or `null` when idle.
  String? _busy;
  String? _error;

  /// Google's own wording behind [_error], shown under the friendly sentence
  /// so a failure can be read back verbatim instead of guessed at.
  String? _errorDetail;
  String? _note;

  /// Result of the last *Check connection*, or `null` when none has run.
  List<_Check>? _checks;

  /// Spreadsheets the Drive search found, waiting to be linked.
  List<SheetReference> _found = const <SheetReference>[];

  bool _fetched = false;
  List<String> _headers = const <String>[];
  List<List<String>> _rows = const <List<String>>[];
  Map<_Field, int> _mapping = const <_Field, int>{};
  List<_Candidate> _parsed = const <_Candidate>[];
  int _duplicates = 0;
  MergeReport? _report;

  @override
  void dispose() {
    _linkController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ helpers

  GoogleSheetsService _service(String token) =>
      GoogleSheetsService(accessToken: token);

  /// Whether sign-in is allowed right now: the client ids saved under
  /// *Settings → Google Sheets setup*, falling back to the build-time
  /// `--dart-define` values only while the settings stream has not produced
  /// anything yet.
  ///
  /// Read at the moment an action runs (not in [build]) so the gate follows
  /// an id saved on the setup screen without a rebuild.
  bool get _configured =>
      ref.read(settingsProvider).valueOrNull?.hasGoogleConfig ??
      AppConfig.hasGoogleCredentials;

  /// Runs [action] behind a busy label, turning any failure into one sentence
  /// the user can act on instead of an unhandled exception.
  Future<void> _run(String label, Future<void> Function() action) async {
    if (_busy != null) return;
    setState(() {
      _busy = label;
      _error = null;
      _errorDetail = null;
      _note = null;
    });
    try {
      await action();
      if (mounted) setState(() => _busy = null);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = null;
          _error = friendlyMessage(error);
          _errorDetail = _detailOf(error);
        });
      }
    }
  }

  /// The raw platform or Google wording behind [error], when there is one.
  ///
  /// It never replaces the friendly sentence above it: it sits underneath so
  /// the actual refusal can be searched, pasted or reported rather than being
  /// summarised into something that could apply to four different failures.
  static String? _detailOf(Object error) {
    if (error is AppException) return error.technical;
    if (error is PlatformException) {
      return '${error.code}${error.message == null ? '' : ': ${error.message}'}';
    }
    return null;
  }

  void _say(String message) {
    if (mounted) setState(() => _note = message);
  }

  // ------------------------------------------------------------- operations

  /// Verifies the connection one step at a time and shows which step broke.
  ///
  /// "Unable to connect" covers four unrelated failures - no ids saved, nobody
  /// signed in, a token Google will not mint, and an API that is switched off -
  /// and each has its own fix. Running them in order and stopping at the first
  /// failure turns one vague sentence into a specific one.
  Future<void> _check() => _run('Checking…', () async {
        final results = <_Check>[];

        // 1. Are there ids to sign in with at all?
        final settings = ref.read(settingsProvider).valueOrNull;
        if (settings == null || !settings.hasGoogleConfig) {
          results.add(const _Check(
            'OAuth client ids',
            false,
            'None found. Open Google Sheets setup and paste your Android '
            'client id - without it nothing can reach Google.',
          ));
          setState(() => _checks = results);
          return;
        }
        final saved = settings.googleClientIdAndroid.isNotEmpty ||
            settings.googleClientIdWeb.isNotEmpty;
        results.add(_Check(
          'OAuth client ids',
          true,
          saved
              ? 'Saved under Settings → Google Sheets setup.'
              : 'Baked into this build with --dart-define.',
        ));

        // 2. Is anybody signed in?
        final email = GoogleAuthService.signedInEmail;
        if (email == null) {
          results.add(const _Check(
            'Google account',
            false,
            'Not connected yet. Tap Connect Google account.',
          ));
          setState(() => _checks = results);
          return;
        }
        results.add(_Check('Google account', true, 'Connected as $email.'));

        // 3. Will Google mint a token for this account?
        String token;
        try {
          token = await GoogleAuthService.requireAccessToken(configured: true);
          results.add(const _Check(
            'Access token',
            true,
            'Google issued one for this account.',
          ));
        } catch (error) {
          results.add(_Check('Access token', false, friendlyMessage(error)));
          setState(() => _checks = results);
          return;
        }

        // 4. Does Google answer for the Sheets API?
        //
        // With a sheet linked the real one is read, which also proves this
        // account may open it. Without one, a request for an id that cannot
        // exist does the same job while writing nothing: any answer at all -
        // even "not found" - means the device is online, the token was
        // accepted and the API is enabled.
        try {
          final linked = ref.read(settingsProvider).valueOrNull;
          if (linked != null && linked.hasLinkedSheet) {
            final sheet =
                await _service(token).open(linked.googleSpreadsheetId);
            results.add(_Check(
              'Google Sheets',
              true,
              'Reached “${sheet.title}” - read access to your sheet works.',
            ));
          } else {
            await _service(token).probe();
            results.add(const _Check(
              'Google Sheets',
              true,
              'Google answered: the API is enabled and this token is '
              'accepted. Nothing was written.',
            ));
          }
        } catch (error) {
          results.add(_Check('Google Sheets', false, friendlyMessage(error)));
        }

        setState(() => _checks = results);
      });

  Future<void> _connect() => _run('Signing in…', () async {
        final account =
            await GoogleAuthService.signIn(configured: _configured);
        if (account == null) {
          _say('Sign-in was cancelled.');
          return;
        }
        _say('Signed in as ${account.email}.');
      });

  Future<void> _disconnect() => _run('Signing out…', () async {
        await GoogleAuthService.disconnect();
        setState(() => _found = const <SheetReference>[]);
        _say('Google account disconnected.');
      });

  /// Hands the phone over to somebody else's Google account.
  ///
  /// [GoogleAuthService.switchAccount] signs out first, which is what forces
  /// Play Services to show its account chooser - `google_sign_in` otherwise
  /// returns the account that is already authorised. Backing out of that
  /// chooser leaves us disconnected rather than as we were, so it is reported
  /// as a plain note and not as a failure.
  Future<void> _switchAccount() => _run('Switching account…', () async {
        final account =
            await GoogleAuthService.switchAccount(configured: _configured);
        if (account == null) {
          _say('No other account was chosen.');
          return;
        }
        _say('Now connected as ${account.email}.');
      });

  Future<void> _create() => _run('Creating…', () async {
        final token =
            await GoogleAuthService.requireAccessToken(configured: _configured);
        final name = _titleController.text.trim().isEmpty
            ? ref.read(appNameProvider)
            : _titleController.text.trim();
        final sheet = await _service(token).createSpreadsheet(name);
        await _service(token).writeHeader(sheet.id);

        await ref.read(settingsRepositoryProvider).linkSheet(
              spreadsheetId: sheet.id,
              title: sheet.title,
              accountEmail: GoogleAuthService.signedInEmail ?? '',
            );
        _resetImport();
        _say('Created “${sheet.title}”.');
      });

  Future<void> _link() => _run('Linking…', () async {
        final id = SheetReference.idFrom(_linkController.text);
        if (id == null) {
          throw const ValidationException(
            'Paste a Google Sheets link, or the spreadsheet id.',
            field: 'link',
          );
        }
        final token =
            await GoogleAuthService.requireAccessToken(configured: _configured);
        final sheet = await _service(token).open(id);

        await ref.read(settingsRepositoryProvider).linkSheet(
              spreadsheetId: sheet.id,
              title: sheet.title,
              accountEmail: GoogleAuthService.signedInEmail ?? '',
            );
        _linkController.clear();
        _resetImport();
        _say('Linked “${sheet.title}”.');
        // A pasted link is the restore path after a reinstall, so the rows are
        // pulled straight away instead of waiting to be asked for them.
        _fetchAfterLink(sheet.id);
      });

  /// Searches the connected account for a spreadsheet this app wrote before
  /// the app was deleted, or on another phone.
  ///
  /// The Sheets API can open a sheet by id but cannot list them, so this is
  /// the only thing that can work out *which* sheet to open once the local
  /// database - and with it the remembered id - is gone.
  Future<void> _find() => _run('Searching your Drive…', () async {
        final token = await GoogleAuthService.requireDiscoveryToken(
          configured: _configured,
        );
        final found =
            await GoogleDriveService(accessToken: token).findSpreadsheets();
        setState(() => _found = found);
        if (found.isEmpty) {
          _say('No spreadsheet was found in this Google account.');
        } else {
          _say('Found ${found.length} spreadsheet'
              '${found.length == 1 ? '' : 's'}. Tap the one that holds your '
              'history to link it and import it.');
        }
      });

  /// Links a sheet the search found and reads it in the same motion, because
  /// finding it is only half of "give me my data back".
  Future<void> _adopt(SheetReference sheet) => _run('Linking…', () async {
        final token =
            await GoogleAuthService.requireAccessToken(configured: _configured);
        final opened = await _service(token).open(sheet.id);

        await ref.read(settingsRepositoryProvider).linkSheet(
              spreadsheetId: opened.id,
              title: opened.title,
              accountEmail: GoogleAuthService.signedInEmail ?? '',
            );
        setState(() => _found = const <SheetReference>[]);
        _resetImport();
        _fetchAfterLink(opened.id);
      });

  /// Reads the sheet the moment it is linked, so restoring is not a second
  /// tap the person has to know about.
  ///
  /// A timer rather than a direct call because [_run] is still holding the
  /// busy flag while the action above is running; this lands on the next turn
  /// of the loop, after the flag has been cleared, so it is never swallowed by
  /// the `_busy != null` guard.
  void _fetchAfterLink(String spreadsheetId) {
    Future<void>.delayed(Duration.zero, () {
      if (!mounted || _busy != null) return;
      _run('Fetching…', () => _fetchFrom(spreadsheetId, quietWhenEmpty: true));
    });
  }

  Future<void> _unlink() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Unlink this spreadsheet?',
      message: 'The transactions already in the app stay exactly as they are. '
          'Only the link is removed.',
      confirmLabel: 'Unlink',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _run('Unlinking…', () async {
      await ref.read(settingsRepositoryProvider).unlinkSheet();
      _resetImport();
      _say('Spreadsheet unlinked.');
    });
  }

  Future<void> _openSheet(AppSettings settings) async {
    try {
      final uri = Uri.parse(
        'https://docs.google.com/spreadsheets/d/${settings.googleSpreadsheetId}',
      );
      final opened =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        throw AppException('No app on this device can open that link.');
      }
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, friendlyMessage(error), error: true);
    }
  }

  Future<void> _export(AppSettings settings) => _run('Exporting…', () async {
        if (!settings.hasLinkedSheet) {
          throw const ValidationException('Link a spreadsheet first.');
        }
        final rows = await ref
            .read(transactionRepositoryProvider)
            .getTransactions(const TransactionFilter(
              sort: TxSort.dateAsc,
              pageSize: 1000000,
            ));

        final token =
            await GoogleAuthService.requireAccessToken(configured: _configured);
        final service = _service(token);
        // One call writes heading and rows together so re-exporting replaces
        // the table instead of stacking a second copy underneath it.
        final warning = await service.writeTable(
          settings.googleSpreadsheetId,
          <List<String>>[for (final row in rows) _toCells(row)],
        );
        await ref.read(settingsRepositoryProvider).markSynced(DateTime.now());

        final done = 'Exported ${rows.length} transaction'
            '${rows.length == 1 ? '' : 's'}, oldest date first.';
        _say(warning == null ? done : '$done $warning');
      });

  /// Step 1 of import: pull the sheet down and work out the column mapping.
  Future<void> _fetch(AppSettings settings) => _run('Fetching…', () async {
        if (!settings.hasLinkedSheet) {
          throw const ValidationException('Link a spreadsheet first.');
        }
        await _fetchFrom(settings.googleSpreadsheetId);
      });

  /// Reads [spreadsheetId] and works out the column mapping.
  ///
  /// Split out of [_fetch] so the restore path can read a sheet in the same
  /// breath as linking it, without waiting for the settings stream to catch up
  /// with a link that was only just written.
  ///
  /// [quietWhenEmpty] turns "no rows" from a failure into a note: a sheet that
  /// was linked moments ago and has never been exported to is not broken, it
  /// is simply waiting to be filled.
  Future<void> _fetchFrom(
    String spreadsheetId, {
    bool quietWhenEmpty = false,
  }) async {
    final token =
        await GoogleAuthService.requireAccessToken(configured: _configured);
    final rows = await _service(token).read(spreadsheetId);

    if (rows.isEmpty) {
      if (quietWhenEmpty) {
        _say('That spreadsheet has no rows yet. Export will fill it.');
        return;
      }
      throw const ValidationException(
        'That spreadsheet has no rows to import.',
      );
    }

    final headers = <String>[for (final cell in rows.first) cell.trim()];
    final body = <List<String>>[
      for (final row in rows.skip(1))
        if (row.any((cell) => cell.trim().isNotEmpty)) row,
    ];

    final mapping = _autoMap(headers);
    final parsed = _parseAll(body, mapping);
    final duplicates = await _countDuplicates(parsed);

    setState(() {
      _headers = headers;
      _rows = body;
      _mapping = mapping;
      _parsed = parsed;
      _duplicates = duplicates;
      _fetched = true;
      _report = null;
    });
    _say('Loaded ${body.length} row${body.length == 1 ? '' : 's'}.');
  }

  /// Step 4 of import: resolve names to ids and hand the rows to the ledger.
  Future<void> _import() => _run('Importing…', () async {
        final catalog = ref.read(catalogRepositoryProvider);
        final events = ref.read(eventRepositoryProvider);
        final inputs = <TransactionInput>[];

        for (final candidate in _parsed) {
          final input = candidate.input;
          if (input == null) continue;

          var resolved = input;
          if (candidate.category.isNotEmpty) {
            resolved = resolved.copyWith(
              categoryId: await catalog.findOrCreate(
                CatalogKind.category,
                candidate.category,
              ),
            );
          }
          if (candidate.incomeSource.isNotEmpty) {
            resolved = resolved.copyWith(
              incomeSourceId: await catalog.findOrCreate(
                CatalogKind.incomeSource,
                candidate.incomeSource,
              ),
            );
          }
          if (candidate.paymentMethod.isNotEmpty) {
            resolved = resolved.copyWith(
              paymentMethodId: await catalog.findOrCreate(
                CatalogKind.paymentMethod,
                candidate.paymentMethod,
              ),
            );
          }
          if (candidate.event.isNotEmpty) {
            resolved = resolved.copyWith(
              specialEventId: await events.findOrCreate(candidate.event),
            );
          }
          inputs.add(resolved);
        }

        if (inputs.isEmpty) {
          throw const ValidationException(
            'None of the rows could be read. Check the column mapping.',
          );
        }

        final report = await ref
            .read(transactionRepositoryProvider)
            .importTransactions(inputs, skipDuplicates: true);

        setState(() => _report = report);
        _say('Added ${report.inserted} new transaction'
            '${report.inserted == 1 ? '' : 's'}; skipped '
            '${report.skippedDuplicates} duplicate'
            '${report.skippedDuplicates == 1 ? '' : 's'}.');
      });

  void _resetImport() {
    setState(() {
      _fetched = false;
      _headers = const <String>[];
      _rows = const <List<String>>[];
      _mapping = const <_Field, int>{};
      _parsed = const <_Candidate>[];
      _duplicates = 0;
      _report = null;
    });
  }

  // ------------------------------------------------------------------ parsing

  /// Best-guess column for each field, matching aliases case-insensitively.
  Map<_Field, int> _autoMap(List<String> headers) {
    final result = <_Field, int>{};
    for (final field in _Field.values) {
      result[field] = -1;
      for (var i = 0; i < headers.length; i++) {
        final header = headers[i].trim().toLowerCase();
        if (header.isEmpty) continue;
        if (header == field.label.toLowerCase() ||
            (_aliases[field]?.contains(header) ?? false)) {
          result[field] = i;
          break;
        }
      }
    }
    return result;
  }

  String _cell(_Field field, List<String> row) {
    final index = _mapping[field] ?? -1;
    if (index < 0 || index >= row.length) return '';
    return row[index].trim();
  }

  List<_Candidate> _parseAll(List<List<String>> rows, Map<_Field, int> mapping) {
    // _cell reads _mapping, so swap it in for the parse and leave the field
    // mapping as the user last approved it.
    final previous = _mapping;
    _mapping = mapping;
    final parsed = <_Candidate>[];
    for (final row in rows) {
      parsed.add(_parseRow(row));
    }
    _mapping = previous;
    return parsed;
  }

  _Candidate _parseRow(List<String> row) {
    final dateText = _cell(_Field.date, row);
    final date = AppDates.tryParseDate(dateText);
    if (date == null) {
      return _Candidate.skipped('Date “$dateText” could not be read.');
    }

    final amountText = _cell(_Field.amount, row);
    final amount = parseImportedMoney(amountText);
    if (amount == null || amount <= 0) {
      return _Candidate.skipped('Amount “$amountText” is not a positive number.');
    }

    final timeText = _cell(_Field.time, row);
    final time = AppDates.tryParseTime(timeText) ?? '00:00';

    final category = _cell(_Field.category, row);
    final incomeSource = _cell(_Field.incomeSource, row);
    final paymentMethod = _cell(_Field.paymentMethod, row);
    final event = _cell(_Field.event, row);
    final note = _cell(_Field.note, row);

    final typeText = _cell(_Field.type, row).toLowerCase();
    final type = typeText.contains('incom')
        ? TxType.income
        : typeText.isNotEmpty && typeText.contains('exp')
            ? TxType.expense
            : // No explicit type: an income source on the row means income.
            (incomeSource.isNotEmpty && category.isEmpty)
                ? TxType.income
                : TxType.expense;

    return _Candidate.ok(
      input: TransactionInput(
        type: type,
        amountMinor: amount,
        date: date,
        time: time,
        note: note,
      ),
      category: category,
      incomeSource: incomeSource,
      paymentMethod: paymentMethod,
      event: event,
    );
  }

  /// How many parsed rows are already in the database, so the preview can say
  /// so before a single row is written.
  Future<int> _countDuplicates(List<_Candidate> candidates) async {
    final existing = await ref
        .read(transactionRepositoryProvider)
        .getTransactions(const TransactionFilter());
    final keys = existing.map(txItemDuplicateKey).toSet();

    var count = 0;
    for (final candidate in candidates) {
      final input = candidate.input;
      if (input == null) continue;
      final key = inputDuplicateKey(
        input,
        category: candidate.category,
        incomeSource: candidate.incomeSource,
        paymentMethod: candidate.paymentMethod,
      );
      if (keys.contains(key)) count++;
    }
    return count;
  }

  /// One sheet row in the same column order [AppConfig.sheetColumns] defines.
  static List<String> _toCells(TxItem row) => <String>[
        AppDates.isoDay(row.date),
        row.time,
        row.type.name,
        minorToDecimalString(row.amountMinor),
        row.categoryName ?? '',
        row.incomeSourceName ?? '',
        row.paymentMethodName ?? '',
        row.specialEventName ?? '',
        row.note,
      ];

  // -------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Google Sheets')),
      body: AsyncValueView<AppSettings>(
        value: settings,
        loadingLabel: 'Reading settings…',
        onRetry: () => ref.invalidate(settingsProvider),
        data: (data) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (_busy != null) ...[
              _BusyCard(label: _busy!),
              const SizedBox(height: 12),
            ],
            if (_error != null) ...[
              _MessageCard(
                text: _error!,
                tone: _MessageTone.error,
                detail: _errorDetail,
              ),
              const SizedBox(height: 12),
            ],
            if (_note != null) ...[
              _MessageCard(text: _note!, tone: _MessageTone.info),
              const SizedBox(height: 12),
            ],
            _accountCard(data),
            if (_checks != null) ...[
              const SizedBox(height: 12),
              _checkCard(),
            ],
            const SizedBox(height: 12),
            _spreadsheetCard(data),
            const SizedBox(height: 12),
            _exportCard(data),
            const SizedBox(height: 12),
            _importCard(data),
          ],
        ),
      ),
    );
  }

  /// Sign-in state: not set up, connected, or ready to connect.
  ///
  /// [configured] comes from the runtime settings, so ids pasted into *Settings
  /// → Google Sheets setup* switch this card over without a rebuild.
  Widget _accountCard(AppSettings settings) {
    final configured = settings.hasGoogleConfig;
    final email = GoogleAuthService.signedInEmail;
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_circle_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text('Google account', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            if (!configured) ...[
              const Text(
                'Google sign-in has not been set up yet. Open Google Sheets '
                'setup and paste your OAuth client ids to switch it on. '
                'Everything else in the app keeps working offline.',
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.pushNamed(context, AppRoutes.googleSetup),
                icon: const Icon(Icons.vpn_key_outlined),
                label: const Text('Open Google Sheets setup'),
              ),
            ] else if (email != null) ...[
              Text('Connected as $email', style: theme.textTheme.bodyLarge),
              const SizedBox(height: 10),
              // Wrap rather than Row: two labels side by side must fall onto
              // a second line on a narrow phone instead of overflowing.
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy == null ? _disconnect : null,
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Sign out'),
                  ),
                  TextButton.icon(
                    onPressed: _busy == null ? _switchAccount : null,
                    icon: const Icon(Icons.swap_horiz_rounded),
                    label: const Text('Switch account'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Several Google accounts on this phone? Switch to another '
                'one without signing the app out for good.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ] else ...[
              const Text(
                'Signing in is only needed to read or write a spreadsheet. '
                'It is never required to record a transaction.',
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _busy == null ? _connect : null,
                icon: const Icon(Icons.login_rounded),
                label: const Text('Connect Google account'),
              ),
            ],
            if (configured) ...[
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: _busy == null ? _check : null,
                icon: const Icon(Icons.rule_rounded),
                label: const Text('Check connection'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The report produced by [_check]: one line per step, stopping nowhere.
  Widget _checkCard() {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.rule_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text('Connection check', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 10),
            for (final check in _checks!) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    check.ok
                        ? Icons.check_circle_rounded
                        : Icons.error_outline_rounded,
                    size: 20,
                    color: check.ok
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          check.label,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(check.detail, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              if (check != _checks!.last) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }

  Widget _spreadsheetCard(AppSettings settings) {
    final theme = Theme.of(context);
    final linked = settings.hasLinkedSheet;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.table_chart_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text('Spreadsheet', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            if (linked) ...[
              Text(settings.googleSpreadsheetTitle,
                  style: theme.textTheme.bodyLarge),
              if (settings.googleAccountEmail.isNotEmpty)
                Text(
                  'via ${settings.googleAccountEmail}',
                  style: theme.textTheme.bodySmall,
                ),
              if (settings.lastSyncAt != null)
                Text(
                  'Last exported ${AppDates.dateTimeLabel(settings.lastSyncAt!, null)}',
                  style: theme.textTheme.bodySmall,
                ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _openSheet(settings),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Open in Sheets'),
                  ),
                  TextButton.icon(
                    onPressed: _busy == null ? _unlink : null,
                    icon: const Icon(Icons.link_off_rounded),
                    label: const Text('Unlink'),
                  ),
                ],
              ),
            ] else ...[
              TextField(
                controller: _linkController,
                decoration: const InputDecoration(
                  labelText: 'Paste a spreadsheet link',
                  hintText: 'https://docs.google.com/spreadsheets/d/…',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _busy == null ? _link : null,
                    icon: const Icon(Icons.link_rounded),
                    label: const Text('Link spreadsheet'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy == null ? _create : null,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Create new'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'New spreadsheet name',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Text(
                'Looking for a sheet you already had?',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Deleted the app, reinstalled it, or on another phone? Search '
                'this Google account for the spreadsheet this app wrote '
                'before, then tap it to link it and bring your history back.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed:
                    (_busy == null && settings.hasGoogleConfig) ? _find : null,
                icon: const Icon(Icons.manage_search_rounded),
                label: const Text('Find my spreadsheet'),
              ),
              if (!settings.hasGoogleConfig)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Sign-in is not set up yet - open Google Sheets setup '
                    'first.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              for (final sheet in _found) ...[
                const SizedBox(height: 8),
                Material(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: const Icon(Icons.table_chart_outlined),
                    title: Text(
                      sheet.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: const Text('Link it and read its rows'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _busy == null ? () => _adopt(sheet) : null,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _exportCard(AppSettings settings) {
    final theme = Theme.of(context);
    final ready = settings.hasLinkedSheet && _busy == null;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.upload_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text('Export', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Writes the headings and every expense and income, oldest date '
              'first, so the sheet reads day by day. Exporting again replaces '
              'the table instead of adding a second copy of it, and stamps '
              'the time of the export.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: ready ? () => _export(settings) : null,
              icon: const Icon(Icons.upload_rounded),
              label: const Text('Export to sheet'),
            ),
            if (!settings.hasLinkedSheet)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Link a spreadsheet first.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _importCard(AppSettings settings) {
    final theme = Theme.of(context);
    final canFetch = settings.hasLinkedSheet && _busy == null;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.download_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text('Import', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Reads the sheet, lets you confirm which column is which, shows '
              'what would change, and only then writes anything. Rows that '
              'already exist are skipped rather than duplicated.',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: canFetch ? () => _fetch(settings) : null,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(_fetched ? 'Fetch sheet again' : 'Fetch sheet'),
            ),
            if (!_fetched) ...[
              if (!settings.hasLinkedSheet)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Link a spreadsheet first.',
                      style: theme.textTheme.bodySmall),
                ),
            ] else ...[
              const SizedBox(height: 16),
              _mappingEditor(),
              const SizedBox(height: 8),
              _preview(),
              const SizedBox(height: 12),
              _importActions(),
            ],
          ],
        ),
      ),
    );
  }

  /// Step 2: which sheet column holds which field.
  Widget _mappingEditor() {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Column mapping', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        for (final field in _Field.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(child: Text(field.label)),
                const SizedBox(width: 12),
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<int>(
                    initialValue: _mapping[field] ?? -1,
                    isExpanded: true,
                    isDense: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: <DropdownMenuItem<int>>[
                      const DropdownMenuItem<int>(
                        value: -1,
                        child: Text('Skip', overflow: TextOverflow.ellipsis),
                      ),
                      for (var i = 0; i < _headers.length; i++)
                        DropdownMenuItem<int>(
                          value: i,
                          child: Text(
                            _headers[i].isEmpty ? 'Column ${i + 1}' : _headers[i],
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _busy == null
                        ? (value) => setState(() {
                              _mapping = <_Field, int>{
                                ..._mapping,
                                field: value ?? -1,
                              };
                              _parsed = _parseAll(_rows, _mapping);
                              _report = null;
                            })
                        : null,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Step 3: what the first rows look like, and how much would change.
  Widget _preview() {
    final theme = Theme.of(context);
    final ok = _parsed.where((c) => c.isOk).length;
    final bad = _parsed.length - ok;
    final preview = _parsed.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Preview', style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            AppBadge(label: '$ok ready to import'),
            AppBadge(label: '$_duplicates already in the app'),
            if (bad > 0)
              AppBadge(
                label: '$bad need attention',
                color: theme.colorScheme.error,
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (final candidate in preview)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  candidate.isOk ? Icons.check_circle_rounded : Icons.warning_rounded,
                  size: 16,
                  color: candidate.isOk
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    candidate.isOk
                        ? '${AppDates.dateLabel(candidate.input!.date)} · '
                            '${_describe(candidate)}'
                        : candidate.problem!,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        if (_parsed.length > preview.length)
          Text(
            '…and ${_parsed.length - preview.length} more',
            style: theme.textTheme.bodySmall,
          ),
        if (_report != null) ...[
          const SizedBox(height: 8),
          _reportCard(_report!),
        ],
      ],
    );
  }

  String _describe(_Candidate candidate) {
    final input = candidate.input!;
    final parts = <String>[
      formatMinor(input.amountMinor),
      if (input.type == TxType.income) 'Income' else 'Expense',
      if (candidate.category.isNotEmpty) candidate.category,
      if (candidate.incomeSource.isNotEmpty) candidate.incomeSource,
      if (candidate.paymentMethod.isNotEmpty) candidate.paymentMethod,
      if (candidate.event.isNotEmpty) candidate.event,
    ];
    return parts.join(' · ');
  }

  Widget _reportCard(MergeReport report) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Import result', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text('${report.inserted} added · '
              '${report.skippedDuplicates} skipped as duplicates · '
              '${report.invalid} could not be read'),
          for (final error in report.errors.take(5))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(error, style: theme.textTheme.bodySmall),
            ),
          if (report.errors.length > 5)
            Text('…and ${report.errors.length - 5} more',
                style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _importActions() {
    final ready = _parsed.any((c) => c.isOk);
    return FilledButton.icon(
      onPressed: ready && _busy == null ? _import : null,
      icon: const Icon(Icons.download_done_rounded),
      label: Text('Import ${_parsed.where((c) => c.isOk).length} row'
          '${_parsed.where((c) => c.isOk).length == 1 ? '' : 's'}'),
    );
  }
}

enum _MessageTone { info, error }

/// A status or failure, styled so the two are never confused.
///
/// [detail] carries Google's own wording when there is any. It sits under the
/// friendly sentence rather than replacing it: the sentence says what to do,
/// the detail says exactly what Google refused, which is what turns "it did not
/// work" into a report somebody can act on.
class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.text,
    required this.tone,
    this.detail,
  });

  final String text;
  final _MessageTone tone;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isError = tone == _MessageTone.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isError
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            size: 20,
            color: isError
                ? theme.colorScheme.onErrorContainer
                : theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isError
                        ? theme.colorScheme.onErrorContainer
                        : theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                if (detail != null && detail!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    detail!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isError
                          ? theme.colorScheme.onErrorContainer
                          : theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Progress indicator with the label of what is running.
class _BusyCard extends StatelessWidget {
  const _BusyCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    );
  }
}
