import 'dart:io';

import 'app_config.dart';
import 'logger.dart';
import 'rclone_manager.dart';

/// Implements `flutter_release_manager init`.
///
/// Steps:
///   1. Detect / install rclone.
///   2. Detect / create the "flutter_release_manager" Google Drive remote.
///   3. Verify the remote can connect to Drive.
///   4. List root Drive folders and let the user pick one.
///   5. Ask for Diawi API token (optional).
///   6. Save config to ~/.config/flutter_release_manager/config.json.
class InitCommand {
  Future<void> run() async {
    _printBanner();

    // Migrate machine config and Diawi token from previous package names.
    AppConfig.migrateFromOldPackageName();
    AppConfig.migrateFromCredentialsJson();

    // ── STEP 1: rclone ───────────────────────────────────────────────────────
    _printStep(1, 'rclone');
    await RcloneManager.ensureInstalled();

    // ── STEP 2: Google Drive remote ──────────────────────────────────────────
    _printStep(2, 'Google Drive Remote');
    await RcloneManager.ensureRemoteAndAuthenticated();

    // ── STEP 3: Verify connection ────────────────────────────────────────────
    _printStep(3, 'Verify Connection');
    await RcloneManager.verifyRemote();

    // ── STEP 4: Select Drive folder ──────────────────────────────────────────
    _printStep(4, 'Drive Folder');
    final folderName = _selectFolder();

    // ── STEP 5: Diawi token ──────────────────────────────────────────────────
    _printStep(5, 'Diawi Token (optional)');
    final diawiToken = _askDiawiToken();

    // ── Save ─────────────────────────────────────────────────────────────────
    AppConfig.saveFolderName(folderName);
    if (diawiToken != null) AppConfig.saveDiawiToken(diawiToken);

    stdout.writeln('');
    Logger.ok('Configuration saved to ${AppConfig.path}');
    stdout.writeln('');
    stdout.writeln('  Setup complete.');
    stdout.writeln('  Run flutter_release_manager to build and upload.');
    stdout.writeln('');
  }

  // ── Folder selection ───────────────────────────────────────────────────────

  String _selectFolder() {
    stdout.writeln('  Fetching top-level folders from your Google Drive...');
    stdout.writeln('');

    final folders = RcloneManager.listTopLevelFolders();

    if (folders.isEmpty) {
      stdout.writeln('  No folders found in the root of your Google Drive.');
      stdout.writeln('  Create a folder in Google Drive first, then re-run:');
      stdout.writeln('    flutter_release_manager init');
      stdout.writeln('');
      stdout.writeln('  Or enter a folder name to create it on first upload:');
      return _promptFolderName(null);
    }

    for (var i = 0; i < folders.length; i++) {
      stdout.writeln('  ${i + 1}. ${folders[i]}');
    }
    stdout.writeln('  ${folders.length + 1}. Enter folder name manually');
    stdout.writeln('');

    while (true) {
      stdout.write('  Select destination folder [1-${folders.length + 1}]: ');
      final raw = stdin.readLineSync()?.trim() ?? '';
      final choice = int.tryParse(raw);

      if (choice == null || choice < 1 || choice > folders.length + 1) {
        stderr.writeln(
          '  ❌  Enter a number between 1 and ${folders.length + 1}.',
        );
        continue;
      }

      if (choice == folders.length + 1) {
        return _promptFolderName(null);
      }

      final selected = folders[choice - 1];
      Logger.ok('Drive folder: $selected');
      return selected;
    }
  }

  String _promptFolderName(String? defaultValue) {
    while (true) {
      if (defaultValue != null) {
        stdout.write('  Drive folder name [$defaultValue]: ');
      } else {
        stdout.write('  Drive folder name: ');
      }
      final raw = stdin.readLineSync()?.trim() ?? '';
      final name = raw.isEmpty && defaultValue != null ? defaultValue : raw;
      if (name.isNotEmpty) {
        Logger.ok('Drive folder: $name');
        return name;
      }
      stderr.writeln('  ❌  Folder name cannot be empty.');
    }
  }

  // ── Diawi token ────────────────────────────────────────────────────────────

  String? _askDiawiToken() {
    stdout.writeln('');
    stdout.writeln(
        '  \x1B[0;36mℹ\x1B[0m  Diawi gives testers an install link for iOS builds.');
    stdout.writeln(
        '  \x1B[0;36mℹ\x1B[0m  Sign up at diawi.com → Account → API Access Tokens.');
    stdout.writeln(
        '  \x1B[0;36mℹ\x1B[0m  Press Enter to skip if you don\'t need iOS uploads.');
    stdout.writeln('');

    final existing = AppConfig.diawiToken;
    if (existing != null) {
      stdout.write('  Diawi API token [already saved — Enter to keep]: ');
      final raw = stdin.readLineSync()?.trim() ?? '';
      if (raw.isEmpty) {
        Logger.ok('Existing Diawi token kept.');
        return null;
      }
      Logger.ok('Diawi token updated.');
      return raw;
    }

    stdout.write('  Diawi API token (or Enter to skip): ');
    final token = stdin.readLineSync()?.trim() ?? '';
    if (token.isEmpty) return null;
    Logger.ok('Diawi token saved.');
    return token;
  }

  // ── UI helpers ─────────────────────────────────────────────────────────────

  void _printBanner() {
    stdout.writeln('');
    stdout.writeln('╔══════════════════════════════════════════════╗');
    stdout.writeln('  flutter_release_manager — init');
    stdout.writeln('  One-time Google Drive setup');
    stdout.writeln('╚══════════════════════════════════════════════╝');
    stdout.writeln('');
    stdout.writeln('  This wizard will:');
    stdout.writeln('    • Install rclone if needed');
    stdout.writeln('    • Sign you into Google Drive (browser opens once)');
    stdout.writeln('    • Select your destination Drive folder');
    stdout.writeln('    • Optionally save your Diawi token');
    stdout.writeln('');
    stdout.writeln('  No Google Cloud Console. No Client IDs. No secrets.');
    stdout.writeln('');
  }

  void _printStep(int n, String title) {
    stdout.writeln('');
    stdout.writeln('╔══════════════════════════════════════════════╗');
    stdout.writeln('  Step $n — $title');
    stdout.writeln('╚══════════════════════════════════════════════╝');
    stdout.writeln('');
  }
}
