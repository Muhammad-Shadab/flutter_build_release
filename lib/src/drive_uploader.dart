import 'dart:io';
import 'config.dart';
import 'logger.dart';

class DriveUploader {
  final Config config;

  DriveUploader(this.config);

  Future<void> upload(File apkFile) async {
    Logger.header('Uploading APK to Google Drive');

    _validateRclone();

    if (!apkFile.existsSync()) {
      Logger.error('APK not found: ${apkFile.path}');
      exit(1);
    }

    final now = DateTime.now();
    final year = now.year.toString();
    final month = _monthName(now.month);
    final timestamp = _timestamp(now);
    final flavour = config.flavour!;
    final remote = config.rcloneRemote;
    final folderId = config.driveFolderId!;
    final apkName = '${config.appName}_${month}_${year}_$timestamp.apk';
    final destPath = '$flavour/$year/$month/$apkName';

    Logger.info('Destination : $remote:$destPath');
    Logger.info('Root folder : $folderId');

    await _ensureFolder(flavour, folderId, remote);
    await _ensureFolder('$flavour/$year', folderId, remote);
    await _ensureFolder('$flavour/$year/$month', folderId, remote);

    Logger.step('Uploading: $apkName');
    final result = await Process.run('rclone', [
      'copyto', apkFile.path, '$remote:$destPath',
      '--drive-root-folder-id', folderId,
      '--progress',
    ]);
    stdout.write(result.stdout);
    if (result.exitCode != 0) {
      stderr.write(result.stderr);
      Logger.error('Upload failed. Check your rclone config and internet connection.');
      exit(1);
    }

    final url = await _generateLink(destPath, folderId, remote);

    stdout.writeln('\n╔══════════════════════════════════════════════╗');
    stdout.writeln('  Upload completed successfully');
    stdout.writeln('╚══════════════════════════════════════════════╝\n');
    stdout.writeln('  APK Name:\n  $apkName\n');
    stdout.writeln('  Google Drive Path:\n  $remote:$destPath\n');
    if (url != null) {
      stdout.writeln('  Google Drive URL:\n  $url\n');
    }
  }

  void _validateRclone() {
    final which = Process.runSync('which', ['rclone']);
    if (which.exitCode != 0) {
      Logger.error('rclone not found. Install with: brew install rclone');
      exit(1);
    }
    final remotes = Process.runSync('rclone', ['listremotes']).stdout as String;
    if (!remotes.contains('${config.rcloneRemote}:')) {
      Logger.error('rclone remote "${config.rcloneRemote}" not configured. Run: rclone config');
      exit(1);
    }
  }

  Future<void> _ensureFolder(String path, String folderId, String remote) async {
    final check = await Process.run('rclone', [
      'lsf', '$remote:$path',
      '--drive-root-folder-id', folderId,
    ]);
    if (check.exitCode == 0) {
      Logger.info('Folder exists: $path');
    } else {
      Logger.step('Creating folder: $path');
      await Process.run('rclone', [
        'mkdir', '$remote:$path',
        '--drive-root-folder-id', folderId,
      ]);
      Logger.ok('Created: $path');
    }
  }

  Future<String?> _generateLink(String path, String folderId, String remote) async {
    Logger.step('Generating shareable Drive URL...');
    final result = await Process.run('rclone', [
      'link', '$remote:$path',
      '--drive-root-folder-id', folderId,
    ]);
    if (result.exitCode == 0) {
      final url = (result.stdout as String).trim();
      Logger.ok('Drive URL generated');
      return url;
    }
    Logger.skip('Could not generate Drive URL (manual sharing may be needed).');
    return null;
  }

  String _monthName(int m) => const [
    '', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ][m];

  String _timestamp(DateTime dt) {
    final h = dt.hour == 0 ? 12 : dt.hour > 12 ? dt.hour - 12 : dt.hour;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${_pad(h)}-${_pad(dt.minute)}-$ampm';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
