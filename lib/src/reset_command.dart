import 'dart:io';

import 'adapters.dart';
import 'app_config.dart';
import 'interfaces.dart';
import 'logger.dart';
import 'rclone_manager.dart';

/// Implements `flutter_release_manager reset` and `flutter_release_manager reset --all`.
///
/// Soft reset (no flags):
///   Clears machine config and project config.
///   Google Drive connection (rclone remote + OAuth token) is preserved.
///
/// Full reset (--all):
///   Everything in soft reset, plus removes the rclone remote so Google Drive
///   authentication is fully revoked. Next run requires a fresh Google sign-in.
class ResetCommand {
  final MachineConfigStore _config;
  final DriveRemote _remote;
  final String? Function() _readLine;
  final StringSink _out;

  ResetCommand({
    required MachineConfigStore config,
    required DriveRemote remote,
    required String? Function() readLine,
    StringSink? out,
  })  : _config = config,
        _remote = remote,
        _readLine = readLine,
        _out = out ?? stdout;

  factory ResetCommand.production() => ResetCommand(
        config: AppConfigAdapter(),
        remote: RcloneAdapter(),
        readLine: () => stdin.readLineSync()?.trim(),
      );

  Future<void> run(List<String> args) async {
    final isFullReset = args.contains('--all');
    _printHeader(isFullReset);

    final machine = _config.load();
    final projectDir = machine['projectDirectory'] as String?;

    // ── Show exactly what will be removed ──────────────────────────────────────
    _out.writeln('  The following will be permanently removed:');
    _out.writeln('');
    _out.writeln('    • Machine config     ${_config.configPath}');
    if (projectDir != null) {
      _out.writeln(
        '    • Project config     '
        '$projectDir/.flutter_release_manager_config.json',
      );
    }
    if (isFullReset) {
      final driveConnected = _remote.exists();
      if (driveConnected) {
        final email = AppConfig.driveEmail;
        final accountLabel = email ?? 'connected';
        _out.writeln(
          '    • Google Drive       '
          'rclone remote "${RcloneManager.remoteName}" ($accountLabel)',
        );
      }
    } else {
      _out.writeln('');
      _out.writeln(
        '  Google Drive connection is NOT removed (soft reset).',
      );
      _out.writeln(
        '  Use: flutter_release_manager reset --all   '
        'to also disconnect Drive.',
      );
    }
    _out.writeln('');

    // ── Confirmation ───────────────────────────────────────────────────────────
    _out.writeln('  Type "reset" to confirm, or press Enter to cancel:');
    _out.write('  > ');
    final confirm = _readLine() ?? '';
    _out.writeln('');

    if (confirm != 'reset') {
      _out.writeln('  Reset cancelled. No changes were made.');
      _out.writeln('');
      return;
    }

    // ── Execute ────────────────────────────────────────────────────────────────
    _deleteProjectConfig(projectDir);

    if (isFullReset && _remote.exists()) {
      _remote.delete();
      Logger.ok('Google Drive disconnected.');
    }

    _config.resetAll();
    Logger.ok('Machine configuration cleared.');

    // ── Done ───────────────────────────────────────────────────────────────────
    _out.writeln('');
    _out.writeln(isFullReset ? '  Full reset complete.' : '  Reset complete.');
    _out.writeln('');
    _out.writeln(
      '  Run: flutter_release_manager init   to set up Google Drive',
    );
    _out.writeln(
      '  Run: flutter_release_manager        to build and configure',
    );
    _out.writeln('');
  }

  void _deleteProjectConfig(String? projectDir) {
    if (projectDir == null) return;
    final f = File('$projectDir/.flutter_release_manager_config.json');
    if (!f.existsSync()) return;
    try {
      f.deleteSync();
      Logger.ok('Project configuration removed.');
    } catch (_) {
      Logger.skip('Could not delete project config — check permissions.');
    }
  }

  void _printHeader(bool isFullReset) {
    _out.writeln('');
    _out.writeln('╔══════════════════════════════════════════════╗');
    _out.writeln(
      isFullReset
          ? '  flutter_release_manager — full reset'
          : '  flutter_release_manager — reset',
    );
    _out.writeln('╚══════════════════════════════════════════════╝');
    _out.writeln('');
  }
}
