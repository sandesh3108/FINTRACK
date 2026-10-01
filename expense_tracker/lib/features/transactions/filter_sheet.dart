import 'package:flutter/material.dart';

import '../../core/utils/money.dart';
import '../../shared/models/catalog_item.dart';
import '../../shared/models/range_spec.dart';
import '../../shared/models/transaction_filter.dart';
import '../../shared/models/tx_type.dart';
import '../../shared/widgets/catalog_picker.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/form_fields.dart';

/// Opens the transaction filter sheet and resolves with the edited filter.
///
/// Resolves with `null` when the sheet is dismissed without applying, so the
/// caller can keep its current filter untouched. The returned filter always
/// starts on page one; sorting and the search text are owned by the history
/// screen and are passed through unchanged.
Future<TransactionFilter?> showTransactionFilterSheet(
  BuildContext context,
  TransactionFilter initial,
) {
  // Everything below outlives individual rebuilds: the sheet is built with a
  // StatefulBuilder, so its state lives in these captured variables.
  var draft = initial;
  String? minError;
  String? maxError;
  final minController =
      TextEditingController(text: _minorText(initial.minAmountMinor));
  final maxController =
      TextEditingController(text: _minorText(initial.maxAmountMinor));

  return showModalBottomSheet<TransactionFilter>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) {
      return StatefulBuilder(
        builder: (context, setState) {
          void update(TransactionFilter next) => setState(() => draft = next);

          void reset() {
            setState(() {
              draft = TransactionFilter(
                search: draft.search,
                sort: draft.sort,
                pageSize: draft.pageSize,
              );
              minError = null;
              maxError = null;
              minController.clear();
              maxController.clear();
            });
          }

          void apply() {
            final minText = minController.text.trim();
            final maxText = maxController.text.trim();
            final min = minText.isEmpty ? null : parseMoneyToMinor(minText);
            final max = maxText.isEmpty ? null : parseMoneyToMinor(maxText);

            String? nextMinError;
            String? nextMaxError;
            if (minText.isNotEmpty && min == null) {
              nextMinError = 'Enter a valid amount.';
            }
            if (maxText.isNotEmpty && max == null) {
              nextMaxError = 'Enter a valid amount.';
            }
            if (nextMinError == null &&
                nextMaxError == null &&
                min != null &&
                max != null &&
                min > max) {
              nextMaxError = 'Must be greater than the minimum.';
            }
            setState(() {
              minError = nextMinError;
              maxError = nextMaxError;
            });
            if (nextMinError != null || nextMaxError != null) return;

            final withAmounts = draft
                .copyWith(clearAmountRange: true)
                .copyWith(minAmountMinor: min, maxAmountMinor: max);
            Navigator.of(context).pop(withAmounts);
          }

          final theme = Theme.of(context);
          final colors = theme.colorScheme;
          // The sheet is scroll controlled, so bound it explicitly: it may use
          // most of the display, minus whatever the keyboard occupies.
          var maxSheetHeight = MediaQuery.sizeOf(context).height * 0.85 -
              MediaQuery.viewInsetsOf(context).bottom;
          if (maxSheetHeight < 200) maxSheetHeight = 200;

          return SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxSheetHeight),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Filters',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        draft.isEmpty
                            ? 'Everything is included right now.'
                            : '${draft.activeCount} active - ${draft.describe()}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),

                      // ---------------------------------------------------- type
                      const SectionHeader(
                        'Type',
                        padding: EdgeInsets.fromLTRB(0, 20, 0, 8),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('All'),
                            showCheckmark: true,
                            selected: draft.type == null,
                            onSelected: (_) =>
                                update(draft.copyWith(clearType: true)),
                          ),
                          ChoiceChip(
                            label: const Text('Expense'),
                            showCheckmark: true,
                            selected: draft.type == TxType.expense,
                            onSelected: (_) =>
                                update(draft.copyWith(type: TxType.expense)),
                          ),
                          ChoiceChip(
                            label: const Text('Income'),
                            showCheckmark: true,
                            selected: draft.type == TxType.income,
                            onSelected: (_) =>
                                update(draft.copyWith(type: TxType.income)),
                          ),
                        ],
                      ),

                      // ------------------------------------------------date range
                      const SectionHeader(
                        'Date range',
                        padding: EdgeInsets.fromLTRB(0, 20, 0, 8),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final option in _rangeOptions())
                            ChoiceChip(
                              label: Text(option.$1),
                              showCheckmark: true,
                              selected: draft.range == option.$2,
                              onSelected: (_) {
                                final range = option.$2;
                                update(
                                  range == null
                                      ? draft.copyWith(clearRange: true)
                                      : draft.copyWith(range: range),
                                );
                              },
                            ),
                        ],
                      ),

                      // ------------------------------------------ classification
                      const SectionHeader(
                        'Classification',
                        padding: EdgeInsets.fromLTRB(0, 20, 0, 8),
                      ),
                      CatalogPicker(
                        kind: CatalogKind.category,
                        label: 'Category',
                        valueId: draft.categoryId,
                        onChanged: (id) => update(
                          draft.copyWith(
                              categoryId: id, clearCategory: id == null),
                        ),
                      ),
                      const SizedBox(height: 12),
                      CatalogPicker(
                        kind: CatalogKind.incomeSource,
                        label: 'Income source',
                        valueId: draft.incomeSourceId,
                        onChanged: (id) => update(
                          draft.copyWith(
                              incomeSourceId: id,
                              clearIncomeSource: id == null),
                        ),
                      ),
                      const SizedBox(height: 12),
                      CatalogPicker(
                        kind: CatalogKind.paymentMethod,
                        label: 'Payment method',
                        valueId: draft.paymentMethodId,
                        onChanged: (id) => update(
                          draft.copyWith(
                              paymentMethodId: id,
                              clearPaymentMethod: id == null),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SpecialEventPicker(
                        valueId: draft.specialEventId,
                        onChanged: (id) => update(
                          draft.copyWith(
                              specialEventId: id, clearEvent: id == null),
                        ),
                      ),

                      // -------------------------------------------------- amount
                      const SectionHeader(
                        'Amount range',
                        padding: EdgeInsets.fromLTRB(0, 20, 0, 8),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: AmountField(
                              controller: minController,
                              label: 'Minimum',
                              errorText: minError,
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AmountField(
                              controller: maxController,
                              label: 'Maximum',
                              errorText: maxError,
                              textInputAction: TextInputAction.done,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),
                      Row(
                        children: [
                          TextButton(
                            onPressed: reset,
                            child: const Text('Reset'),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: apply,
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('Apply'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  ).whenComplete(() {
    minController.dispose();
    maxController.dispose();
  });
}

/// The offered date ranges, in display order; a `null` range means "All time".
List<(String, RangeSpec?)> _rangeOptions() => <(String, RangeSpec?)>[
      ('All time', null),
      ('Today', RangeSpec.today()),
      ('This week', RangeSpec.thisWeek()),
      ('This month', RangeSpec.thisMonth()),
      ('Last month', RangeSpec.thisMonth().previousMonth()),
      ('This year', RangeSpec.thisYear()),
    ];

/// Seed text for an amount field: empty when the filter has no bound.
String _minorText(int? minor) =>
    minor == null ? '' : minorToDecimalString(minor);
