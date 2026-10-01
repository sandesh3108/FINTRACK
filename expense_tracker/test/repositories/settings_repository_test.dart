import 'dart:convert';

import 'package:expense_tracker/repositories/backup_repository.dart';
import 'package:expense_tracker/shared/models/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_harness.dart';

/// Repeats [char] into a string of [length] - the Pads-and-joins idiom used
/// wherever a fixed-width placeholder is needed.
String filled(int length, String char) => List<String>.filled(length, char).join();

/// Settings are a key/value table, so it is easy to add a field and quietly
/// drop it on the way back out. These tests hold the new keys to their round
/// trip, including through a backup, because both are places a value can
/// disappear without anything failing loudly.
void main() {
  late TestHarness harness;

  setUp(() => harness = TestHarness());
  tearDown(() => harness.close());

  group('Google OAuth ids', () {
    test('are absent on a fresh install', () async {
      final loaded = await harness.settings.load();

      expect(loaded.googleClientIdAndroid, isEmpty);
      expect(loaded.googleClientIdWeb, isEmpty);
      expect(loaded.googleProjectId, isEmpty);
      expect(loaded.hasGoogleConfig, isFalse);
    });

    test('round-trip through save and load', () async {
      await harness.settings.save(
        const AppSettings(
          googleClientIdAndroid: 'android-1.apps.googleusercontent.com',
          googleClientIdWeb: 'web-1.apps.googleusercontent.com',
          googleProjectId: 'my-project-123',
        ),
      );

      final loaded = await harness.settings.load();

      expect(loaded.googleClientIdAndroid, 'android-1.apps.googleusercontent.com');
      expect(loaded.googleClientIdWeb, 'web-1.apps.googleusercontent.com');
      expect(loaded.googleProjectId, 'my-project-123');
      expect(loaded.hasGoogleConfig, isTrue);
    });

    test('a single id is enough to enable sign-in', () async {
      await harness.settings.save(
        const AppSettings(googleClientIdAndroid: 'android-1.apps.googleusercontent.com'),
      );

      final loaded = await harness.settings.load();
      expect(loaded.hasGoogleConfig, isTrue);
    });

    test('clearing them disables the gate again', () async {
      await harness.settings.save(
        const AppSettings(
          googleClientIdAndroid: 'android-1.apps.googleusercontent.com',
          googleClientIdWeb: 'web-1.apps.googleusercontent.com',
        ),
      );

      await harness.settings
          .save((await harness.settings.load()).copyWith(clearGoogleConfig: true));

      final loaded = await harness.settings.load();
      expect(loaded.googleClientIdAndroid, isEmpty);
      expect(loaded.googleClientIdWeb, isEmpty);
      expect(loaded.hasGoogleConfig, isFalse);
    });

    test('leaving other settings untouched when one is edited', () async {
      await harness.settings.save(
        const AppSettings(
          currencySymbol: '€',
          googleClientIdWeb: 'web-1.apps.googleusercontent.com',
        ),
      );

      await harness.settings.save(
        (await harness.settings.load()).copyWith(googleProjectId: 'p'),
      );

      final loaded = await harness.settings.load();
      expect(loaded.currencySymbol, '€',
          reason: 'copyWith must not drop fields it was not told about');
      expect(loaded.googleClientIdWeb, 'web-1.apps.googleusercontent.com');
      expect(loaded.googleProjectId, 'p');
    });
  });

  group('balance PIN', () {
    test('is unset on a fresh install', () async {
      final loaded = await harness.settings.load();
      expect(loaded.hasBalanceLock, isFalse);
    });

    test('round-trips as a hash and salt, never as the PIN', () async {
      const pin = '48291';
      // Hashing happens in the UI layer; settings only carry the pair.
      final digest = filled(64, 'a');
      await harness.settings
          .save(AppSettings(balancePinHash: digest, balancePinSalt: filled(32, 'b')));

      final loaded = await harness.settings.load();
      expect(loaded.balancePinHash, digest);
      expect(loaded.balancePinSalt, filled(32, 'b'));
      expect(loaded.hasBalanceLock, isTrue);
      expect(pin, isNot(loaded.balancePinHash));
    });

    test('clearing the lock removes both halves', () async {
      await harness.settings
          .save(AppSettings(balancePinHash: filled(64, 'a'), balancePinSalt: 's'));

      await harness.settings
          .save((await harness.settings.load()).copyWith(clearBalanceLock: true));

      final loaded = await harness.settings.load();
      expect(loaded.balancePinHash, isEmpty);
      expect(loaded.balancePinSalt, isEmpty);
      expect(loaded.hasBalanceLock, isFalse);
    });

    test('a half-written lock never reports as enabled', () async {
      // A hash without its salt cannot be checked against anything, so
      // [hasBalanceLock] must treat it as off rather than as a locked door
      // nobody can open.
      await harness.settings.save(AppSettings(balancePinHash: filled(64, 'a')));
      expect((await harness.settings.load()).hasBalanceLock, isFalse);

      await harness.settings.save(const AppSettings(balancePinSalt: 's'));
      expect((await harness.settings.load()).hasBalanceLock, isFalse);
    });
  });

  group('backup', () {
    test('carries the OAuth ids so a restored device keeps its setup', () async {
      await harness.settings.save(
        const AppSettings(
          googleClientIdAndroid: 'android-1.apps.googleusercontent.com',
          googleProjectId: 'my-project-123',
        ),
      );
      final json = await harness.backup.createBackupJson();

      await harness.settings.save(const AppSettings());
      await harness.backup.restore(json, mode: BackupRestoreMode.replace);

      final restored = await harness.settings.load();
      expect(restored.googleClientIdAndroid, 'android-1.apps.googleusercontent.com');
      expect(restored.googleProjectId, 'my-project-123');
      expect(restored.hasGoogleConfig, isTrue);
    });

    test('keeps the balance lock after a replace restore', () async {
      final salt = filled(32, 'f');
      final digest = filled(64, '9');
      await harness.settings.save(
        AppSettings(balancePinHash: digest, balancePinSalt: salt),
      );
      final json = await harness.backup.createBackupJson();

      await harness.settings.save(const AppSettings());
      await harness.backup.restore(json, mode: BackupRestoreMode.replace);

      final restored = await harness.settings.load();
      expect(
        restored.hasBalanceLock,
        isTrue,
        reason: 'a restore must not silently unlock a locked app',
      );
      expect(restored.balancePinHash, digest);
      expect(restored.balancePinSalt, salt);
    });

    test('a backup written before these keys existed still restores', () async {
      // Same document, minus the five keys this change introduced - which is
      // exactly what an older build would have produced.
      final document =
          jsonDecode(await harness.backup.createBackupJson()) as Map<String, dynamic>;
      final settingsBlock = document['settings'] as Map<String, dynamic>;
      for (final key in const <String>[
        'googleClientIdAndroid',
        'googleClientIdWeb',
        'googleProjectId',
        'balancePinHash',
        'balancePinSalt',
      ]) {
        settingsBlock.remove(key);
      }

      await harness.settings.save(
        const AppSettings(
          googleClientIdAndroid: 'android-1.apps.googleusercontent.com',
          balancePinHash: 'h',
          balancePinSalt: 's',
        ),
      );
      await harness.backup.restore(
        jsonEncode(document),
        mode: BackupRestoreMode.replace,
      );

      final restored = await harness.settings.load();
      expect(restored.currencySymbol, isNotEmpty,
          reason: 'the rest of the document must still land');
      expect(restored.googleClientIdAndroid, isEmpty);
      expect(
        restored.hasBalanceLock,
        isFalse,
        reason: 'an old backup clears a lock rather than half-restoring it',
      );
    });
  });
}
