import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/state/app_identity.dart';
import '../../core/backup/backup_formats.dart';
import '../../core/backup/month_grid.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/date_utils.dart';
import '../../repositories/backup_repository.dart';
import '../../repositories/providers.dart';
import '../../shared/models/catalog_item.dart';
import '../../shared/models/transaction_filter.dart';
import '../../shared/models/transaction_input.dart';
import '../../shared/models/tx_type.dart';
import '../../shared/models/validation.dart';
import '../../shared/widgets/catalog_picker.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/import_defaults_dialog.dart';

/// The readers a picked file can be routed to, decided from the extension
/// and, when that carries nothing usable, from the first bytes.
enum _ImportFormat { json, csv, xlsx }

/// How the backup screen is opened.
///
/// One screen serves two entries on the More tab: the full `Backup & restore`
/// tool, and a direct `Import spreadsheet` link that lands here already
/// reaching for the file picker.
enum BackupLaunch {
  /// The regular backup screen: nothing happens until the user acts.
  full,

  /// The file picker opens as soon as the first frame is on screen, and the
  /// screen reads as an importer rather than a backup tool.
  importFile,
}

/// Backup and restore: export the whole database as a portable JSON file and
/// bring it back on this or another device.
///
/// Restore also reads CSV and XLSX files: whichever format is picked, it is
/// decoded into the same backup document before anything runs, so preview,
/// duplicate detection and merge behave identically for every file.
///
/// Nothing is written before the user has seen a preview of the picked file
/// and confirmed the restore, and the destructive path (replace) always asks a
/// second, explicitly destructive question.
class BackupScreen extends ConsumerStatefulWidget {
  /// Creates the pushed backup screen; [launch] decides whether the file
  /// picker opens straight away (see [BackupLaunch]).
  const BackupScreen({super.key, this.launch = BackupLaunch.full});

  /// Whether the picker should open automatically after the first frame.
  final BackupLaunch launch;

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  /// True when the screen was opened as a direct import entry, which hides
  /// the export side and leads with the picker instead of the backup tool.
  bool get _importing => widget.launch == BackupLaunch.importFile;

  @override
  void initState() {
    super.initState();
    if (widget.launch == BackupLaunch.importFile) {
      // Opening the picker is a platform call, so it waits for the first
      // frame instead of racing the route transition; `mounted` guards a
      // screen popped before that frame landed. A cancel simply leaves this
      // screen up - the visible "Choose a file" button opens the picker again.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pickFile();
      });
    }
  }

  /// True while an export, an analysis or a restore is running.
  bool _busy = false;

  /// How a restore should treat rows that already exist.
  BackupRestoreMode _mode = BackupRestoreMode.merge;

  /// Decoded backup document from the picked file; the input for preview and
  /// restore, whatever format it arrived in.
  Map<String, dynamic>? _document;

  /// A month-grid read instead of a document: months across the top, days
  /// down the side, blocks below the table as special events. Mutually
  /// exclusive with [_document] - a file is one or the other.
  MonthGrid? _grid;

  /// The answers from the one dialog a grid import asks for. Stays `null`
  /// until they are given, which is what the Import button waits on.
  ImportDefaults? _defaults;

  /// Name of the picked file, shown above the preview.
  String? _sourceName;

  /// Result of the last analysis. Starts as "nothing selected yet" so the
  /// screen can render its empty state before any file has been chosen.
  AsyncValue<BackupPreview?> _preview = const AsyncValue.data(null);

  /// First and last calendar day covered by the backup transactions.
  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  /// Rows of the backup that already exist on this device (merge estimate).
  int _duplicates = 0;

  /// Name and size of the last successful export.
  String? _exportedName;
  int _exportedBytes = 0;

  /// Result of the last successful restore.
  MergeReport? _report;

  /// Last recoverable failure, shown inline until the next action.
  String? _failure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final failure = _failure;
    final report = _report;
    final canRestore =
        _document != null && _preview.valueOrNull != null && !_busy;
    final replacing = _mode == BackupRestoreMode.replace;

    return Scaffold(
      appBar: AppBar(
        title: Text(_importing ? 'Import from file' : 'Backup & restore'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // The direct import entry is about bringing data in, so the export
          // side stays out of the way entirely.
          if (!_importing) ...[
            const SectionHeader('Export'),
            _exportCard(context),
          ],
          SectionHeader(_importing ? 'Import' : 'Restore'),
          _importCard(context, failure),
          // A month grid cannot be shown as a backup preview - it has no
          // document shape - so it gets its own summary and its own button.
          if (_grid != null)
            ..._gridSection(context, _grid!)
          else ...[
            AsyncValueView<BackupPreview?>(
              value: _preview,
              loadingLabel: 'Reading the backup file...',
              onRetry: _revalidate,
              empty: const EmptyState(
                icon: Icons.folder_open_outlined,
                title: 'No backup selected',
                message: 'Choose a backup file to see exactly what it contains '
                    'before anything is written.',
                compact: true,
              ),
              data: (preview) => preview == null
                  ? const SizedBox.shrink()
                  : _previewCard(context, preview),
            ),
            if (_document != null) ...[
              const SizedBox(height: 16),
              _modePicker(context, replacing: replacing),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: canRestore ? _restore : null,
                  icon: const Icon(Icons.settings_backup_restore_rounded),
                  label: const Text('Restore'),
                ),
              ),
            ],
          ],
          if (report != null) ...[
            const SizedBox(height: 12),
            _reportCard(context, report),
          ],
          const SectionHeader('How restore works'),
          _howRestoreWorks(context, theme, colors),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- export

  /// Explains the format and offers the export action with its last result.
  Widget _exportCard(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final exported = _exportedName;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.upload_file_rounded, color: colors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Create a backup',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'A backup is a portable JSON file containing your transactions, '
              'categories, income sources, payment methods, special events '
              'and settings.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _busy ? null : () => _export(),
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('Export backup'),
              ),
            ),
            if (exported != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 20,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            exported,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${_humanBytes(_exportedBytes)} - ready to share',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Share the backup again',
                      onPressed: _busy ? null : () => _export(),
                      icon: const Icon(Icons.share_rounded),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Builds the backup JSON, writes it to a temporary file and opens the
  /// share sheet. Every step is guarded so a failure explains itself instead
  /// of leaving a half-finished export behind.
  Future<void> _export() async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final json = await ref.read(backupRepositoryProvider).createBackupJson();
      final directory = await getTemporaryDirectory();
      final name =
          'expense-tracker-backup-${AppDates.isoDay(DateTime.now())}.json';
      final file = File(p.join(directory.path, name));
      await file.writeAsString(json, flush: true);
      final bytes = utf8.encode(json).length;

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          title: '${ref.read(appNameProvider)} backup',
          text: 'Backup exported on ${AppDates.dateLabel(DateTime.now())}',
        ),
      );

      if (!mounted) return;
      setState(() {
        _exportedName = name;
        _exportedBytes = bytes;
      });
      showAppMessage(context, 'Backup exported');
    } catch (error) {
      if (!mounted) return;
      final message = _friendlyMessage(error);
      setState(() => _failure = message);
      showAppMessage(context, message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------- import

  /// Offers the file picker and explains what happens before anything runs.
  Widget _importCard(BuildContext context, String? failure) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final source = _sourceName;

    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.download_rounded, color: colors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _importing ? 'Import a spreadsheet' : 'Restore a backup',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _importing
                      ? 'Pick a CSV / XLSX spreadsheet of transactions, or a '
                          'JSON backup exported from this app. Nothing is '
                          'written until you have seen the preview and '
                          'confirmed the restore.'
                      : 'Pick a JSON backup exported from this app, or a CSV / '
                          'XLSX spreadsheet of transactions. Nothing is '
                          'written until you have seen the preview and '
                          'confirmed the restore.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: _busy ? null : () => _pickFile(),
                    icon: const Icon(Icons.folder_open_outlined),
                    // In import mode this doubles as the retry after a
                    // cancelled pick, so it always stays visible.
                    label: Text(
                      _importing ? 'Choose a file' : 'Restore from file',
                    ),
                  ),
                ),
                if (source != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Selected: $source',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (failure != null) ...[
          const SizedBox(height: 12),
          _messageCard(
            context,
            message: failure,
            icon: Icons.error_outline_rounded,
            background: colors.errorContainer,
            foreground: colors.onErrorContainer,
          ),
        ],
      ],
    );
  }

  /// Picks a JSON, CSV or XLSX file, decodes it into a backup document and
  /// runs the preview analysis.
  Future<void> _pickFile() async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      // file_picker 13 returns `List<PlatformFile>` directly (FilePickerResult
      // was removed) and no longer takes `withData`; bytes are read on demand.
      final picks = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json', 'csv', 'xlsx', 'xls'],
      );
      if (picks.isEmpty) return;
      final picked = picks.single;

      // Read the bytes once; every reader below works from that single copy.
      final pickedPath = picked.path;
      final bytes = pickedPath != null
          ? await File(pickedPath).readAsBytes()
          // Non file:// URIs (content:// on Android, blobs on the web) have
          // no local path, so ask the picker for the bytes instead.
          : await picked.readAsBytes();

      // Try the month-grid shape *before* heading matching. That layout has
      // no Date / Amount header row, so the ordinary reader would reject the
      // file before anyone could see what was inside it.
      final grid = _readGrid(picked.name, bytes);
      if (grid != null) {
        if (!mounted) return;
        setState(() {
          _grid = grid;
          _defaults = null;
          _document = null;
          _sourceName = picked.name;
          _report = null;
          _preview = const AsyncValue.data(null);
          _failure = null;
        });
        await _askGridDefaults();
        return;
      }

      final document = _readDocument(picked.name, bytes);

      if (!mounted) return;
      setState(() {
        _document = document;
        _grid = null;
        _defaults = null;
        _sourceName = picked.name;
        _report = null;
      });
      await _analyse(document);
    } catch (error) {
      if (!mounted) return;
      final message = _friendlyMessage(error);
      setState(() {
        _document = null;
        _grid = null;
        _defaults = null;
        _sourceName = null;
        _preview = const AsyncValue.data(null);
        _failure = message;
      });
      showAppMessage(context, message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Turns the picked file's bytes into a backup document, whatever format
  /// it arrived in.
  ///
  /// The extension decides first; without a usable one the leading bytes do
  /// (`{` means JSON, the letters PK mean a workbook, everything else is
  /// given to the CSV reader, which explains itself if the columns are not
  /// there).
  Map<String, dynamic> _readDocument(String name, List<int> bytes) {
    final repository = ref.read(backupRepositoryProvider);
    switch (_detectFormat(name, bytes)) {
      case _ImportFormat.json:
        return repository.decodeDocument(utf8.decode(bytes));
      case _ImportFormat.csv:
        return BackupFormats.fromCsv(utf8.decode(bytes));
      case _ImportFormat.xlsx:
        return BackupFormats.fromXlsx(bytes);
    }
  }

  // ------------------------------------------------------------ month grid

  /// The month-grid reader, or `null` when this file is not one.
  ///
  /// JSON is this app's own document and is never a grid. The two
  /// spreadsheet formats are decoded to raw rows and handed to the detector,
  /// which decides purely from the shape of the thing - which is the whole
  /// point, because that layout has no `Date` / `Amount` header row for the
  /// ordinary reader to match against.
  MonthGrid? _readGrid(String name, List<int> bytes) {
    switch (_detectFormat(name, bytes)) {
      case _ImportFormat.json:
        return null;
      case _ImportFormat.csv:
        return MonthGridReader.detect(
          BackupFormats.csvRows(utf8.decode(bytes)),
        );
      case _ImportFormat.xlsx:
        return MonthGridReader.detect(BackupFormats.xlsxRows(bytes));
    }
  }

  /// Asks the one question a month grid cannot answer for itself.
  ///
  /// Cancel leaves the preview on screen with the Import button waiting, so
  /// backing out costs nothing and can be undone by asking again - the file
  /// is never thrown away because somebody changed their mind.
  Future<void> _askGridDefaults() async {
    final grid = _grid;
    if (grid == null) return;

    final defaults = await showImportDefaultsDialog(
      context,
      rowCount: grid.entries.length,
      eventCount: grid.blockNames.length,
      showEventMonth: grid.blockNames.isNotEmpty,
    );
    if (!mounted || defaults == null) return;
    setState(() => _defaults = defaults);
  }

  /// Applies the year and the event month, dropping rows whose calendar day
  /// does not exist.
  ///
  /// A fixed 31-day grid offers a 30th of February, and no month has a 31st
  /// in February either. Rows nobody wrote anything on are already gone (they
  /// carry no amount), so this only ever removes a date that could not be
  /// stored honestly.
  static List<GridEntry> _readyRows(MonthGrid grid, ImportDefaults defaults) {
    final rows = <GridEntry>[];
    for (final entry in grid.entries) {
      final month = entry.month ?? defaults.eventMonth;
      if (_hasDay(defaults.year, month, entry.day)) rows.add(entry);
    }
    return rows;
  }

  /// True when that calendar day really exists.
  static bool _hasDay(int year, int month, int day) {
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day;
  }

  /// The grid's own preview and its two buttons.
  ///
  /// Returned as a list because it sits among the ListView's other children;
  /// there is no document to run the normal backup preview over.
  List<Widget> _gridSection(BuildContext context, MonthGrid grid) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final defaults = _defaults;
    final rows = defaults == null ? grid.entries : _readyRows(grid, defaults);
    final total = rows.fold<int>(0, (sum, row) => sum + row.amountMinor);

    return [
      const SizedBox(height: 16),
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.grid_view_rounded, color: colors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Month grid detected',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${grid.monthCount} months across the top, days down the '
                'side. ${rows.length} row${rows.length == 1 ? '' : 's'} '
                'ready to write.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
              if (grid.blockNames.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Special events from the blocks below the table: '
                  '${grid.blockNames.join(', ')} '
                  '(${grid.eventRows.length} row'
                  '${grid.eventRows.length == 1 ? '' : 's'}).',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  MoneyText(
                    total,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              if (grid.skipped > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '${grid.skipped} row'
                  '${grid.skipped == 1 ? ' was' : 's were'} skipped: '
                  'a description with no amount beside it.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      if (defaults == null) ...[
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _busy ? null : _askGridDefaults,
            icon: const Icon(Icons.tune_rounded),
            label: const Text('Set import options'),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'The sheet never says the year, whether the money is coming in or '
          'going out, or which wallet paid - so those are asked once for the '
          'whole file.',
          style:
              theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ] else ...[
        _defaultsCard(context, defaults),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _busy || rows.isEmpty ? null : _importGrid,
            icon: const Icon(Icons.file_download_done_rounded),
            label: Text(
              rows.isEmpty
                  ? 'Nothing to import'
                  : 'Import ${rows.length} row${rows.length == 1 ? '' : 's'}',
            ),
          ),
        ),
      ],
    ];
  }

  /// The answers already given, so they can be checked before committing.
  Widget _defaultsCard(BuildContext context, ImportDefaults defaults) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final gridBlocks = _grid?.blockNames.length ?? 0;
    final methods = ref
            .watch(catalogListProvider(CatalogKind.paymentMethod))
            .valueOrNull ??
        const <CatalogItem>[];
    final sources =
        ref.watch(catalogListProvider(CatalogKind.incomeSource)).valueOrNull ??
            const <CatalogItem>[];

    String nameOf(List<CatalogItem> items, int? id) {
      for (final item in items) {
        if (item.id == id) return item.name;
      }
      return 'not chosen';
    }

    final paid = defaults.type == TxType.expense
        ? nameOf(methods, defaults.paymentMethodId)
        : nameOf(sources, defaults.incomeSourceId);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune_rounded, color: colors.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Applied to every row',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : _askGridDefaults,
                  child: const Text('Change'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${defaults.type == TxType.expense ? 'Expense' : 'Income'} · '
              '$paid · ${defaults.year}',
              style: theme.textTheme.bodyMedium,
            ),
            if (gridBlocks > 0)
              Text(
                'Event blocks: ${_monthName(defaults.eventMonth)}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }

  static String _monthName(int month) => const <String>[
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ][month - 1];

  /// Writes the grid out: confirm first, then resolve names to ids.
  ///
  /// Nothing is resolved before the confirmation, because `findOrCreate`
  /// writes as it goes - confirming and then cancelling would leave a trail of
  /// categories nobody asked for.
  Future<void> _importGrid() async {
    final grid = _grid;
    final defaults = _defaults;
    if (grid == null || defaults == null) return;

    final rows = _readyRows(grid, defaults);
    if (rows.isEmpty) return;

    final confirmed = await showConfirmDialog(
      context,
      title: 'Import these rows?',
      message: '${rows.length} row${rows.length == 1 ? '' : 's'} will be added '
          'as ${defaults.type == TxType.expense ? 'expenses' : 'income'}'
          '${grid.blockNames.isEmpty ? '' : ', including ${grid.blockNames.length} '
              'special event${grid.blockNames.length == 1 ? '' : 's'} '
              '(${grid.blockNames.join(', ')})'}. '
          'Rows you already have are skipped rather than duplicated.',
      confirmLabel: 'Import',
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final catalog = ref.read(catalogRepositoryProvider);
      final events = ref.read(eventRepositoryProvider);
      final inputs = <TransactionInput>[];
      final eventIds = <String, int>{};

      for (final row in rows) {
        final month = row.month ?? defaults.eventMonth;
        var resolved = TransactionInput(
          type: defaults.type,
          amountMinor: row.amountMinor,
          date: DateTime(defaults.year, month, row.day),
          time: '00:00',
        );

        if (defaults.type == TxType.expense) {
          resolved = resolved.copyWith(
            // Every expense needs a category; a cell with an amount and no
            // description still describes money that was spent, so it is
            // filed rather than dropped.
            categoryId: await catalog.findOrCreate(
              CatalogKind.category,
              row.things.isEmpty ? 'Uncategorised' : row.things,
            ),
            paymentMethodId: defaults.paymentMethodId,
          );
        } else {
          resolved = resolved.copyWith(
            incomeSourceId: await catalog.findOrCreate(
              CatalogKind.incomeSource,
              row.things.isEmpty ? 'Other' : row.things,
            ),
          );
        }

        final name = row.eventName;
        if (name != null) {
          var eventId = eventIds[name];
          if (eventId == null) {
            final start =
                DateTime(defaults.year, defaults.eventMonth, row.day);
            DateTime? end;
            final endDay = row.eventEndDay;
            if (endDay != null &&
                _hasDay(defaults.year, defaults.eventMonth, endDay)) {
              end = DateTime(defaults.year, defaults.eventMonth, endDay);
            }
            eventId = await events.findOrCreate(
              name,
              startDate: start,
              endDate: end,
            );
            eventIds[name] = eventId;
          }
          resolved = resolved.copyWith(specialEventId: eventId);
        }

        inputs.add(resolved);
      }

      final report = await ref
          .read(transactionRepositoryProvider)
          .importTransactions(inputs, skipDuplicates: true);

      if (!mounted) return;
      setState(() => _report = report);
      showAppMessage(
        context,
        'Imported ${report.inserted} transaction'
        '${report.inserted == 1 ? '' : 's'}',
      );
      await _showReport(report, title: 'Import complete');
    } catch (error) {
      if (!mounted) return;
      final message = _friendlyMessage(error);
      setState(() => _failure = message);
      showAppMessage(context, message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Works out which reader a picked file needs.
  ///
  /// The legacy `.xls` format is refused here with instructions rather than
  /// being handed to the workbook reader, which can only fail worse.
  static _ImportFormat _detectFormat(String name, List<int> bytes) {
    final dot = name.lastIndexOf('.');
    final extension = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();

    if (extension == 'xls') {
      throw const AppException(
        'That file is in the old .xls format, which this app cannot read. '
        'Open it and save it as .xlsx, then try again.',
      );
    }
    if (extension == 'json') return _ImportFormat.json;
    if (extension == 'csv') return _ImportFormat.csv;
    if (extension == 'xlsx') return _ImportFormat.xlsx;

    // No usable extension: fall back to sniffing the contents.
    if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
      return _ImportFormat.xlsx;
    }
    final head = utf8
        .decode(
          bytes.length > 1024 ? bytes.sublist(0, 1024) : bytes,
          allowMalformed: true,
        )
        .replaceFirst('\uFEFF', '')
        .trimLeft();
    return head.startsWith('{') ? _ImportFormat.json : _ImportFormat.csv;
  }

  /// Validates [document] and measures what a merge would add.
  Future<void> _analyse(Map<String, dynamic> document) async {
    setState(() {
      _preview = const AsyncValue.loading();
      _duplicates = 0;
      _rangeStart = null;
      _rangeEnd = null;
    });

    try {
      final repository = ref.read(backupRepositoryProvider);
      final preview = repository.previewDocument(document);
      final (start, end, duplicates) = await _scan(document);
      if (!mounted) return;
      setState(() {
        _preview = AsyncValue.data(preview);
        _rangeStart = start;
        _rangeEnd = end;
        _duplicates = duplicates;
      });
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() => _preview = AsyncValue.error(error, stackTrace));
      showAppMessage(context, _friendlyMessage(error), error: true);
    }
  }

  /// Re-runs the analysis for the currently selected file.
  Future<void> _revalidate() async {
    final document = _document;
    if (document == null) return;
    await _analyse(document);
  }

  /// Measures the date range of the backup and how many of its rows already
  /// exist here - the two numbers a user needs before choosing a mode.
  Future<(DateTime?, DateTime?, int)> _scan(Map<String, dynamic> document) async {
    final existing = await ref
        .read(transactionRepositoryProvider)
        .getTransactions(const TransactionFilter(pageSize: 1000000));
    final existingKeys = existing.map(txItemDuplicateKey).toSet();

    DateTime? start;
    DateTime? end;
    var duplicates = 0;

    final rows = document['transactions'];
    if (rows is! List) return (null, null, 0);

    for (final row in rows) {
      if (row is! Map) continue;
      final amount = _readInt(row['amount']);
      final type = TxType.tryParse(row['type']?.toString());
      final rawDate = row['date']?.toString() ?? '';
      final date = DateTime.tryParse(rawDate);

      if (date != null) {
        final day = AppDates.day(date);
        if (start == null || day.isBefore(start)) start = day;
        if (end == null || day.isAfter(end)) end = day;
      }
      if (amount == null || type == null || date == null) continue;

      final key = duplicateKey(
        date: AppDates.day(date),
        time: row['time']?.toString() ?? '',
        amountMinor: amount,
        type: type,
        category: row['category']?.toString() ?? '',
        incomeSource: row['incomeSource']?.toString() ?? '',
        paymentMethod: row['paymentMethod']?.toString() ?? '',
        note: row['note']?.toString() ?? '',
      );
      if (existingKeys.contains(key)) duplicates++;
    }

    return (start, end, duplicates);
  }

  /// Renders the analysis: counts, created-at, date range and duplicates.
  Widget _previewCard(BuildContext context, BackupPreview preview) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final source = _sourceName;

    final start = _rangeStart;
    final end = _rangeEnd;
    final range = start != null && end != null
        ? '${AppDates.dateLabel(start)} - ${AppDates.dateLabel(end)}'
        : 'No dated transactions';
    final created = DateTime.tryParse(preview.createdAt);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.assignment_turned_in_outlined,
                  color: colors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Backup preview',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (source != null)
                        Text(
                          source,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _valueRow(context, 'Transactions', '${preview.transactions}'),
            _valueRow(context, 'Categories', '${preview.categories}'),
            _valueRow(context, 'Income sources', '${preview.incomeSources}'),
            _valueRow(
              context,
              'Payment methods',
              '${preview.paymentMethods}',
            ),
            _valueRow(context, 'Special events', '${preview.specialEvents}'),
            _valueRow(
              context,
              'Settings',
              preview.hasSettings ? 'Included' : 'Not included',
            ),
            _valueRow(
              context,
              'Created',
              created == null
                  ? 'Unknown'
                  : AppDates.dateTimeLabel(
                      created,
                      AppDates.timeFrom(created),
                    ),
            ),
            _valueRow(context, 'Date range', range),
            _valueRow(
              context,
              'Already on this device',
              '$_duplicates would be skipped',
            ),
          ],
        ),
      ),
    );
  }

  /// Merge / replace choice with the exact consequence of each option.
  Widget _modePicker(BuildContext context, {required bool replacing}) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How should the backup be restored?',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        _modeCard(
          context,
          title: 'Merge',
          message: 'Keeps everything you already have and adds new records. '
              'Nothing is overwritten.',
          selected: !replacing,
          onTap: () =>
              setState(() => _mode = BackupRestoreMode.merge),
        ),
        const SizedBox(height: 10),
        _modeCard(
          context,
          title: 'Replace',
          message: 'Deletes current data first, then restores the backup. '
              'This cannot be undone.',
          selected: replacing,
          onTap: () =>
              setState(() => _mode = BackupRestoreMode.replace),
        ),
      ],
    );
  }

  /// One selectable restore mode. Selection is marked with a ring, a check
  /// and the label, never with colour alone.
  Widget _modeCard(
    BuildContext context, {
    required String title,
    required String message,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: selected
                ? colors.secondaryContainer
                : colors.surfaceContainerLow,
            border: Border.all(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 22,
                color: selected ? colors.primary : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: selected
                            ? colors.onSecondaryContainer
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------- restore

  /// Confirms the restore (destructively for replace) and applies it.
  Future<void> _restore() async {
    final document = _document;
    if (document == null) return;

    final replacing = _mode == BackupRestoreMode.replace;
    final confirmed = await showConfirmDialog(
      context,
      title: replacing ? 'Replace everything?' : 'Merge this backup?',
      message: replacing
          ? 'Every transaction, category, income source, payment method, '
              'special event and setting on this device is deleted, then the '
              'backup is loaded. This cannot be undone.'
          : 'Records you already have stay exactly as they are; only missing '
              'records are added.',
      confirmLabel: 'Restore',
      destructive: replacing,
    );
    if (!confirmed) return;
    if (!mounted) return;

    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final report = await ref
          .read(backupRepositoryProvider)
          .restoreDocument(document, mode: _mode);
      // Settings may have been restored too, so re-subscribe to the stream.
      ref.invalidate(settingsProvider);

      if (!mounted) return;
      setState(() => _report = report);
      showAppMessage(context, 'Backup restored');
      await _showReport(report);
      // Re-measure the file against what was just written so the preview
      // numbers stay truthful if the user restores again.
      await _analyse(document);
    } catch (error) {
      if (!mounted) return;
      final message = _friendlyMessage(error);
      setState(() => _failure = message);
      showAppMessage(context, message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Shows the merge counts of a completed restore or import.
  ///
  /// [title] differs only in wording - the numbers below it are the same
  /// either way, because both paths end in the same `MergeReport`.
  Future<void> _showReport(MergeReport report, {String title = 'Restore complete'}) async {
    if (!mounted) return;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_reportSummary(report), style: theme.textTheme.bodyMedium),
            if (report.errors.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                report.errors.take(3).join('\n'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.error,
                ),
              ),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- widgets

  /// Persistent summary of the last restore.
  Widget _reportCard(BuildContext context, MergeReport report) {
    final colors = Theme.of(context).colorScheme;
    return _messageCard(
      context,
      message: 'Backup restored. ${_reportSummary(report)}',
      icon: Icons.check_circle_rounded,
      background: colors.primaryContainer,
      foreground: colors.onPrimaryContainer,
    );
  }

  /// Success / error banner used by the failure and report cards.
  Widget _messageCard(
    BuildContext context, {
    required String message,
    required IconData icon,
    required Color background,
    required Color foreground,
  }) {
    final theme = Theme.of(context);
    return Card(
      color: background,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: foreground),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One label/value line of the preview card.
  Widget _valueRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The three promises the restore screen makes.
  Widget _howRestoreWorks(
    BuildContext context,
    ThemeData theme,
    ColorScheme colors,
  ) {
    const lines = <String>[
      'Merge never overwrites: records you already have stay exactly as they '
          'are, duplicates are skipped.',
      'Replace wipes first: everything stored on this device is deleted, then '
          'the backup is loaded.',
      'Backups are plain files you control: JSON from this app, or CSV and '
          'XLSX spreadsheets. They stay on this device, work fully offline '
          'and never need an account.',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      size: 18,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(line, style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------- helpers

  /// `1234` -> `1.2 KB`. Sizes are presentation only, never money.
  String _humanBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Human wording for a completed [MergeReport].
  String _reportSummary(MergeReport report) {
    final parts = <String>[
      '${report.inserted} added',
      '${report.skippedDuplicates} skipped as duplicates',
    ];
    if (report.invalid > 0) parts.add('${report.invalid} invalid');
    return '${parts.join(', ')}.';
  }

  /// Reads an integer that may have been stored as a JSON number or string.
  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  /// Turns any caught error into a short sentence safe to show in the UI.
  ///
  /// Repository failures ([AppException] and its subclasses - validation,
  /// storage, backup) already carry user-facing wording, so it is shown as is.
  String _friendlyMessage(Object error) {
    if (error is AppException) return error.message;
    if (error is FormatException) {
      return 'That file is not readable text. Choose a JSON, CSV or XLSX '
          'file exported by this app.';
    }
    return 'Something went wrong. Please try again.';
  }
}
