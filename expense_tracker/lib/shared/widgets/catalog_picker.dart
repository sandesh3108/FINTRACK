import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart';
import '../../repositories/providers.dart';
import '../../shared/models/catalog_item.dart';
import '../../shared/models/special_event.dart';

/// Live catalog list for [kind], used by every picker and management screen.
final catalogListProvider = StreamProvider.family<List<CatalogItem>, CatalogKind>(
  (ref, kind) => ref.watch(catalogRepositoryProvider).watch(kind),
);

/// Live event list; the flag keeps archived events selectable when editing a
/// historical transaction.
final eventListProvider = StreamProvider.family<List<SpecialEvent>, bool>(
  (ref, includeArchived) =>
      ref.watch(eventRepositoryProvider).watchAll(includeArchived: includeArchived),
);

/// What a [CatalogSearchDialog] handed back.
///
/// A real id means "select this one". A `null` id means the person asked for
/// something that does not exist yet, and [newName] carries whatever they had
/// typed so the name prompt opens pre-filled instead of asking them to retype
/// it.
class CatalogPick {
  /// Records an existing id, or `null` with the text to create from.
  const CatalogPick(this.id, [this.newName = '']);

  /// The chosen catalog id, or `null` when a new entry was requested.
  final int? id;

  /// The search text, used as the starting value of the name prompt.
  final String newName;
}

/// Form field over one of the three catalogs with an "Other..." escape hatch.
///
/// Tapping it opens [CatalogSearchDialog] rather than a plain dropdown: a
/// dropdown has to render every category at once, which stops being usable the
/// moment somebody keeps forty of them. The dialog filters as you type, and
/// "Other..." creates the missing name through `CatalogRepository.findOrCreate`
/// - the exact quick-entry behaviour the specification asks for.
class CatalogPicker extends ConsumerWidget {
  const CatalogPicker({
    super.key,
    required this.kind,
    required this.label,
    required this.valueId,
    required this.onChanged,
    this.errorText,
    this.icon,
    this.hint,
  });

  final CatalogKind kind;
  final String label;
  final int? valueId;
  final ValueChanged<int?> onChanged;
  final String? errorText;
  final IconData? icon;
  final String? hint;

  static const int otherValue = -1;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final items =
        ref.watch(catalogListProvider(kind)).valueOrNull ?? const <CatalogItem>[];
    final known = valueId == null || items.any((item) => item.id == valueId);
    String? selectedName;
    if (known && valueId != null) {
      for (final item in items) {
        if (item.id == valueId) {
          selectedName = item.name;
          break;
        }
      }
    }

    // `isEmpty` is computed exactly as `DropdownButtonFormField` did it: a
    // hint counts as content, so the label floats above it instead of
    // collapsing into the box and sitting next to the hint.
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _open(context, ref, items),
      child: InputDecorator(
        isEmpty: selectedName == null && hint == null,
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          prefixIcon: Icon(icon ?? iconFor(kind), color: theme.colorScheme.primary),
          suffixIcon: Icon(
            Icons.arrow_drop_down_rounded,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        child: Text(
          selectedName ?? hint ?? '',
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  /// Opens the searchable list and turns what comes back into an [onChanged].
  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    List<CatalogItem> items,
  ) async {
    // Read before the first `await`: after it the element may be unmounted.
    final repository = ref.read(catalogRepositoryProvider);

    final pick = await showDialog<CatalogPick>(
      context: context,
      builder: (_) => CatalogSearchDialog(
        kind: kind,
        items: items,
        selectedId: valueId,
      ),
    );
    if (pick == null || !context.mounted) return;

    if (pick.id != null) {
      onChanged(pick.id);
      return;
    }

    final created = await promptForNewName(context, kind, initial: pick.newName);
    if (created == null || created.isEmpty) return;
    onChanged(await repository.findOrCreate(kind, created));
  }

  static IconData iconFor(CatalogKind kind) => switch (kind) {
        CatalogKind.category => Icons.category_outlined,
        CatalogKind.incomeSource => Icons.savings_outlined,
        CatalogKind.paymentMethod => Icons.account_balance_wallet_outlined,
      };

  /// Returns the typed name (trimmed), or `null` when cancelled.
  ///
  /// [initial] seeds the field - the searchable list passes what was typed
  /// there, so adding a name that was just searched for costs no retyping.
  static Future<String?> promptForNewName(
    BuildContext context,
    CatalogKind kind, {
    String initial = '',
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('New ${kind.singular.toLowerCase()}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 80,
          style: Theme.of(dialogContext).textTheme.bodyLarge,
          decoration: InputDecoration(
            labelText: kind.singular,
            hintText: _exampleFor(kind),
            counterText: '',
          ),
          onSubmitted: (value) {
            if (value.trim().isEmpty) return;
            Navigator.of(dialogContext).pop(value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.of(dialogContext).pop(name);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    ).then((value) => value?.trim());
  }

  static String _exampleFor(CatalogKind kind) => switch (kind) {
        CatalogKind.category => 'e.g. Gym',
        CatalogKind.incomeSource => 'e.g. Freelance',
        CatalogKind.paymentMethod => 'e.g. UPI',
      };
}

/// Searchable list of one catalog: what a [CatalogPicker] opens on tap.
///
/// A dropdown shows every entry at once, which only works while the list is
/// short. This filters as the person types, marks the current selection, keeps
/// archived entries visible (they must stay selectable when editing history)
/// and always offers "Other..." so an unknown name can still be created
/// without leaving the field.
class CatalogSearchDialog extends StatefulWidget {
  /// Creates the picker dialog over [items].
  const CatalogSearchDialog({
    super.key,
    required this.kind,
    required this.items,
    required this.selectedId,
  });

  final CatalogKind kind;
  final List<CatalogItem> items;
  final int? selectedId;

  @override
  State<CatalogSearchDialog> createState() => _CatalogSearchDialogState();
}

class _CatalogSearchDialogState extends State<CatalogSearchDialog> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Case-insensitive substring match, so "trav" finds "Travelling".
  List<CatalogItem> get _matches {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.items;
    return widget.items
        .where((item) => item.name.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final matches = _matches;
    final query = _query.trim();

    return AlertDialog(
      title: Text('Choose ${widget.kind.singular.toLowerCase()}'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _search,
              autofocus: true,
              textInputAction: TextInputAction.search,
              textCapitalization: TextCapitalization.words,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                labelText: 'Search',
                hintText: 'Type to filter',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.clear_rounded),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (matches.isEmpty)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.search_off_rounded),
                      title: Text(query.isEmpty
                          ? 'Nothing here yet'
                          : 'No matches for "$query"'),
                    ),
                  for (final item in matches)
                    ListTile(
                      dense: true,
                      selected: item.id == widget.selectedId,
                      title: Text(item.name),
                      subtitle: item.isActive ? null : const Text('Archived'),
                      trailing: item.id == widget.selectedId
                          ? Icon(
                              Icons.check_rounded,
                              color: theme.colorScheme.primary,
                            )
                          : null,
                      onTap: () =>
                          Navigator.of(context).pop(CatalogPick(item.id)),
                    ),
                  const Divider(height: 1),
                  ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.add_circle_outline_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    title: Text(query.isEmpty ? 'Other...' : 'Add "$query"'),
                    onTap: () => Navigator.of(context).pop(CatalogPick(null, query)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

/// Dropdown for special events, including an "Event name" free-entry option.
class SpecialEventPicker extends ConsumerWidget {
  const SpecialEventPicker({
    super.key,
    required this.valueId,
    required this.onChanged,
    this.errorText,
    this.label = 'Special event',
  });

  final int? valueId;
  final ValueChanged<int?> onChanged;
  final String? errorText;
  final String label;

  static const int noneValue = 0;
  static const int otherValue = -1;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selectingExisting = valueId != null && valueId! > 0;
    final events = ref
            .watch(eventListProvider(selectingExisting))
            .valueOrNull ??
        const <SpecialEvent>[];
    final known = valueId == null || valueId == noneValue || valueId == otherValue ||
        events.any((event) => event.id == valueId);

    return DropdownButtonFormField<int?>(
      initialValue: known ? valueId : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        errorText: errorText,
        prefixIcon: Icon(Icons.celebration_outlined, color: theme.colorScheme.primary),
      ),
      items: [
        const DropdownMenuItem<int?>(value: noneValue, child: Text('None')),
        for (final event in events)
          DropdownMenuItem<int?>(
            value: event.id,
            child: Text(event.name, overflow: TextOverflow.ellipsis),
          ),
        const DropdownMenuItem<int?>(value: otherValue, child: Text('New event...')),
      ],
      onChanged: (next) async {
        if (next == null) return;
        if (next == noneValue) {
          onChanged(null);
          return;
        }
        if (next == otherValue) {
          final draft = await promptForNewEvent(context);
          if (draft == null) return;
          final id = await ref.read(eventRepositoryProvider).create(draft);
          onChanged(id);
          return;
        }
        onChanged(next);
      },
    );
  }
}

/// Collects a name (and optional dates) for a brand-new special event.
Future<SpecialEventDraft?> promptForNewEvent(BuildContext context) {
  final controller = TextEditingController();
  DateTime start = AppDates.today();
  DateTime? end;

  return showDialog<SpecialEventDraft>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: const Text('New special event'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Event name',
                  hintText: 'e.g. Mumbai Trip',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('Start date'),
                subtitle: Text(AppDates.dateLabel(start)),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: dialogContext,
                    initialDate: start,
                    firstDate: DateTime(DateTime.now().year - 30),
                    lastDate: DateTime(DateTime.now().year + 30),
                  );
                  if (picked != null) setState(() => start = picked);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Has an end date'),
                value: end != null,
                onChanged: (enabled) {
                  setState(() => end = enabled ? start : null);
                },
              ),
              if (end != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_available_outlined),
                  title: const Text('End date'),
                  subtitle: Text(AppDates.dateLabel(end!)),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: end!,
                      firstDate: start,
                      lastDate: DateTime(DateTime.now().year + 30),
                    );
                    if (picked != null) setState(() => end = picked);
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.of(dialogContext).pop(
                SpecialEventDraft(
                  name: name,
                  startDate: start,
                  endDate: end,
                ),
              );
            },
            child: const Text('Create'),
          ),
        ],
      ),
    ),
  );
}
