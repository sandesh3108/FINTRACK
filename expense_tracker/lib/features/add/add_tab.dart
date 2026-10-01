/// Add tab: the quick-entry form for new transactions.
///
/// The form itself is the shared [TransactionForm]; this file only owns the
/// draft it edits, the save call, and the "Recently added" list below it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../core/errors/app_exception.dart' show ValidationException;
import '../../repositories/providers.dart';
import '../../shared/models/app_settings.dart';
import '../../shared/models/transaction_filter.dart';
import '../../shared/models/transaction_input.dart';
import '../../shared/models/tx_item.dart';
import '../../shared/models/tx_type.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/transaction_form.dart';
import '../dashboard/transaction_list_tile.dart';
import '../more/app_errors.dart';

/// The five newest transactions of the whole ledger, live.
///
/// Streams refresh themselves, so a save here - or an edit made in the pushed
/// editor - shows up without any explicit invalidation. The type is inferred:
/// `StreamProvider.family` is a factory method, not a type.
final _recentTransactionsProvider =
    StreamProvider.family<List<TxItem>, TransactionFilter>(
  (ref, filter) =>
      ref.watch(transactionRepositoryProvider).watchTransactions(filter),
);

/// Newest first, five rows. As a value-equality key it keeps the family at a
/// single instance for the lifetime of this screen.
const TransactionFilter _recentFilter =
    TransactionFilter(pageSize: 5, sort: TxSort.dateDesc);

/// The Add bottom-bar tab: a fresh transaction form plus the last few saved
/// entries, so what was just recorded can be checked or corrected at once.
class AddTab extends ConsumerStatefulWidget {
  /// Creates the Add tab.
  const AddTab({super.key});

  @override
  ConsumerState<AddTab> createState() => _AddTabState();
}

class _AddTabState extends ConsumerState<AddTab> {
  /// The draft currently loaded in the form.
  ///
  /// Held in a local field - not rebuilt from settings on every emission -
  /// so a settings stream refresh can never clobber what the user is typing.
  TransactionInput _input = freshTransactionInput();

  /// Replaced on every reset: [TransactionForm] only reads its `initial` value
  /// when its state is created, so a new key is what applies the new draft.
  Key _formKey = const ValueKey<String>('add-transaction-form');

  /// Serial number mixed into the key so two resets never share one.
  int _resetSerial = 0;

  /// True while the repository call is in flight.
  bool _busy = false;

  /// Friendly text for the last failure, cleared when the form is resubmitted.
  String? _errorMessage;

  /// Settings defaults are applied exactly once: on the first build where
  /// they are readable, and again after a successful save or a manual reset.
  bool _defaultsApplied = false;

  @override
  Widget build(BuildContext context) {
    final AppSettings? settings = ref.watch(settingsProvider).valueOrNull;
    if (!_defaultsApplied && settings != null) {
      // The database answers within the first frames, so the form is still
      // untouched here; the guard keeps that true even if it does not.
      final applyDefaults = _isPristine();
      _defaultsApplied = true;
      if (applyDefaults) {
        _input = _freshInput(settings);
        _formKey = _freshFormKey();
      }
    }

    final recentAsync = ref.watch(_recentTransactionsProvider(_recentFilter));

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: const Text('Add transaction')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          TransactionForm(
            key: _formKey,
            initial: _input,
            onSubmit: _submit,
            busy: _busy,
            errorMessage: _errorMessage,
            onErrorCleared: () => setState(() => _errorMessage = null),
          ),
          Center(
            child: TextButton.icon(
              onPressed: _busy ? null : _resetForm,
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Reset form'),
            ),
          ),
          const SectionHeader('Recently added'),
          AsyncValueView<List<TxItem>>(
            value: recentAsync,
            onRetry: () => ref.invalidate(_recentTransactionsProvider),
            data: (items) => items.isEmpty
                ? const EmptyState(
                    icon: Icons.receipt_long_rounded,
                    title: 'Nothing saved yet',
                    message:
                        'The transactions you add appear here so you can check them straight away.',
                    compact: true,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final transaction in items)
                        TransactionListTile(
                          transaction: transaction,
                          onTap: () => Navigator.pushNamed(
                            context,
                            AppRoutes.editTransaction,
                            arguments: EditTransactionArgs(transaction),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// True while the draft still equals what a blank form would hold.
  bool _isPristine() =>
      _input.type == TxType.expense &&
      _input.amountMinor == 0 &&
      _input.note.isEmpty &&
      _input.categoryId == null &&
      _input.incomeSourceId == null &&
      _input.paymentMethodId == null &&
      _input.specialEventId == null;

  /// A brand-new draft carrying the user's configured defaults.
  TransactionInput _freshInput([AppSettings? settings]) {
    final effective = settings ?? ref.read(settingsProvider).valueOrNull;
    return freshTransactionInput(
      defaultCategoryId: effective?.defaultCategoryId,
      defaultPaymentMethodId: effective?.defaultPaymentMethodId,
    );
  }

  /// Time-based key that forces [TransactionForm] to rebuild from [_input].
  ///
  /// The serial is bumped with a plain assignment so two resets inside the
  /// same millisecond still produce two different keys.
  Key _freshFormKey() {
    _resetSerial = _resetSerial + 1;
    return ValueKey<String>(
      'add-transaction-form-$_resetSerial-${DateTime.now().millisecondsSinceEpoch}',
    );
  }

  /// Restores a blank form and drops any error from the previous attempt.
  void _resetForm() {
    setState(() {
      _input = _freshInput();
      _formKey = _freshFormKey();
      _errorMessage = null;
      _defaultsApplied = true;
    });
  }

  /// Persists [input]; on success the form starts over, on any failure the
  /// draft stays exactly as the user left it.
  Future<void> _submit(TransactionInput input) async {
    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    try {
      await ref.read(transactionRepositoryProvider).add(input);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorMessage = null;
        _input = _freshInput();
        _formKey = _freshFormKey();
        _defaultsApplied = true;
      });
      showAppMessage(
        context,
        input.type == TxType.expense ? 'Expense added' : 'Income added',
      );
    } on ValidationException catch (error) {
      // A business rule only the repository can check: keep the draft exactly
      // as typed so the offending value can be corrected, and say what failed.
      _reportFailure(error);
    } catch (error) {
      // Storage failures behave the same way - never discard the user's input.
      _reportFailure(error);
    }
  }

  /// Turns a failed save into friendly text without losing the draft.
  void _reportFailure(Object error) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _errorMessage = friendlyMessage(error);
    });
  }
}
