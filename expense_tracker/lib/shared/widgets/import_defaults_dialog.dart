import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/catalog_item.dart';
import '../../shared/models/tx_type.dart';
import 'catalog_picker.dart';

/// What a month-grid import uses for the columns the sheet does not carry.
///
/// A sheet laid out as months across the top knows a day, a month, a
/// description and an amount. It does not know the year (never written
/// anywhere on it), whether the row is money coming in or going out, which
/// wallet paid, or which month the event blocks below the table fall in.
///
/// Asking once per file rather than once per row is the point: 400 rows get
/// one dialog, and every answer applies to all of them.
class ImportDefaults {
  const ImportDefaults({
    required this.type,
    required this.paymentMethodId,
    required this.incomeSourceId,
    required this.year,
    required this.eventMonth,
  });

  final TxType type;

  /// Chosen wallet, when [type] is an expense.
  final int? paymentMethodId;

  /// Chosen source, when [type] is income.
  final int? incomeSourceId;

  /// Year to stamp on every row - the sheet never states one.
  final int year;

  /// Month the event blocks belong to; their headings give days only.
  final int eventMonth;
}

/// Asks for [ImportDefaults]; `null` means the person backed out.
///
/// [rowCount] and [eventCount] are shown in the message so the question is
/// about *this* file rather than in the abstract. [showEventMonth] is false
/// for a sheet with no blocks below the table, because a month for events
/// that do not exist is a question nobody should have to answer.
Future<ImportDefaults?> showImportDefaultsDialog(
  BuildContext context, {
  required int rowCount,
  required int eventCount,
  required bool showEventMonth,
}) {
  return showDialog<ImportDefaults>(
    context: context,
    // A tap on the backdrop must not throw the answers away: the person has
    // just typed a year and picked a wallet, and the only way to express
    // "not now" is an explicit Cancel.
    barrierDismissible: false,
    builder: (context) => _ImportDefaultsDialog(
      rowCount: rowCount,
      eventCount: eventCount,
      showEventMonth: showEventMonth,
    ),
  );
}

class _ImportDefaultsDialog extends ConsumerStatefulWidget {
  const _ImportDefaultsDialog({
    required this.rowCount,
    required this.eventCount,
    required this.showEventMonth,
  });

  final int rowCount;
  final int eventCount;
  final bool showEventMonth;

  @override
  ConsumerState<_ImportDefaultsDialog> createState() =>
      _ImportDefaultsDialogState();
}

class _ImportDefaultsDialogState
    extends ConsumerState<_ImportDefaultsDialog> {
  final _year = TextEditingController(
    text: DateTime.now().year.toString(),
  );

  TxType _type = TxType.expense;
  int? _paymentMethodId;
  int? _incomeSourceId;
  int _eventMonth = DateTime.now().month;
  String? _error;

  @override
  void dispose() {
    _year.dispose();
    super.dispose();
  }

  /// `Cash` if the phone has it, otherwise the first wallet listed - matching
  /// what somebody importing a personal expense sheet almost always means.
  static int? _defaultId(List<CatalogItem> items) {
    if (items.isEmpty) return null;
    for (final item in items) {
      if (item.name.toLowerCase() == 'cash') return item.id;
    }
    return items.first.id;
  }

  void _submit() {
    final year = int.tryParse(_year.text.trim()) ?? 0;
    if (year < 1900 || year > 2999) {
      setState(() => _error = 'Enter a four-digit year.');
      return;
    }

    // `read`, not `watch`: this runs from a tap, outside build. The lists are
    // already on screen, so there is nothing to subscribe to here.
    final methods = ref.read(catalogListProvider(CatalogKind.paymentMethod))
            .valueOrNull ??
        const <CatalogItem>[];
    final sources = ref.read(catalogListProvider(CatalogKind.incomeSource))
            .valueOrNull ??
        const <CatalogItem>[];

    final methodId = _paymentMethodId ?? _defaultId(methods);
    final sourceId = _incomeSourceId ?? _defaultId(sources);

    if (_type == TxType.expense && methodId == null) {
      setState(() => _error = 'Add a payment method first.');
      return;
    }
    if (_type == TxType.income && sourceId == null) {
      setState(() => _error = 'Add an income source first.');
      return;
    }

    Navigator.of(context).pop(
      ImportDefaults(
        type: _type,
        paymentMethodId: _type == TxType.expense ? methodId : null,
        incomeSourceId: _type == TxType.income ? sourceId : null,
        year: year,
        eventMonth: _eventMonth,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final methods =
        ref.watch(catalogListProvider(CatalogKind.paymentMethod)).valueOrNull ??
            const <CatalogItem>[];
    final sources =
        ref.watch(catalogListProvider(CatalogKind.incomeSource)).valueOrNull ??
            const <CatalogItem>[];

    return AlertDialog(
      title: const Text('Before importing'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This sheet gives ${widget.rowCount} row'
                '${widget.rowCount == 1 ? '' : 's'}'
                '${widget.eventCount > 0 ? ' across ${widget.eventCount} '
                    'special event${widget.eventCount == 1 ? '' : 's'}' : ''}, '
                'but not the fields below. Set them once for the whole file.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),

              Text('Type', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              SegmentedButton<TxType>(
                segments: const <ButtonSegment<TxType>>[
                  ButtonSegment<TxType>(
                    value: TxType.expense,
                    label: Text('Expense'),
                    icon: Icon(Icons.arrow_upward_rounded),
                  ),
                  ButtonSegment<TxType>(
                    value: TxType.income,
                    label: Text('Income'),
                    icon: Icon(Icons.arrow_downward_rounded),
                  ),
                ],
                selected: <TxType>{_type},
                onSelectionChanged: (selection) =>
                    setState(() => _type = selection.first),
              ),
              const SizedBox(height: 16),

              if (_type == TxType.expense)
                CatalogPicker(
                  kind: CatalogKind.paymentMethod,
                  label: 'Paid from',
                  valueId: _paymentMethodId ?? _defaultId(methods),
                  onChanged: (id) => setState(() => _paymentMethodId = id),
                )
              else
                CatalogPicker(
                  kind: CatalogKind.incomeSource,
                  label: 'Income source',
                  valueId: _incomeSourceId ?? _defaultId(sources),
                  onChanged: (id) => setState(() => _incomeSourceId = id),
                ),
              const SizedBox(height: 16),

              TextField(
                controller: _year,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: const InputDecoration(
                  labelText: 'Year',
                  helperText: 'The sheet never says which year these are.',
                  counterText: '',
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 8),

              if (widget.showEventMonth) ...[
                DropdownButtonFormField<int>(
                  initialValue: _eventMonth,
                  decoration: const InputDecoration(
                    labelText: 'Event blocks fall in',
                    helperText: 'Their headings give days, never a month.',
                  ),
                  items: <DropdownMenuItem<int>>[
                    for (var month = 1; month <= 12; month++)
                      DropdownMenuItem<int>(
                        value: month,
                        child: Text(_monthName(month)),
                      ),
                  ],
                  onChanged: (value) => setState(
                    () => _eventMonth = value ?? _eventMonth,
                  ),
                ),
                const SizedBox(height: 8),
              ],

              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Import'),
        ),
      ],
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
}
