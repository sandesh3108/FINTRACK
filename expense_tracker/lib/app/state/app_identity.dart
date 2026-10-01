import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../features/settings/local_settings.dart';

/// The name the app should call itself right now.
///
/// *Settings* lets the person rename the app, and that rename has to show up
/// **everywhere** the app names itself - the Home bar, the task switcher, the
/// About card, the file it shares, the mail it composes - not only on the row
/// that was tapped. Every one of those reads this provider instead of
/// [AppConfig.appName], which is a compile-time constant and therefore cannot
/// change after the APK is installed.
///
/// Falls back to the build-time name while the preference is still loading
/// and when the field has been cleared, so there is never a blank title.
final Provider<String> appNameProvider = Provider<String>((ref) {
  final stored = ref.watch(localSettingsProvider).valueOrNull?.appName.trim();
  return (stored == null || stored.isEmpty) ? AppConfig.appName : stored;
});
