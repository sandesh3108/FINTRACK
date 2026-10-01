import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/date_utils.dart';
import '../../repositories/providers.dart';
import '../../shared/models/transaction_input.dart';
import '../../shared/models/tx_item.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/transaction_form.dart';

/// Live copy of the transaction being edited.
///
/// A `null` result means the row was removed somewhere else while this screen
/// was open, which is reported instead of letting the user edit a ghost.
final _liveTransactionProvider =
    FutureProvider.autoDispose.family<TxItem?, int>(
  (ref, id) => ref.watch(transactionRepositoryProvider).getById(id),
);

/// Edit an existing transaction: change any field, save, or delete it.
class EditTransactionScreen extends ConsumerStatefulWidget {
  const EditTransactionScreen({super.key, required this.transaction});

  /// The row as it looked when the screen was opened; the live copy is loaded
  /// separately so a concurrent change or deletion is noticed.
  final TxItem transaction;

  @override
  ConsumerState<EditTransactionScreen> createState() =>
      _EditTransactionScreenState();
}

class _EditTransactionScreenState extends ConsumerState<EditTransactionScreen> {
  /// Pristine input the form started from; the basis for the dirty check.
  late TransactionInput _original;

  /// Replaced with a fresh key to rebuild the form when the user discards.
  Key _formKey = UniqueKey();

  bool _dirty = false;
  bool _busy = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _original = widget.transaction.toInput();
  }

  /// Field-by-field comparison against the input the screen started with.
  bool _hasChanges(TransactionInput input) =>
      input.type != _original.type ||
      input.amountMinor != _original.amountMinor ||
      !input.date.isAtSameMomentAs(_original.date) ||
      input.time != _original.time ||
      input.categoryId != _original.categoryId ||
      input.incomeSourceId != _original.incomeSourceId ||
      input.paymentMethodId != _original.paymentMethodId ||
      input.specialEventId != _original.specialEventId ||
      input.note != _original.note;

  // ------------------------------------------------------------------- save

  Future<void> _save(TransactionInput input) async {
    if (_busy) return;
    if (!_hasChanges(input)) {
      showAppMessage(context, 'No changes to save');
      return;
    }
    setState(() {
      _busy = true;
      _dirty = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(transactionRepositoryProvider)
          .edit(widget.transaction.id, input);
      if (!mounted) return;
      setState(() => _busy = false);
      ref.invalidate(_liveTransactionProvider(widget.transaction.id));
      showAppMessage(context, 'Changes saved');
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorMessage = friendlyMessage(error);
      });
    }
  }

  // ---------------------------------------------------------------- discard

  Future<void> _discardChanges() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Discard changes?',
      message: 'Your edits to this transaction will be lost.',
      confirmLabel: 'Discard',
      cancelLabel: 'Keep editing',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _original = widget.transaction.toInput();
      _formKey = UniqueKey();
      _dirty = false;
      _errorMessage = null;
    });
    showAppMessage(context, 'Changes discarded');
  }

  /// Runs when [PopScope] blocks the back gesture because the form is dirty:
  /// confirms, then closes the screen without saving.
  Future<void> _confirmDiscardAndPop() async {
    final discard = await showConfirmDialog(
      context,
      title: 'Discard changes?',
      message: 'Your edits to this transaction have not been saved.',
      confirmLabel: 'Discard',
      cancelLabel: 'Keep editing',
      destructive: true,
    );
    if (!discard || !mounted) return;
    setState(() => _dirty = false);
    Navigator.of(context).pop();
  }

  // ----------------------------------------------------------------- delete

  Future<void> _deleteTransaction() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete transaction?',
      message: 'This permanently removes the transaction from your history. '
          'This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref
          .read(transactionRepositoryProvider)
          .remove(widget.transaction.id);
      ref.invalidate(_liveTransactionProvider(widget.transaction.id));
      if (!mounted) return;
      showAppMessage(context, 'Transaction deleted');
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, friendlyMessage(error), error: true);
    }
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _confirmDiscardAndPop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Edit transaction'),
          actions: [
            IconButton(
              tooltip: 'Delete transaction',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _busy ? null : _deleteTransaction,
            ),
          ],
        ),
        body: AsyncValueView<TxItem?>(
          value: ref.watch(_liveTransactionProvider(widget.transaction.id)),
          onRetry: () =>
              ref.invalidate(_liveTransactionProvider(widget.transaction.id)),
          data: (tx) => tx == null ? _buildMissingState() : _buildEditor(tx),
        ),
      ),
    );
  }

  Widget _buildMissingState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'This transaction no longer exists',
              message: 'It may have been deleted from another screen.',
              compact: true,
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Go back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor(TxItem tx) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Focus(
        // TransactionForm only reports back when it is submitted, so focus
        // moving into the form is the earliest reliable signal that the user
        // started editing - that is what arms the discard prompt.
        onFocusChange: (hasFocus) {
          if (hasFocus && !_dirty) setState(() => _dirty = true);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TransactionForm(
              key: _formKey,
              initial: _original,
              submitLabel: 'Save changes',
              busy: _busy,
              errorMessage: _errorMessage,
              onErrorCleared: () {
                if (_errorMessage != null) setState(() => _errorMessage = null);
              },
              onSubmit: _save,
            ),
            _buildInfoCard(tx),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: _discardChanges,
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Discard changes'),
            ),
          ],
        ),
      ),
    );
  }

  /// Created / last-updated stamps plus the linked special event, if any.
  Widget _buildInfoCard(TxItem tx) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final eventName = tx.specialEventName;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _infoCell(
                theme,
                Icons.schedule_rounded,
                'Created',
                _stamp(tx.createdAt),
              ),
              _infoCell(
                theme,
                Icons.update_rounded,
                'Last updated',
                _stamp(tx.updatedAt),
              ),
            ],
          ),
          if (eventName != null && eventName.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.celebration_outlined,
                    size: 16, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    eventName,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoCell(ThemeData theme, IconData icon, String label, String value) {
    final color = theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '$label $value',
            style: theme.textTheme.bodySmall?.copyWith(color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _stamp(DateTime value) =>
      AppDates.dateTimeLabel(AppDates.day(value), AppDates.timeFrom(value));
}
