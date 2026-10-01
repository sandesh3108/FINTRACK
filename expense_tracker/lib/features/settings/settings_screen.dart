import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../app/state/ui_preferences.dart';
import '../../core/errors/app_exception.dart';
import '../../core/security/balance_pin.dart';
import '../../core/utils/money.dart';
import '../../repositories/providers.dart';
import '../../shared/models/app_settings.dart';
import '../../shared/models/catalog_item.dart';
import '../../shared/models/tx_type.dart';
import '../../shared/widgets/catalog_picker.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/pin_dialog.dart';
import '../about/app_version.dart';
import 'local_settings.dart';

/// Application settings: identity, Add-tab defaults, appearance, data links,
/// about entries and the danger zone.
///
/// Everything is read live - durable values from [settingsProvider] (SQLite)
/// and device-local values from [localSettingsProvider] - so a change made
/// here is reflected by every other screen at once, and both stores are
/// wrapped in [AsyncValueView] with a retry when they fail to load.
class SettingsScreen extends ConsumerWidget {
  /// Creates the pushed `Settings` screen.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final local = ref.watch(localSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: AsyncValueView<AppSettings>(
        value: settings,
        loadingLabel: 'Loading settings...',
        onRetry: () => ref.invalidate(settingsProvider),
        data: (loaded) => AsyncValueView<LocalSettings>(
          value: local,
          loadingLabel: 'Loading preferences...',
          onRetry: () => ref.invalidate(localSettingsProvider),
          data: (preferences) => _content(context, ref, loaded, preferences),
        ),
      ),
    );
  }

  /// The scrolling content: one [SectionHeader] + card pair per section.
  Widget _content(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
    LocalSettings local,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        ..._appSection(context, ref, settings, local),
        ..._defaultsSection(context, ref, settings, local),
        ..._appearanceSection(context, ref),
        ..._dataSection(context, settings),
        ..._securitySection(context, ref, settings),
        ..._aboutSection(context, ref),
        ..._dangerSection(context, ref),
      ],
    );
  }

  // ------------------------------------------------------------------- App

  /// "App": the name shown for the app and the currency symbol used
  /// everywhere money is rendered.
  List<Widget> _appSection(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
    LocalSettings local,
  ) {
    final colors = Theme.of(context).colorScheme;
    return [
      const SectionHeader('App'),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: Icon(
                Icons.drive_file_rename_outline_rounded,
                color: colors.primary,
              ),
              title: const Text('App name'),
              subtitle: Text(
                local.appName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _editAppName(context, ref, local.appName),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                Icons.currency_exchange_rounded,
                color: colors.primary,
              ),
              title: const Text('Currency symbol'),
              subtitle: Text(settings.currencySymbol),
              onTap: () => _editCurrencySymbol(context, ref, settings),
            ),
          ],
        ),
      ),
    ];
  }

  /// Prompts for a new app name and stores it in [localSettingsProvider].
  Future<void> _editAppName(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('App name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'App name',
            hintText: 'Shown wherever the app names itself',
            counterText: '',
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (result == null) return;
    if (!context.mounted) return;

    final name = result.trim();
    if (name.isEmpty) {
      showAppMessage(context, 'The app name cannot be empty.', error: true);
      return;
    }

    try {
      await ref.read(localSettingsProvider.notifier).setAppName(name);
    } catch (error) {
      if (!context.mounted) return;
      showAppMessage(context, _friendlyMessage(error), error: true);
      return;
    }
    if (!context.mounted) return;
    showAppMessage(context, 'App name updated');
  }

  /// Prompts for a new currency symbol with a live money preview.
  ///
  /// The symbol is saved through the settings repository behind
  /// [settingsProvider], so every amount rendered with the currency symbol
  /// across the app updates immediately.
  Future<void> _editCurrencySymbol(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) async {
    final controller = TextEditingController(text: settings.currencySymbol);
    var draft = settings.currencySymbol;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (stateContext, setState) {
          final theme = Theme.of(stateContext);
          final colors = theme.colorScheme;
          final symbol = draft.trim();
          final valid = symbol.isNotEmpty && symbol.length <= 4;
          return AlertDialog(
            title: const Text('Currency symbol'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 4,
                  decoration: const InputDecoration(
                    labelText: 'Currency symbol',
                    hintText: '1-4 characters, e.g. \u20b9, \$ or \u20ac',
                    counterText: '',
                  ),
                  onChanged: (value) => setState(() => draft = value),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Preview',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Sample amount in minor units: 12345678 -> 1,23,456.78.
                      Text(
                        formatMinor(
                          12345678,
                          symbol: valid ? symbol : settings.currencySymbol,
                        ),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!valid) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Use between 1 and 4 characters.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.error,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: valid
                    ? () => Navigator.of(dialogContext).pop(controller.text)
                    : null,
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();

    if (result == null) return;
    if (!context.mounted) return;

    final symbol = result.trim();
    if (symbol.isEmpty || symbol.length > 4) {
      showAppMessage(
        context,
        'Use a currency symbol of 1 to 4 characters.',
        error: true,
      );
      return;
    }
    await _save(context, ref, settings.copyWith(currencySymbol: symbol));
  }

  // -------------------------------------------------------------- Defaults

  /// "Defaults": what the Add tab pre-selects for a new transaction.
  List<Widget> _defaultsSection(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
    LocalSettings local,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return [
      const SectionHeader('Defaults'),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(
          'Applied automatically when you open the Add tab.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CatalogPicker(
                kind: CatalogKind.category,
                label: 'Default category',
                valueId: settings.defaultCategoryId,
                onChanged: (id) => _editDefaultCategory(context, ref, settings, id),
              ),
              const SizedBox(height: 16),
              CatalogPicker(
                kind: CatalogKind.paymentMethod,
                label: 'Default payment method',
                valueId: settings.defaultPaymentMethodId,
                onChanged: (id) =>
                    _editDefaultPaymentMethod(context, ref, settings, id),
              ),
              const Divider(height: 32),
              Text(
                'Default transaction type',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<TxType>(
                segments: const [
                  ButtonSegment<TxType>(
                    value: TxType.expense,
                    label: Text('Expense'),
                    icon: Icon(Icons.remove_circle_outline_rounded),
                  ),
                  ButtonSegment<TxType>(
                    value: TxType.income,
                    label: Text('Income'),
                    icon: Icon(Icons.add_circle_outline_rounded),
                  ),
                ],
                selected: {local.defaultTransactionType},
                onSelectionChanged: (selection) =>
                    _editDefaultType(context, ref, selection.first),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  /// Persists the default category chosen in the [CatalogPicker].
  Future<void> _editDefaultCategory(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
    int? id,
  ) async {
    if (id == null || id == settings.defaultCategoryId) return;
    await _save(context, ref, settings.copyWith(defaultCategoryId: id));
  }

  /// Persists the default payment method chosen in the [CatalogPicker].
  Future<void> _editDefaultPaymentMethod(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
    int? id,
  ) async {
    if (id == null || id == settings.defaultPaymentMethodId) return;
    await _save(context, ref, settings.copyWith(defaultPaymentMethodId: id));
  }

  /// Persists the default transaction type in [localSettingsProvider].
  Future<void> _editDefaultType(
    BuildContext context,
    WidgetRef ref,
    TxType type,
  ) async {
    try {
      await ref.read(localSettingsProvider.notifier).setDefaultTransactionType(type);
    } catch (error) {
      if (!context.mounted) return;
      showAppMessage(context, _friendlyMessage(error), error: true);
    }
  }

  // ------------------------------------------------------------ Appearance

  /// "Appearance": theme mode, accent colour and Material You dynamic colour.
  List<Widget> _appearanceSection(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final prefs = ref.watch(uiPreferencesProvider);

    return [
      const SectionHeader('Appearance'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Theme mode',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<ThemeModeSetting>(
                segments: [
                  for (final mode in ThemeModeSetting.values)
                    ButtonSegment<ThemeModeSetting>(
                      value: mode,
                      label: Text(mode.label),
                    ),
                ],
                selected: {prefs.themeMode},
                onSelectionChanged: (selection) => ref
                    .read(uiPreferencesProvider.notifier)
                    .setThemeMode(selection.first),
              ),
              const Divider(height: 32),
              Text(
                'Accent colour',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final accent in AccentColor.values)
                    _accentSwatch(
                      context,
                      accent,
                      selected: accent == prefs.accent,
                      onTap: () => ref
                          .read(uiPreferencesProvider.notifier)
                          .setAccent(accent),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.palette_outlined,
                    size: 16,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      prefs.accent.label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const Divider(height: 32),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use dynamic colour (Material You)'),
                subtitle: const Text(
                  'Follows your wallpaper colours on Android 12 and above.',
                ),
                value: prefs.dynamicColor,
                onChanged: (value) => ref
                    .read(uiPreferencesProvider.notifier)
                    .setDynamicColor(value),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  /// One selectable colour circle.
  ///
  /// The selected swatch is marked three ways - a ring, a check badge and the
  /// name printed below the row - so the state never depends on colour alone,
  /// and the whole 44px circle is the touch target.
  Widget _accentSwatch(
    BuildContext context,
    AccentColor accent, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: accent.label,
      selected: selected,
      button: true,
      child: Tooltip(
        message: accent.label,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(accent.argb),
                  border: Border.all(
                    color: selected ? colors.onSurface : colors.outlineVariant,
                    width: selected ? 3 : 1,
                  ),
                ),
              ),
              if (selected)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.surface,
                      border: Border.all(color: colors.outline, width: 1.5),
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      size: 13,
                      color: colors.onSurface,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ Data

  /// "Data": backup and the optional Google Sheets link.
  List<Widget> _dataSection(BuildContext context, AppSettings settings) {
    final colors = Theme.of(context).colorScheme;
    final sheetTitle = settings.googleSpreadsheetTitle.trim();
    return [
      const SectionHeader('Data'),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: Icon(Icons.save_alt_rounded, color: colors.primary),
              title: const Text('Backup & restore'),
              subtitle: const Text('Export or restore a JSON backup'),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: colors.onSurfaceVariant,
              ),
              onTap: () => Navigator.pushNamed(context, AppRoutes.backup),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.table_view_rounded, color: colors.primary),
              title: const Text('Google Sheets sync'),
              subtitle: Text(
                sheetTitle.isNotEmpty ? sheetTitle : 'Not connected',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: colors.onSurfaceVariant,
              ),
              onTap: () => Navigator.pushNamed(context, AppRoutes.googleSheets),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.vpn_key_outlined, color: colors.primary),
              title: const Text('Google Sheets setup'),
              subtitle: Text(
                settings.hasGoogleConfig
                    ? 'Client ids saved on this device'
                    : 'Enter your OAuth client ids',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: colors.onSurfaceVariant,
              ),
              onTap: () => Navigator.pushNamed(context, AppRoutes.googleSetup),
            ),
          ],
        ),
      ),
    ];
  }

  // -------------------------------------------------------------- Security

  /// "Security": the numeric PIN that guards the account balances.
  List<Widget> _securitySection(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) {
    final colors = Theme.of(context).colorScheme;
    final locked = settings.hasBalanceLock;
    return [
      const SectionHeader('Security'),
      Card(
        child: ListTile(
          leading: Icon(
            locked ? Icons.lock_rounded : Icons.lock_open_rounded,
            color: locked ? colors.primary : colors.onSurfaceVariant,
          ),
          title: const Text('Protect account balances'),
          subtitle: Text(
            locked
                ? 'On - a PIN is asked for before balances are shown'
                : 'Off - anyone holding the phone can see them',
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: colors.onSurfaceVariant,
          ),
          onTap: () => locked
              ? _manageBalancePin(context, ref, settings)
              : _setBalancePin(context, ref, settings),
        ),
      ),
    ];
  }

  /// Turning the lock on: enter the new PIN, then type it again.
  Future<void> _setBalancePin(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) async {
    final pin = await showPinDialog(
      context,
      title: 'Set a balance PIN',
      message:
          'Digits only, ${BalancePin.minLength} to ${BalancePin.maxLength} of them. '
          'You will be asked for it before any balance is shown.',
      confirm: true,
    );
    if (pin == null || !context.mounted) return;

    final salt = BalancePin.newSalt();
    await _save(
      context,
      ref,
      settings.copyWith(
        balancePinHash: BalancePin.hash(pin, salt),
        balancePinSalt: salt,
      ),
    );
  }

  /// Turning it off, or replacing the PIN: the current one is asked for first.
  Future<void> _manageBalancePin(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.pin_outlined),
              title: const Text('Change PIN'),
              onTap: () => Navigator.pop(sheetContext, 'change'),
            ),
            ListTile(
              leading: const Icon(Icons.lock_open_rounded),
              title: const Text('Turn protection off'),
              subtitle: const Text('Requires the current PIN'),
              onTap: () => Navigator.pop(sheetContext, 'off'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;

    final current = await showPinDialog(
      context,
      title: 'Enter your current PIN',
      message: 'Confirm it is you before the lock is changed.',
    );
    if (current == null || !context.mounted) return;

    if (!BalancePin.matches(current, settings.balancePinHash, settings.balancePinSalt)) {
      showAppMessage(context, 'That PIN is not correct.', error: true);
      return;
    }

    if (action == 'off') {
      await _save(context, ref, settings.copyWith(clearBalanceLock: true));
      return;
    }

    final next = await showPinDialog(
      context,
      title: 'Set a new balance PIN',
      message:
          'Digits only, ${BalancePin.minLength} to ${BalancePin.maxLength} of them.',
      confirm: true,
    );
    if (next == null || !context.mounted) return;

    final salt = BalancePin.newSalt();
    await _save(
      context,
      ref,
      settings.copyWith(
        balancePinHash: BalancePin.hash(next, salt),
        balancePinSalt: salt,
      ),
    );
  }

  // ---------------------------------------------------------------- About

  /// "About": contact, about page and the installed version.
  List<Widget> _aboutSection(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return [
      const SectionHeader('About'),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: Icon(Icons.mail_outline_rounded, color: colors.primary),
              title: const Text('Contact'),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: colors.onSurfaceVariant,
              ),
              onTap: () => Navigator.pushNamed(context, AppRoutes.contact),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.info_outline_rounded, color: colors.primary),
              title: const Text('About'),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: colors.onSurfaceVariant,
              ),
              onTap: () => Navigator.pushNamed(context, AppRoutes.about),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  Icon(Icons.verified_rounded, color: colors.primary),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Version',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        AsyncValueView<AppVersion>(
                          value: ref.watch(appVersionProvider),
                          loadingLabel: 'Reading version...',
                          onRetry: () => ref.invalidate(appVersionProvider),
                          data: (version) => Text(
                            version.label,
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
          ],
        ),
      ),
    ];
  }

  // ---------------------------------------------------------- Danger zone

  /// "Danger zone": restore every setting to the values the app ships with.
  List<Widget> _dangerSection(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return [
      const SectionHeader('Danger zone'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Resets the app name, currency symbol, Add-tab defaults, theme, '
                'accent, dynamic colour and any linked Google Sheet. Your '
                'transactions, categories and events are not touched.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: colors.errorContainer,
                    foregroundColor: colors.onErrorContainer,
                    side: BorderSide(color: colors.error),
                  ),
                  onPressed: () => _reset(context, ref),
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Reset settings to defaults'),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  /// Confirms, then writes a fresh [AppSettings] and the shipped UI defaults.
  Future<void> _reset(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Reset settings?',
      message: 'The app name, currency symbol, Add-tab defaults, theme, '
          'accent, dynamic colour and the linked Google Sheet go back to '
          'their original values. Your transactions, categories and events '
          'are kept.',
      confirmLabel: 'Reset everything',
      destructive: true,
    );
    if (!confirmed) return;
    if (!context.mounted) return;

    const defaults = AppUiPreferences();
    try {
      await ref.read(settingsRepositoryProvider).save(const AppSettings());
      final appearance = ref.read(uiPreferencesProvider.notifier);
      await appearance.setThemeMode(defaults.themeMode);
      await appearance.setAccent(defaults.accent);
      await appearance.setDynamicColor(defaults.dynamicColor);
      await ref.read(localSettingsProvider.notifier).reset();
    } catch (error) {
      if (!context.mounted) return;
      showAppMessage(context, _friendlyMessage(error), error: true);
      return;
    }
    if (!context.mounted) return;
    showAppMessage(context, 'Settings reset');
  }

  // -------------------------------------------------------------- helpers

  /// Writes [next] to SQLite and surfaces a readable error if it fails.
  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    AppSettings next,
  ) async {
    try {
      await ref.read(settingsRepositoryProvider).save(next);
    } catch (error) {
      if (!context.mounted) return;
      showAppMessage(context, _friendlyMessage(error), error: true);
    }
  }

  /// Turns any caught error into a short sentence safe to show in the UI.
  String _friendlyMessage(Object error) {
    if (error is AppException) return error.message;
    return 'Something went wrong. Please try again.';
  }
}
