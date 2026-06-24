import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'config.dart';
import 'logger.dart';

/// Uploads an APK to Google Drive using the hierarchy:
///
///   <root>/<AppName>/<year>/<month>/<ENV>/<AppName>_<ENV>_<date>.apk
///
/// Folder resolution is case-insensitive: existing "ruloans" folder is
/// reused when "Ruloans" is requested, preventing duplicates.
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
    final env = config.environment!;
    final year = now.year.toString();
    final month = _monthName(now.month);
    final fileName = _buildFileName(now, env);
    final root = config.driveFolderName!;
    final remoteBase = '${config.rcloneRemote}:$root';

    // ── Resolve each folder level (case-insensitive matching) ────────────────
    Logger.step('Resolving folder structure...');
    final appFolder = _resolveFolder(remoteBase, config.appName);
    final yearFolder = _resolveFolder('$remoteBase/$appFolder', year);
    final monthFolder =
        _resolveFolder('$remoteBase/$appFolder/$yearFolder', month);
    final envFolder =
        _resolveFolder('$remoteBase/$appFolder/$yearFolder/$monthFolder', env);

    final remotePath =
        '$remoteBase/$appFolder/$yearFolder/$monthFolder/$envFolder/$fileName';

    // ── Destination preview ──────────────────────────────────────────────────
    _printDestinationPreview(
      root: root,
      appFolder: appFolder,
      yearFolder: yearFolder,
      monthFolder: monthFolder,
      envFolder: envFolder,
      fileName: fileName,
    );

    Logger.info('Local  : ${apkFile.path} (${_fileSize(apkFile)})');

    // ── Upload with retry ────────────────────────────────────────────────────
    final fileSize = apkFile.lengthSync();
    final success = await _uploadWithRetry(apkFile.path, remotePath, fileSize);
    if (!success) {
      Logger.error('Upload failed after all retries.');
      exit(1);
    }

    final url = _getLink(remotePath);

    // ── Result banner ────────────────────────────────────────────────────────
    stdout.writeln('');
    stdout.writeln('╔══════════════════════════════════════════════╗');
    stdout.writeln('  Upload complete');
    stdout.writeln('╚══════════════════════════════════════════════╝');
    stdout.writeln('');
    stdout.writeln('  File    $fileName');
    stdout.writeln(
      '  Path    $root/$appFolder/$yearFolder/$monthFolder/$envFolder/',
    );
    stdout.writeln('');
    if (url != null) {
      stdout.writeln('  Google Drive URL:');
      stdout.writeln('  $url');
      await _copyToClipboard(url);
    } else {
      stdout.writeln('  (Open Google Drive to find the file)');
    }
    stdout.writeln('');

    return url;
  }

  // ── Filename ──────────────────────────────────────────────────────────────

  String _buildFileName(DateTime now, String env) => '${config.appName}_${env}_'
      '${now.year}_${_pad(now.month)}_${_pad(now.day)}_'
      '${_pad(now.hour)}${_pad(now.minute)}.apk';

  // ── Smart folder resolution ───────────────────────────────────────────────

  /// Lists subdirectories at [remotePath] and returns the existing folder
  /// name that case-insensitively matches [requestedName], or returns
  /// [requestedName] unchanged (rclone will create it during copyto).
  String _resolveFolder(String remotePath, String requestedName) {
    final result = Process.runSync(
      'rclone',
      ['lsf', remotePath, '--dirs-only'],
      runInShell: true,
    );

    if (result.exitCode != 0) {
      // Path doesn't exist yet — folder will be created by rclone.
      Logger.step('Creating  : $requestedName');
      return requestedName;
    }

    final normalized = requestedName.trim().toLowerCase();
    final dirs = (result.stdout as String)
        .split('\n')
        .map((s) => s.trim().replaceAll('/', ''))
        .where((s) => s.isNotEmpty);

    for (final dir in dirs) {
      if (dir.trim().toLowerCase() == normalized) {
        Logger.ok('Found existing folder: $dir');
        return dir;
      }
    }

    Logger.step('Creating  : $requestedName');
    return requestedName;
  }

  // ── Destination preview ───────────────────────────────────────────────────

  void _printDestinationPreview({
    required String root,
    required String appFolder,
    required String yearFolder,
    required String monthFolder,
    required String envFolder,
    required String fileName,
  }) {
    stdout.writeln('');
    stdout.writeln('  Google Drive Destination');
    stdout.writeln('');
    stdout.writeln('  $root/');
    stdout.writeln('  └── $appFolder/');
    stdout.writeln('      └── $yearFolder/');
    stdout.writeln('          └── $monthFolder/');
    stdout.writeln('              └── $envFolder/');
    stdout.writeln('                  └── $fileName');
    stdout.writeln('');
  }

  // ── Upload with retry ─────────────────────────────────────────────────────

  Future<bool> _uploadWithRetry(
    String localPath,
    String remotePath,
    int fileSize,
  ) async {
    const maxAttempts = 3;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      Logger.step('Uploading (attempt $attempt/$maxAttempts)...');
      stdout.writeln('');

      final ok = await _uploadOnce(localPath, remotePath, fileSize);
      if (ok) return true;

      if (attempt < maxAttempts) {
        final delay = attempt * 3;
        Logger.skip('Upload failed. Retrying in ${delay}s...');
        await Future<void>.delayed(Duration(seconds: delay));
      }
    }

    return false;
  }

  /// Runs `rclone copyto` and renders a live progress bar by parsing
  /// rclone's JSON log output.
  ///
  /// `--use-json-log` forces rclone to write one JSON object per line to
  /// stderr regardless of whether stderr is a TTY — unlike `--stats-one-line`
  /// which suppresses output when not connected to a terminal.
  Future<bool> _uploadOnce(
    String localPath,
    String remotePath,
    int fileSize,
  ) async {
    final process = await Process.start(
      'rclone',
      [
        'copyto',
        localPath,
        remotePath,
        '--use-json-log',
        '--log-level',
        'INFO',
        '--stats',
        '1s',
      ],
      runInShell: false,
    );
    process.stdin.close().ignore();

    // rclone copyto has no meaningful stdout — pass through in case.
    final stdoutSub = process.stdout.listen(stdout.add);

    // Parse JSON log lines from stderr. Each line is one JSON object:
    //   {"level":"notice","msg":"Transferred: 42.1 MiB / 65.4 MiB, 64%, ..."}
    // Collect error-level messages to display on failure.
    final errorLines = <String>[];
    final stderrSub = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (line.trim().isEmpty) return;
      try {
        final data = jsonDecode(line) as Map<String, dynamic>;
        final msg = (data['msg'] as String? ?? '').trim();
        final level = data['level'] as String? ?? '';
        if (msg.contains('Transferred:') && msg.contains('%')) {
          _renderProgress(msg, fileSize);
        } else if (level == 'error' || level == 'fatal') {
          errorLines.add(msg);
        }
      } catch (_) {
        // Non-JSON fallback — try parsing as a plain stats line.
        if (line.contains('Transferred:') && line.contains('%')) {
          _renderProgress(line, fileSize);
        }
      }
    });

    try {
      final code = await process.exitCode.timeout(const Duration(minutes: 30));
      await stdoutSub.cancel();
      await stderrSub.cancel();
      stdout.write('\r\x1B[K'); // erase progress line
      if (code != 0) {
        for (final line in errorLines) {
          if (line.isNotEmpty) stderr.writeln('  $line');
        }
      } else {
        Logger.ok('Upload complete.');
      }
      return code == 0;
    } on TimeoutException {
      process.kill(ProcessSignal.sigterm);
      await Future<void>.delayed(const Duration(seconds: 3));
      process.kill(ProcessSignal.sigkill);
      await stdoutSub.cancel();
      await stderrSub.cancel();
      stdout.write('\r\x1B[K');
      Logger.error('Upload timed out after 30 minutes.');
      return false;
    }
  }

  // ── Progress bar ──────────────────────────────────────────────────────────

  /// Parses rclone's --stats-one-line output and renders a custom progress bar.
  ///
  /// rclone format (to stderr, ending with \r):
  ///   Transferred: 42.1 MiB / 65.4 MiB, 64%, 4.2 MiB/s, ETA 6s
  void _renderProgress(String chunk, int fileSize) {
    final match = RegExp(
      r'Transferred:\s+[\d.]+\s*\w+\s*/\s*[\d.]+\s*\w+,\s*(\d+)%'
      r',\s*([\d.]+)\s*([\w/]+),\s*ETA\s*(\S+)',
    ).firstMatch(chunk);

    if (match == null) return;

    final pct = int.tryParse(match.group(1)!) ?? 0;
    final speedVal = double.tryParse(match.group(2)!) ?? 0;
    final speedUnit = _si(match.group(3)!);
    final eta = match.group(4)!;

    // Use the known local file size for done/total so the display is accurate
    // regardless of rclone's internal retry byte accumulation.
    final totalMb = fileSize / (1024 * 1024);
    final doneMb = totalMb * pct / 100;

    const barWidth = 20;
    final filled = (pct / 100 * barWidth).round().clamp(0, barWidth);
    final bar = '${'█' * filled}${'░' * (barWidth - filled)}';

    stdout.write(
      '\r\x1B[K'
      '  [$bar] $pct%  '
      '${doneMb.toStringAsFixed(1)} MB'
      ' / ${totalMb.toStringAsFixed(1)} MB  '
      '${speedVal.toStringAsFixed(1)} $speedUnit  '
      'ETA: $eta',
    );
  }

  /// Converts rclone's binary-prefix units (MiB, GiB) to SI labels (MB, GB).
  String _si(String unit) => unit.replaceAll('iB', 'B');

  // ── Shareable link ────────────────────────────────────────────────────────

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
        'Could not generate a shareable link '
        '(org sharing policy may restrict this).\n'
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

  // ── Clipboard ─────────────────────────────────────────────────────────────

  Future<void> _copyToClipboard(String text) async {
    try {
      final encoded = utf8.encode(text);
      if (Platform.isMacOS) {
        final p = await Process.start('pbcopy', []);
        p.stdin.add(encoded);
        await p.stdin.close();
        await p.exitCode;
      } else if (Platform.isWindows) {
        final p = await Process.start('clip', [], runInShell: true);
        p.stdin.add(encoded);
        await p.stdin.close();
        await p.exitCode;
      } else if (Platform.isLinux) {
        const candidates = [
          ['xclip', '-selection', 'clipboard'],
          ['xsel', '--clipboard', '--input'],
          ['wl-copy'],
        ];
        for (final cmd in candidates) {
          if (Process.runSync('which', [cmd[0]], runInShell: true).exitCode ==
              0) {
            final p = await Process.start(cmd[0], cmd.sublist(1));
            p.stdin.add(encoded);
            await p.stdin.close();
            await p.exitCode;
            break;
          }
        }
      }
      Logger.ok('Link copied to clipboard.');
    } catch (_) {
      // Clipboard copy is optional — never block the release flow.
    }
  }
}
