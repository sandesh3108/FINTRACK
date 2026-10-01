import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Version identifiers of the installed build.
class AppVersion {
  /// Creates a version snapshot.
  const AppVersion({required this.version, required this.buildNumber});

  /// Package version reported by the platform, e.g. `1.0.0`.
  final String version;

  /// Package build number reported by the platform, e.g. `1`.
  final String buildNumber;

  /// Mirrors the `version` declared in `pubspec.yaml`.
  ///
  /// Used when the platform channel cannot answer - in widget tests, or on a
  /// platform without `package_info_plus` - so the About and Settings screens
  /// still render a complete version row instead of an error state.
  static const AppVersion fallback =
      AppVersion(version: '1.0.0', buildNumber: '1');

  /// `v1.0.0 (1)` - the single format every version label uses.
  String get label => 'v$version ($buildNumber)';
}

/// Version of the installed app, read once from `package_info_plus`.
///
/// The future always resolves: [PackageInfo.fromPlatform] failures fall back
/// to [AppVersion.fallback], because a cosmetic label must never show an error
/// screen.
final FutureProvider<AppVersion> appVersionProvider =
    FutureProvider<AppVersion>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    return AppVersion(version: info.version, buildNumber: info.buildNumber);
  } catch (_) {
    return AppVersion.fallback;
  }
});
