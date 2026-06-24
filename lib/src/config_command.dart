import 'dart:io';

import 'app_config.dart';
import 'config_store.dart';
import 'logger.dart';
import 'rclone_manager.dart';

/// Interactive configuration editor.
/// flutter_release_manager config
class ConfigCommand {
  Future<void> run() async {
    _printHeader();

    while (true) {
      await _printMenu();
      final choice = stdin.readLineSync()?.trim() ?? '';
      stdout.writeln('');

      switch (choice) {
        case '1':
          await _editProjectDirectory();
        case '2':
          await _editAppName();
        case '3':
          await _editGoogleDriveAccount();
        case '4':
          await _editGoogleDriveFolder();
        case '5':
          await _editDiawiToken();
        case '6':
          await _editUploadPreferences();
        case '7':
          await _editExportMethod();
        case '8':
          await _editApkAbi();
        case '9':
          await _resetConfiguration();
        case '10':
        case 'q':
        case 'Q':
          stdout.writeln('  Exiting configuration.');
          stdout.writeln('');
          return;
        default:
          stdout.writeln('  Enter a number from 1–10.');
      }
    }
  }

  // ── Menu ───────────────────────────────────────────────────────────────────

  void _printHeader() {
    stdout.writeln('');
    stdout.writeln('╔══════════════════════════════════════════════╗');
    stdout.writeln('  flutter_release_manager — Configuration');
    stdout.writeln('╚══════════════════════════════════════════════╝');
    stdout.writeln('');
  }

  Future<void> _printMenu() async {
    final cfg = AppConfig.load();

    final projectDir = cfg['projectDirectory'] as String?;
    final appName = cfg['appName'] as String?;
    final folderName = cfg['folderName'] as String?;
    final hasDiawi = (cfg['diawiToken'] as String?)?.isNotEmpty == true;
    final autoDrive = cfg['autoUploadDrive'];
    final autoDiawi = cfg['autoUploadDiawi'];
    final driveConnected = RcloneManager.remoteExists();

    // Fetch email lazily — cached after first successful call.
    if (driveConnected && AppConfig.driveEmail == null) {
      await RcloneManager.fetchAndCacheEmail();
    }
    final email = AppConfig.driveEmail;

    final driveStatus = driveConnected
        ? (email != null
            ? '\x1B[0;32m$email\x1B[0m'
            : '\x1B[0;32mConnected\x1B[0m')
        : '\x1B[0;31mNot set up\x1B[0m';
    final diawiStatus =
        hasDiawi ? '\x1B[0;32mConfigured\x1B[0m' : '\x1B[1;33mNot set\x1B[0m';

    stdout.writeln('');
    stdout.writeln('  ─── Current Configuration ──────────────────────────');
    stdout.writeln('');
    _row('1', 'Project Directory', projectDir ?? '\x1B[1;33mnot set\x1B[0m');
    _row('2', 'App Name', appName ?? '\x1B[1;33mnot set\x1B[0m');
    _row('3', 'Google Account', driveStatus);
    _row('4', 'Google Drive Root Folder',
        folderName ?? '\x1B[1;33mnot set\x1B[0m');
    _row('5', 'Diawi Token', diawiStatus);
    _row('6', 'Upload Preferences', _uploadPrefLabel(autoDrive, autoDiawi));
    _row('7', 'iOS Export Method', _exportMethodLabel());
    _row('8', 'Android APK Version', _apkAbiLabel());
    stdout.writeln('  9)  Reset Configuration');
    stdout.writeln('  10) Exit');
    stdout.writeln('');
    stdout.write('  Enter choice [1–10]: ');
  }

  void _row(String num, String label, String value) {
    final padded = label.padRight(30);
    stdout.writeln('  $num)  $padded $value');
  }

  String _uploadPrefLabel(dynamic drive, dynamic diawi) {
    if (drive == null && diawi == null) return '\x1B[1;33mask each run\x1B[0m';
    final parts = <String>[];
    if (drive == true) parts.add('Drive: auto-upload');
    if (drive == false) parts.add('Drive: skip');
    if (diawi == true) parts.add('Diawi: auto-upload');
    if (diawi == false) parts.add('Diawi: skip');
    return parts.join(', ');
  }

  // ── 1. Project directory ───────────────────────────────────────────────────

  Future<void> _editProjectDirectory() async {
    _section('Flutter Project Directory');
    stdout.writeln(
      '  Enter the full path to your Flutter project (contains pubspec.yaml).',
    );
    stdout.writeln('  Example: /Users/john/projects/my_app');
    stdout.writeln('');

    final current = AppConfig.projectDirectory;
    if (current != null) {
      stdout.writeln('  Current: $current');
      stdout.writeln('  Press Enter to keep, or type a new path.');
      stdout.writeln('');
    }

    while (true) {
      stdout.write('  Path: ');
      final raw = stdin.readLineSync()?.trim() ?? '';

      if (raw.isEmpty && current != null) {
        Logger.ok('Kept: $current');
        return;
      }
      if (raw.isEmpty) {
        stdout.writeln('  Enter a path, or press Ctrl+C to cancel.');
        continue;
      }

      if (!Directory(raw).existsSync()) {
        stdout.writeln('  Directory not found: $raw');
        continue;
      }
      if (!File('$raw/pubspec.yaml').existsSync()) {
        stdout
            .writeln('  No pubspec.yaml in: $raw — is this a Flutter project?');
        continue;
      }

      AppConfig.saveProjectDirectory(raw);
      Logger.ok('Saved: $raw');
      return;
    }
  }

  // ── 2. App name ────────────────────────────────────────────────────────────

  Future<void> _editAppName() async {
    _section('App Name');
    stdout.writeln('  Used as the file name prefix for APK/IPA output.');
    stdout.writeln('  Example: MyApp  (no spaces)');
    stdout.writeln('');

    final cfg = AppConfig.load();
    final current = cfg['appName'] as String?;
    if (current != null) {
      stdout.writeln('  Current: $current');
    }

    while (true) {
      stdout.write('  App name: ');
      final raw = stdin.readLineSync()?.trim() ?? '';

      if (raw.isEmpty && current != null) {
        Logger.ok('Kept: $current');
        return;
      }
      if (raw.isEmpty) {
        stdout.writeln('  Enter a name.');
        continue;
      }
      if (raw.contains(' ')) {
        stdout.writeln(
          '  Spaces not allowed. Try: ${raw.replaceAll(' ', '_')}',
        );
        continue;
      }

      AppConfig.save({'appName': raw});
      Logger.ok('Saved: $raw');
      return;
    }
  }

  // ── 3. Google Drive account ────────────────────────────────────────────────

  Future<void> _editGoogleDriveAccount() async {
    _section('Google Drive Account');

    if (RcloneManager.remoteExists()) {
      final email = AppConfig.driveEmail;
      if (email != null) {
        stdout.writeln('  Connected as: \x1B[0;32m$email\x1B[0m');
      } else {
        stdout.writeln('  Google Drive is connected.');
      }
      stdout.writeln('');
      stdout.writeln('  1)  Keep current account');
      stdout.writeln('  2)  Change Google account');
      stdout.writeln('  3)  Disconnect Google account');
      stdout.writeln('');
      stdout.write('  Choice [1/2/3]: ');
      final choice = stdin.readLineSync()?.trim() ?? '1';
      stdout.writeln('');

      switch (choice) {
        case '2':
          await _changeGoogleAccount();
          return;
        case '3':
          await _disconnectDrive();
          return;
        default:
          Logger.ok('Kept current Google account.');
          return;
      }
    }

    // Not connected — go straight to fresh setup.
    stdout.writeln('  Your browser will open for Google sign-in.');
    stdout.writeln('  Sign in and click Allow — this resumes automatically.');
    stdout.writeln('');
    await RcloneManager.ensureRemoteAndAuthenticated();
    final email = AppConfig.driveEmail;
    if (email != null) {
      Logger.ok('Connected as: $email');
    } else {
      Logger.ok('Google Drive connected.');
    }
  }

  Future<void> _changeGoogleAccount() async {
    stdout.writeln('  Removing existing Google Drive connection...');
    RcloneManager.deleteRemote();
    AppConfig.clearDriveEmail();
    Logger.ok('Previous account removed.');
    stdout.writeln('');
    stdout.writeln('  Your browser will open for Google sign-in.');
    stdout.writeln('  Sign in with the new account and click Allow.');
    stdout.writeln('');
    await RcloneManager.ensureRemoteAndAuthenticated();
    final email = AppConfig.driveEmail;
    if (email != null) {
      Logger.ok('Google account changed. Connected as: $email');
    } else {
      Logger.ok('Google account changed.');
    }
  }

  Future<void> _disconnectDrive() async {
    stdout.writeln('  Disconnecting Google Drive...');
    RcloneManager.deleteRemote();
    AppConfig.clearDriveEmail();
    Logger.ok('Google Drive account removed.');
    stdout.writeln('');
    stdout.writeln(
      '  Run flutter_release_manager init to connect a new account.',
    );
  }

  // ── 4. Google Drive root folder ────────────────────────────────────────────

  Future<void> _editGoogleDriveFolder() async {
    _section('Google Drive Root Folder');

    if (!RcloneManager.remoteExists()) {
      stdout.writeln(
        '  Google Drive is not connected. Set up account first (option 3).',
      );
      return;
    }

    final current = AppConfig.folderName;
    if (current != null) {
      stdout.writeln('  Current folder: $current');
      stdout.writeln('');
    }

    Logger.step('Fetching your Drive folders...');
    final folders = RcloneManager.listTopLevelFolders();

    if (folders.isNotEmpty) {
      stdout.writeln('');
      stdout.writeln('  Available folders:');
      for (var i = 0; i < folders.length; i++) {
        stdout.writeln('  ${i + 1})  ${folders[i]}');
      }
      stdout.writeln('  ${folders.length + 1})  Enter folder name manually');
      stdout.writeln('');
      stdout.write('  Choice: ');

      final raw = stdin.readLineSync()?.trim() ?? '';
      final idx = int.tryParse(raw);

      if (idx != null && idx >= 1 && idx <= folders.length) {
        final selected = folders[idx - 1];
        AppConfig.saveFolderName(selected);
        Logger.ok('Drive folder set to: $selected');
        return;
      }
    }

    stdout.writeln('');
    stdout.writeln(
      '  Type the folder name as it appears in Google Drive.',
    );
    stdout.write('  Folder name: ');
    final name = stdin.readLineSync()?.trim() ?? '';
    if (name.isEmpty) {
      stdout.writeln('  No change made.');
      return;
    }
    AppConfig.saveFolderName(name);
    Logger.ok('Drive folder set to: $name');
  }

  // ── 5. Diawi token ─────────────────────────────────────────────────────────

  Future<void> _editDiawiToken() async {
    _section('Diawi Token');
    stdout.writeln(
      '  Get your token at: diawi.com → Account → API Access Tokens',
    );
    stdout.writeln('');

    if (AppConfig.hasDiawiToken) {
      stdout.writeln('  A Diawi token is already saved.');
      stdout.writeln('  1)  Keep current token');
      stdout.writeln('  2)  Replace token');
      stdout.writeln('  3)  Remove token');
      stdout.writeln('');
      stdout.write('  Choice [1/2/3]: ');
      final choice = stdin.readLineSync()?.trim() ?? '1';
      if (choice == '1') {
        Logger.ok('Kept current Diawi token.');
        return;
      }
      if (choice == '3') {
        AppConfig.clearDiawiToken();
        Logger.ok('Diawi token removed.');
        return;
      }
    }

    stdout.write('  Paste token: ');
    final token = stdin.readLineSync()?.trim() ?? '';
    if (token.isEmpty) {
      stdout.writeln('  No change made.');
      return;
    }
    AppConfig.saveDiawiToken(token);
    Logger.ok('Diawi token saved.');
  }

  // ── 6. Upload preferences ──────────────────────────────────────────────────

  Future<void> _editUploadPreferences() async {
    _section('Upload Preferences');
    stdout.writeln(
      '  When set, the tool will not ask about uploads on every run.',
    );
    stdout.writeln('');

    stdout.writeln('  Google Drive upload:');
    stdout.writeln('  1)  Always upload automatically');
    stdout.writeln('  2)  Never upload (keep APK local)');
    stdout.writeln('  3)  Ask me every run (default)');
    stdout.writeln('');
    stdout.write('  Choice [1/2/3]: ');
    final driveChoice = stdin.readLineSync()?.trim() ?? '3';
    switch (driveChoice) {
      case '1':
        AppConfig.saveAutoUploadDrive(true);
        Logger.ok('Drive upload: always upload.');
      case '2':
        AppConfig.saveAutoUploadDrive(false);
        Logger.ok('Drive upload: never upload.');
      default:
        AppConfig.clearUploadPreferences();
        Logger.ok('Drive upload: ask each run.');
    }

    stdout.writeln('');
    stdout.writeln('  Diawi (iOS) upload:');
    stdout.writeln('  1)  Always upload automatically');
    stdout.writeln('  2)  Never upload (keep IPA local)');
    stdout.writeln('  3)  Ask me every run (default)');
    stdout.writeln('');
    stdout.write('  Choice [1/2/3]: ');
    final diawiChoice = stdin.readLineSync()?.trim() ?? '3';
    switch (diawiChoice) {
      case '1':
        AppConfig.saveAutoUploadDiawi(true);
        Logger.ok('Diawi upload: always upload.');
      case '2':
        AppConfig.saveAutoUploadDiawi(false);
        Logger.ok('Diawi upload: never upload.');
      default:
        Logger.ok('Diawi upload: ask each run.');
    }
  }

  // ── 7. iOS export method ───────────────────────────────────────────────────

  String _exportMethodLabel() {
    final dir = AppConfig.projectDirectory;
    if (dir == null) return '\x1B[1;33mnot set\x1B[0m';
    final saved = ConfigStore(dir).load()['exportMethod'] as String?;
    return saved ?? '\x1B[1;33mnot set\x1B[0m';
  }

  Future<void> _editExportMethod() async {
    _section('iOS Export Method');

    final dir = AppConfig.projectDirectory;
    if (dir == null) {
      stdout.writeln(
          '  No project directory set. Configure it first (option 1).');
      return;
    }

    final store = ConfigStore(dir);
    final saved = store.load();
    final current = saved['exportMethod'] as String?;

    stdout.writeln('  How should the IPA be signed?');
    stdout.writeln('');
    stdout.writeln(
        '  1) development     — device must be registered in Apple Developer portal');
    stdout.writeln(
        '  2) release-testing — Ad Hoc (requires Ad Hoc provisioning profiles)');
    stdout.writeln('');

    final defaultIdx = current == 'release-testing' ? '2' : '1';
    if (current != null) {
      stdout.writeln('  Current: $current');
    }

    while (true) {
      stdout.write('  Enter choice [1/2] (default: $defaultIdx): ');
      final raw = stdin.readLineSync()?.trim() ?? '';
      final choice = raw.isEmpty ? defaultIdx : raw;
      final String method;
      switch (choice) {
        case '1':
          method = 'development';
        case '2':
          method = 'release-testing';
        default:
          stdout.writeln('  Please enter 1 or 2.');
          continue;
      }
      saved['exportMethod'] = method;
      store.save(saved);
      Logger.ok('iOS export method set to: $method');
      return;
    }
  }

  // ── 8. Android APK version ────────────────────────────────────────────────

  String _apkAbiLabel() {
    final dir = AppConfig.projectDirectory;
    if (dir == null) return '\x1B[1;33mnot set\x1B[0m';
    final saved = ConfigStore(dir).load()['apkAbi'] as String?;
    return saved ?? '\x1B[1;33mnot set\x1B[0m';
  }

  Future<void> _editApkAbi() async {
    _section('Android APK Version');

    final dir = AppConfig.projectDirectory;
    if (dir == null) {
      stdout.writeln(
          '  No project directory set. Configure it first (option 1).');
      return;
    }

    final store = ConfigStore(dir);
    final saved = store.load();
    final current = saved['apkAbi'] as String?;

    stdout.writeln(
        '  Flutter builds three APK variants. Which one should be uploaded?');
    stdout.writeln('');
    stdout.writeln(
        '  1) arm64-v8a   — 64-bit ARM  (recommended — covers most modern phones)');
    stdout.writeln(
        '  2) armeabi-v7a — 32-bit ARM  (for older Android devices)');
    stdout.writeln(
        '  3) x86_64      — 64-bit x86  (for emulators)');
    stdout.writeln('');

    final defaultIdx = switch (current) {
      'armeabi-v7a' => '2',
      'x86_64' => '3',
      _ => '1',
    };
    if (current != null) {
      stdout.writeln('  Current: $current');
    }

    while (true) {
      stdout.write('  Enter choice [1/2/3] (default: $defaultIdx): ');
      final raw = stdin.readLineSync()?.trim() ?? '';
      final choice = raw.isEmpty ? defaultIdx : raw;
      final String abi;
      switch (choice) {
        case '1':
          abi = 'arm64-v8a';
        case '2':
          abi = 'armeabi-v7a';
        case '3':
          abi = 'x86_64';
        default:
          stdout.writeln('  Please enter 1, 2, or 3.');
          continue;
      }
      saved['apkAbi'] = abi;
      store.save(saved);
      Logger.ok('Android APK version set to: $abi');
      return;
    }
  }

  // ── 9. Reset ───────────────────────────────────────────────────────────────

  Future<void> _resetConfiguration() async {
    _section('Reset Configuration');
    stdout.writeln('  This clears all saved settings from this machine.');
    stdout.writeln(
        '  The rclone remote (Google Drive connection) is NOT deleted.');
    stdout.writeln('');
    stdout.write('  Type "yes" to confirm reset: ');
    final answer = stdin.readLineSync()?.trim().toLowerCase() ?? '';
    if (answer != 'yes') {
      stdout.writeln('  Reset cancelled.');
      return;
    }
    AppConfig.resetAll();
    Logger.ok(
        'Configuration reset. Run flutter_release_manager init to reconfigure.');
  }

  // ── UI helpers ─────────────────────────────────────────────────────────────

  void _section(String title) {
    final pad = title.length < 40 ? '─' * (40 - title.length) : '';
    stdout.writeln('  ─── $title $pad');
    stdout.writeln('');
  }
}
