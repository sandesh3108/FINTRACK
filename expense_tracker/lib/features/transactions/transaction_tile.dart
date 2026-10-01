import 'package:flutter/material.dart';

import '../../core/utils/date_utils.dart';
import '../../shared/models/tx_item.dart';
import '../../shared/widgets/common.dart';

/// A single row of the transaction history.
///
/// The row is entirely self describing: the type icon, the leading colour
/// circle, the trend icon next to the amount and the menu all carry the same
/// meaning, so nothing is communicated by colour alone. Long-pressing the row
/// is a shortcut for the trailing "Delete" menu entry.
class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.tx,
    required this.onTap,
    required this.onDelete,
  });

  /// Transaction rendered by this row.
  final TxItem tx;

  /// Opens the edit screen for [tx].
  final VoidCallback onTap;

  /// Asks for confirmation and then deletes [tx].
  final VoidCallback onDelete;

  static const String _deleteValue = 'delete';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final expense = tx.isExpense;
    final circleColor =
        expense ? colors.errorContainer : colors.primaryContainer;
    final circleContent =
        expense ? colors.onErrorContainer : colors.onPrimaryContainer;
    final amountColor = expense ? colors.error : colors.primary;
    final trendIcon =
        expense ? Icons.trending_down_rounded : Icons.trending_up_rounded;
    final secondary = _secondaryLine(tx);
    final time = AppDates.timeLabel(tx.time);

    return InkWell(
      onTap: onTap,
      onLongPress: onDelete,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ------------------------------------------------------- type mark
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration:
                  BoxDecoration(color: circleColor, shape: BoxShape.circle),
              child: Icon(trendIcon, size: 20, color: circleContent),
            ),
            const SizedBox(width: 12),

            // --------------------------------------------------------- labels
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tx.primaryLabel,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (secondary.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      secondary,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),

            // -------------------------------------------------- time & amount
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(trendIcon, size: 14, color: amountColor),
                    const SizedBox(width: 4),
                    Flexible(
                      child: MoneyText(
                        tx.amountMinor,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: amountColor,
                        ),
                      ),
                    ),
                  ],
                ),
                if (time.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    time,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),

            // --------------------------------------------------------- actions
            PopupMenuButton<String>(
              tooltip: 'Transaction options',
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (value) {
                if (value == _deleteValue) onDelete();
              },
              itemBuilder: (context) => const <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: _deleteValue,
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, size: 20),
                      SizedBox(width: 12),
                      Text('Delete'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Secondary line under the primary label: the category / income source when
/// it differs from [TxItem.primaryLabel] plus the payment method, falling back
/// to the note so the row never renders blank.
String _secondaryLine(TxItem tx) {
  final parts = <String>[];
  final classifier = tx.isExpense ? tx.categoryName : tx.incomeSourceName;
  if (classifier != null &&
      classifier.isNotEmpty &&
      classifier != tx.primaryLabel) {
    parts.add(classifier);
  }
  final method = tx.paymentMethodName;
  if (method != null && method.isNotEmpty) parts.add(method);
  if (parts.isEmpty && tx.note.isNotEmpty) parts.add(tx.note);
  return parts.join(' · ');
}
