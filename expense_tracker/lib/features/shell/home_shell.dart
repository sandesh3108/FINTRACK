import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/shell.dart';
import '../add/add_tab.dart';
import '../dashboard/dashboard_screen.dart';
import '../more/more_screen.dart';
import '../reports/reports_tab.dart';
import '../transactions/transactions_tab.dart';

/// The five-tab application frame.
///
/// Tabs live in an [IndexedStack] so switching away and back preserves scroll
/// offset, form drafts and expanded state - the behaviour users expect from a
/// bottom navigation bar.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  static const List<String> _labels = <String>[
    'Home',
    'Transactions',
    'Add',
    'Reports',
    'More',
  ];

  static const List<IconData> _icons = <IconData>[
    Icons.dashboard_outlined,
    Icons.receipt_long_outlined,
    Icons.add_circle_outline_rounded,
    Icons.pie_chart_outline_rounded,
    Icons.menu_rounded,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(shellIndexProvider);
    final theme = Theme.of(context);

    // Each tab owns its own [Scaffold] + [AppBar] so the status bar, scroll
    // under-bar elevation and nested back behaviour all behave exactly like a
    // pushed route. The shell only owns the frame and the bottom bar.
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: IndexedStack(
        index: index,
        children: const <Widget>[
          DashboardScreen(),
          TransactionsTab(),
          AddTab(),
          ReportsTab(),
          MoreScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (next) =>
            ref.read(shellIndexProvider.notifier).select(next),
        destinations: [
          for (var i = 0; i < _labels.length; i++)
            NavigationDestination(
              icon: Icon(_icons[i]),
              selectedIcon: Icon(_selectedIcon(_icons[i])),
              label: _labels[i],
            ),
        ],
      ),
    );
  }

  static IconData _selectedIcon(IconData icon) {
    if (icon == Icons.dashboard_outlined) return Icons.dashboard_rounded;
    if (icon == Icons.receipt_long_outlined) return Icons.receipt_long_rounded;
    if (icon == Icons.add_circle_outline_rounded) return Icons.add_circle_rounded;
    if (icon == Icons.pie_chart_outline_rounded) return Icons.pie_chart_rounded;
    return icon;
  }
}
