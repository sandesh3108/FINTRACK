import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/routes.dart';
import '../../core/config/app_config.dart';
import '../../core/config/signing_fingerprint.dart';
import '../../core/errors/app_exception.dart';
import '../../repositories/providers.dart';
import '../../shared/models/app_settings.dart';
import '../../shared/widgets/common.dart';

/// One-time setup for Google sign-in: the instructions that lead to the OAuth
/// client ids, the fields that store them, and a link to the Sheets screen.
///
/// The ids are ordinary public identifiers - they ship inside every installed
/// APK - so they are typed in at runtime and kept in SQLite: nothing is ever
/// rebuilt to connect, rotate or clear them. Everything on this screen reads
/// through [settingsProvider], so a save here flips the sign-in gate for the
/// Google Sheets screen and the Settings tile at once.
class GoogleSetupScreen extends ConsumerWidget {
  /// Creates the pushed `Google Sheets setup` screen.
  const GoogleSetupScreen({super.key});

  /// Where the OAuth client ids are created, shown and opened from here.
  static const String consoleUrl = 'https://console.cloud.google.com/';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Google Sheets setup')),
      body: AsyncValueView<AppSettings>(
        value: settings,
        loadingLabel: 'Loading settings...',
        onRetry: () => ref.invalidate(settingsProvider),
        data: (loaded) => _content(context, loaded),
      ),
    );
  }

  /// The scrolling content: instructions, the client-id form and the test link.
  Widget _content(BuildContext context, AppSettings settings) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        const SectionHeader('How to set this up'),
        _instructions(context),
        const SectionHeader('Your client IDs'),
        _ClientIdsCard(settings: settings),
        const SectionHeader('Test'),
        _testCard(context),
      ],
    );
  }

  // ---------------------------------------------------------- instructions

  /// Section A: the Cloud Console steps that produce the client ids.
  Widget _instructions(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Google sign-in needs OAuth client ids registered against this '
              'app in the Google Cloud Console. The console work happens once, '
              'in a browser, and the ids are then pasted into this screen - '
              'nothing is ever rebuilt.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            _Step(
              number: 1,
              children: [
                Text('Open $consoleUrl in a browser and create a project for '
                    'this app.'),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _openConsole(context),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Open Google Cloud Console'),
                  ),
                ),
              ],
            ),
            _Step(
              number: 2,
              children: const [
                Text('APIs & Services → Library → Google Sheets API → Enable.'),
              ],
            ),
            _Step(
              number: 3,
              children: [
                const Text(
                  'APIs & Services → OAuth consent screen → External, then add '
                  'your own email under Test users. While the app is in '
                  'Testing, only listed test users can sign in. The scopes '
                  'must include:',
                ),
                _CopyableValue(
                  'https://www.googleapis.com/auth/spreadsheets\n'
                  'https://www.googleapis.com/auth/userinfo.email',
                  caption: 'Scopes',
                ),
              ],
            ),
            _Step(
              number: 4,
              children: [
                const Text(
                  'APIs & Services → Credentials → Create credentials → OAuth '
                  'client ID, then register the app twice:',
                ),
                const SizedBox(height: 10),
                const Text('Application type Android → paste this package '
                    'name:'),
                _CopyableValue(AppConfig.packageName, caption: 'Package name'),
                const SizedBox(height: 10),
                const Text(
                  'Application type Android → paste the SHA-1 fingerprint of '
                  'the signing certificate:',
                ),
                const _Sha1Box(),
                const SizedBox(height: 10),
                const Text(
                  'Application type Web application → copy its client ID. It '
                  'becomes the Web client ID below; it is optional on Android '
                  'but recommended.',
                ),
              ],
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Android identifies your app by package name + signing '
                      'certificate SHA-1, so that console-side registration '
                      'is what actually authorises sign-in; the IDs you paste '
                      'below let the app know setup is complete so it will '
                      'offer the sign-in button.',
                      style: theme.textTheme.bodySmall?.copyWith(
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

  /// Opens the Cloud Console from the instructions.
  Future<void> _openConsole(BuildContext context) async {
    try {
      final uri = Uri.parse(consoleUrl);
      final canLaunch = await canLaunchUrl(uri);
      if (!canLaunch) {
        throw const AppException('No app on this device can open that link.');
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

  // ------------------------------------------------------------- test card

  /// Section C: straight-through route to the Sheets screen for a first try.
  Widget _testCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'With the ids saved, the Google Sheets screen offers Connect '
              'Google account. Jump straight there to try it.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () =>
                    Navigator.pushNamed(context, AppRoutes.googleSheets),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Open Google Sheets screen'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- form

/// Section B: the status line, the three id fields and the save/clear pair.
///
/// The controllers are created once from the *effective* configuration - a
/// value pasted on this device wins, otherwise the one this build was compiled
/// with - and only re-synced when that effective value changes from the
/// outside (another screen clearing the ids, a restored backup), so typing is
/// never interrupted by the very stream this screen writes to.
class _ClientIdsCard extends ConsumerStatefulWidget {
  const _ClientIdsCard({required this.settings});

  final AppSettings settings;

  @override
  ConsumerState<_ClientIdsCard> createState() => _ClientIdsCardState();
}

class _ClientIdsCardState extends ConsumerState<_ClientIdsCard> {
  late final TextEditingController _android;
  late final TextEditingController _web;
  late final TextEditingController _project;

  /// What a field should display: an id pasted here wins, otherwise the one
  /// this build was compiled with.
  ///
  /// The build-time value is a *display* fallback only and is never written
  /// back into settings, so saving an empty field still clears it and a later
  /// build carrying different `--dart-define`s is not frozen out by an
  /// earlier one having saved nothing.
  static String _effective(String stored, String builtIn) =>
      stored.isNotEmpty ? stored : builtIn;

  @override
  void initState() {
    super.initState();
    _android = TextEditingController(
      text: _effective(
        widget.settings.googleClientIdAndroid,
        AppConfig.googleClientIdAndroid,
      ),
    );
    _web = TextEditingController(
      text: _effective(
        widget.settings.googleClientIdWeb,
        AppConfig.effectiveGoogleClientId,
      ),
    );
    _project = TextEditingController(
      text: _effective(
        widget.settings.googleProjectId,
        AppConfig.googleProjectId,
      ),
    );
  }

  @override
  void didUpdateWidget(_ClientIdsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resync(
      _android,
      _effective(
        oldWidget.settings.googleClientIdAndroid,
        AppConfig.googleClientIdAndroid,
      ),
      _effective(
        widget.settings.googleClientIdAndroid,
        AppConfig.googleClientIdAndroid,
      ),
    );
    _resync(
      _web,
      _effective(
        oldWidget.settings.googleClientIdWeb,
        AppConfig.effectiveGoogleClientId,
      ),
      _effective(
        widget.settings.googleClientIdWeb,
        AppConfig.effectiveGoogleClientId,
      ),
    );
    _resync(
      _project,
      _effective(
        oldWidget.settings.googleProjectId,
        AppConfig.googleProjectId,
      ),
      _effective(
        widget.settings.googleProjectId,
        AppConfig.googleProjectId,
      ),
    );
  }

  /// Follows an external change without clobbering what is being typed.
  void _resync(TextEditingController controller, String before, String after) {
    if (before != after && controller.text != after) controller.text = after;
  }

  @override
  void dispose() {
    _android.dispose();
    _web.dispose();
    _project.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final configured = widget.settings.hasGoogleConfig;
    // "Configured" can mean two different things, and only the first is one
    // you can change from this screen: ids pasted on this device, or ids this
    // build was compiled with. Saying which avoids a person staring at fields
    // that already look filled in, wondering why nothing happened.
    final saved = widget.settings.googleClientIdAndroid.isNotEmpty ||
        widget.settings.googleClientIdWeb.isNotEmpty;
    final status = !configured
        ? 'Not configured — sign-in is disabled'
        : saved
            ? 'Configured — ids saved on this device'
            : 'Configured — ids supplied by this build';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  configured
                      ? Icons.check_circle_rounded
                      : Icons.info_outline_rounded,
                  size: 18,
                  color: configured ? colors.primary : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: configured
                          ? colors.primary
                          : colors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _android,
              decoration: const InputDecoration(
                labelText: 'Android client ID',
                hintText: '….apps.googleusercontent.com',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _web,
              decoration: const InputDecoration(
                labelText: 'Web client ID',
                hintText: '….apps.googleusercontent.com',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _project,
              decoration: const InputDecoration(
                labelText: 'Project ID',
                hintText: 'your-project-id',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.text,
            ),
            const SizedBox(height: 12),
            Text(
              'Android and Web client IDs normally end in '
              '.apps.googleusercontent.com. Leave a field empty when it does '
              'not apply - an empty field just means "not configured".',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: _save,
                    child: const Text('Save'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: _clear,
                    child: const Text('Clear'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------- actions

  /// Validates and writes the three ids through the settings repository.
  ///
  /// Whitespace inside a value always means the paste broke across lines, so
  /// it blocks the save. Other unusual shapes only produce a warning, because
  /// Google issues ids in more than one form and an empty field is a legal
  /// "not configured" answer.
  Future<void> _save() async {
    final android = _android.text.trim();
    final web = _web.text.trim();
    final project = _project.text.trim();

    final hasWhitespace = RegExp(r'\s');
    final broken = <String>[
      if (hasWhitespace.hasMatch(android)) 'The Android client ID',
      if (hasWhitespace.hasMatch(web)) 'The Web client ID',
      if (hasWhitespace.hasMatch(project)) 'The project ID',
    ];
    if (broken.isNotEmpty) {
      showAppMessage(
        context,
        '${broken.first} must not contain spaces or line breaks.',
        error: true,
      );
      return;
    }

    const suffix = '.apps.googleusercontent.com';
    final warnings = <String>[
      if (android.isNotEmpty && !android.endsWith(suffix))
        'The Android client ID does not end in $suffix',
      if (web.isNotEmpty && !web.endsWith(suffix))
        'The Web client ID does not end in $suffix',
    ];

    try {
      await ref.read(settingsRepositoryProvider).save(
            widget.settings.copyWith(
              googleClientIdAndroid: android,
              googleClientIdWeb: web,
              googleProjectId: project,
            ),
          );
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, _friendlyMessage(error), error: true);
      return;
    }
    if (!mounted) return;
    showAppMessage(
      context,
      warnings.isEmpty
          ? 'Google Sheets setup saved'
          : 'Saved, but ${warnings.join(' and ').toLowerCase()} - double-check '
              'the paste.',
    );
  }

  /// Removes all three ids; sign-in goes back to being offered nowhere.
  Future<void> _clear() async {
    try {
      await ref
          .read(settingsRepositoryProvider)
          .save(widget.settings.copyWith(clearGoogleConfig: true));
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, _friendlyMessage(error), error: true);
      return;
    }
    if (!mounted) return;
    showAppMessage(context, 'Google client IDs cleared');
  }

  /// Turns any caught error into a short sentence safe to show in the UI.
  String _friendlyMessage(Object error) {
    if (error is AppException) return error.message;
    return 'Something went wrong. Please try again.';
  }
}

// --------------------------------------------------------------- helpers

/// One numbered instruction in the "How to set this up" card.
class _Step extends StatelessWidget {
  const _Step({required this.number, required this.children});

  final int number;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// A monospace value with a copy button, for pasting into the console.
class _CopyableValue extends StatelessWidget {
  const _CopyableValue(this.value, {this.caption});

  final String value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (caption != null) ...[
            Text(
              caption!,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy',
                  iconSize: 18,
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: value));
                    if (!context.mounted) return;
                    showAppMessage(context, 'Copied to clipboard');
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The SHA-1 fingerprint of this install, read from `MainActivity.kt`.
///
/// When the platform channel cannot answer (widget tests, for example) the box
/// falls back to [SigningFingerprint.fallback] plus a note telling the user to
/// verify the real value with `keytool`, so the step is never a dead end and
/// never throws.
class _Sha1Box extends StatefulWidget {
  const _Sha1Box();

  @override
  State<_Sha1Box> createState() => _Sha1BoxState();
}

class _Sha1BoxState extends State<_Sha1Box> {
  /// Started once: rebuilding the screen must not re-query the channel.
  late final Future<String?> _fingerprint;

  @override
  void initState() {
    super.initState();
    _fingerprint = SigningFingerprint.read();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _fingerprint,
      builder: (context, snapshot) {
        final value = snapshot.data ?? SigningFingerprint.fallback;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CopyableValue(value, caption: 'SHA-1 fingerprint'),
            if (snapshot.data == null) ...[
              const SizedBox(height: 6),
              Text(
                'Not your fingerprint? Read the real one from the signing '
                'keystore with keytool: keytool -list -v -keystore '
                'YOUR_KEYSTORE -alias YOUR_ALIAS',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ],
        );
      },
    );
  }
}
