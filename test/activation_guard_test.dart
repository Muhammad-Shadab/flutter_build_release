import 'dart:io';

import 'package:flutter_release_manager/src/activation_guard.dart';
import 'package:test/test.dart';

import 'helpers/fakes.dart';

void main() {
  group('ActivationGuard', () {
    test('1. first run — stamps activationTime without prompting', () async {
      final config = FakeMachineConfig(); // empty, no activationTime
      final remote = FakeDriveRemote();
      final guard = ActivationGuard(
        config: config,
        remote: remote,
        getLockFileMtime: () => '1000',
        readLine: () => fail('should not prompt on first run'),
        out: StringBuffer(),
      );

      await guard.handle(isCiMode: false);

      expect(config.data['activationTime'], equals('1000'));
      expect(config.resetAllCalled, isFalse);
      expect(remote.deleteCalled, isFalse);
    });

    test('2. normal run — same mtime, does nothing', () async {
      final config = FakeMachineConfig({
        'activationTime': '1000',
        'folderName': 'MyApp',
      });
      final remote = FakeDriveRemote();
      var promptCalled = false;
      final guard = ActivationGuard(
        config: config,
        remote: remote,
        getLockFileMtime: () => '1000', // same as saved
        readLine: () {
          promptCalled = true;
          return 'n';
        },
        out: StringBuffer(),
      );

      await guard.handle(isCiMode: false);

      expect(promptCalled, isFalse);
      expect(config.resetAllCalled, isFalse);
      expect(config.saveCallCount, equals(0));
    });

    test('3. new activation + answer n — stamps only, no reset', () async {
      final config = FakeMachineConfig({
        'activationTime': '1000',
        'folderName': 'MyApp',
      });
      final remote = FakeDriveRemote(exists: true);
      final guard = ActivationGuard(
        config: config,
        remote: remote,
        getLockFileMtime: () => '2000',
        readLine: fakeReadLine(['n']),
        out: StringBuffer(),
      );

      await guard.handle(isCiMode: false);

      expect(config.data['activationTime'], equals('2000'));
      expect(config.resetAllCalled, isFalse);
      expect(remote.deleteCalled, isFalse);
    });

    test('4. new activation + answer y — performs full reset', () async {
      final tempDir = await Directory.systemTemp.createTemp('frm_test_');
      final projectConfigFile = File(
          '${tempDir.path}/.flutter_release_manager_config.json');
      await projectConfigFile.writeAsString('{}');

      try {
        final config = FakeMachineConfig({
          'activationTime': '1000',
          'folderName': 'MyApp',
          'projectDirectory': tempDir.path,
        });
        final remote = FakeDriveRemote(exists: true);
        final guard = ActivationGuard(
          config: config,
          remote: remote,
          getLockFileMtime: () => '2000',
          readLine: fakeReadLine(['y']),
          out: StringBuffer(),
        );

        await guard.handle(isCiMode: false);

        expect(config.resetAllCalled, isTrue);
        expect(remote.deleteCalled, isTrue);
        expect(projectConfigFile.existsSync(), isFalse);
        // activationTime is re-stamped after reset
        expect(config.data['activationTime'], equals('2000'));
      } finally {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      }
    });

    test('5. CI mode — silently stamps, no prompt', () async {
      final config = FakeMachineConfig({
        'activationTime': '1000',
        'folderName': 'MyApp',
      });
      final remote = FakeDriveRemote(exists: true);
      var promptCalled = false;
      final guard = ActivationGuard(
        config: config,
        remote: remote,
        getLockFileMtime: () => '2000',
        readLine: () {
          promptCalled = true;
          return 'y';
        },
        out: StringBuffer(),
      );

      await guard.handle(isCiMode: true);

      expect(promptCalled, isFalse);
      expect(config.resetAllCalled, isFalse);
      expect(config.data['activationTime'], equals('2000'));
      expect(remote.deleteCalled, isFalse);
    });

    test('lock file absent — skips entirely (not globally activated)',
        () async {
      final config = FakeMachineConfig({
        'activationTime': '1000',
        'folderName': 'MyApp',
      });
      final remote = FakeDriveRemote();
      final guard = ActivationGuard(
        config: config,
        remote: remote,
        getLockFileMtime: () => null, // file does not exist
        readLine: () => fail('should not prompt when lock file absent'),
        out: StringBuffer(),
      );

      await guard.handle(isCiMode: false);

      expect(config.saveCallCount, equals(0));
      expect(config.resetAllCalled, isFalse);
    });

    // ── Regression: bug where savedMtime != null gate silenced the prompt ────
    //
    // Users who had config BEFORE activation tracking was added had no
    // activationTime key. The old condition:
    //   hasExistingConfig = meaningfulKeys.isNotEmpty && savedMtime != null
    // evaluated to false (savedMtime was null), so the prompt was silently
    // skipped. The fix: hasExistingConfig = meaningfulKeys.isNotEmpty only.
    test(
        'regression — meaningful config with no prior activationTime still prompts',
        () async {
      // Simulate a user who had the tool before activation tracking existed:
      // real config keys but no activationTime stamp.
      final config = FakeMachineConfig({
        'projectDirectory': '/path/to/app',
        'appName': 'MyApp',
        'folderName': 'AppReleases',
        'autoUploadDrive': true,
      });
      final remote = FakeDriveRemote(exists: true);
      var promptShown = false;
      final guard = ActivationGuard(
        config: config,
        remote: remote,
        getLockFileMtime: () => '2000',
        readLine: () {
          promptShown = true;
          return 'n'; // user keeps config
        },
        out: StringBuffer(),
      );

      await guard.handle(isCiMode: false);

      // With the fix, the prompt MUST appear.
      expect(promptShown, isTrue,
          reason: 'prompt must appear for users with config but no activationTime');
      expect(config.resetAllCalled, isFalse);
      expect(config.data['activationTime'], equals('2000'));
      expect(remote.deleteCalled, isFalse);
    });

    test('new activation with no Drive — resets without calling delete',
        () async {
      final config = FakeMachineConfig({
        'activationTime': '1000',
        'folderName': 'MyApp',
      });
      final remote = FakeDriveRemote(exists: false); // Drive not connected
      final guard = ActivationGuard(
        config: config,
        remote: remote,
        getLockFileMtime: () => '2000',
        readLine: fakeReadLine(['y']),
        out: StringBuffer(),
      );

      await guard.handle(isCiMode: false);

      expect(config.resetAllCalled, isTrue);
      expect(remote.deleteCalled, isFalse); // no remote to delete
    });
  });
}
