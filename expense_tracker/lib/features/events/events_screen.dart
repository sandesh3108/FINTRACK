import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../core/errors/app_exception.dart' show ValidationException;
import '../../repositories/providers.dart';
import '../../shared/models/range_spec.dart';
import '../../shared/models/special_event.dart';
import '../../shared/widgets/common.dart';
import '../more/app_errors.dart';

/// Live list of the events shown on this screen.
///
/// Archived events are excluded, so archiving a card removes it from the list
/// the moment the repository re-emits.
final eventsListProvider = StreamProvider<List<SpecialEvent>>(
  (ref) => ref.watch(eventRepositoryProvider).watchAll(includeArchived: false),
);

/// Number of transactions linked to each event.
final eventUsageCountsProvider = FutureProvider.autoDispose<Map<int, int>>(
  (ref) => ref.watch(transactionRepositoryProvider).usageCountsByEvent(),
);

/// Lists every special event with its totals and per-event actions.
class EventsScreen extends ConsumerWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(eventsListProvider);
    final counts = ref.watch(eventUsageCountsProvider).valueOrNull ?? const <int, int>{};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Special events'),
        actions: [
          IconButton(
            onPressed: () => Navigator.pushNamed(context, AppRoutes.eventForm),
            tooltip: 'Create an event',
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: AsyncValueView<List<SpecialEvent>>(
        value: events,
        onRetry: () => ref.invalidate(eventsListProvider),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.celebration_outlined,
              title: 'No special events yet',
              message:
                  'Group transactions for a trip, festival or project and see exactly what it cost.',
              actionLabel: 'Create an event',
              onAction: () => Navigator.pushNamed(context, AppRoutes.eventForm),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              const _NoDoubleCountingNote(),
              const SizedBox(height: 4),
              for (final event in list) ...[
                _EventCard(
                  event: event,
                  transactionCount: counts[event.id] ?? event.transactionCount,
                  onOpen: () => _openReport(context, event),
                  onEdit: () => Navigator.pushNamed(
                    context,
                    AppRoutes.eventForm,
                    arguments: EventFormArgs(eventId: event.id),
                  ),
                  onArchive: () => _archive(context, ref, event),
                  onDelete: () => _delete(
                    context,
                    ref,
                    event,
                    counts[event.id] ?? event.transactionCount,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }

  void _openReport(BuildContext context, SpecialEvent event) {
    Navigator.pushNamed(
      context,
      AppRoutes.reportDetail,
      arguments: ReportDetailArgs(
        title: event.name,
        range: RangeSpec.thisYear(),
        specialEventId: event.id,
      ),
    );
  }

  Future<void> _archive(
    BuildContext context,
    WidgetRef ref,
    SpecialEvent event,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Archive ${event.name}?',
      message: 'Archiving hides it from new entries but keeps it on existing '
          'transactions - nothing is deleted.',
      confirmLabel: 'Archive',
    );
    if (!confirmed || !context.mounted) return;

    try {
      await ref.read(eventRepositoryProvider).setArchived(event.id, true);
      ref.invalidate(eventsListProvider);
      if (!context.mounted) return;
      showAppMessage(
        context,
        '${event.name} archived - history is always kept',
      );
    } catch (error) {
      if (!context.mounted) return;
      showAppMessage(context, friendlyMessage(error), error: true);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    SpecialEvent event,
    int count,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete ${event.name}?',
      message: count > 0
          ? '${event.name} is linked to $count ${count == 1 ? 'transaction' : 'transactions'}. '
              'An event with history cannot be deleted - archive it instead, history is always kept.'
          : 'This permanently removes ${event.name}. Existing transactions are not affected.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    try {
      await ref.read(eventRepositoryProvider).delete(event.id);
      ref.invalidate(eventsListProvider);
      ref.invalidate(eventUsageCountsProvider);
      if (!context.mounted) return;
      showAppMessage(context, 'Event deleted');
    } on ValidationException catch (error) {
      if (!context.mounted) return;
      showAppMessage(context, eventDeleteRefusedMessage(error, count), error: true);
    } catch (error) {
      if (!context.mounted) return;
      showAppMessage(context, friendlyMessage(error), error: true);
    }
  }
}

/// Explains a refused event delete: the repository's reason plus the explicit
/// archive-not-delete rule the UI must always spell out.
String eventDeleteRefusedMessage(ValidationException error, int usage) {
  final base = friendlyMessage(error);
  if (base.toLowerCase().contains('archive')) return base;
  return '$base Used by $usage transactions. '
      'Archive it instead - history is always kept.';
}

/// One card per event: identity, totals, transaction count and actions.
class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.transactionCount,
    required this.onOpen,
    required this.onEdit,
    required this.onArchive,
    required this.onDelete,
  });

  final SpecialEvent event;
  final int transactionCount;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final count = transactionCount;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          event.dateRangeLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'More actions for ${event.name}',
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          onEdit();
                        case 'archive':
                          onArchive();
                        case 'delete':
                          onDelete();
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem<String>(
                        value: 'edit',
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.edit_outlined, size: 18),
                            SizedBox(width: 10),
                            Text('Edit event'),
                          ],
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'archive',
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.archive_outlined, size: 18),
                            SizedBox(width: 10),
                            Text('Archive'),
                          ],
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.delete_outline_rounded, size: 18),
                            SizedBox(width: 10),
                            Text('Delete'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (event.description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  event.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              _MoneyRow(label: 'Income', minor: event.incomeMinor, color: colors.primary),
              _MoneyRow(label: 'Expense', minor: event.expenseMinor, color: colors.tertiary),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Divider(height: 1),
              ),
              _MoneyRow(
                label: 'Balance',
                minor: event.balanceMinor,
                color: colors.onSurface,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  AppBadge(
                    label: '$count ${count == 1 ? 'transaction' : 'transactions'}',
                    icon: Icons.receipt_long_outlined,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tap to open the event report',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Label / amount line used inside the event cards.
class _MoneyRow extends StatelessWidget {
  const _MoneyRow({
    required this.label,
    required this.minor,
    required this.color,
  });

  final String label;
  final int minor;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          MoneyText(
            minor,
            style: theme.textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Banner explaining why event totals never double count a transaction.
class _NoDoubleCountingNote extends StatelessWidget {
  const _NoDoubleCountingNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: colors.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Event totals only count transactions linked to this event, so a '
              'transaction in an event is never counted twice in reports.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
