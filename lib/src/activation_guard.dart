import 'dart:io';

import 'adapters.dart';
import 'interfaces.dart';
import 'logger.dart';
import 'version.dart';

/// Detects `dart pub global activate` runs and prompts the user to reset
/// configuration when a new activation is found alongside existing config.
///
/// Extracted from Wizard for testability — all I/O is injected.
class ActivationGuard {
  final MachineConfigStore _config;
  final DriveRemote _remote;
  final String? Function() _getLockFileMtime;
  final String? Function() _readLine;
  final StringSink _out;

  ActivationGuard({
    required MachineConfigStore config,
    required DriveRemote remote,
    required String? Function() getLockFileMtime,
    required String? Function() readLine,
    StringSink? out,
  })  : _config = config,
        _remote = remote,
        _getLockFileMtime = getLockFileMtime,
        _readLine = readLine,
        _out = out ?? stdout;

  factory ActivationGuard.production() {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    final lockPath =
        '$home/.pub-cache/global_packages/$packageName/pubspec.lock';
    return ActivationGuard(
      config: AppConfigAdapter(),
      remote: RcloneAdapter(),
      getLockFileMtime: () {
        final f = File(lockPath);
        if (!f.existsSync()) return null;
        return f.lastModifiedSync().millisecondsSinceEpoch.toString();
      },
      readLine: () => stdin.readLineSync()?.trim(),
    );
  }

  /// Runs the activation-detection logic.
  ///
  /// In CI mode (flags were parsed), skips the interactive prompt and silently
  /// stamps the new activation time so automation is never blocked.
  Future<void> handle({required bool isCiMode}) async {
    final currentMtime = _getLockFileMtime();
    if (currentMtime == null) return; // not a globally activated package

    final machine = _config.load();
    final savedMtime = machine['activationTime'] as String?;

    if (savedMtime == currentMtime) return; // same activation — nothing to do

    // Decide whether there is meaningful config worth prompting the user about.
    // Meta-only keys (activationTime, macosGatekeeperNoticeSeen) are excluded
    // because they carry no user-entered data.
    //
    // NOTE: do NOT require savedMtime != null here. A user who has meaningful
    // config (projectDirectory, folderName, etc.) but no activationTime stamp
    // (e.g. they upgraded from a version before activation tracking existed)
    // must still see the prompt.  The old `&& savedMtime != null` guard was
    // the root cause of the prompt silently never appearing in that case.
    final meaningfulKeys = machine.keys
        .where(
          (k) => k != 'activationTime' && k != 'macosGatekeeperNoticeSeen',
        )
        .toList();
    final hasExistingConfig = meaningfulKeys.isNotEmpty;

    if (!hasExistingConfig) {
      // First-ever run or no real config — stamp and continue without prompt.
      _config.save({'activationTime': currentMtime});
      return;
    }

    if (isCiMode) {
      // Never block automation with an interactive prompt.
      _config.save({'activationTime': currentMtime});
      return;
    }

    // ── Interactive prompt ────────────────────────────────────────────────────
    _out.writeln(
        '  ─── New Package Activation Detected ────────────────────');
    _out.writeln('');
    _out.writeln('  A new activation of $packageName was detected.');
    _out.writeln('');
    _out.writeln('  Existing configuration:');
    _activationInfoRow('Project', machine['projectDirectory'] as String?);
    _activationInfoRow('App', machine['appName'] as String?);
    _activationInfoRow('Drive folder', machine['folderName'] as String?);
    if ((machine['diawiToken'] as String?)?.isNotEmpty == true) {
      _out.writeln('    Diawi         Configured');
    }
    _out.writeln('');
    _out.writeln(
      '  Clear existing configuration and run setup again? [y/N]: ',
    );
    _out.write('  > ');

    final answer = _readLine()?.toLowerCase() ?? '';
    _out.writeln('');

    if (answer == 'y' || answer == 'yes') {
      // Full reset: remove project config, disconnect Google Drive,
      // clear all machine config.
      final projectDir = machine['projectDirectory'] as String?;
      if (projectDir != null) {
        final projectConfig =
            File('$projectDir/.flutter_release_manager_config.json');
        if (projectConfig.existsSync()) {
          projectConfig.deleteSync();
          Logger.ok('Project configuration removed.');
        }
      }
      if (_remote.exists()) {
        _remote.delete();
        Logger.ok('Google Drive disconnected.');
      }
      _config.resetAll();
      Logger.ok('Machine configuration cleared.');
      // Re-stamp so this prompt does not reappear until the next activation.
      _config.save({'activationTime': currentMtime});
      _out.writeln('');
      _out.writeln('  Starting fresh setup...');
      _out.writeln('');
    } else {
      // User keeps existing configuration — just stamp the new activation time.
      _config.save({'activationTime': currentMtime});
      Logger.ok('Configuration kept. Continuing with existing settings.');
      _out.writeln('');
    }
  }

  void _activationInfoRow(String label, String? value) {
    if (value == null || value.isEmpty) return;
    _out.writeln('    ${label.padRight(14)} $value');
  }
}
