import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../app/state/shell.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/date_utils.dart';
import '../../repositories/providers.dart';
import '../../shared/models/transaction_filter.dart';
import '../../shared/models/tx_item.dart';
import '../../shared/widgets/common.dart';
import 'filter_sheet.dart';
import 'transaction_tile.dart';

/// Live page of transactions matching one [TransactionFilter].
///
/// [TransactionFilter] has value equality, so an unchanged filter keeps the
/// same stream subscription instead of restarting the query.
final txListProvider =
    StreamProvider.autoDispose.family<List<TxItem>, TransactionFilter>(
  (ref, filter) =>
      ref.watch(transactionRepositoryProvider).watchTransactions(filter),
);

/// Total number of rows matching one [TransactionFilter], across all pages.
final txCountProvider =
    FutureProvider.autoDispose.family<int, TransactionFilter>(
  (ref, filter) =>
      ref.watch(transactionRepositoryProvider).countTransactions(filter),
);

/// Transaction history: search, filters, sorting, day grouping and paging.
class TransactionsTab extends ConsumerStatefulWidget {
  const TransactionsTab({super.key});

  @override
  ConsumerState<TransactionsTab> createState() => _TransactionsTabState();
}

class _TransactionsTabState extends ConsumerState<TransactionsTab> {
  /// The single source of truth for what the list shows.
  TransactionFilter _filter = const TransactionFilter();

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  Timer? _debounce;
  bool _searchHasText = false;
  bool _clampPending = false;

  /// True while any constraint - including a non default sort - is applied.
  bool get _hasActiveQuery =>
      _filter.activeCount > 0 || _filter.sort != TxSort.dateDesc;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ search

  void _onSearchChanged(String value) {
    if (_searchHasText != value.isNotEmpty) {
      setState(() => _searchHasText = value.isNotEmpty);
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(
          () => _filter = _filter.copyWith(search: value, resetPage: true));
      _jumpToTop();
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() {
      _searchHasText = false;
      _filter = _filter.copyWith(search: '', resetPage: true);
    });
    _jumpToTop();
  }

  // ----------------------------------------------------------------- filters

  Future<void> _openFilterSheet() async {
    final updated = await showTransactionFilterSheet(context, _filter);
    if (!mounted || updated == null) return;
    setState(() => _filter = updated.copyWith(resetPage: true));
    _jumpToTop();
  }

  void _clearAllFilters() {
    _debounce?.cancel();
    setState(() {
      _filter = const TransactionFilter();
      _searchController.clear();
      _searchHasText = false;
    });
    _jumpToTop();
  }

  // -------------------------------------------------------------- pagination

  void _goToPage(int page) {
    if (page < 0 || page == _filter.page) return;
    setState(() => _filter = _filter.copyWith(page: page, resetPage: false));
    _jumpToTop();
  }

  /// Steps back one page when the current page emptied out - usually the last
  /// row on it was deleted - so an older transaction is never left behind a
  /// blank screen.
  void _schedulePageClamp() {
    if (_clampPending) return;
    _clampPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _clampPending = false;
        if (_filter.page > 0) {
          _filter = _filter.copyWith(page: _filter.page - 1, resetPage: false);
        }
      });
    });
  }

  void _jumpToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (!position.hasContentDimensions) return;
      _scrollController.jumpTo(position.minScrollExtent);
    });
  }

  // ------------------------------------------------------------------ delete

  Future<void> _confirmDelete(TxItem tx) async {
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
      await ref.read(transactionRepositoryProvider).remove(tx.id);
      // The list stream re-emits on its own; the count is a one-shot future
      // and has to be refreshed explicitly.
      ref.invalidate(txCountProvider(_filter));
      if (!mounted) return;
      showAppMessage(context, 'Transaction deleted');
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, friendlyMessage(error), error: true);
    }
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(txListProvider(_filter));
    final total = ref.watch(txCountProvider(_filter)).valueOrNull;

    // The count is a single future, so re-run it whenever the live list
    // re-emits: that is the signal that something changed somewhere in the app.
    ref.listen(txListProvider(_filter), (previous, next) {
      if (previous?.valueOrNull == null || next.valueOrNull == null) return;
      ref.invalidate(txCountProvider(_filter));
    });

    final currentPage = listAsync.valueOrNull;
    if (currentPage != null &&
        currentPage.isEmpty &&
        _filter.page > 0 &&
        (total ?? 0) > 0) {
      _schedulePageClamp();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(txListProvider(_filter));
              ref.invalidate(txCountProvider(_filter));
              showAppMessage(context, 'Refreshed');
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSearchField(),
          _buildToolbar(),
          Expanded(
            child: AsyncValueView<List<TxItem>>(
              value: listAsync,
              onRetry: () => ref.invalidate(txListProvider(_filter)),
              data: (items) =>
                  items.isEmpty ? _buildEmptyState() : _buildDayList(items),
            ),
          ),
          if (currentPage != null && currentPage.isNotEmpty)
            _buildPagination(currentPage, total),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search note, category, amount...',
          prefixIcon: Icon(Icons.search_rounded, color: colors.primary),
          suffixIcon: _searchHasText
              ? IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _clearSearch,
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    final count = _filter.activeCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: count > 0 ? 'Filters, $count active' : 'Filters',
            onPressed: _openFilterSheet,
            icon: Badge(
              isLabelVisible: count > 0,
              label: Text('$count'),
              child: const Icon(Icons.filter_list_rounded),
            ),
          ),
          PopupMenuButton<TxSort>(
            tooltip: 'Sort transactions',
            icon: const Icon(Icons.sort_rounded),
            onSelected: (sort) {
              if (sort == _filter.sort) return;
              setState(() => _filter = _filter.copyWith(sort: sort));
              _jumpToTop();
            },
            itemBuilder: (context) => <PopupMenuEntry<TxSort>>[
              for (final sort in TxSort.values)
                PopupMenuItem<TxSort>(
                  value: sort,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        child: sort == _filter.sort
                            ? const Icon(Icons.check_rounded, size: 18)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Text(sort.label),
                    ],
                  ),
                ),
            ],
          ),
          const Spacer(),
          if (_hasActiveQuery)
            TextButton(onPressed: _clearAllFilters, child: const Text('Clear')),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    if (!_hasActiveQuery) {
      return EmptyState(
        icon: Icons.receipt_long_rounded,
        title: 'No transactions yet',
        message: 'Add your first expense or income and it will appear here.',
        actionLabel: 'Add a transaction',
        onAction: () => ref
            .read(shellIndexProvider.notifier)
            .select(ShellIndexController.add),
      );
    }
    return EmptyState(
      icon: Icons.search_off_rounded,
      title: 'No transactions match',
      message:
          'Try removing some filters or changing your search to see more results.',
      actionLabel: 'Clear filters',
      onAction: _clearAllFilters,
    );
  }

  Widget _buildDayList(List<TxItem> items) {
    final groups = _groupByDay(items);
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        for (final group in groups) ...[
          _DayHeader(day: group.day, netMinor: group.netMinor),
          for (final tx in group.items)
            TransactionTile(
              tx: tx,
              onTap: () => _openEdit(tx),
              onDelete: () => _confirmDelete(tx),
            ),
        ],
      ],
    );
  }

  /// Page footer: "Page x of y" plus previous / next controls and the number
  /// of rows currently shown against the matching total.
  ///
  /// The history is paged rather than using an infinite "load more" list: the
  /// count is known up front, so both ends of the range stay visible and the
  /// next button can be disabled on the final page.
  Widget _buildPagination(List<TxItem> items, int? total) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final pageSize = _filter.pageSize;
    final pages =
        total == null || total < 1 ? 1 : (total + pageSize - 1) ~/ pageSize;
    // While the count is still loading the page count is unknown, so only the
    // size of the returned page decides whether there can be a next one.
    final canGoNext =
        items.length >= pageSize && (total == null || _filter.page + 1 < pages);
    final canGoPrevious = _filter.page > 0;

    return Material(
      color: colors.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    tooltip: 'Previous page',
                    onPressed: canGoPrevious
                        ? () => _goToPage(_filter.page - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Text(
                    total == null
                        ? 'Page ${_filter.page + 1}'
                        : 'Page ${_filter.page + 1} of $pages',
                    style: theme.textTheme.labelLarge,
                  ),
                  IconButton(
                    tooltip: 'Next page',
                    onPressed:
                        canGoNext ? () => _goToPage(_filter.page + 1) : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              Text(
                total == null
                    ? 'Showing ${items.length} transactions'
                    : 'Showing ${items.length} of $total transactions',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openEdit(TxItem tx) {
    Navigator.pushNamed(
      context,
      AppRoutes.editTransaction,
      arguments: EditTransactionArgs(tx),
    );
  }

  /// Groups [items] into consecutive day buckets, preserving list order.
  List<_DayGroup> _groupByDay(List<TxItem> items) {
    final groups = <_DayGroup>[];
    final indexByKey = <String, int>{};
    for (final tx in items) {
      final key = AppDates.isoDay(tx.date);
      final existing = indexByKey[key];
      if (existing == null) {
        indexByKey[key] = groups.length;
        groups.add(_DayGroup(tx.date, <TxItem>[tx]));
      } else {
        groups[existing].items.add(tx);
      }
    }
    return groups;
  }
}

/// All transactions of one calendar day, in list order.
class _DayGroup {
  _DayGroup(this.day, this.items);

  final DateTime day;
  final List<TxItem> items;

  /// Income minus expense for the day, in minor units.
  int get netMinor => items.fold<int>(
        0,
        (sum, tx) => sum + (tx.isIncome ? tx.amountMinor : -tx.amountMinor),
      );
}

/// Sticky-look header introducing the transactions of a single day.
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.netMinor});

  final DateTime day;
  final int netMinor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      width: double.infinity,
      color: colors.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              AppDates.dateLabel(day),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            'Net',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(width: 6),
          MoneyText(
            netMinor,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
