import 'dart:io';

import 'package:args/args.dart';

import 'app_config.dart';
import 'config.dart';
import 'config_command.dart';
import 'config_store.dart';
import 'gatekeeper.dart';
import 'logger.dart';
import 'project_detector.dart';
import 'rclone_manager.dart';
import 'version.dart';

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

    // Migrate config from previous package names on first run.
    AppConfig.migrateFromOldPackageName();
    AppConfig.migrateFromCredentialsJson();

    _printWelcome();

    // ── Startup screen — show current state if configured ─────────────────────
    final bool isCiMode = args.wasParsed('platform') ||
        args.wasParsed('app-dir') ||
        args.wasParsed('upload-drive');

    if (!isCiMode) await _showStartupScreen();

    // Show macOS security notice once before any subprocess is invoked.
    GatekeeperGuard.showNoticeIfNeeded();

    // ── 1. App directory ──────────────────────────────────────────────────────
    final appDir = await _resolveAppDir(args['app-dir'] as String?);

    // ── 2. Project config ─────────────────────────────────────────────────────
    _store = ConfigStore(appDir);
    _saved = _store!.load();

    // Merge machine-level appName into saved if present.
    final machineAppName = AppConfig.load()['appName'] as String?;
    if (machineAppName != null && !_saved.containsKey('appName')) {
      _saved['appName'] = machineAppName;
    }

    // Migrate diawiToken from project config (v1.x / v2.x).
    final legacyDiawi = _saved['diawiToken'] as String?;
    if (legacyDiawi != null && !AppConfig.hasDiawiToken) {
      AppConfig.saveDiawiToken(legacyDiawi);
    }

    // ── 3. Flags ──────────────────────────────────────────────────────────────
    final skipBuild =
        (args['skip-build'] as bool) || (args['upload-only'] as bool);

    // ── 4. Platform ───────────────────────────────────────────────────────────
    // Never auto-select from saved config — platform is a build-time decision.
    final platform = args['platform'] as String? ?? await _pickPlatform();
    final buildAndroid = platform == 'android' || platform == 'both';
    final buildIos = platform == 'ios' || platform == 'both';

    // ── 5. App name ───────────────────────────────────────────────────────────
    final appName =
        args['app-name'] as String? ?? await _resolveAppName(appDir);

    // ── 6. Android / Google Drive ─────────────────────────────────────────────
    bool uploadDrive;
    String? driveFolderName;
    String? environment;

    if (args.wasParsed('upload-drive')) {
      uploadDrive = args['upload-drive'] as bool;
    } else {
      uploadDrive = await _resolveUploadDrive(buildAndroid);
    }

    if (uploadDrive) {
      RcloneManager.migrateOldRemoteIfNeeded();
      if (!RcloneManager.isInstalled()) {
        uploadDrive = await _offerContinueWithoutDrive(
          'rclone is not installed. It is required for Google Drive uploads.',
        );
      } else if (!RcloneManager.remoteExists()) {
        uploadDrive = await _offerContinueWithoutDrive(
          'Google Drive has not been configured yet.',
        );
      } else {
        driveFolderName = AppConfig.folderName;
        if (driveFolderName == null) {
          uploadDrive = await _offerContinueWithoutDrive(
            'No Drive folder has been selected yet.',
          );
        }
      }

      if (uploadDrive) {
        Logger.ok('Drive root folder: $driveFolderName');

        // ── 6b. Environment (mandatory, never persisted) ─────────────────────
        final envArg = args['environment'] as String?;
        environment =
            envArg != null ? _normalizeEnv(envArg) : await _pickEnvironment();
      }
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

      if (diawiToken == null) {
        diawiToken = AppConfig.diawiToken;

        if (diawiToken == null) {
          final uploadDiawi = await _resolveUploadDiawi();
          if (uploadDiawi) {
            diawiToken = await _askDiawiToken();
            AppConfig.saveDiawiToken(diawiToken);
            Logger.ok('Diawi token saved.');
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
    // Platform is intentionally excluded — user must choose every build.
    _store!.save({
      'appName': appName,
      if (teamId != null) 'teamId': teamId,
      'scheme': scheme,
      'exportMethod': exportMethod,
    });

    // Also save appDir and appName at machine level for startup screen.
    AppConfig.saveProjectDirectory(appDir);
    AppConfig.save({'appName': appName});

    // ── 11. Summary + confirmation ────────────────────────────────────────────
    _printSummary(
      platform: platform,
      appDir: appDir,
      appName: appName,
      uploadDrive: uploadDrive,
      driveFolderName: driveFolderName,
      environment: environment,
      teamId: teamId,
      scheme: scheme,
      exportMethod: exportMethod,
      diawiToken: diawiToken,
      skipBuild: skipBuild,
    );

    stdout.write('  Press Enter to start the build, or Ctrl+C to cancel... ');
    stdin.readLineSync();
    stdout.writeln('');

    return Config(
      platform: platform,
      appDir: appDir,
      appName: appName,
      uploadDrive: uploadDrive,
      rcloneRemote: AppConfig.remoteName,
      driveFolderName: driveFolderName,
      environment: environment,
      teamId: teamId,
      scheme: scheme,
      exportMethod: exportMethod,
      diawiToken: diawiToken,
      skipBuild: skipBuild,
    );
  }

  // ── Startup screen ────────────────────────────────────────────────────────

  /// Shows current configuration summary. Exits if user chose quit.
  Future<void> _showStartupScreen() async {
    final cfg = AppConfig.load();
    final projectDir = cfg['projectDirectory'] as String?;
    final appName = cfg['appName'] as String?;
    final folderName = cfg['folderName'] as String?;
    final hasDiawi = (cfg['diawiToken'] as String?)?.isNotEmpty == true;
    final driveConnected = RcloneManager.remoteExists();

    // Only show startup screen if something is already configured.
    if (projectDir == null && folderName == null && !driveConnected) return;

    // Fetch email lazily — cached after first successful call.
    if (driveConnected && AppConfig.driveEmail == null) {
      await RcloneManager.fetchAndCacheEmail();
    }
    final driveEmail = AppConfig.driveEmail;

    stdout.writeln('  ─── Current Configuration ──────────────────────────');
    stdout.writeln('');

    if (projectDir != null && appName != null) {
      _infoRow('Project', '$appName  ($projectDir)');
    } else if (projectDir != null) {
      _infoRow('Project', projectDir);
    }

    _infoRow(
      'Drive Account',
      driveConnected
          ? (driveEmail != null
              ? '\x1B[0;32m$driveEmail\x1B[0m'
              : '\x1B[0;32mConnected\x1B[0m')
          : '\x1B[1;33mNot set up\x1B[0m',
    );

    if (folderName != null) {
      _infoRow('Drive Folder', folderName);
    }

    _infoRow(
      'Diawi',
      hasDiawi ? '\x1B[0;32mConfigured\x1B[0m' : '\x1B[1;33mNot set\x1B[0m',
    );

    stdout.writeln('');
    stdout.writeln('  [Enter]  Continue with these settings');
    stdout.writeln('  [c]      Edit configuration');
    stdout.writeln('  [q]      Quit');
    stdout.writeln('');
    stdout.write('  > ');

    final input = stdin.readLineSync()?.trim().toLowerCase() ?? '';
    stdout.writeln('');

    if (input == 'q') {
      stdout.writeln('  Goodbye.');
      exit(0);
    }

    if (input == 'c') {
      await ConfigCommand().run();
      // Re-show startup screen so updated values are visible.
      await _showStartupScreen();
    }
  }

  void _infoRow(String label, String value) {
    stdout.writeln('  ${label.padRight(16)}$value');
  }

  // ── Upload preference resolution ──────────────────────────────────────────

  Future<bool> _resolveUploadDrive(bool buildingAndroid) async {
    if (!buildingAndroid) return false;

    final pref = AppConfig.autoUploadDrive;
    if (pref != null) {
      Logger.ok(
        'Drive upload: ${pref ? "enabled" : "disabled"} (saved preference).',
      );
      return pref;
    }

    _printSection('Google Drive Upload');
    _printHints([
      'APKs are uploaded via rclone — no OAuth setup needed.',
      'Run flutter_release_manager init once to configure Drive.',
      'Save your preference in: flutter_release_manager config',
    ]);

    final answer = await _confirm('Upload APK to Google Drive after building?');
    AppConfig.saveAutoUploadDrive(answer);
    Logger.ok('Preference saved.');
    return answer;
  }

  Future<bool> _resolveUploadDiawi() async {
    final pref = AppConfig.autoUploadDiawi;
    if (pref != null) {
      Logger.ok(
        'Diawi upload: ${pref ? "enabled" : "disabled"} (saved preference).',
      );
      return pref;
    }

    _printSection('Diawi Upload (iOS)');
    _printHints([
      'Diawi gives testers a simple install link — no App Store needed.',
      'Sign up at diawi.com → Account → API Access Tokens.',
      'Save your preference in: flutter_release_manager config',
    ]);

    final answer = await _confirm('Upload IPA to Diawi?');
    AppConfig.saveAutoUploadDiawi(answer);
    Logger.ok('Preference saved.');
    return answer;
  }

  // ── Drive not configured — friendly fallback ──────────────────────────────

  Future<bool> _offerContinueWithoutDrive(String reason) async {
    stdout.writeln('');
    stdout.writeln('  ─── Google Drive Not Configured ──────────────────────');
    stdout.writeln('');
    stdout.writeln('  $reason');
    stdout.writeln('');
    stdout.writeln('  Run:  flutter_release_manager init');
    stdout.writeln('  (This setup is required only once.)');
    stdout.writeln('');
    stdout.write('  Continue without Drive upload? [Y/n]: ');
    final answer = stdin.readLineSync()?.trim().toLowerCase() ?? 'y';
    if (answer == 'n' || answer == 'no') {
      stdout.writeln('  Build cancelled.');
      exit(0);
    }
    Logger.ok('Continuing with local build only.');
    return false;
  }

  // ── Pre-flight validation ─────────────────────────────────────────────────

  Future<void> _validatePrerequisites({
    required bool buildAndroid,
    required bool buildIos,
    required bool uploadDrive,
  }) async {
    Logger.header('Pre-flight checks');

    final whichCmd = Platform.isWindows ? 'where' : 'which';

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

    if (buildIos &&
        Process.runSync(whichCmd, ['xcodebuild'], runInShell: true).exitCode !=
            0) {
      _printError(
        missing: 'xcodebuild command',
        reason: 'xcodebuild is required to archive and export iOS apps.',
        fix: 'Install Xcode command-line tools: xcode-select --install',
      );
      exit(1);
    }
    if (buildIos) Logger.ok('xcodebuild found');

    if (uploadDrive) {
      Logger.ok('rclone found — ${RcloneManager.installedVersion()}');
      Logger.ok('rclone remote "${RcloneManager.remoteName}" configured');

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

    // 1. Saved machine-level project directory.
    final saved = AppConfig.projectDirectory;
    if (saved != null) {
      if (!Directory(saved).existsSync()) {
        Logger.skip(
          'Saved project directory no longer exists: $saved',
        );
        AppConfig.clearProjectDirectory();
      } else if (File('$saved/pubspec.yaml').existsSync()) {
        Logger.ok('Project: $saved');
        return saved;
      }
    }

    // 2. Detect from CWD.
    final detected = ProjectDetector.detectAppDir();
    if (detected != null) {
      Logger.ok('Flutter project detected: $detected');
      return detected;
    }

    // 3. Ask.
    return _ask(
      label: 'Flutter app directory',
      hints: [
        'This is the folder that contains your pubspec.yaml file.',
        'Example: /Users/john/projects/my_app',
        'Tip: run this command from inside your Flutter project.',
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
    if (savedName != null) {
      Logger.ok('App name: $savedName');
      return savedName;
    }

    final detectedName = ProjectDetector.readAppName(appDir);

    return _ask(
      label: 'App name',
      defaultValue: detectedName,
      hints: [
        'Used as a prefix in the output file name.',
        'No spaces. CamelCase or underscores.',
        if (detectedName != null)
          'Detected from pubspec.yaml: $detectedName — press Enter to accept.',
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
    _printSection('Platform');
    stdout.writeln('');
    stdout.writeln('  What would you like to build?');
    stdout.writeln('');
    stdout.writeln('  1. Android APK');
    stdout.writeln('  2. iOS IPA');
    stdout.writeln('  3. Android + iOS');
    stdout.writeln('');

    while (true) {
      stdout.write('  Choice: ');
      final raw = stdin.readLineSync()?.trim() ?? '';

      switch (raw) {
        case '1':
          return 'android';
        case '2':
          return 'ios';
        case '3':
          return 'both';
        default:
          stdout.writeln('  Enter 1, 2, or 3.');
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

  // ── Environment picker ────────────────────────────────────────────────────

  Future<String> _pickEnvironment() async {
    _printSection('Environment');
    stdout.writeln('');
    stdout.writeln('  Select the build environment for Google Drive upload.');
    stdout.writeln('  This determines where the APK is placed in Drive.');
    stdout.writeln('');
    stdout.writeln('  1) DEV   — development build for internal testing');
    stdout.writeln('  2) UAT   — user acceptance testing');
    stdout.writeln('  3) PROD  — production release');
    stdout.writeln('');

    while (true) {
      stdout.write('  Enter choice [1/2/3]: ');
      final raw = stdin.readLineSync()?.trim() ?? '';
      switch (raw) {
        case '1':
          return 'DEV';
        case '2':
          return 'UAT';
        case '3':
          return 'PROD';
        default:
          _printError(
            missing: 'Environment',
            reason: 'Enter 1, 2, or 3.',
            fix: '1 = DEV, 2 = UAT, 3 = PROD',
          );
      }
    }
  }

  String _normalizeEnv(String raw) {
    final upper = raw.trim().toUpperCase();
    if (upper == 'DEV' || upper == 'UAT' || upper == 'PROD') return upper;
    // Accept numeric shorthand from CI callers
    return switch (upper) {
      '1' => 'DEV',
      '2' => 'UAT',
      '3' => 'PROD',
      _ => upper
    };
  }

  // ── Summary ───────────────────────────────────────────────────────────────

  void _printSummary({
    required String platform,
    required String appDir,
    required String appName,
    required bool uploadDrive,
    required String? driveFolderName,
    required String? environment,
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

    final driveEmail = AppConfig.driveEmail;
    final driveAccount = driveEmail ??
        (RcloneManager.remoteExists() ? 'Connected' : 'Not set up');

    stdout.writeln('');
    stdout.writeln('╔══════════════════════════════════════════════╗');
    stdout.writeln('  Build Summary');
    stdout.writeln('╚══════════════════════════════════════════════╝');
    stdout.writeln('');
    _summaryRow('Project', appName);
    _summaryRow('Directory', appDir);
    _summaryRow('Platform', platformLabel);
    if (skipBuild) _summaryRow('Mode', 'Upload only (skip build)');

    if (platform == 'android' || platform == 'both') {
      stdout.writeln('');
      stdout.writeln('  Android');
      _summaryRow(
        '  Drive Upload',
        uploadDrive ? 'Enabled' : 'Disabled — APK stays local',
      );
      if (uploadDrive && environment != null && driveFolderName != null) {
        final now = DateTime.now();
        final year = now.year.toString();
        final month = _monthName(now.month);
        final destination =
            '$driveFolderName/$appName/$year/$month/$environment/';
        _summaryRow('  Google Account', driveAccount);
        _summaryRow('  Drive Folder', driveFolderName);
        _summaryRow('  Environment', environment);
        _summaryRow('  Destination', destination);
      }
    }

    if (platform == 'ios' || platform == 'both') {
      stdout.writeln('');
      stdout.writeln('  iOS');
      _summaryRow('  Team ID', teamId ?? '—');
      _summaryRow('  Scheme', scheme);
      _summaryRow('  Export Method', exportMethod);
      _summaryRow(
        '  Diawi Upload',
        diawiToken != null ? 'Enabled' : 'Disabled — IPA stays local',
      );
    }

    stdout.writeln('');
  }

  void _summaryRow(String label, String value) {
    stdout.writeln('  ${label.padRight(18)}$value');
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
        '  ❌  Example${examples.length > 1 ? "s" : ""}:',
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
    stdout.writeln('  $packageName  v$packageVersion');
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
flutter_release_manager v$packageVersion — Build and distribute Flutter apps

Commands:
  flutter_release_manager          Build and upload (interactive)
  flutter_release_manager init     First-time setup: install rclone, sign into Google Drive
  flutter_release_manager doctor   Check all prerequisites
  flutter_release_manager config   Edit saved configuration
  flutter_release_manager version  Show version information

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
      'environment',
      abbr: 'e',
      help:
          'Upload environment: DEV | UAT | PROD (required when --upload-drive)',
      allowed: ['DEV', 'UAT', 'PROD', 'dev', 'uat', 'prod'],
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
