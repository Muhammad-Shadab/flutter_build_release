import 'dart:io';

import 'package:args/args.dart';

import 'app_config.dart';
import 'config.dart';
import 'config_store.dart';
import 'logger.dart';
import 'project_detector.dart';
import 'rclone_manager.dart';

class Wizard {
  Map<String, dynamic> _saved = {};
  ConfigStore? _store;

  Future<Config> run(List<String> cliArgs) async {
    final parser = _buildParser();

    ArgResults args;
    try {
      args = parser.parse(cliArgs);
    } catch (e) {
      stderr.writeln('Error: $e\n');
      _printUsage(parser);
      exit(1);
    }

    if (args['help'] as bool) {
      _printUsage(parser);
      exit(0);
    }

    _printWelcome();

    // Migrate config and Diawi token from previous package names on first run.
    AppConfig.migrateFromOldPackageName();
    AppConfig.migrateFromCredentialsJson();

    // ── 1. App directory ──────────────────────────────────────────────────────
    final appDir = await _resolveAppDir(args['app-dir'] as String?);

    // ── 2. Project config ─────────────────────────────────────────────────────
    _store = ConfigStore(appDir);
    _saved = _store!.load();

    // Migrate diawiToken that was saved in the project config (v1.x / v2.x).
    final legacyDiawi = _saved['diawiToken'] as String?;
    if (legacyDiawi != null && !AppConfig.hasDiawiToken) {
      AppConfig.saveDiawiToken(legacyDiawi);
    }

    // ── 3. Flags ──────────────────────────────────────────────────────────────
    final skipBuild =
        (args['skip-build'] as bool) || (args['upload-only'] as bool);

    // ── 4. Platform ───────────────────────────────────────────────────────────
    final platform = args['platform'] as String? ??
        (_saved['platform'] as String?) ??
        await _pickPlatform();
    final buildAndroid = platform == 'android' || platform == 'both';
    final buildIos = platform == 'ios' || platform == 'both';

    // ── 5. App name ───────────────────────────────────────────────────────────
    final appName =
        args['app-name'] as String? ?? await _resolveAppName(appDir);

    // ── 6. Android / Google Drive ─────────────────────────────────────────────
    bool uploadDrive = args['upload-drive'] as bool;
    String? driveFolderName;

    if (buildAndroid && !uploadDrive && !args.wasParsed('upload-drive')) {
      _printSection('Google Drive Upload');
      _printHints([
        'APKs are uploaded via rclone — no OAuth setup needed.',
        'Run flutter_release_manager init once to configure Drive.',
        'Skip to keep the APK on your machine.',
      ]);
      uploadDrive =
          await _confirm('Upload APK to Google Drive after building?');
    }

    if (uploadDrive) {
      // Migrate old rclone remote if user skipped init after renaming package.
      RcloneManager.migrateOldRemoteIfNeeded();
      // Ensure rclone and the remote are ready.
      _ensureRcloneReady();

      // Folder name comes from AppConfig (set during init).
      driveFolderName = AppConfig.folderName;
      if (driveFolderName == null) {
        _printError(
          missing: 'Drive folder configuration',
          reason: 'No Drive folder has been selected yet.',
          fix: 'Run: flutter_release_manager init',
        );
        exit(1);
      }
      Logger.ok('Drive folder: $driveFolderName');
    }

    // ── 7. Advanced options ───────────────────────────────────────────────────
    final scheme = args.wasParsed('scheme')
        ? args['scheme'] as String
        : (_saved['scheme'] as String? ?? 'Runner');
    final exportMethod = args.wasParsed('export-method')
        ? args['export-method'] as String
        : (_saved['exportMethod'] as String? ?? 'development');

    // ── 8. iOS / Diawi ────────────────────────────────────────────────────────
    String? teamId = args['team-id'] as String?;
    String? diawiToken = args['diawi-token'] as String?;

    if (buildIos) {
      teamId ??= (_saved['teamId'] as String?) ?? await _askTeamId();

      // Resolve Diawi token: CLI > AppConfig > prompt.
      if (diawiToken == null) {
        diawiToken = AppConfig.diawiToken;

        if (diawiToken == null) {
          _printSection('Diawi Upload (iOS)');
          _printHints([
            'Diawi gives testers a simple install link — no App Store needed.',
            'Sign up at diawi.com → Account → API Access Tokens.',
            'Skip to keep the IPA local.',
          ]);
          if (await _confirm('Upload IPA to Diawi?')) {
            diawiToken = await _askDiawiToken();
            AppConfig.saveDiawiToken(diawiToken);
            Logger.ok('Diawi token saved to ${AppConfig.path}');
          }
        }
      }
    }

    // ── 9. Pre-flight validation ───────────────────────────────────────────────
    await _validatePrerequisites(
      buildAndroid: buildAndroid,
      buildIos: buildIos,
      uploadDrive: uploadDrive,
    );

    // ── 10. Persist project-level config ──────────────────────────────────────
    _store!.save({
      'platform': platform,
      'appName': appName,
      if (teamId != null) 'teamId': teamId,
      'scheme': scheme,
      'exportMethod': exportMethod,
    });

    // ── 11. Summary + confirmation ────────────────────────────────────────────
    _printSummary(
      platform: platform,
      appDir: appDir,
      appName: appName,
      uploadDrive: uploadDrive,
      driveFolderName: driveFolderName,
      teamId: teamId,
      scheme: scheme,
      exportMethod: exportMethod,
      diawiToken: diawiToken,
      skipBuild: skipBuild,
    );

    stdout.write(
      '  Press Enter to start the build, or Ctrl+C to cancel... ',
    );
    stdin.readLineSync();
    stdout.writeln('');

    return Config(
      platform: platform,
      appDir: appDir,
      appName: appName,
      uploadDrive: uploadDrive,
      rcloneRemote: AppConfig.remoteName,
      driveFolderName: driveFolderName,
      teamId: teamId,
      scheme: scheme,
      exportMethod: exportMethod,
      diawiToken: diawiToken,
      skipBuild: skipBuild,
    );
  }

  // ── rclone readiness ──────────────────────────────────────────────────────

  void _ensureRcloneReady() {
    if (!RcloneManager.isInstalled()) {
      _printError(
        missing: 'rclone',
        reason: 'rclone is required for Google Drive uploads.',
        fix: 'Run: flutter_release_manager init',
      );
      exit(1);
    }

    if (!RcloneManager.remoteExists()) {
      _printError(
        missing: 'rclone remote "${RcloneManager.remoteName}"',
        reason: 'Google Drive has not been configured yet.',
        fix: 'Run: flutter_release_manager init',
      );
      exit(1);
    }
  }

  // ── Pre-flight validation ─────────────────────────────────────────────────

  Future<void> _validatePrerequisites({
    required bool buildAndroid,
    required bool buildIos,
    required bool uploadDrive,
  }) async {
    Logger.header('Pre-flight checks');

    final whichCmd = Platform.isWindows ? 'where' : 'which';

    // flutter
    if (Process.runSync(whichCmd, ['flutter'], runInShell: true).exitCode !=
        0) {
      _printError(
        missing: 'flutter command',
        reason: 'flutter is required to build the app.',
        fix: 'Install Flutter: flutter.dev/docs/get-started/install',
      );
      exit(1);
    }
    Logger.ok('flutter found');

    // xcodebuild (iOS only)
    if (buildIos &&
        Process.runSync(
              whichCmd,
              ['xcodebuild'],
              runInShell: true,
            ).exitCode !=
            0) {
      _printError(
        missing: 'xcodebuild command',
        reason: 'xcodebuild is required to archive and export iOS apps.',
        fix: 'Install Xcode command-line tools: xcode-select --install',
      );
      exit(1);
    }
    if (buildIos) Logger.ok('xcodebuild found');

    // rclone + remote (Drive only)
    if (uploadDrive) {
      Logger.ok('rclone found — ${RcloneManager.installedVersion()}');
      Logger.ok('rclone remote "${RcloneManager.remoteName}" configured');

      // Quick connection test.
      final about = Process.runSync(
        'rclone',
        ['about', '${RcloneManager.remoteName}:'],
        runInShell: true,
      );
      if (about.exitCode != 0) {
        _printError(
          missing: 'Google Drive connection',
          reason: 'Cannot reach Google Drive via rclone.',
          fix: 'Run: flutter_release_manager init',
        );
        exit(1);
      }
      Logger.ok('Google Drive — connected');
    }

    stdout.writeln('');
  }

  // ── App directory ─────────────────────────────────────────────────────────

  Future<String> _resolveAppDir(String? cliValue) async {
    if (cliValue != null) {
      _assertAppDir(cliValue);
      return cliValue;
    }

    final detected = ProjectDetector.detectAppDir();
    if (detected != null) {
      Logger.ok('Flutter project detected: $detected');
      return detected;
    }

    return _ask(
      label: 'Flutter app directory',
      hints: [
        'This is the folder that contains your pubspec.yaml file.',
        'Example: /Users/john/projects/my_app',
      ],
      missing: 'Flutter app directory path',
      reason: 'The build process needs to know where your Flutter project is.',
      fix: 'Enter the full path to the folder that contains pubspec.yaml.',
      examples: ['/Users/john/projects/my_app'],
      validate: (v) {
        if (!Directory(v).existsSync()) return 'Directory not found: $v';
        if (!File('$v/pubspec.yaml').existsSync()) {
          return 'No pubspec.yaml found in: $v';
        }
        return null;
      },
    );
  }

  void _assertAppDir(String dir) {
    if (!Directory(dir).existsSync()) {
      _printError(
        missing: 'Flutter app directory',
        reason: 'The path "$dir" does not exist on disk.',
        fix: 'Check the --app-dir flag value.',
      );
      exit(1);
    }
    if (!File('$dir/pubspec.yaml').existsSync()) {
      _printError(
        missing: 'pubspec.yaml in $dir',
        reason: 'Directory must be the root of a Flutter project.',
        fix:
            'Make sure --app-dir points to the folder containing pubspec.yaml.',
      );
      exit(1);
    }
  }

  // ── App name ──────────────────────────────────────────────────────────────

  Future<String> _resolveAppName(String appDir) async {
    final savedName = _saved['appName'] as String?;
    final detectedName = ProjectDetector.readAppName(appDir);
    final defaultName = savedName ?? detectedName;

    final sourceNote = savedName != null
        ? 'Saved from last run: $savedName'
        : detectedName != null
            ? 'Detected from pubspec.yaml: $detectedName'
            : null;

    return _ask(
      label: 'App name',
      defaultValue: defaultName,
      hints: [
        'Used as a prefix in the output file name.',
        'No spaces allowed. Use CamelCase or underscores.',
        if (sourceNote != null) '$sourceNote — press Enter to accept.',
      ],
      missing: 'App name',
      reason: 'The name labels the output APK and IPA files.',
      fix: 'Enter a short name with no spaces.',
      examples: ['MyApp', 'my_app'],
      validate: (v) {
        if (v.contains(' ')) {
          return 'App name cannot contain spaces. '
              'Try: ${v.replaceAll(' ', '_')}';
        }
        return null;
      },
    );
  }

  // ── Apple Team ID ─────────────────────────────────────────────────────────

  Future<String> _askTeamId() => _ask(
        label: 'Apple Developer Team ID',
        defaultValue: _saved['teamId'] as String?,
        hints: [
          'Sign in at developer.apple.com',
          'Click your name top-right → Membership details',
          'Copy the Team ID — 10 uppercase alphanumeric characters.',
        ],
        missing: 'Apple Developer Team ID',
        reason:
            'xcodebuild needs your Team ID to sign the app during archiving.',
        fix: 'Find it at developer.apple.com → your name → Membership details.',
        examples: ['UC2HYA24R2', 'ABCD1234EF'],
        validate: (v) {
          if (v.length != 10 || !RegExp(r'^[A-Z0-9]+$').hasMatch(v)) {
            return 'Team ID must be exactly 10 uppercase letters and digits.\n'
                '  Example: UC2HYA24R2';
          }
          return null;
        },
      );

  // ── Diawi token ───────────────────────────────────────────────────────────

  Future<String> _askDiawiToken() => _ask(
        label: 'Diawi API token',
        hints: [
          'Sign in at diawi.com',
          'Go to Account → API Access Tokens → create a new token.',
        ],
        missing: 'Diawi API token',
        reason: 'The Diawi API requires a token to authenticate uploads.',
        fix: 'Go to diawi.com → Account → API Access Tokens.',
      );

  // ── Platform picker ───────────────────────────────────────────────────────

  Future<String> _pickPlatform() async {
    final savedPlatform = _saved['platform'] as String?;
    final savedChoice = switch (savedPlatform) {
      'android' => '1',
      'ios' => '2',
      'both' => '3',
      _ => null,
    };

    _printSection('Platform');
    stdout.writeln('');
    stdout.writeln('  What do you want to build?');
    stdout.writeln('  1) Android only  — generates APK');
    stdout.writeln('  2) iOS only      — generates IPA');
    stdout.writeln('  3) Both          — APK + IPA');
    stdout.writeln('');

    while (true) {
      if (savedChoice != null) {
        stdout.write('  Enter choice [1/2/3] (last: $savedChoice): ');
      } else {
        stdout.write('  Enter choice [1/2/3]: ');
      }

      final raw = stdin.readLineSync()?.trim() ?? '';
      final choice = (raw.isEmpty && savedChoice != null) ? savedChoice : raw;

      switch (choice) {
        case '1':
          return 'android';
        case '2':
          return 'ios';
        case '3':
          return 'both';
        default:
          _printError(
            missing: 'Platform selection',
            reason: 'Enter 1, 2, or 3.',
            fix: '1 = Android, 2 = iOS, 3 = Both',
          );
      }
    }
  }

  // ── Confirm prompt ────────────────────────────────────────────────────────

  Future<bool> _confirm(String question) async {
    stdout.write('  $question [y/N]: ');
    final answer = stdin.readLineSync()?.trim().toLowerCase() ?? '';
    return answer == 'y' || answer == 'yes';
  }

  // ── Generic text prompt ───────────────────────────────────────────────────

  Future<String> _ask({
    required String label,
    String? defaultValue,
    List<String> hints = const [],
    required String missing,
    required String reason,
    required String fix,
    List<String> examples = const [],
    String? Function(String)? validate,
  }) async {
    _printSection(label);
    if (hints.isNotEmpty) _printHints(hints);

    while (true) {
      if (defaultValue != null) {
        stdout.write('  $label [$defaultValue]: ');
      } else {
        stdout.write('  $label: ');
      }

      final raw = stdin.readLineSync()?.trim() ?? '';
      final value = (raw.isEmpty && defaultValue != null) ? defaultValue : raw;

      if (value.isEmpty) {
        _printError(
          missing: missing,
          reason: reason,
          fix: fix,
          examples: examples,
        );
        continue;
      }

      if (validate != null) {
        final error = validate(value);
        if (error != null) {
          stderr.writeln('');
          stderr.writeln('  ❌  $error');
          stderr.writeln('');
          continue;
        }
      }

      return value;
    }
  }

  // ── Summary ───────────────────────────────────────────────────────────────

  void _printSummary({
    required String platform,
    required String appDir,
    required String appName,
    required bool uploadDrive,
    required String? driveFolderName,
    required String? teamId,
    required String scheme,
    required String exportMethod,
    required String? diawiToken,
    required bool skipBuild,
  }) {
    final platformLabel = switch (platform) {
      'android' => 'Android',
      'ios' => 'iOS',
      _ => 'Android + iOS',
    };

    stdout.writeln('');
    stdout.writeln('╔══════════════════════════════════════════════╗');
    stdout.writeln('  Build Summary');
    stdout.writeln('╚══════════════════════════════════════════════╝');
    stdout.writeln('');
    stdout.writeln('  Platform      $platformLabel');
    stdout.writeln('  App dir       $appDir');
    stdout.writeln('  App name      $appName');
    if (skipBuild) stdout.writeln('  Mode          Upload only (skip build)');

    if (platform == 'android' || platform == 'both') {
      stdout.writeln('');
      stdout.writeln('  Android');
      if (uploadDrive) {
        stdout.writeln('    Drive upload  Yes (via rclone)');
        stdout.writeln('    Folder        $driveFolderName');
      } else {
        stdout.writeln('    Drive upload  No — APK stays local');
      }
    }

    if (platform == 'ios' || platform == 'both') {
      stdout.writeln('');
      stdout.writeln('  iOS');
      stdout.writeln('    Team ID       $teamId');
      stdout.writeln('    Scheme        $scheme');
      stdout.writeln('    Export        $exportMethod');
      stdout.writeln(
        '    Diawi upload  ${diawiToken != null ? 'Yes' : 'No — IPA stays local'}',
      );
    }

    stdout.writeln('');
  }

  // ── Error display ─────────────────────────────────────────────────────────

  void _printError({
    required String missing,
    required String reason,
    required String fix,
    List<String> examples = const [],
  }) {
    stderr.writeln('');
    stderr.writeln('  ❌  Missing: $missing');
    stderr.writeln('  ❌  Reason:  $reason');
    if (examples.isNotEmpty) {
      stderr.writeln(
        '  ❌  Example${examples.length > 1 ? 's' : ''}:',
      );
      for (final e in examples) {
        stderr.writeln('      $e');
      }
    }
    if (fix.isNotEmpty) stderr.writeln('  ❌  Fix:     $fix');
    stderr.writeln('');
  }

  // ── UI helpers ────────────────────────────────────────────────────────────

  void _printWelcome() {
    stdout.writeln('');
    stdout.writeln('╔══════════════════════════════════════════════╗');
    stdout.writeln('  flutter_release_manager  v3');
    stdout.writeln('  Build · Archive · Distribute');
    stdout.writeln('╚══════════════════════════════════════════════╝');
    stdout.writeln('');
    stdout.writeln('  Builds your Flutter app and uploads it via rclone.');
    stdout.writeln('  First time? Run: flutter_release_manager init');
    stdout.writeln('');
  }

  void _printSection(String title) {
    final pad = title.length < 42 ? '─' * (42 - title.length) : '';
    stdout.writeln('');
    stdout.writeln('  ─── $title $pad');
  }

  void _printHints(List<String> hints) {
    stdout.writeln('');
    for (final h in hints) {
      stdout.writeln('  \x1B[0;36mℹ\x1B[0m  $h');
    }
    stdout.writeln('');
  }

  void _printUsage(ArgParser parser) {
    stdout.writeln('''
flutter_release_manager — Build and distribute Flutter apps

Commands:
  flutter_release_manager          Build and upload (interactive)
  flutter_release_manager init     First-time setup: install rclone, sign into Google Drive
  flutter_release_manager doctor   Check all prerequisites

Flags (useful for CI/scripts):
  flutter_release_manager --platform <android|ios|both> --app-dir <path> --app-name <name> [options]

${parser.usage}
''');
  }

  // ── Arg parser ────────────────────────────────────────────────────────────

  ArgParser _buildParser() => ArgParser()
    ..addOption(
      'platform',
      abbr: 'p',
      help: 'Target platform: android | ios | both',
      allowed: ['android', 'ios', 'both'],
    )
    ..addOption(
      'app-dir',
      abbr: 'd',
      help: 'Path to the Flutter app directory.',
    )
    ..addOption(
      'app-name',
      abbr: 'n',
      help: 'App name used in output file names.',
    )
    ..addFlag(
      'upload-drive',
      help: 'Upload the APK to Google Drive after build.',
      negatable: false,
    )
    ..addOption(
      'team-id',
      abbr: 't',
      help: 'Apple Developer Team ID (iOS only).',
    )
    ..addOption('scheme', help: 'Xcode scheme name.', defaultsTo: 'Runner')
    ..addOption(
      'export-method',
      help: 'development | release-testing | app-store',
      allowed: ['development', 'release-testing', 'app-store'],
      defaultsTo: 'development',
    )
    ..addOption('diawi-token', help: 'Diawi API token for IPA upload.')
    ..addFlag(
      'skip-build',
      help: 'Skip the Flutter build and upload an already-built artifact.',
      negatable: false,
    )
    ..addFlag(
      'upload-only',
      help: 'Alias for --skip-build.',
      negatable: false,
    )
    ..addFlag('help', abbr: 'h', help: 'Print this help.', negatable: false);
}
