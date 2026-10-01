/// One tappable row summarising a transaction.
///
/// Shared by the dashboard's "Recent transactions" section and by the Add
/// tab's "Recently added" list, so both show exactly the same information in
/// exactly the same shape. The widget only renders a [TxItem]; opening the
/// editor is the caller's decision, which keeps navigation in the screens.
library;

import 'package:flutter/material.dart';

import '../../core/utils/date_utils.dart';
import '../../shared/models/tx_item.dart';
import '../../shared/widgets/common.dart';

/// Displays [transaction] as an icon, its primary label, the note, the date
/// and time, and the amount coloured by type.
///
/// Colour is never the only signal: the leading icon shows the direction of
/// the money (up for income, down for expense) and the amount repeats the
/// same figure as text, so the row stays readable without colour perception.
class TransactionListTile extends StatelessWidget {
  /// Creates a transaction row.
  const TransactionListTile({super.key, required this.transaction, this.onTap});

  /// The row to render.
  final TxItem transaction;

  /// Called when the user taps the row - typically pushes the edit route.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tx = transaction;

    // Income reads as "money in" (primary + upward arrow) and expense as
    // "money out" (error + downward arrow); the icon carries the meaning.
    final accent = tx.isIncome ? colors.primary : colors.error;
    final details = <String>[
      if (tx.note.isNotEmpty) tx.note,
      AppDates.dateLabel(tx.date),
      AppDates.timeLabel(tx.time),
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            tx.isIncome
                ? Icons.trending_up_rounded
                : Icons.trending_down_rounded,
            size: 20,
            color: accent,
          ),
        ),
        title: Text(
          tx.primaryLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          details.join(' • '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        trailing: MoneyText(
          tx.amountMinor,
          align: TextAlign.right,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: accent,
          ),
        ),
      ),
    );
  }
}
