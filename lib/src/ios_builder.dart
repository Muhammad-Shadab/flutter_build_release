import 'dart:io';
import 'config.dart';
import 'diawi_uploader.dart';
import 'logger.dart';
import 'process_utils.dart';

class IosBuilder {
  final Config config;

  IosBuilder(this.config);

  Future<void> build() async {
    final now = DateTime.now();
    final dateLabel =
        '${now.year}-${_pad(now.month)}-${_pad(now.day)}_${_pad(now.hour)}-${_pad(now.minute)}';

    final iosDir = '${config.appDir}/ios';
    final workspace = '$iosDir/Runner.xcworkspace';
    final buildOutput = '${config.appDir}/build/release_output';
    final archivePath = '$buildOutput/${config.appName}_$dateLabel.xcarchive';
    final exportPath = '$buildOutput/${config.appName}_${dateLabel}_ipa';
    final exportPlist = '$buildOutput/ExportOptions.plist';

    // Clean old artifacts
    final outputDir = Directory(buildOutput);
    if (outputDir.existsSync()) {
      Logger.header('Cleaning iOS build output');
      for (final e in outputDir.listSync()) {
        if (e.path.endsWith('.xcarchive') ||
            e.path.endsWith('_ipa') ||
            e.path.endsWith('ExportOptions.plist')) {
          e.deleteSync(recursive: true);
        }
      }
      Logger.ok('Old iOS artifacts deleted');
    }
    outputDir.createSync(recursive: true);

    Logger.header('iOS IPA  ($dateLabel)');

    // 1. flutter build ios
    Logger.step('Running: flutter build ios --release --no-codesign');
    var code = await runLive(
      'flutter',
      ['build', 'ios', '--release', '--no-codesign'],
      workingDirectory: config.appDir,
    );
    if (code != 0) {
      Logger.error('flutter build ios failed (exit $code)');
      exit(code);
    }

    // 2. ExportOptions.plist
    Logger.step('Writing ExportOptions.plist (method: ${config.exportMethod})');
    File(exportPlist).writeAsStringSync(_exportPlist());

    // 3. Archive
    Logger.step('Archiving → $archivePath');
    code = await runLive('xcodebuild', [
      'archive',
      '-workspace', workspace,
      '-scheme', config.scheme,
      '-configuration', 'Release',
      '-archivePath', archivePath,
      '-destination', 'generic/platform=iOS',
      'CODE_SIGN_STYLE=Automatic',
      'DEVELOPMENT_TEAM=${config.teamId}',
    ]);
    if (code != 0 || !Directory(archivePath).existsSync()) {
      Logger.error('Archive failed');
      exit(1);
    }
    Logger.ok('Archive created');

    // 4. Export IPA
    Logger.step('Exporting IPA → $exportPath');
    code = await runLive('xcodebuild', [
      '-exportArchive',
      '-archivePath', archivePath,
      '-exportPath', exportPath,
      '-exportOptionsPlist', exportPlist,
    ]);

    final ipaFile = _findIpa(exportPath);
    if (ipaFile == null) {
      Logger.error('Export failed — no IPA found in $exportPath');
      exit(1);
    }
    Logger.ok('IPA ready (${_fileSize(ipaFile)}) → ${ipaFile.path}');

    // 5. Upload to Diawi
    if (config.diawiToken != null) {
      await DiawiUploader(config).upload(ipaFile);
    }
  }

  File? _findIpa(String dir) {
    try {
      return Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .firstWhere((f) => f.path.endsWith('.ipa'));
    } catch (_) {
      return null;
    }
  }

  String _exportPlist() => '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>export</string>
  <key>method</key>
  <string>${config.exportMethod}</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>teamID</key>
  <string>${config.teamId}</string>
  <key>thinning</key>
  <string>&lt;thin-for-all-variants&gt;</string>
</dict>
</plist>''';

  String _fileSize(File f) {
    final bytes = f.lengthSync();
    return bytes < 1024 * 1024
        ? '${(bytes / 1024).toStringAsFixed(1)} KB'
        : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
