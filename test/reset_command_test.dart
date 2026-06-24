import 'dart:io';

import 'package:flutter_release_manager/src/reset_command.dart';
import 'package:test/test.dart';

import 'helpers/fakes.dart';

void main() {
  group('ResetCommand', () {
    test('5. soft reset — removes configs, preserves Drive', () async {
      final tempDir = await Directory.systemTemp.createTemp('frm_test_');
      final projectConfigFile = File(
          '${tempDir.path}/.flutter_release_manager_config.json');
      await projectConfigFile.writeAsString('{}');

      try {
        final config = FakeMachineConfig({
          'projectDirectory': tempDir.path,
          'folderName': 'MyApp',
        });
        final remote = FakeDriveRemote(exists: true);
        final cmd = ResetCommand(
          config: config,
          remote: remote,
          readLine: fakeReadLine(['reset']),
          out: StringBuffer(),
        );

        await cmd.run([]);

        expect(config.resetAllCalled, isTrue);
        expect(remote.deleteCalled, isFalse);
        expect(projectConfigFile.existsSync(), isFalse);
      } finally {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      }
    });

    test('6. full reset (--all) — removes configs and Drive', () async {
      final tempDir = await Directory.systemTemp.createTemp('frm_test_');
      final projectConfigFile = File(
          '${tempDir.path}/.flutter_release_manager_config.json');
      await projectConfigFile.writeAsString('{}');

      try {
        final config = FakeMachineConfig({
          'projectDirectory': tempDir.path,
          'folderName': 'MyApp',
        });
        final remote = FakeDriveRemote(exists: true);
        final cmd = ResetCommand(
          config: config,
          remote: remote,
          readLine: fakeReadLine(['reset']),
          out: StringBuffer(),
        );

        await cmd.run(['--all']);

        expect(config.resetAllCalled, isTrue);
        expect(remote.deleteCalled, isTrue);
        expect(projectConfigFile.existsSync(), isFalse);
      } finally {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      }
    });

    test('cancelled — does nothing when user presses Enter', () async {
      final config = FakeMachineConfig({
        'projectDirectory': '/some/project',
        'folderName': 'MyApp',
      });
      final remote = FakeDriveRemote(exists: true);
      final cmd = ResetCommand(
        config: config,
        remote: remote,
        readLine: fakeReadLine(['']), // Enter without typing 'reset'
        out: StringBuffer(),
      );

      await cmd.run([]);

      expect(config.resetAllCalled, isFalse);
      expect(remote.deleteCalled, isFalse);
    });

    test('soft reset with no project config — still clears machine config',
        () async {
      final config = FakeMachineConfig({
        'folderName': 'MyApp', // no projectDirectory
      });
      final remote = FakeDriveRemote(exists: true);
      final cmd = ResetCommand(
        config: config,
        remote: remote,
        readLine: fakeReadLine(['reset']),
        out: StringBuffer(),
      );

      await cmd.run([]);

      expect(config.resetAllCalled, isTrue);
      expect(remote.deleteCalled, isFalse);
    });

    test('full reset with no Drive — resets without calling delete', () async {
      final config = FakeMachineConfig({'folderName': 'MyApp'});
      final remote = FakeDriveRemote(exists: false);
      final cmd = ResetCommand(
        config: config,
        remote: remote,
        readLine: fakeReadLine(['reset']),
        out: StringBuffer(),
      );

      await cmd.run(['--all']);

      expect(config.resetAllCalled, isTrue);
      expect(remote.deleteCalled, isFalse);
    });
  });
}
