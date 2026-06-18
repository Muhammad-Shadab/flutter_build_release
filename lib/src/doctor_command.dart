import 'dart:io';

import 'app_config.dart';
import 'logger.dart';
import 'rclone_manager.dart';

/// Implements `flutter_release_manager doctor`.
///
/// Checks every prerequisite and reports pass/fail with fix instructions.
class DoctorCommand {
  Future<void> run() async {
    Logger.header('flutter_release_manager doctor');
    stdout.writeln('');

    var allOk = true;

    allOk = _check('flutter', _checkFlutter()) && allOk;
    allOk = _check('rclone', _checkRclone()) && allOk;
    allOk = _check('Drive remote', _checkRemote()) && allOk;
    allOk = _check('Drive connection', _checkDriveConnection()) && allOk;
    allOk = _check('Drive folder', _checkFolder()) && allOk;
    _checkDiawi(); // advisory only — not a blocker

    stdout.writeln('');
    if (allOk) {
      Logger.ok('All checks passed. Ready to build and upload.');
    } else {
      Logger.skip(
        'Some checks failed. Run: flutter_release_manager init',
      );
    }
    stdout.writeln('');
  }

  // ── Checks ─────────────────────────────────────────────────────────────────

  _CheckResult _checkFlutter() {
    final cmd = Platform.isWindows ? 'where' : 'which';
    if (Process.runSync(cmd, ['flutter'], runInShell: true).exitCode == 0) {
      return _CheckResult.ok('flutter found');
    }
    return _CheckResult.fail(
      'flutter not found',
      'Install Flutter: https://flutter.dev/docs/get-started/install',
    );
  }

  _CheckResult _checkRclone() {
    if (RcloneManager.isInstalled()) {
      return _CheckResult.ok(RcloneManager.installedVersion());
    }
    return _CheckResult.fail(
      'rclone not found',
      'Run: flutter_release_manager init',
    );
  }

  _CheckResult _checkRemote() {
    if (!RcloneManager.isInstalled()) {
      return _CheckResult.skip('skipped (rclone not installed)');
    }
    if (RcloneManager.remoteExists()) {
      return _CheckResult.ok('remote "${RcloneManager.remoteName}" configured');
    }
    return _CheckResult.fail(
      'remote "${RcloneManager.remoteName}" not found',
      'Run: flutter_release_manager init',
    );
  }

  _CheckResult _checkDriveConnection() {
    if (!RcloneManager.isInstalled() || !RcloneManager.remoteExists()) {
      return _CheckResult.skip('skipped (remote not configured)');
    }
    final result = Process.runSync(
      'rclone',
      ['about', '${RcloneManager.remoteName}:'],
      runInShell: true,
    );
    if (result.exitCode == 0) {
      return _CheckResult.ok('Google Drive reachable');
    }
    return _CheckResult.fail(
      'cannot connect to Google Drive',
      'Run: flutter_release_manager init',
    );
  }

  _CheckResult _checkFolder() {
    final folder = AppConfig.folderName;
    if (folder == null) {
      return _CheckResult.fail(
        'Drive folder not configured',
        'Run: flutter_release_manager init',
      );
    }
    if (!RcloneManager.isInstalled() || !RcloneManager.remoteExists()) {
      return _CheckResult.skip('Drive folder "$folder" (remote unavailable)');
    }
    if (RcloneManager.folderExists(folder)) {
      return _CheckResult.ok('Drive folder "$folder" accessible');
    }
    return _CheckResult.skip(
      'Drive folder "$folder" not found in root '
      '(will be created on first upload)',
    );
  }

  void _checkDiawi() {
    if (AppConfig.hasDiawiToken) {
      _check('Diawi token', _CheckResult.ok('token saved'));
    } else {
      _check(
        'Diawi token',
        _CheckResult.skip('not set — iOS Diawi upload will be skipped'),
      );
    }
  }

  bool _check(String label, _CheckResult result) {
    final pad = label.length < 16 ? ' ' * (16 - label.length) : '';
    switch (result.status) {
      case _Status.ok:
        Logger.ok('$label$pad  ${result.message}');
        return true;
      case _Status.skip:
        Logger.skip('$label$pad  ${result.message}');
        return true;
      case _Status.fail:
        Logger.error('$label$pad  ${result.message}');
        if (result.fix != null) {
          stderr.writeln('               Fix: ${result.fix}');
        }
        return false;
    }
  }
}

enum _Status { ok, skip, fail }

class _CheckResult {
  final _Status status;
  final String message;
  final String? fix;

  const _CheckResult._(this.status, this.message, [this.fix]);

  factory _CheckResult.ok(String message) =>
      _CheckResult._(_Status.ok, message);

  factory _CheckResult.skip(String message) =>
      _CheckResult._(_Status.skip, message);

  factory _CheckResult.fail(String message, String fix) =>
      _CheckResult._(_Status.fail, message, fix);
}
