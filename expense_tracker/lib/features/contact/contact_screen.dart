import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/state/app_identity.dart';
import '../../core/config/app_config.dart';
import '../../core/errors/app_exception.dart';
import '../../shared/widgets/common.dart';
import 'contact_channels.dart';

/// One way to reach the developer, with the data needed to open and copy it.
class _ContactChannel {
  /// Creates a channel descriptor.
  const _ContactChannel({
    required this.label,
    required this.address,
    required this.icon,
    required this.uri,
  });

  /// Human name: `Email`, `Phone`, `WhatsApp`.
  final String label;

  /// What the user sees (and what gets copied to the clipboard).
  final String address;

  /// Leading icon of the card.
  final IconData icon;

  /// Deep link opened by the "Contact" button.
  final Uri uri;
}

/// Contact options for support, feedback and bug reports.
///
/// Every channel is configured at build time (see [ContactChannels]), opens
/// with the matching Android handler and can be copied to the clipboard, so
/// the screen works even on a device with no e-mail or telephone app.
class ContactScreen extends ConsumerWidget {
  /// Creates the pushed `Contact` screen.
  const ContactScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final email = ContactChannels.email;
    final phone = ContactChannels.phone;
    final whatsapp = ContactChannels.whatsappUrl;

    final channels = <_ContactChannel>[];
    if (email.isNotEmpty) {
      channels.add(
        _ContactChannel(
          label: 'Email',
          address: email,
          icon: Icons.mail_outline_rounded,
          uri: Uri(
            scheme: 'mailto',
            path: email,
            queryParameters: <String, String>{
              'subject': '${ref.watch(appNameProvider)} - feedback',
            },
          ),
        ),
      );
    }
    if (phone.isNotEmpty) {
      channels.add(
        _ContactChannel(
          label: 'Phone',
          address: phone,
          icon: Icons.call_outlined,
          uri: Uri(scheme: 'tel', path: phone.replaceAll(' ', '')),
        ),
      );
    }
    if (whatsapp != null) {
      channels.add(
        _ContactChannel(
          label: 'WhatsApp',
          address: phone,
          icon: Icons.chat_bubble_outline_rounded,
          uri: Uri.parse(whatsapp),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Contact')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            '${AppConfig.developerName} builds and maintains this app. '
            'Questions, feedback or a bug report are always welcome - pick '
            'the channel below that suits you.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (channels.isEmpty)
            const EmptyState(
              icon: Icons.contact_mail_outlined,
              title: 'No contact channel configured',
              message: 'This build does not include a support e-mail address '
                  'or phone number. The About screen still lists what the app '
                  'does, where your data lives and the privacy statement.',
              compact: true,
            )
          else
            for (final channel in channels) _channelCard(context, channel),
          if (email.isNotEmpty) ...[
            const SizedBox(height: 4),
            _noteCard(context),
          ],
          if (ContactChannels.privacyPolicyUrl.isNotEmpty) ...[
            const SizedBox(height: 12),
            _privacyCard(context),
          ],
        ],
      ),
    );
  }

  /// A card for one channel: icon, label, address, open button, copy button.
  Widget _channelCard(BuildContext context, _ContactChannel channel) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
                    color: colors.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    channel.icon,
                    size: 20,
                    color: colors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        channel.label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        channel.address,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: () => _launch(
                      context,
                      channel.uri,
                      channel.label,
                    ),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Contact'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _copy(context, channel),
                  tooltip: 'Copy ${channel.label}',
                  icon: const Icon(Icons.copy_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Advice card shown whenever e-mail is available.
  Widget _noteCard(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.tips_and_updates_outlined, color: colors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Email is the fastest way to reach me. Please include your '
                'app version and device model.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Link to the published privacy policy, only when one exists.
  Widget _privacyCard(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      child: ListTile(
        leading: Icon(Icons.privacy_tip_outlined, color: colors.primary),
        title: const Text('Privacy policy'),
        subtitle: Text(
          'How your data is handled',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        trailing: Icon(
          Icons.open_in_new_rounded,
          color: colors.onSurfaceVariant,
        ),
        onTap: () => _launch(
          context,
          Uri.parse(ContactChannels.privacyPolicyUrl),
          'Privacy policy',
        ),
      ),
    );
  }

  /// Opens [uri] with the platform handler, reporting why it could not.
  Future<void> _launch(BuildContext context, Uri uri, String label) async {
    try {
      final canLaunch = await canLaunchUrl(uri);
      if (!canLaunch) {
        throw AppException(
          'No app on this device can open $label links.',
        );
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      if (!context.mounted) return;
      showAppMessage(context, _friendlyMessage(error), error: true);
    }
  }

  /// Copies the visible address to the clipboard.
  Future<void> _copy(BuildContext context, _ContactChannel channel) async {
    try {
      await Clipboard.setData(ClipboardData(text: channel.address));
    } catch (error) {
      if (!context.mounted) return;
      showAppMessage(context, _friendlyMessage(error), error: true);
      return;
    }
    if (!context.mounted) return;
    showAppMessage(context, 'Copied');
  }

  /// Turns any caught error into a short sentence safe to show in the UI.
  String _friendlyMessage(Object error) {
    if (error is AppException) return error.message;
    return 'Something went wrong. Please try again.';
  }
}
