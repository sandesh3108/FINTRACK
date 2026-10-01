import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/routes.dart';
import '../../app/state/app_identity.dart';
import '../../core/config/app_config.dart';
import '../../core/errors/app_exception.dart';
import '../../shared/widgets/common.dart';
import '../contact/contact_channels.dart';
import 'app_version.dart';

/// About page: what the app does, where the data lives, the privacy
/// statement, the technologies it is built with and the two follow-up
/// actions (open source licences, contact the developer).
class AboutScreen extends ConsumerWidget {
  /// Creates the pushed `About` screen.
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watched once here so both the header and the licence page follow a
    // rename made on Settings without re-reading a constant that cannot change.
    final appName = ref.watch(appNameProvider);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final version = ref.watch(appVersionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _hero(context, version, appName),
          ..._whatItDoes(context),
          ..._yourData(context),
          ..._privacy(context),
          ..._credits(context),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: appName,
                    applicationVersion:
                        version.valueOrNull?.label ?? AppVersion.fallback.label,
                  ),
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('Open source licenses'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () =>
                      Navigator.pushNamed(context, AppRoutes.contact),
                  icon: const Icon(Icons.mail_outline_rounded),
                  label: const Text('Contact developer'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Center(
            child: Column(
              children: [
                Text(
                  AppConfig.developerName,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '\u00a9 ${DateTime.now().year} ${AppConfig.developerName}. '
                  'All rights reserved.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// App icon placeholder, name and installed version.
  Widget _hero(BuildContext context, AsyncValue<AppVersion> version,
      String appName) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.account_balance_wallet_rounded,
                size: 34,
                color: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appName,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  AsyncValueView<AppVersion>(
                    value: version,
                    loadingLabel: 'Reading version...',
                    data: (info) => Text(
                      info.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Feature list.
  List<Widget> _whatItDoes(BuildContext context) {
    return [
      const SectionHeader('What it does'),
      _bulletCard(
        context,
        const [
          'Offline-first: every feature except Google Sheets works without an '
              'account or an internet connection.',
          'Twelve months of expenses and income tracked month by month.',
          'Seven reports covering trends, categories, payment methods, '
              'rankings and comparisons.',
          'Special events that group the transactions belonging to one trip, '
              'festival or project.',
          'JSON backup you can export, keep and restore on any device.',
          'Optional Google Sheets sync, only when you choose to connect a '
              'spreadsheet.',
        ],
      ),
    ];
  }

  /// Storage and network guarantees.
  List<Widget> _yourData(BuildContext context) {
    return [
      const SectionHeader('Your data'),
      _bulletCard(
        context,
        const [
          'Everything is stored in a SQLite database on this device - nothing '
              'is uploaded, tracked or shared.',
          'The only feature that touches the network is the optional Google '
              'Sheets sync, and it sends data solely to the account and '
              'spreadsheet you pick.',
          'There are no analytics, advertising or crash-reporting SDKs in this '
              'app.',
        ],
      ),
    ];
  }

  /// Privacy statement plus the published policy, when one exists.
  List<Widget> _privacy(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final policyUrl = ContactChannels.privacyPolicyUrl;
    return [
      const SectionHeader('Privacy'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppConfig.privacyStatement,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              if (policyUrl.isNotEmpty) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _openPolicy(context, policyUrl),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Read the full privacy policy'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ];
  }

  /// Technologies the app is built with.
  List<Widget> _credits(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    const tools = <String>['Flutter', 'Drift', 'Riverpod', 'fl_chart'];
    return [
      const SectionHeader('Credits / built with'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Built with open source technology:',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final tool in tools) AppBadge(label: tool)],
              ),
            ],
          ),
        ),
      ),
    ];
  }

  /// Shared renderer for a card of short, check-marked lines.
  Widget _bulletCard(BuildContext context, List<String> lines) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      size: 18,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        line,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Opens the privacy policy in the browser.
  Future<void> _openPolicy(BuildContext context, String url) async {
    try {
      final uri = Uri.parse(url);
      final canLaunch = await canLaunchUrl(uri);
      if (!canLaunch) {
        throw const AppException(
          'No app on this device can open this link.',
        );
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      if (!context.mounted) return;
      showAppMessage(
        context,
        error is AppException ? error.message : 'Could not open the link.',
        error: true,
      );
    }
  }
}
