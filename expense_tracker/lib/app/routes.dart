import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/about/about_screen.dart';
import '../features/accounts/accounts_screen.dart';
import '../features/backup/backup_screen.dart';
import '../features/backup/import_spreadsheet_screen.dart';
import '../features/contact/contact_screen.dart';
import '../features/events/event_form_screen.dart';
import '../features/events/events_screen.dart';
import '../features/google_sheets/google_setup_screen.dart';
import '../features/google_sheets/google_sheets_screen.dart';
import '../features/manage/catalog_screen.dart';
import '../features/reports/report_definitions.dart';
import '../features/reports/report_detail_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shell/home_shell.dart';
import '../features/transactions/edit_transaction_screen.dart';
import '../shared/models/catalog_item.dart';
import '../shared/models/range_spec.dart';
import '../shared/models/tx_item.dart';
import 'state/shell.dart';

/// Every route name in the application.
///
/// Declaring them once means links can be created from anywhere (including
/// empty states and the Contact screen) without repeating string literals.
class AppRoutes {
  const AppRoutes._();

  static const String home = '/';
  static const String transactions = '/transactions';
  static const String add = '/add';
  static const String reports = '/reports';
  static const String more = '/more';

  static const String editTransaction = '/transaction/edit';
  static const String reportDetail = '/report/detail';
  static const String manageCatalog = '/manage';
  static const String accounts = '/accounts';
  static const String specialEvents = '/events';
  static const String eventForm = '/events/form';
  static const String settings = '/settings';
  static const String contact = '/contact';
  static const String about = '/about';
  static const String backup = '/backup';

  /// `Import spreadsheet` landing page: the choice between reading from a
  /// Google account and reading a file that is already on the phone.
  static const String importSheet = '/import-sheet';

  /// Straight into the device reader: the backup screen opened in import
  /// mode, which reaches for the file picker as soon as it appears.
  static const String importFile = '/import-file';

  static const String googleSheets = '/sheets';
  static const String googleSetup = '/sheets/setup';
}

/// Arguments for [AppRoutes.editTransaction].
class EditTransactionArgs {
  const EditTransactionArgs(this.transaction);
  final TxItem transaction;
}

/// Arguments for [AppRoutes.reportDetail].
///
/// [type] is optional so existing call sites (the event screen, for example)
/// can keep passing only a title and a range; the screen then infers the
/// report kind from [specialEventId].
class ReportDetailArgs {
  const ReportDetailArgs({
    required this.title,
    this.range,
    this.specialEventId,
    this.type,
  });
  final String title;
  final RangeSpec? range;
  final int? specialEventId;
  final ReportType? type;
}

/// Arguments for [AppRoutes.manageCatalog].
class ManageCatalogArgs {
  const ManageCatalogArgs(this.kind, {this.title});
  final CatalogKind kind;
  final String? title;
}

/// Arguments for [AppRoutes.eventForm]. A `null` event means "create".
class EventFormArgs {
  const EventFormArgs({this.eventId});
  final int? eventId;
}

/// The application's [Navigator.onGenerateRoute].
///
/// The five primary destinations live in the [HomeShell] [IndexedStack] and are
/// switched by the bottom bar; everything else is pushed on top so the system
/// back gesture works exactly as users expect.
Route<dynamic> onGenerateRoute(RouteSettings settings) {
  final name = settings.name ?? AppRoutes.home;

  switch (name) {
    case AppRoutes.home:
      return MaterialPageRoute<void>(builder: (_) => const HomeShell(), settings: settings);

    case AppRoutes.transactions:
      return MaterialPageRoute<void>(settings: settings, builder: (_) => const _TabRedirect(1));

    case AppRoutes.add:
      return MaterialPageRoute<void>(settings: settings, builder: (_) => const _TabRedirect(2));

    case AppRoutes.reports:
      return MaterialPageRoute<void>(settings: settings, builder: (_) => const _TabRedirect(3));

    case AppRoutes.more:
      return MaterialPageRoute<void>(settings: settings, builder: (_) => const _TabRedirect(4));

    case AppRoutes.editTransaction:
      final args = settings.arguments;
      if (args is! EditTransactionArgs) return _notFound(settings);
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => EditTransactionScreen(transaction: args.transaction),
      );

    case AppRoutes.reportDetail:
      final args = settings.arguments;
      if (args is! ReportDetailArgs) return _notFound(settings);
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => ReportDetailScreen(
          title: args.title,
          range: args.range,
          specialEventId: args.specialEventId,
          type: args.type,
        ),
      );

    case AppRoutes.manageCatalog:
      final args = settings.arguments;
      if (args is! ManageCatalogArgs) return _notFound(settings);
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => CatalogScreen(kind: args.kind, title: args.title),
      );

    case AppRoutes.accounts:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const AccountsScreen(),
      );

    case AppRoutes.googleSetup:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const GoogleSetupScreen(),
      );

    case AppRoutes.specialEvents:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const EventsScreen(),
      );

    case AppRoutes.eventForm:
      final args = settings.arguments;
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => EventFormScreen(eventId: args is EventFormArgs ? args.eventId : null),
      );

    case AppRoutes.settings:
      return MaterialPageRoute<void>(settings: settings, builder: (_) => const SettingsScreen());

    case AppRoutes.contact:
      return MaterialPageRoute<void>(settings: settings, builder: (_) => const ContactScreen());

    case AppRoutes.about:
      return MaterialPageRoute<void>(settings: settings, builder: (_) => const AboutScreen());

    case AppRoutes.backup:
      return MaterialPageRoute<void>(settings: settings, builder: (_) => const BackupScreen());

    case AppRoutes.importSheet:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const ImportSpreadsheetScreen(),
      );

    case AppRoutes.importFile:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const BackupScreen(launch: BackupLaunch.importFile),
      );

    case AppRoutes.googleSheets:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const GoogleSheetsScreen(),
      );

    default:
      return _notFound(settings);
  }
}

MaterialPageRoute<void> _notFound(RouteSettings settings) => MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Not found')),
        body: Center(
          child: Text('No screen is registered for "${settings.name}".'),
        ),
      ),
    );

/// Selects a bottom-bar tab and returns to the existing shell.
///
/// Used by the tab routes so that opening `/reports` (from a notification, a
/// link or a test) reuses the live [HomeShell] instead of stacking a second
/// copy of the whole frame on the navigator.
class _TabRedirect extends ConsumerWidget {
  const _TabRedirect(this.index);

  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(shellIndexProvider.notifier).select(index);
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.popUntil((route) => route.isFirst);
      }
    });

    // Fallback for the case where this route *is* the first route.
    return const HomeShell();
  }
}
