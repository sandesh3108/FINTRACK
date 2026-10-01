import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart' show ValidationException;
import '../../repositories/providers.dart';
import '../../shared/models/catalog_item.dart';
import '../../shared/widgets/catalog_picker.dart';
import '../../shared/widgets/common.dart';
import '../more/app_errors.dart';

/// Number of transactions that reference each row of one catalog.
///
/// The catalog stream itself carries no usage figures, so the management
/// screen loads them separately and shows why a row can be archived but not
/// deleted.
final catalogUsageCountsProvider =
    FutureProvider.autoDispose.family<Map<int, int>, CatalogKind>((ref, kind) {
  final repository = ref.watch(transactionRepositoryProvider);
  return switch (kind) {
    CatalogKind.category => repository.usageCountsByCategory(),
    CatalogKind.incomeSource => repository.usageCountsByIncomeSource(),
    CatalogKind.paymentMethod => repository.usageCountsByPaymentMethod(),
  };
});

/// Client-side search text applied to the catalog list.
final catalogSearchProvider = StateProvider.autoDispose<String>((ref) => '');

/// Manages exactly one catalog: categories, income sources or payment
/// methods.
///
/// The screen is intentionally generic - [kind] decides the title, the icons,
/// the repository calls and the copy, so all three catalogs behave
/// identically.
class CatalogScreen extends ConsumerWidget {
  const CatalogScreen({super.key, required this.kind, this.title});

  /// Which catalog is being managed.
  final CatalogKind kind;

  /// Optional override for the app bar title.
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final search = ref.watch(catalogSearchProvider).trim().toLowerCase();
    final items = ref.watch(catalogListProvider(kind));
    final counts =
        ref.watch(catalogUsageCountsProvider(kind)).valueOrNull ?? const <int, int>{};

    // These are futures, not streams, so without this the screen would keep
    // whatever was computed the first time it opened. Watching the ledger
    // revision re-runs them whenever a transaction is added, edited or deleted
    // anywhere in the app - which is what makes a new row appear without
    // closing and reopening the app.
    ref.listen(ledgerRevisionProvider, (previous, next) {
      if (next.hasValue && next.valueOrNull != previous?.valueOrNull) {
        ref.invalidate(catalogUsageCountsProvider);
      }
    });


    return Scaffold(
      appBar: AppBar(
        title: Text(title ?? kind.title),
        actions: [
          IconButton(
            onPressed: () => _add(context, ref),
            tooltip: 'Add ${kind.singular}',
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              onChanged: (value) =>
                  ref.read(catalogSearchProvider.notifier).state = value,
              textInputAction: TextInputAction.search,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Search ${kind.title.toLowerCase()}',
                hintText: 'Type to filter',
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            ),
          ),
          Expanded(
            child: AsyncValueView<List<CatalogItem>>(
              value: items,
              onRetry: () => ref.invalidate(catalogListProvider(kind)),
              data: (rows) => _buildList(context, ref, rows, search, counts),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ list

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    List<CatalogItem> rows,
    String search,
    Map<int, int> counts,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (rows.isEmpty) {
      return EmptyState(
        icon: CatalogPicker.iconFor(kind),
        title: 'No ${kind.title.toLowerCase()} yet',
        message:
            'Create your first ${kind.singular.toLowerCase()} so entries only take a tap.',
        actionLabel: 'Add ${kind.singular}',
        onAction: () => _add(context, ref),
      );
    }

    final matches = rows
        .where((item) => search.isEmpty || item.name.toLowerCase().contains(search))
        .toList();
    if (matches.isEmpty) {
      return EmptyState(
        compact: true,
        icon: Icons.search_off_rounded,
        title: 'No matches',
        message: 'Nothing in ${kind.title.toLowerCase()} matches your search.',
        actionLabel: 'Add ${kind.singular}',
        onAction: () => _add(context, ref),
      );
    }

    final active = matches.where((item) => item.isActive).toList();
    final archived = matches.where((item) => !item.isActive).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (active.isNotEmpty)
          Card(
            child: Column(
              children: [
                for (var i = 0; i < active.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _buildRow(context, ref, active[i], counts),
                ],
              ],
            ),
          ),
        if (archived.isNotEmpty) ...[
          SectionHeader(
            'Archived',
            trailing: Text(
              '${archived.length}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < archived.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _buildRow(context, ref, archived[i], counts),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ------------------------------------------------------------------ row

  Widget _buildRow(
    BuildContext context,
    WidgetRef ref,
    CatalogItem item,
    Map<int, int> counts,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final count = counts[item.id] ?? item.usageCount;
    final nameStyle = item.isActive
        ? null
        : TextStyle(
            fontStyle: FontStyle.italic,
            color: colors.onSurfaceVariant,
          );

    final String subtitle;
    if (!item.isActive) {
      subtitle = 'Archived - hidden from new entries, history kept';
    } else if (count > 0) {
      subtitle =
          'Used by $count ${count == 1 ? 'transaction' : 'transactions'} - archive instead of deleting';
    } else {
      subtitle = 'Active - available for new entries';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colors.primaryContainer.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            item.isActive ? CatalogPicker.iconFor(kind) : Icons.archive_outlined,
            size: 20,
            color: colors.onPrimaryContainer,
          ),
        ),
        title: Text(
          item.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: nameStyle,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            if (count > 0 || item.isDefault)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (count > 0)
                      AppBadge(
                        label: '$count tx',
                        icon: Icons.receipt_long_outlined,
                      ),
                    if (item.isDefault)
                      Tooltip(
                        message:
                            'Built-in ${kind.singular.toLowerCase()} - it can be renamed but never deleted',
                        child: const AppBadge(
                          label: 'Default',
                          icon: Icons.lock_outline_rounded,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () => _toggleArchive(context, ref, item),
              tooltip: item.isActive
                  ? 'Archive ${item.name}'
                  : 'Unarchive ${item.name}',
              icon: Icon(
                item.isActive ? Icons.archive_outlined : Icons.unarchive_rounded,
              ),
            ),
            _rowMenu(context, ref, item, count),
          ],
        ),
      ),
    );
  }

  PopupMenuButton<String> _rowMenu(
    BuildContext context,
    WidgetRef ref,
    CatalogItem item,
    int count,
  ) {
    return PopupMenuButton<String>(
      tooltip: 'More actions for ${item.name}',
      onSelected: (value) {
        switch (value) {
          case 'rename':
            _rename(context, ref, item);
          case 'archive':
            _toggleArchive(context, ref, item);
          case 'delete':
            _delete(context, ref, item, count);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem<String>(
          value: 'rename',
          child: _MenuEntry(icon: Icons.edit_outlined, label: 'Rename'),
        ),
        if (item.isActive)
          const PopupMenuItem<String>(
            value: 'archive',
            child: _MenuEntry(
              icon: Icons.archive_outlined,
              label: 'Archive instead',
              caption:
                  'Archiving hides it from new entries but keeps it on existing transactions',
            ),
          )
        else
          const PopupMenuItem<String>(
            value: 'archive',
            child: _MenuEntry(icon: Icons.unarchive_rounded, label: 'Unarchive'),
          ),
        if (item.isDefault)
          PopupMenuItem<String>(
            value: 'delete',
            enabled: false,
            child: Tooltip(
              message: 'Built-in rows are always kept - archive it instead',
              child: const _MenuEntry(
                icon: Icons.lock_outline_rounded,
                label: 'Delete',
                caption: 'Not available for built-in rows',
              ),
            ),
          )
        else
          const PopupMenuItem<String>(
            value: 'delete',
            child: _MenuEntry(
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
              caption: 'Only rows with no transactions can be deleted',
            ),
          ),
      ],
    );
  }

  // -------------------------------------------------------------- actions

  /// Add flow: one shared name dialog, then `findOrCreate`.
  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = await showCatalogNameDialog(context, kind: kind);
    if (name == null || !context.mounted) return;
    try {
      await ref.read(catalogRepositoryProvider).findOrCreate(kind, name);
      ref.invalidate(catalogUsageCountsProvider(kind));
      if (!context.mounted) return;
      showAppMessage(context, '${kind.singular} added');
    } catch (error) {
      if (!context.mounted) return;
      showAppMessage(context, friendlyMessage(error), error: true);
    }
  }

  /// Rename flow: the same dialog, prefilled with the current name.
  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    CatalogItem item,
  ) async {
    final name = await showCatalogNameDialog(
      context,
      kind: kind,
      initialName: item.name,
    );
    if (name == null || !context.mounted) return;
    try {
      await ref.read(catalogRepositoryProvider).rename(kind, item.id, name);
      if (!context.mounted) return;
      showAppMessage(context, '${kind.singular} renamed');
    } catch (error) {
      if (!context.mounted) return;
      showAppMessage(context, friendlyMessage(error), error: true);
    }
  }

  /// Archiving is always allowed: it only hides the row from new entries.
  Future<void> _toggleArchive(
    BuildContext context,
    WidgetRef ref,
    CatalogItem item,
  ) async {
    final next = !item.isActive;
    try {
      await ref.read(catalogRepositoryProvider).setActive(kind, item.id, next);
      if (!context.mounted) return;
      showAppMessage(
        context,
        next
            ? '${item.name} archived - hidden from new entries, kept on existing ones'
            : '${item.name} available for new entries again',
      );
    } catch (error) {
      if (!context.mounted) return;
      showAppMessage(context, friendlyMessage(error), error: true);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    CatalogItem item,
    int count,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete ${item.name}?',
      message: count > 0
          ? '${item.name} is used by $count ${count == 1 ? 'transaction' : 'transactions'}. '
              'A row with history cannot be deleted - archive it instead, history is always kept.'
          : 'This permanently removes ${item.name}. Existing transactions are not affected.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    try {
      await ref.read(catalogRepositoryProvider).delete(kind, item.id);
      ref.invalidate(catalogUsageCountsProvider(kind));
      if (!context.mounted) return;
      showAppMessage(context, '${kind.singular} deleted');
    } on ValidationException catch (error) {
      if (!context.mounted) return;
      showAppMessage(context, refusedDeleteMessage(error, count), error: true);
    } catch (error) {
      if (!context.mounted) return;
      showAppMessage(context, friendlyMessage(error), error: true);
    }
  }
}

/// Explains a refused delete: why the repository said no, plus the explicit
/// archive-not-delete rule the UI must always spell out.
String refusedDeleteMessage(ValidationException error, int usage) {
  final base = friendlyMessage(error);
  if (base.toLowerCase().contains('archive')) return base;
  return '$base Used by $usage transactions. '
      'Archive it instead - history is always kept.';
}

/// Title / caption pair used by the row popup menu.
class _MenuEntry extends StatelessWidget {
  const _MenuEntry({
    required this.icon,
    required this.label,
    this.caption,
  });

  final IconData icon;
  final String label;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final captionText = caption;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: colors.onSurfaceVariant),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodyMedium),
              if (captionText != null)
                Text(
                  captionText,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Prompts for a catalog name and returns the trimmed value, or `null` when
/// the user cancels.
///
/// Shared by the Add and Rename flows so both validate and look identical.
Future<String?> showCatalogNameDialog(
  BuildContext context, {
  required CatalogKind kind,
  String? initialName,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _CatalogNameDialog(kind: kind, initialName: initialName),
  );
}

class _CatalogNameDialog extends StatefulWidget {
  const _CatalogNameDialog({required this.kind, this.initialName});

  final CatalogKind kind;
  final String? initialName;

  @override
  State<_CatalogNameDialog> createState() => _CatalogNameDialogState();
}

class _CatalogNameDialogState extends State<_CatalogNameDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a ${widget.kind.singular.toLowerCase()} name.');
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final renaming = widget.initialName != null;
    return AlertDialog(
      title: Text(
        renaming
            ? 'Rename ${kind.singular.toLowerCase()}'
            : 'New ${kind.singular.toLowerCase()}',
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        maxLength: 80,
        decoration: InputDecoration(
          labelText: kind.singular,
          hintText: renaming ? null : 'e.g. ${_exampleFor(kind)}',
          counterText: '',
          errorText: _error,
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

String _exampleFor(CatalogKind kind) => switch (kind) {
      CatalogKind.category => 'Groceries',
      CatalogKind.incomeSource => 'Freelance',
      CatalogKind.paymentMethod => 'UPI',
    };
