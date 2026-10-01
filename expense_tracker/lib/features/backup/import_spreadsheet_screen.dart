import 'package:flutter/material.dart';

import '../../app/routes.dart';

/// Where an import should read its rows from: a Google account, or a file
/// already on the phone.
///
/// The screen exists because these two paths were previously three taps apart
/// in different places - one behind *Google Sheets*, one behind *More* - and
/// somebody holding a spreadsheet did not know which one they needed. Answering
/// "where is it?" and then going straight to that reader removes the guess.
///
/// Nothing is read on this screen; it only routes.
class ImportSpreadsheetScreen extends StatelessWidget {
  const ImportSpreadsheetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Import spreadsheet')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            'Where should the rows come from?',
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 16),

          _SourceCard(
            icon: Icons.table_chart_outlined,
            tint: colors.primaryContainer,
            onTint: colors.onPrimaryContainer,
            title: 'Import from Google Sheets',
            subtitle:
                'Connect a Google account and read a spreadsheet from it - '
                'either the sheet this app exports, or a month grid with '
                'months across the top.',
            caption: 'Needs a Google account; everything else stays offline.',
            onTap: () => Navigator.pushNamed(context, AppRoutes.googleSheets),
          ),
          const SizedBox(height: 12),

          _SourceCard(
            icon: Icons.folder_open_rounded,
            tint: colors.secondaryContainer,
            onTint: colors.onSecondaryContainer,
            title: 'Import from this device',
            subtitle:
                'Pick a .xlsx or .csv file that is already on the phone. '
                'Columns are matched by name, or the whole file is read as a '
                'month grid.',
            caption: 'Nothing leaves the phone.',
            onTap: () =>
                Navigator.pushNamed(context, AppRoutes.importFile),
          ),
          const SizedBox(height: 20),

          Text(
            'Either way, you see a preview and confirm before a single row '
            'is written, and rows you already have are skipped rather than '
            'duplicated.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// One of the two sources, as a tappable card.
class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.icon,
    required this.tint,
    required this.onTint,
    required this.title,
    required this.subtitle,
    required this.caption,
    required this.onTap,
  });

  final IconData icon;
  final Color tint;
  final Color onTint;
  final String title;
  final String subtitle;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 20, color: onTint),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(title, style: theme.textTheme.titleMedium),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: colors.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 10),
              Text(subtitle, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text(
                caption,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
