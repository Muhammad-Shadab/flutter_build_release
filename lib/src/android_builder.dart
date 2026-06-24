import 'dart:io';

import 'config.dart';
import 'gatekeeper.dart';
import 'logger.dart';
import 'process_utils.dart';
import 'rclone_uploader.dart';

class AndroidBuilder {
  final Config config;
  final _gk = const GatekeeperBuildGuard('flutter');

  AndroidBuilder(this.config);

  Future<String?> build() async {
    final now = DateTime.now();
    final dateLabel = '${now.year}-${_pad(now.month)}-${_pad(now.day)}_'
        '${_pad(now.hour)}-${_pad(now.minute)}';

    final apkDir = Directory('${config.appDir}/build/app/outputs/flutter-apk');

    if (config.skipBuild) {
      return _skipBuild(apkDir);
    }

    // Clean previous output.
    if (apkDir.existsSync()) {
      Logger.header('Cleaning Android build output');
      Logger.step('Removing old APKs from: ${apkDir.path}');
      for (final f in apkDir.listSync().whereType<File>()) {
        if (f.path.endsWith('.apk')) f.deleteSync();
      }
      Logger.ok('Old APKs deleted');
    }

    Logger.header('Android APK  ($dateLabel)');
    Logger.step('Running: flutter build apk --split-per-abi');

    final (code, output) = await runLiveCapturing(
      'flutter',
      ['build', 'apk', '--split-per-abi'],
      workingDirectory: config.appDir,
    );

    if (code != 0) {
      _gk.handleFailure(output, code);
      Logger.error('Android build failed (exit $code)');
      exit(code);
    }

    stdout.writeln('\n  Output APKs:');
    for (final abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64']) {
      final f = File('${apkDir.path}/app-$abi-release.apk');
      if (f.existsSync()) {
        Logger.ok('app-$abi-release.apk  (${_fileSize(f)})');
      } else {
        Logger.skip('app-$abi-release.apk not found');
      }
    }

    if (config.uploadDrive) {
      final apk = _findApk(apkDir.path);
      return RcloneUploader(config).upload(apk);
    }
    return null;
  }

  // ── Skip-build (upload only) ──────────────────────────────────────────────

  Future<String?> _skipBuild(Directory apkDir) async {
    Logger.header('Android — skip build, uploading existing APK');
    final apk = apkDir.existsSync() ? _findApkOrNull(apkDir.path) : null;
    if (apk == null) {
      Logger.error(
        'No existing APK found in ${apkDir.path}.\n'
        '  Run without --skip-build first to produce an artifact.',
      );
      exit(1);
    }
    Logger.ok('Found existing APK: ${apk.path} (${_fileSize(apk)})');
    if (config.uploadDrive) {
      return RcloneUploader(config).upload(apk);
    }
    return null;
  }

  // ── APK selection ─────────────────────────────────────────────────────────

  File _findApk(String dir) {
    final preferred = File('$dir/app-${config.apkAbi}-release.apk');
    if (preferred.existsSync()) return preferred;
    // Fallback: try arm64-v8a then armeabi-v7a if the preferred ABI is missing.
    for (final abi in ['arm64-v8a', 'armeabi-v7a']) {
      final f = File('$dir/app-$abi-release.apk');
      if (f.existsSync()) {
        Logger.skip(
            '${config.apkAbi} APK not found — uploading $abi instead.');
        return f;
      }
    }
    return preferred; // let the uploader surface the missing-file error
  }

  File? _findApkOrNull(String dir) {
    final preferred = File('$dir/app-${config.apkAbi}-release.apk');
    if (preferred.existsSync()) return preferred;
    for (final abi in ['arm64-v8a', 'armeabi-v7a']) {
      final f = File('$dir/app-$abi-release.apk');
      if (f.existsSync()) {
        if (abi != config.apkAbi) {
          Logger.skip(
              '${config.apkAbi} APK not found — uploading $abi instead.');
        }
        return f;
      }
    }
    return null;
  }

  // ── Utilities ─────────────────────────────────────────────────────────────

  String _fileSize(File f) {
    final bytes = f.lengthSync();
    return bytes < 1024 * 1024
        ? '${(bytes / 1024).toStringAsFixed(1)} KB'
        : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
