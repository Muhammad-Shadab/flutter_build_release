import 'dart:io';

import 'config.dart';
import 'logger.dart';
import 'process_utils.dart';

/// Uploads an APK to Google Drive using rclone copyto with retry logic.
class RcloneUploader {
  final Config config;

  RcloneUploader(this.config);

  Future<String?> upload(File apkFile) async {
    Logger.header('Uploading APK to Google Drive');

    if (!apkFile.existsSync()) {
      Logger.error('APK not found: ${apkFile.path}');
      exit(1);
    }

    final now = DateTime.now();
    final year = now.year.toString();
    final month = _monthName(now.month);
    final apkName = '${config.appName}'
        '_${now.year}'
        '_${_pad(now.month)}'
        '_${_pad(now.day)}'
        '_${_pad(now.hour)}${_pad(now.minute)}'
        '.apk';

    final folder = config.driveFolderName!;
    final remote = config.rcloneRemote;
    final remotePath = '$remote:$folder/$year/$month/$apkName';

    Logger.info('Destination : $folder/$year/$month/$apkName');
    Logger.info('Local file  : ${apkFile.path} (${_fileSize(apkFile)})');

    final success = await _uploadWithRetry(apkFile.path, remotePath);
    if (!success) {
      Logger.error('Upload failed after all retries.');
      exit(1);
    }

    final url = _getLink(remotePath);

    stdout.writeln('');
    stdout.writeln('╔══════════════════════════════════════════════╗');
    stdout.writeln('  Upload completed successfully');
    stdout.writeln('╚══════════════════════════════════════════════╝');
    stdout.writeln('');
    stdout.writeln('  APK Name:');
    stdout.writeln('  $apkName');
    stdout.writeln('');
    if (url != null) {
      stdout.writeln('  Google Drive URL:');
      stdout.writeln('  $url');
    } else {
      stdout.writeln('  Location: $folder/$year/$month/$apkName');
      stdout.writeln('  (Open Google Drive to find the file)');
    }
    stdout.writeln('');

    return url;
  }

  // ── Upload with retry ─────────────────────────────────────────────────────

  Future<bool> _uploadWithRetry(
    String localPath,
    String remotePath,
  ) async {
    const maxAttempts = 3;
    Exception? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        Logger.step('Uploading (attempt $attempt/$maxAttempts)...');
        final code = await runLive(
          'rclone',
          ['copyto', localPath, remotePath, '--stats', '5s'],
          timeout: const Duration(minutes: 30),
        );
        if (code == 0) {
          Logger.ok('Upload complete.');
          return true;
        }
        throw Exception('rclone exited with code $code');
      } on Exception catch (e) {
        lastError = e;
        if (attempt < maxAttempts) {
          final delaySecs = attempt * 3;
          Logger.skip(
            'Upload failed (attempt $attempt/$maxAttempts): $e\n'
            '  Retrying in ${delaySecs}s...',
          );
          await Future<void>.delayed(Duration(seconds: delaySecs));
        }
      }
    }

    Logger.error('All $maxAttempts upload attempts failed: $lastError');
    return false;
  }

  // ── Shareable link ────────────────────────────────────────────────────────

  /// Gets a public sharing link via `rclone link`.
  /// Non-fatal: returns null if sharing is restricted by Workspace policy.
  String? _getLink(String remotePath) {
    try {
      final result = Process.runSync(
        'rclone',
        ['link', remotePath],
        runInShell: true,
      );
      if (result.exitCode == 0) {
        final link = (result.stdout as String).trim();
        return link.isNotEmpty ? link : null;
      }
      Logger.skip(
        'Could not generate a shareable link (org sharing policy may restrict this).\n'
        '  The file is in your Drive — share it manually if needed.',
      );
    } catch (_) {}
    return null;
  }

  // ── Utilities ─────────────────────────────────────────────────────────────

  String _fileSize(File f) {
    final bytes = f.lengthSync();
    return bytes < 1024 * 1024
        ? '${(bytes / 1024).toStringAsFixed(1)} KB'
        : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _monthName(int m) => const [
        '',
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ][m];

  String _pad(int n) => n.toString().padLeft(2, '0');
}
