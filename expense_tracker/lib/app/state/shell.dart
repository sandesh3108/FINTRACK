import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which tab of the bottom navigation bar is active.
///
/// Held outside the widget tree so routes can switch tabs (and pop back to the
/// shell) without duplicating the [IndexedStack] that keeps each tab's scroll
/// position and state alive.
class ShellIndexController extends Notifier<int> {
  @override
  int build() => 0;

  /// Index of the Home tab.
  static const int home = 0;
  static const int transactions = 1;
  static const int add = 2;
  static const int reports = 3;
  static const int more = 4;

  void select(int index) {
    if (index < 0 || index > 4 || index == state) return;
    state = index;
  }

  void goHome() => state = home;
}

final NotifierProvider<ShellIndexController, int> shellIndexProvider =
    NotifierProvider<ShellIndexController, int>(ShellIndexController.new);
