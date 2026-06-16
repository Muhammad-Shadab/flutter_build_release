import 'dart:io';
import 'package:args/args.dart';
import 'package:flutter_build_release/src/android_builder.dart';
import 'package:flutter_build_release/src/config.dart';
import 'package:flutter_build_release/src/ios_builder.dart';
import 'package:flutter_build_release/src/logger.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('platform',
        abbr: 'p',
        help: 'Target platform: android | ios | both',
        allowed: ['android', 'ios', 'both'])
    ..addOption('app-dir',
        abbr: 'd', help: 'Path to the Flutter app directory.')
    ..addOption('app-name',
        abbr: 'n', help: 'App name used in output file names.')
    ..addFlag('upload-drive',
        help: 'Upload the APK to Google Drive after build.',
        negatable: false)
    ..addOption('rclone-remote',
        help: 'rclone remote name.', defaultsTo: 'gdrive')
    ..addOption('drive-folder-id', help: 'Google Drive root folder ID.')
    ..addOption('flavour',
        abbr: 'f',
        help: 'dev | prod | uat — top-level Drive folder.',
        allowed: ['dev', 'prod', 'uat'])
    ..addOption('team-id',
        abbr: 't', help: 'Apple Developer Team ID (iOS only).')
    ..addOption('scheme',
        help: 'Xcode scheme name.', defaultsTo: 'Runner')
    ..addOption('export-method',
        help: 'development | release-testing | app-store',
        allowed: ['development', 'release-testing', 'app-store'],
        defaultsTo: 'development')
    ..addOption('diawi-token', help: 'Diawi API token for IPA upload.')
    ..addFlag('help', abbr: 'h', help: 'Print this help.', negatable: false);

  ArgResults results;
  try {
    results = parser.parse(args);
  } catch (e) {
    stderr.writeln('Error: $e\n');
    _printUsage(parser);
    exit(1);
  }

  if (results['help'] as bool) {
    _printUsage(parser);
    exit(0);
  }

  _printWelcome();

  // ── Platform ────────────────────────────────────────────────────────────────
  final platform = results['platform'] as String? ?? await _pickPlatform();

  final buildAndroid = platform == 'android' || platform == 'both';
  final buildIos = platform == 'ios' || platform == 'both';

  // ── App directory ───────────────────────────────────────────────────────────
  final appDir = results['app-dir'] as String? ??
      await _promptWithHints(
        label: 'Flutter app directory path',
        hints: [
          'This is the folder that contains your pubspec.yaml file.',
          'To find it: open a terminal inside your project and run: pwd',
          'Example: /Users/john/projects/my_project/apps/my_app',
        ],
      );

  if (!Directory(appDir).existsSync()) {
    Logger.error('Directory not found: $appDir');
    Logger.error('Make sure the path is correct and the folder exists.');
    exit(1);
  }

  // ── App name ────────────────────────────────────────────────────────────────
  final appName = results['app-name'] as String? ??
      await _promptWithHints(
        label: 'App name',
        hints: [
          'Just a label used in the output file name — not your bundle ID.',
          'Use your app\'s display name with no spaces.',
          'Example: MyApp → MyApp_June_2026_03-45-PM.apk',
        ],
      );

  // ── Android: Drive upload ───────────────────────────────────────────────────
  bool uploadDrive = results['upload-drive'] as bool;
  String? driveFolderId = results['drive-folder-id'] as String?;
  String? flavour = results['flavour'] as String?;

  if (buildAndroid && !uploadDrive) {
    _printSection('Google Drive Upload (Android)');
    uploadDrive = await _confirm('Upload APK to Google Drive?');
  }

  if (uploadDrive) {
    driveFolderId ??= await _promptWithHints(
      label: 'Google Drive folder ID',
      hints: [
        'Open the destination folder in Google Drive in your browser.',
        'Look at the URL — the folder ID is after /folders/',
        'Example URL: drive.google.com/drive/folders/1wP7TZvEoOOo2W_GPV...',
        '                                              ↑ copy everything after /folders/',
        'Tip: Create a dedicated folder like "App Builds" in Drive first.',
      ],
    );

    flavour ??= await _pickFlavour();
  }

  // ── iOS options ─────────────────────────────────────────────────────────────
  String? teamId = results['team-id'] as String?;
  final scheme = results['scheme'] as String;
  final exportMethod = results['export-method'] as String;
  String? diawiToken = results['diawi-token'] as String?;

  if (buildIos) {
    teamId ??= await _promptWithHints(
      label: 'Apple Developer Team ID',
      hints: [
        'Go to: developer.apple.com and sign in.',
        'Click your name in the top-right corner → Membership details.',
        'Copy the Team ID (looks like: UC2HYA24R2).',
        'You must be enrolled in the Apple Developer Program.',
      ],
    );

    if (diawiToken == null) {
      _printSection('Diawi Upload (iOS)');
      _printHints([
        'Diawi lets you share your IPA with testers via a simple link.',
        'Get a free account at: diawi.com',
        'Then go to: Account → API Access Tokens → create a token.',
      ]);
      if (await _confirm('Upload IPA to Diawi?')) {
        diawiToken = await _promptWithHints(
          label: 'Diawi API token',
          hints: [
            'Find it at: diawi.com → Account → API Access Tokens',
          ],
        );
      }
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────
  final config = Config(
    platform: platform,
    appDir: appDir,
    appName: appName,
    flavour: flavour,
    uploadDrive: uploadDrive,
    rcloneRemote: results['rclone-remote'] as String,
    driveFolderId: driveFolderId,
    teamId: teamId,
    scheme: scheme,
    exportMethod: exportMethod,
    diawiToken: diawiToken,
  );

  if (config.buildAndroid) await AndroidBuilder(config).build();
  if (config.buildIos) await IosBuilder(config).build();

  Logger.header('Build complete');
}

// ── Welcome banner ─────────────────────────────────────────────────────────

void _printWelcome() {
  stdout.writeln('');
  stdout.writeln('╔══════════════════════════════════════════════╗');
  stdout.writeln('  flutter_build_release');
  stdout.writeln('  Build · Archive · Distribute');
  stdout.writeln('╚══════════════════════════════════════════════╝');
  stdout.writeln('');
  stdout.writeln('  This tool will ask you a few questions,');
  stdout.writeln('  then build and upload your app automatically.');
  stdout.writeln('');
}

// ── Section divider ────────────────────────────────────────────────────────

void _printSection(String title) {
  stdout.writeln('');
  stdout.writeln('  ─── $title ${'─' * (42 - title.length)}');
}

// ── Hint block ─────────────────────────────────────────────────────────────

void _printHints(List<String> hints) {
  stdout.writeln('');
  for (final h in hints) {
    stdout.writeln('  \x1B[0;36mℹ\x1B[0m  $h');
  }
  stdout.writeln('');
}

// ── Interactive helpers ────────────────────────────────────────────────────

Future<String> _promptWithHints({
  required String label,
  required List<String> hints,
}) async {
  _printSection(label);
  _printHints(hints);
  stdout.write('  $label: ');
  final value = stdin.readLineSync()?.trim() ?? '';
  if (value.isEmpty) {
    Logger.error('$label cannot be empty.');
    exit(1);
  }
  return value;
}

Future<String> _pickPlatform() async {
  _printSection('Platform');
  stdout.writeln('');
  stdout.writeln('  What do you want to build?');
  stdout.writeln('  1) Android only  (generates APK)');
  stdout.writeln('  2) iOS only      (generates IPA)');
  stdout.writeln('  3) Both          (APK + IPA)');
  stdout.writeln('');
  stdout.write('  Enter choice [1/2/3]: ');
  final choice = stdin.readLineSync()?.trim() ?? '';
  switch (choice) {
    case '1': return 'android';
    case '2': return 'ios';
    case '3': return 'both';
    default:
      Logger.error('Invalid choice "$choice". Enter 1, 2, or 3.');
      exit(1);
  }
}

Future<String> _pickFlavour() async {
  _printSection('Flavour');
  _printHints([
    'Flavour sets the top-level folder name in Google Drive.',
    'dev  → for development/testing builds',
    'prod → for production/release builds',
    'uat  → for user acceptance testing builds',
  ]);
  stdout.writeln('  0) dev');
  stdout.writeln('  1) prod');
  stdout.writeln('  2) uat');
  stdout.writeln('');
  stdout.write('  Enter choice [0/1/2]: ');
  final choice = stdin.readLineSync()?.trim() ?? '';
  switch (choice) {
    case '0': return 'dev';
    case '1': return 'prod';
    case '2': return 'uat';
    default:
      Logger.error('Invalid choice "$choice". Enter 0, 1, or 2.');
      exit(1);
  }
}

Future<bool> _confirm(String question) async {
  stdout.write('  $question [y/N]: ');
  final answer = stdin.readLineSync()?.trim().toLowerCase() ?? '';
  return answer == 'y' || answer == 'yes';
}

void _printUsage(ArgParser parser) {
  stdout.writeln('''
flutter_build_release — Build and distribute Flutter apps

Run without flags for guided interactive mode:
  flutter_build_release

Or pass flags directly (useful for CI/scripts):
  flutter_build_release --platform <android|ios|both> --app-dir <path> --app-name <name> [options]

${parser.usage}
''');
}
