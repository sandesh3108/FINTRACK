import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../shared/models/catalog_item.dart';
import '../../shared/models/transaction_input.dart';
import '../../shared/models/tx_type.dart';
import 'catalog_picker.dart';
import 'form_fields.dart';

/// The single add/edit form for a transaction.
///
/// Used unchanged by the quick-add tab and by the edit route, so both paths
/// produce identical [TransactionInput] values and share the same validation
/// messages. Nothing here touches the database directly - the caller persists
/// the input and reports errors back through [onError].
class TransactionForm extends ConsumerStatefulWidget {
  const TransactionForm({
    super.key,
    required this.initial,
    required this.onSubmit,
    this.submitLabel = 'Save transaction',
    this.busy = false,
    this.errorMessage,
    this.onErrorCleared,
  });

  final TransactionInput initial;
  final Future<void> Function(TransactionInput input) onSubmit;
  final String submitLabel;
  final bool busy;

  /// Error reported by the repository (e.g. a validation rule that only the
  /// database layer can check). Displayed above the submit button.
  final String? errorMessage;

  final VoidCallback? onErrorCleared;

  @override
  ConsumerState<TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends ConsumerState<TransactionForm> {
  late TxType _type = widget.initial.type;
  late final TextEditingController _amount =
      TextEditingController(text: widget.initial.amountMinor > 0 ? minorToDecimalString(widget.initial.amountMinor) : '');
  late DateTime _date = widget.initial.date;
  late String _time = widget.initial.time;
  late int? _categoryId = widget.initial.categoryId;
  late int? _incomeSourceId = widget.initial.incomeSourceId;
  late int? _paymentMethodId = widget.initial.paymentMethodId;
  late int? _eventId = widget.initial.specialEventId;
  late final TextEditingController _note =
      TextEditingController(text: widget.initial.note);

  final Map<String, String> _errors = <String, String>{};

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  TransactionInput get _input => TransactionInput(
        type: _type,
        amountMinor: parseMoneyToMinor(_amount.text) ?? 0,
        date: _date,
        time: _time,
        categoryId: _categoryId,
        incomeSourceId: _incomeSourceId,
        paymentMethodId: _paymentMethodId,
        specialEventId: _eventId,
        note: _note.text.trim(),
      );

  bool _validate() {
    _errors.clear();
    final minor = parseMoneyToMinor(_amount.text);

    if (minor == null) {
      _errors['amount'] = 'Enter an amount greater than zero.';
    }
    if (_type == TxType.expense) {
      if (_categoryId == null) _errors['category'] = 'Choose a category.';
      if (_paymentMethodId == null) {
        _errors['paymentMethod'] = 'Choose a payment method.';
      }
    } else if (_incomeSourceId == null) {
      _errors['incomeSource'] = 'Choose an income source.';
    }

    setState(() {});
    return _errors.isEmpty;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    widget.onErrorCleared?.call();
    if (!_validate()) return;
    await widget.onSubmit(_input);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // -------------------------------------------------------- type switch
        SegmentedButton<TxType>(
          segments: [
            ButtonSegment<TxType>(
              value: TxType.expense,
              label: const Text('Expense'),
              icon: const Icon(Icons.trending_down_rounded),
            ),
            ButtonSegment<TxType>(
              value: TxType.income,
              label: const Text('Income'),
              icon: const Icon(Icons.trending_up_rounded),
            ),
          ],
          selected: {_type},
          showSelectedIcon: false,
          onSelectionChanged: (selection) {
            setState(() {
              _type = selection.first;
              _errors.remove('category');
              _errors.remove('paymentMethod');
              _errors.remove('incomeSource');
            });
          },
          style: ButtonStyle(
            visualDensity: VisualDensity.comfortable,
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? (_type == TxType.expense ? colors.errorContainer : colors.primaryContainer)
                  : colors.surfaceContainerHighest.withValues(alpha: 0.5),
            ),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? (_type == TxType.expense
                      ? colors.onErrorContainer
                      : colors.onPrimaryContainer)
                  : colors.onSurfaceVariant,
            ),
          ),
        ),

        const SizedBox(height: 20),

        // ------------------------------------------------------------- amount
        AmountField(
          controller: _amount,
          autofocus: widget.initial.amountMinor == 0,
          errorText: _errors['amount'],
          onChanged: (_) {
            if (_errors.containsKey('amount')) {
              setState(() => _errors.remove('amount'));
            }
          },
          onSubmitted: (_) => _submit(),
        ),

        const SizedBox(height: 16),

        // -------------------------------------------------------- date & time
        Row(
          children: [
            Expanded(
              child: DateField(
                label: 'Date',
                value: _date,
                onChanged: (value) => setState(() => _date = value),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TimeField(
                label: 'Time',
                value: _time,
                onChanged: (value) => setState(() => _time = value),
              ),
            ),
          ],
        ),

        const SizedBox(height: 4),
        Text(
          'Recorded automatically as ${AppDates.dateTimeLabel(_date, _time)} - tap either field to change it.',
          style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),

        const SizedBox(height: 16),

        // --------------------------------------------------------- classifier
        if (_type == TxType.expense) ...[
          CatalogPicker(
            kind: CatalogKind.category,
            label: 'Category',
            valueId: _categoryId,
            errorText: _errors['category'],
            onChanged: (value) => setState(() {
              _categoryId = value;
              _errors.remove('category');
            }),
          ),
          const SizedBox(height: 16),
          CatalogPicker(
            kind: CatalogKind.paymentMethod,
            label: 'Payment method',
            valueId: _paymentMethodId,
            errorText: _errors['paymentMethod'],
            onChanged: (value) => setState(() {
              _paymentMethodId = value;
              _errors.remove('paymentMethod');
            }),
          ),
        ] else ...[
          CatalogPicker(
            kind: CatalogKind.incomeSource,
            label: 'Income source',
            valueId: _incomeSourceId,
            errorText: _errors['incomeSource'],
            onChanged: (value) => setState(() {
              _incomeSourceId = value;
              _errors.remove('incomeSource');
            }),
          ),
          const SizedBox(height: 16),
          // Income needs an account too: without this the money a salary adds
          // to a bank balance could never be reflected on the Accounts screen.
          // Optional, because income has always been recordable without one.
          CatalogPicker(
            kind: CatalogKind.paymentMethod,
            label: 'Deposited to',
            valueId: _paymentMethodId,
            hint: 'Which account received this',
            onChanged: (value) => setState(() {
              _paymentMethodId = value;
              _errors.remove('paymentMethod');
            }),
          ),
        ],

        const SizedBox(height: 16),

        SpecialEventPicker(
          valueId: _eventId ?? SpecialEventPicker.noneValue,
          onChanged: (value) => setState(() {
            _eventId = value == null || value <= 0 ? null : value;
          }),
        ),

        const SizedBox(height: 16),

        TextField(
          controller: _note,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 200,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Note (optional)',
            hintText: 'What was this for?',
            prefixIcon: Icon(Icons.notes_rounded),
            counterText: '',
          ),
        ),

        if (widget.errorMessage != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline_rounded, size: 18, color: colors.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.errorMessage!,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: colors.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),

        FilledButton.icon(
          onPressed: widget.busy ? null : _submit,
          icon: widget.busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded),
          label: Text(widget.submitLabel),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Builds the starting input for a brand-new transaction: now, `HH:mm`, and
/// the user's configured defaults where they exist.
TransactionInput freshTransactionInput({
  TxType type = TxType.expense,
  int? defaultCategoryId,
  int? defaultPaymentMethodId,
}) {
  final now = DateTime.now();
  return TransactionInput(
    type: type,
    amountMinor: 0,
    date: AppDates.day(now),
    time: AppDates.timeFrom(now),
    categoryId: defaultCategoryId,
    paymentMethodId: defaultPaymentMethodId,
  );
}
