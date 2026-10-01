import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/security/balance_pin.dart';
import '../../core/utils/money.dart';
import '../../repositories/providers.dart';
import '../../shared/models/account_balance.dart';
import '../../shared/models/app_settings.dart';
import '../../shared/models/catalog_item.dart';
import '../../shared/widgets/catalog_picker.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/form_fields.dart';
import '../../shared/widgets/pin_dialog.dart';

/// Per-account balances: PhonePe, Google Pay, Cash and BOI(Saving) out of the
/// box, plus anything else the user adds as a payment method.
///
/// A payment method *is* the account here. Picking one on a transaction is what
/// moves money through it, so the remaining balance is derived rather than
/// entered: the opening balance typed once, plus every income ever recorded
/// against the account, minus every expense.
///
/// When the user has turned on *Protect account balances*, this screen is
/// gated: nothing on it is rendered until the PIN has been typed in this
/// session. The gate exists for a phone that has been picked up unlocked, so
/// it starts closed on every launch and is never persisted.
class AccountsScreen extends ConsumerWidget {
  /// Creates the pushed `Accounts` screen.
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountBalancesProvider);
    // Until settings resolve there is no PIN to ask for, so the screen opens
    // normally rather than flashing a padlock at a cold start.
    final settings = ref.watch(settingsProvider).valueOrNull ?? const AppSettings();
    final unlocked = ref.watch(balanceUnlockedProvider);
    final lockEnabled = settings.hasBalanceLock;
    final locked = lockEnabled && !unlocked;

    // Adding, editing or deleting a transaction changes a balance somewhere on
    // this screen, so re-derive them whenever the ledger moves.
    ref.listen(ledgerRevisionProvider, (previous, next) {
      if (next.hasValue && next.valueOrNull != previous?.valueOrNull) {
        ref.invalidate(accountBalancesProvider);
      }
    });

    // Adding, renaming or archiving an account is a catalog change rather than
    // a ledger one, so it needs its own subscription.
    ref.listen(catalogListProvider(CatalogKind.paymentMethod), (previous, next) {
      if (previous?.valueOrNull == null) return; // first snapshot, not a change
      ref.invalidate(accountBalancesProvider);
    });

    return PopScope(
      canPop: true,
      // Leaving this screen closes the lock again, so the figures are only
      // ever on screen for whoever just typed the PIN - not for the next
      // person to pick up a phone the app was left open on. Re-locking here
      // rather than on a timer is what keeps "visible only after the
      // password" true without asking the user to remember to do it.
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) ref.read(balanceUnlockedProvider.notifier).state = false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Accounts'),
          actions: [
            if (lockEnabled && !locked)
              IconButton(
                tooltip: 'Lock balances again',
                onPressed: () =>
                    ref.read(balanceUnlockedProvider.notifier).state = false,
                icon: const Icon(Icons.lock_rounded),
              ),
          ],
        ),
        body: locked
            ? _lockedBody(context, ref, settings)
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  AsyncValueView<List<AccountBalance>>(
                    value: accounts,
                    loadingLabel: 'Working out the balances...',
                    onRetry: () => ref.invalidate(accountBalancesProvider),
                    data: (rows) => rows.isEmpty
                        ? const EmptyState(
                            icon: Icons.account_balance_wallet_outlined,
                            title: 'No accounts yet',
                            message:
                                'Add a payment method from Manage \u2192 Payment '
                                'methods and it will show up here as an account.',
                          )
                        : _content(context, rows),
                  ),
                ],
              ),
      ),
    );
  }

  /// Shown instead of the balances while the PIN is still needed.
  ///
  /// Deliberately reveals nothing about the money - not the total, not which
  /// account is up or down - because the whole point of the lock is that a
  /// borrowed phone cannot read it.
  Widget _lockedBody(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.lock_rounded,
                size: 30,
                color: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Balances are locked',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter your balance PIN to see how much is left in each '
              'account.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: () => _unlock(context, ref, settings),
              icon: const Icon(Icons.lock_open_rounded),
              label: const Text('Unlock'),
            ),
          ],
        ),
      ),
    );
  }

  /// Asks for the PIN and opens the session on a match.
  ///
  /// A wrong entry says so and changes nothing; there is no lockout counter,
  /// because the thing being protected is a balance someone can already see
  /// the moment they open their banking app.
  Future<void> _unlock(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) async {
    final pin = await showPinDialog(
      context,
      title: 'Enter your balance PIN',
      message: 'Required before any balance is shown.',
    );
    if (pin == null || !context.mounted) return;

    if (BalancePin.matches(
      pin,
      settings.balancePinHash,
      settings.balancePinSalt,
    )) {
      ref.read(balanceUnlockedProvider.notifier).state = true;
    } else {
      showAppMessage(context, 'That PIN is not correct.', error: true);
    }
  }

  /// Total card, the how-it-works note and one card per account.
  Widget _content(BuildContext context, List<AccountBalance> rows) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final total =
        rows.fold<int>(0, (sum, account) => sum + account.remainingMinor);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total balance',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 6),
                MoneyText(
                  total,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Opening balance plus everything received minus everything '
                  'spent, across all ${rows.length} '
                  '${rows.length == 1 ? 'account' : 'accounts'}.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SectionHeader('Accounts'),
        for (var i = 0; i < rows.length; i++) ...[
          _AccountCard(account: rows[i]),
          if (i != rows.length - 1) const SizedBox(height: 12),
        ],
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 18, color: colors.primary),
                    const SizedBox(width: 8),
                    Text(
                      'How this works',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter the balance you started each account with, once. From '
                  'then on the balance keeps itself up to date: choosing an '
                  'account when you add a transaction adds to it, and spending '
                  'from it takes away. Nothing here has to be entered twice.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One account: its opening balance, what has flowed through it and what is
/// left, with the opening balance editable in place.
class _AccountCard extends ConsumerWidget {
  const _AccountCard({required this.account});

  final AccountBalance account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final remaining = account.remainingMinor;
    final balanceColor = remaining < 0 ? colors.error : colors.onSurface;
    final needsOpening = account.openingMinor == 0 && !account.hasActivity;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.account_balance_wallet_rounded,
                    size: 20,
                    color: colors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    account.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Edit opening balance for ${account.name}',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _editOpeningBalance(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _figure(
              context,
              label: 'Opening balance',
              value: account.openingMinor,
              color: colors.onSurfaceVariant,
              trailing: needsOpening
                  ? TextButton(
                      onPressed: () => _editOpeningBalance(context, ref),
                      child: const Text('Add balance'),
                    )
                  : null,
            ),
            _figure(
              context,
              label: 'Received',
              value: account.incomeMinor,
              color: colors.primary,
            ),
            _figure(
              context,
              label: 'Spent',
              value: account.expenseMinor,
              color: colors.tertiary,
            ),
            const SizedBox(height: 4),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Remaining balance',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                MoneyText(
                  remaining,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: balanceColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// A label / amount line inside an account card.
  Widget _figure(
    BuildContext context, {
    required String label,
    required int value,
    required Color color,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          if (trailing != null) ...[
            Text(label, style: theme.textTheme.bodyMedium),
            const Spacer(),
            trailing,
          ] else ...[
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            MoneyText(value, style: theme.textTheme.bodyLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            )),
          ],
        ],
      ),
    );
  }

  Future<void> _editOpeningBalance(BuildContext context, WidgetRef ref) async {
    final minor = await showOpeningBalanceDialog(context, account: account);
    if (minor == null) return; // dismissed

    try {
      await ref.read(catalogRepositoryProvider).setOpeningBalance(
            CatalogKind.paymentMethod,
            account.paymentMethodId,
            minor,
          );
      ref.invalidate(accountBalancesProvider);
    } catch (error) {
      if (!context.mounted) return;
      showAppMessage(
        context,
        error is AppException ? error.message : 'Could not save the balance.',
        error: true,
      );
    }
  }
}

/// Prompts for an account's opening balance and returns it in minor units.
///
/// Returns `null` when the dialog is dismissed without saving, so the caller
/// can tell "cancelled" from "saved zero".
Future<int?> showOpeningBalanceDialog(
  BuildContext context, {
  required AccountBalance account,
}) {
  return showDialog<int>(
    context: context,
    builder: (context) => _OpeningBalanceDialog(account: account),
  );
}

class _OpeningBalanceDialog extends StatefulWidget {
  const _OpeningBalanceDialog({required this.account});

  final AccountBalance account;

  @override
  State<_OpeningBalanceDialog> createState() => _OpeningBalanceDialogState();
}

class _OpeningBalanceDialogState extends State<_OpeningBalanceDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: minorToDecimalString(widget.account.openingMinor),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final minor = parseMoneyToMinor(_controller.text);
    if (minor == null) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }
    Navigator.of(context).pop(minor);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('Opening balance'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The balance ${widget.account.name} started with. Every '
            'transaction you record against it updates the rest for you.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          AmountField(
            controller: _controller,
            label: 'Opening balance',
            autofocus: true,
            errorText: _error,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
