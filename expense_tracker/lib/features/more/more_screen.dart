import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/routes.dart';
import '../../app/state/app_identity.dart';
import '../../core/config/app_config.dart';
import '../../repositories/providers.dart';
import '../../shared/models/account_balance.dart';
import '../../shared/models/catalog_item.dart';
import '../../shared/models/period_summary.dart';
import '../../shared/models/range_spec.dart';
import '../../shared/widgets/common.dart';

/// This month's income / expense / balance for the header card.
///
/// Kept in a provider so a change made anywhere in the app refreshes the
/// totals as soon as the user returns to this tab.
final moreMonthSummaryProvider = FutureProvider<PeriodSummary>((ref) {
  return ref.watch(transactionRepositoryProvider).summary(RangeSpec.thisMonth());
});

/// Build version used when the platform cannot answer (mirrors the `version`
/// declared in `pubspec.yaml`).
const String _buildVersionFallback = '1.0.0';

/// Build number paired with [_buildVersionFallback].
const String _buildNumberFallback = '1';

/// `v1.0.0 (1)` read from the installed package.
///
/// [PackageInfo.fromPlatform] can throw on exotic platforms, so the failure is
/// swallowed here and the build-time version is shown instead: a version label
/// is never worth an error screen.
final moreVersionLabelProvider = FutureProvider<String>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    return 'v${info.version} (${info.buildNumber})';
  } catch (_) {
    return 'v$_buildVersionFallback ($_buildNumberFallback)';
  }
});

/// The "More" tab: a month snapshot, the management shortcuts and the app
/// level pages (backup, sheets, settings, contact, about).
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final summary = ref.watch(moreMonthSummaryProvider);

    // These are futures, not streams, so without this the screen would keep
    // whatever was computed the first time it opened. Watching the ledger
    // revision re-runs them whenever a transaction is added, edited or deleted
    // anywhere in the app - which is what makes a new row appear without
    // closing and reopening the app.
    ref.listen(ledgerRevisionProvider, (previous, next) {
      if (next.hasValue && next.valueOrNull != previous?.valueOrNull) {
        ref.invalidate(moreMonthSummaryProvider);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('More'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(moreMonthSummaryProvider);
              showAppMessage(context, 'Refreshed');
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // ------------------------------------------------------- header
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.account_balance_wallet_rounded,
                          size: 22,
                          color: colors.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ref.watch(appNameProvider),
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Offline-first expense tracking',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Text(
                    'This month',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  AsyncValueView<PeriodSummary>(
                    value: summary,
                    loadingLabel: 'Loading this month...',
                    onRetry: () => ref.invalidate(moreMonthSummaryProvider),
                    data: (totals) => totals.isEmpty
                        ? Text(
                            'No entries recorded yet this month.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          )
                        : Row(
                            children: [
                              _TotalCell(
                                label: 'Income',
                                minor: totals.incomeMinor,
                                color: colors.primary,
                              ),
                              _TotalCell(
                                label: 'Expense',
                                minor: totals.expenseMinor,
                                color: colors.tertiary,
                              ),
                              _TotalCell(
                                label: 'Balance',
                                minor: totals.balanceMinor,
                                color: colors.onSurface,
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),

          // ----------------------------------------------------- accounts
          _accountStrip(context, ref),

          // ------------------------------------------------------ manage
          const SectionHeader('Manage'),
          Card(
            child: Column(
              children: [
                _MoreTile(
                  icon: Icons.wallet_outlined,
                  title: 'Accounts & balance',
                  subtitle: 'Remaining balance in each account',
                  onTap: () => Navigator.pushNamed(context, AppRoutes.accounts),
                ),
                const Divider(height: 1),
                _MoreTile(
                  icon: Icons.category_outlined,
                  title: 'Categories',
                  subtitle: 'Create, rename and archive what you spend on',
                  onTap: () => Navigator.pushNamed(
                    context,
                    AppRoutes.manageCatalog,
                    arguments: ManageCatalogArgs(CatalogKind.category),
                  ),
                ),
                const Divider(height: 1),
                _MoreTile(
                  icon: Icons.savings_outlined,
                  title: 'Income sources',
                  subtitle: 'Manage where money comes from',
                  onTap: () => Navigator.pushNamed(
                    context,
                    AppRoutes.manageCatalog,
                    arguments: ManageCatalogArgs(CatalogKind.incomeSource),
                  ),
                ),
                const Divider(height: 1),
                _MoreTile(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Payment methods',
                  subtitle: 'Add, rename or archive the accounts you pay from',
                  onTap: () => Navigator.pushNamed(
                    context,
                    AppRoutes.manageCatalog,
                    arguments: ManageCatalogArgs(CatalogKind.paymentMethod),
                  ),
                ),
                const Divider(height: 1),
                _MoreTile(
                  icon: Icons.celebration_outlined,
                  title: 'Special events',
                  subtitle: 'Group trips, festivals and projects',
                  onTap: () =>
                      Navigator.pushNamed(context, AppRoutes.specialEvents),
                ),
              ],
            ),
          ),

          // -------------------------------------------------------- data
          const SectionHeader('Data'),
          Card(
            child: Column(
              children: [
                _MoreTile(
                  icon: Icons.save_alt_rounded,
                  title: 'Backup and restore',
                  subtitle: 'Export a JSON backup or restore your data',
                  onTap: () => Navigator.pushNamed(context, AppRoutes.backup),
                ),
                const Divider(height: 1),
                _MoreTile(
                  icon: Icons.upload_file_rounded,
                  title: 'Import spreadsheet',
                  subtitle: 'From Google Sheets, or a file on this phone',
                  onTap: () =>
                      Navigator.pushNamed(context, AppRoutes.importSheet),
                ),
                const Divider(height: 1),
                _MoreTile(
                  icon: Icons.table_chart_outlined,
                  title: 'Google Sheets',
                  subtitle: _sheetSubtitle(ref),
                  onTap: () =>
                      Navigator.pushNamed(context, AppRoutes.googleSheets),
                ),
              ],
            ),
          ),

          // -------------------------------------------------------- app
          const SectionHeader('App'),
          Card(
            child: Column(
              children: [
                _MoreTile(
                  icon: Icons.settings_outlined,
                  title: 'Settings',
                  subtitle: 'Theme, currency and entry defaults',
                  onTap: () => Navigator.pushNamed(context, AppRoutes.settings),
                ),
                const Divider(height: 1),
                _MoreTile(
                  icon: Icons.mail_outline_rounded,
                  title: 'Contact',
                  subtitle: 'Questions, feedback or a bug report',
                  onTap: () => Navigator.pushNamed(context, AppRoutes.contact),
                ),
                const Divider(height: 1),
                _MoreTile(
                  icon: Icons.info_outline_rounded,
                  title: 'About',
                  subtitle: 'Privacy, technology and credits',
                  onTap: () => Navigator.pushNamed(context, AppRoutes.about),
                ),
              ],
            ),
          ),

          // ----------------------------------------------------- footer
          _AppFooter(
            versionLabel: ref.watch(moreVersionLabelProvider).valueOrNull,
          ),
        ],
      ),
    );
  }

  /// Every account's remaining balance, as a horizontal strip.
  ///
  /// It sits on More rather than on Home because Home is the screen someone
  /// glances at, and these figures are the ones the balance lock guards. The
  /// lock masks the *amounts* only: which wallets exist is not the secret, so
  /// the names and the padlock stay readable and a tap reaches the full
  /// Accounts screen, where the PIN is asked for.
  ///
  /// Nothing is shown before the first query resolves, or when every payment
  /// method has been archived - the strip simply collapses.
  Widget _accountStrip(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(accountBalancesProvider).valueOrNull;
    if (rows == null || rows.isEmpty) return const SizedBox.shrink();

    final settings = ref.watch(settingsProvider).valueOrNull;
    final masked = (settings?.hasBalanceLock ?? false) &&
        !ref.watch(balanceUnlockedProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Your accounts',
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
          trailing: TextButton(
            onPressed: () => Navigator.pushNamed(context, AppRoutes.accounts),
            child: const Text('See all'),
          ),
        ),
        SizedBox(
          height: 76,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) => _accountChip(
              context,
              rows[index],
              masked: masked,
              onTap: () => Navigator.pushNamed(context, AppRoutes.accounts),
            ),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  /// One account in the strip: its name always, its remaining balance only
  /// while the lock is open.
  Widget _accountChip(
    BuildContext context,
    AccountBalance account, {
    required bool masked,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final remaining = account.remainingMinor;

    return SizedBox(
      width: 154,
      child: Material(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        account.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (masked) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.lock_rounded,
                        size: 13,
                        color: colors.onSurfaceVariant,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                if (masked)
                  Text(
                    '\u2022\u2022\u2022\u2022',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.onSurfaceVariant,
                      letterSpacing: 2,
                    ),
                  )
                else
                  MoneyText(
                    remaining,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: remaining < 0 ? colors.error : colors.onSurface,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Linked spreadsheet name, or an honest "Not connected".
  String _sheetSubtitle(WidgetRef ref) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    if (settings == null || !settings.hasLinkedSheet) return 'Not connected';
    final title = settings.googleSpreadsheetTitle;
    return title.isEmpty ? 'Linked spreadsheet' : title;
  }
}

/// Name / value pair used for the this-month mini totals.
class _TotalCell extends StatelessWidget {
  const _TotalCell({
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
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          MoneyText(
            minor,
            style: theme.textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Navigation row used by every section of the More screen.
class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: colors.primaryContainer.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 20, color: colors.onPrimaryContainer),
      ),
      title: Text(title, style: theme.textTheme.bodyLarge),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
      onTap: onTap,
    );
  }
}

/// Version and developer line at the very bottom of the screen.
class _AppFooter extends StatelessWidget {
  const _AppFooter({this.versionLabel});

  /// `v1.0.0 (1)`, or `null` while package info is still resolving.
  final String? versionLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final version = versionLabel;
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Column(
          children: [
            if (version != null)
              Text(
                version,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 4),
            Text(
              AppConfig.developerName,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
