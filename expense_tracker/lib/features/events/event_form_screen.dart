import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart' show ValidationException;
import '../../core/utils/date_utils.dart';
import '../../repositories/providers.dart';
import '../../shared/models/special_event.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/form_fields.dart';
import '../more/app_errors.dart';
import 'events_screen.dart';

/// The event being edited, or `null` when it no longer exists.
final eventByIdProvider = FutureProvider.autoDispose.family<SpecialEvent?, int>(
  (ref, id) => ref.watch(eventRepositoryProvider).byId(id),
);

/// Create / edit form for a special event.
///
/// A `null` [eventId] means "create"; otherwise the existing event is loaded
/// first and the form also offers archive and delete actions.
class EventFormScreen extends ConsumerStatefulWidget {
  const EventFormScreen({super.key, this.eventId});

  /// Event to edit, or `null` to create a new one.
  final int? eventId;

  @override
  ConsumerState<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends ConsumerState<EventFormScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  DateTime _start = AppDates.today();
  bool _hasEnd = false;
  DateTime? _end;

  bool _busy = false;
  bool _dirty = false;
  int? _loadedId;
  String? _nameError;
  String? _endError;
  String? _saveError;

  bool get _isCreate => widget.eventId == null;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// Seeds the controllers from the loaded event exactly once.
  void _applyEvent(SpecialEvent event) {
    if (_loadedId == event.id) return;
    final end = event.endDate;
    _loadedId = event.id;
    _nameController.text = event.name;
    _descriptionController.text = event.description;
    _start = AppDates.day(event.startDate);
    _hasEnd = end != null;
    _end = end == null ? null : AppDates.day(end);
    _dirty = false;
    _nameError = null;
    _endError = null;
    _saveError = null;
  }

  /// Flags the form as edited so [PopScope] starts blocking back navigation.
  ///
  /// Only the first change rebuilds: every later keystroke would otherwise
  /// re-render the whole form.
  void _markDirty({bool clearNameError = false}) {
    final clearError = clearNameError && _nameError != null;
    if (_dirty && !clearError) return;
    setState(() {
      _dirty = true;
      if (clearError) _nameError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.eventId;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final discard = await showConfirmDialog(
          context,
          title: 'Discard changes?',
          message: 'Your edits to this event have not been saved yet.',
          confirmLabel: 'Discard',
          cancelLabel: 'Keep editing',
          destructive: true,
        );
        if (!discard) return;
        if (!context.mounted) return;
        Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_isCreate ? 'New event' : 'Edit event')),
        body: id == null
            ? _buildForm(context)
            : AsyncValueView<SpecialEvent?>(
                value: ref.watch(eventByIdProvider(id)),
                loadingLabel: 'Loading event...',
                onRetry: () => ref.invalidate(eventByIdProvider(id)),
                empty: _notFound(context),
                data: (event) {
                  if (event == null) return _notFound(context);
                  _applyEvent(event);
                  return _buildForm(context, event: event);
                },
              ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(_busy ? 'Saving...' : 'Save event'),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ form

  Widget _buildForm(BuildContext context, {SpecialEvent? event}) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final saveError = _saveError;
    final archived = event?.isArchived ?? false;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (saveError != null) _errorBox(context, saveError),
        TextField(
          controller: _nameController,
          autofocus: _isCreate,
          maxLength: 120,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Event name',
            hintText: 'e.g. Mumbai Trip',
            counterText: '',
            errorText: _nameError,
          ),
          onChanged: (_) => _markDirty(clearNameError: true),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _descriptionController,
          minLines: 3,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Description (optional)',
            hintText: 'What was this event about?',
          ),
          onChanged: (_) => _markDirty(),
        ),
        const SizedBox(height: 8),
        DateField(
          label: 'Start date',
          value: _start,
          onChanged: (picked) {
            setState(() {
              _start = AppDates.day(picked);
              _endError = null;
              _dirty = true;
            });
          },
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Has an end date'),
          subtitle: const Text('Turn on for a trip or festival that spans days'),
          value: _hasEnd,
          onChanged: _busy
              ? null
              : (enabled) {
                  setState(() {
                    _hasEnd = enabled;
                    _end = enabled ? (_end ?? _start) : null;
                    _endError = null;
                    _dirty = true;
                  });
                },
        ),
        if (_hasEnd)
          DateField(
            label: 'End date',
            value: _end ?? _start,
            errorText: _endError,
            onChanged: (picked) {
              setState(() {
                _end = picked;
                _endError = null;
                _dirty = true;
              });
            },
          ),
        if (event != null) ...[
          const SectionHeader('Manage event'),
          Text(
            'Archiving hides the event from new entries but keeps it on '
            'existing transactions - history is always kept.',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _setArchived(!archived),
            icon: Icon(archived ? Icons.unarchive_rounded : Icons.archive_outlined),
            label: Text(archived ? 'Unarchive event' : 'Archive event'),
          ),
          const SizedBox(height: 16),
          Text(
            'Deleting asks for confirmation and is refused while transactions '
            'are linked to this event - history is always kept.',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.error,
              side: BorderSide(color: colors.error),
            ),
            onPressed: _busy ? null : _delete,
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Delete event'),
          ),
        ],
      ],
    );
  }

  Widget _notFound(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EmptyState(
              compact: true,
              icon: Icons.error_outline_rounded,
              title: 'This event no longer exists',
              message: 'It may have been deleted or removed during a restore.',
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Go back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorBox(BuildContext context, String message) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 20, color: colors.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- actions

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final end = _hasEnd ? _end : null;

    final nameError = name.isEmpty ? 'Enter an event name.' : null;
    final endError = (end != null && end.isBefore(_start))
        ? 'The end date cannot be before the start date.'
        : null;

    setState(() {
      _nameError = nameError;
      _endError = endError;
      _saveError = null;
    });
    if (nameError != null || endError != null) return;

    final id = widget.eventId;
    final draft = SpecialEventDraft(
      name: name,
      description: _descriptionController.text.trim(),
      startDate: _start,
      endDate: end,
    );

    setState(() => _busy = true);
    try {
      if (id == null) {
        await ref.read(eventRepositoryProvider).create(draft);
      } else {
        await ref.read(eventRepositoryProvider).update(id, draft);
        ref.invalidate(eventByIdProvider(id));
      }
      ref.invalidate(eventsListProvider);
      if (!mounted) return;
      showAppMessage(context, id == null ? 'Event created' : 'Event saved');
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _saveError = friendlyMessage(error);
      });
    }
  }

  Future<void> _setArchived(bool archived) async {
    final id = widget.eventId;
    if (id == null) return;

    if (archived) {
      final confirmed = await showConfirmDialog(
        context,
        title: 'Archive this event?',
        message: 'Archiving hides it from new entries but keeps it on '
            'existing transactions - nothing is deleted.',
        confirmLabel: 'Archive',
      );
      if (!confirmed || !mounted) return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(eventRepositoryProvider).setArchived(id, archived);
      ref.invalidate(eventsListProvider);
      ref.invalidate(eventByIdProvider(id));
      if (!mounted) return;
      showAppMessage(
        context,
        archived
            ? 'Event archived - history is always kept'
            : 'Event available for new entries again',
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _saveError = friendlyMessage(error);
      });
    }
  }

  Future<void> _delete() async {
    final id = widget.eventId;
    if (id == null) return;

    final event = ref.read(eventByIdProvider(id)).valueOrNull;
    final counts = ref.read(eventUsageCountsProvider).valueOrNull ?? const <int, int>{};
    final usage = counts[id] ?? event?.transactionCount ?? 0;

    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete ${event?.name ?? 'this event'}?',
      message: usage > 0
          ? 'This event is linked to $usage ${usage == 1 ? 'transaction' : 'transactions'}. '
              'An event with history cannot be deleted - archive it instead, history is always kept.'
          : 'This permanently removes the event. Existing transactions are not affected.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(eventRepositoryProvider).delete(id);
      ref.invalidate(eventsListProvider);
      ref.invalidate(eventUsageCountsProvider);
      if (!mounted) return;
      showAppMessage(context, 'Event deleted');
      Navigator.of(context).pop();
    } on ValidationException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _saveError = eventDeleteRefusedMessage(error, usage);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _saveError = friendlyMessage(error);
      });
    }
  }
}
