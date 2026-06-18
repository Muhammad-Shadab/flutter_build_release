import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'app_config.dart';
import 'logger.dart';
import 'process_utils.dart';

/// Handles rclone binary management and Google Drive remote lifecycle.
///
/// All rclone subprocesses are fully non-interactive:
///   - stdin is closed immediately to send EOF to any blocking read
///   - output is monitored for interactive-prompt patterns; process is killed
///     if any are detected
///   - `rclone config reconnect` is NEVER called (it prompts when token exists)
class RcloneManager {
  static const _oldRemoteName = 'flutter_build_release';
  static String get remoteName => AppConfig.remoteName;

  // ── Binary detection ───────────────────────────────────────────────────────

  static bool isInstalled() {
    final result = Process.runSync(
      'rclone',
      ['version'],
      runInShell: true,
    );
    return result.exitCode == 0;
  }

  static String installedVersion() {
    final result = Process.runSync('rclone', ['version'], runInShell: true);
    if (result.exitCode != 0) return 'unknown';
    return (result.stdout as String).split('\n').first.trim();
  }

  // ── Installation ───────────────────────────────────────────────────────────

  static Future<void> ensureInstalled() async {
    if (isInstalled()) {
      Logger.ok('rclone — ${installedVersion()}');
      return;
    }

    Logger.skip('rclone not found — attempting automatic installation...');
    stdout.writeln('');

    if (Platform.isMacOS) {
      await _installMacOS();
    } else if (Platform.isLinux) {
      await _installLinux();
    } else if (Platform.isWindows) {
      _printWindowsInstructions();
      stdout.write(
        '  Press Enter after installing rclone to continue: ',
      );
      stdin.readLineSync();
    } else {
      stderr.writeln(
        '  ❌  Cannot auto-install rclone on this platform.\n'
        '      Visit https://rclone.org/install/ for instructions.',
      );
      exit(1);
    }

    if (!isInstalled()) {
      stderr.writeln(
        '\n  ❌  rclone is still not found after installation attempt.\n'
        '      Visit https://rclone.org/install/ and install manually,\n'
        '      then re-run: flutter_release_manager init\n',
      );
      exit(1);
    }

    Logger.ok('rclone installed — ${installedVersion()}');
  }

  static Future<void> _installMacOS() async {
    if (Process.runSync('which', ['brew']).exitCode != 0) {
      stderr.writeln(
        '  ❌  Homebrew not found.\n'
        '      Install it from https://brew.sh then re-run init.',
      );
      exit(1);
    }
    Logger.step('Installing rclone via Homebrew...');
    final code = await runLive('brew', ['install', 'rclone']);
    if (code != 0) {
      stderr.writeln('  ❌  brew install rclone failed.');
      exit(1);
    }
  }

  static Future<void> _installLinux() async {
    if (Process.runSync('which', ['apt-get']).exitCode != 0) {
      stderr.writeln(
        '  ❌  apt-get not found.\n'
        '      Visit https://rclone.org/install/ for manual install.',
      );
      exit(1);
    }
    Logger.step('Installing rclone via apt-get...');
    final code = await runLive('sudo', ['apt-get', 'install', '-y', 'rclone']);
    if (code != 0) {
      stderr.writeln('  ❌  apt-get install rclone failed.');
      exit(1);
    }
  }

  static void _printWindowsInstructions() {
    stdout.writeln('  rclone is not installed. Options:');
    stdout.writeln('');
    stdout.writeln('  Option 1 — winget (recommended):');
    stdout.writeln('    winget install Rclone.Rclone');
    stdout.writeln('');
    stdout.writeln('  Option 2 — Chocolatey:');
    stdout.writeln('    choco install rclone');
    stdout.writeln('');
    stdout.writeln('  Option 3 — Manual:');
    stdout.writeln('    https://rclone.org/install/#windows');
    stdout.writeln('');
  }

  // ── Remote auth lifecycle ──────────────────────────────────────────────────

  /// Ensures the Drive remote exists with a valid OAuth token.
  ///
  /// Scenarios handled without any interactive rclone prompts:
  ///   - Upgrade from flutter_build_release: migrates old remote, no re-auth
  ///   - New user: opens browser OAuth, embeds token in config
  ///   - Existing valid token: no-op
  ///   - Expired / revoked token: deletes stale config, re-authorizes
  static Future<void> ensureRemoteAndAuthenticated() async {
    _migrateOldRemoteIfNeeded();

    if (remoteExists()) {
      Logger.step('Remote "$remoteName" found — verifying token...');
      if (await _verifyConnectionQuiet()) {
        Logger.ok('Google Drive — token is valid.');
        return;
      }
      Logger.skip('Token is invalid or expired — re-authorizing...');
      _deleteRemoteConfig();
    }

    final tokenJson = await _obtainOAuthTokenViaBrowser();
    Logger.ok('Authorization complete.');
    Logger.step('Saving credentials to rclone remote "$remoteName"...');
    _createRemoteWithToken(tokenJson);
    Logger.ok('Remote "$remoteName" configured.');
    // Cache the account email now while the token is fresh.
    await fetchAndCacheEmail();
  }

  // ── Remote helpers ─────────────────────────────────────────────────────────

  static bool remoteExists() {
    final result = Process.runSync('rclone', ['listremotes'], runInShell: true);
    if (result.exitCode != 0) return false;
    return (result.stdout as String)
        .split('\n')
        .any((r) => r.trim() == '$remoteName:');
  }

  /// Migrates the old flutter_build_release rclone remote to flutter_release_manager.
  /// Extracts the stored OAuth token from the old remote and creates the new one.
  /// Users retain full Google Drive access — no re-authentication required.
  static void migrateOldRemoteIfNeeded() => _migrateOldRemoteIfNeeded();

  static void _migrateOldRemoteIfNeeded() {
    if (remoteExists()) return; // new remote already present

    final listResult = Process.runSync(
      'rclone',
      ['listremotes'],
      runInShell: true,
    );
    if (listResult.exitCode != 0) return;

    final hasOldRemote = (listResult.stdout as String)
        .split('\n')
        .any((r) => r.trim() == '$_oldRemoteName:');
    if (!hasOldRemote) return;

    // Dump rclone config JSON to extract the old remote's OAuth token.
    final dumpResult = Process.runSync(
      'rclone',
      ['config', 'dump'],
      runInShell: true,
    );
    if (dumpResult.exitCode != 0) return;

    try {
      final all =
          jsonDecode(dumpResult.stdout as String) as Map<String, dynamic>;
      final oldConfig = all[_oldRemoteName] as Map<String, dynamic>?;
      if (oldConfig == null) return;

      final tokenJson = oldConfig['token'] as String?;
      if (tokenJson == null || tokenJson.isEmpty) return;

      Logger.step(
        'Migrating rclone remote: $_oldRemoteName → $remoteName...',
      );
      _createRemoteWithToken(tokenJson);
      Logger.ok(
        'Remote migrated. Your Google Drive access is fully preserved.',
      );
    } catch (_) {}
  }

  // ── Account email ──────────────────────────────────────────────────────────

  /// Cached email for the connected Google account (null = not yet fetched).
  static String? get connectedEmail => AppConfig.driveEmail;

  /// Deletes the rclone remote. Caller is responsible for clearing AppConfig.
  static void deleteRemote() => _deleteRemoteConfig();

  /// Extracts the OAuth token stored by rclone, calls Google's userinfo
  /// endpoint to read the account email, and caches it in AppConfig.
  ///
  /// Calls `rclone about` first so rclone refreshes an expired access token
  /// before we attempt to read it. Returns null on any failure.
  static Future<String?> fetchAndCacheEmail() async {
    if (!remoteExists()) return null;

    final cached = AppConfig.driveEmail;
    if (cached != null) return cached;

    // Trigger token refresh through rclone before reading the stored token.
    Process.runSync('rclone', ['about', '$remoteName:'], runInShell: true);

    final tokenJson = _getStoredTokenJson();
    if (tokenJson == null) return null;

    try {
      final token = jsonDecode(tokenJson) as Map<String, dynamic>;
      final accessToken = token['access_token'] as String?;
      if (accessToken == null) return null;

      final res = await http.get(
        Uri.parse('https://www.googleapis.com/oauth2/v2/userinfo'),
        headers: {'Authorization': 'Bearer $accessToken'},
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final email = data['email'] as String?;
      if (email != null) AppConfig.saveDriveEmail(email);
      return email;
    } catch (_) {
      return null;
    }
  }

  /// Reads the raw OAuth token JSON from `rclone config dump`.
  static String? _getStoredTokenJson() {
    final result =
        Process.runSync('rclone', ['config', 'dump'], runInShell: true);
    if (result.exitCode != 0) return null;
    try {
      final all = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      final remote = all[remoteName] as Map<String, dynamic>?;
      return remote?['token'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Returns true if the remote can reach Google Drive (token is valid).
  static Future<bool> _verifyConnectionQuiet() async {
    final result = Process.runSync(
      'rclone',
      ['about', '$remoteName:'],
      runInShell: true,
    );
    return result.exitCode == 0;
  }

  static void _deleteRemoteConfig() {
    Logger.step('Removing stale remote config...');
    Process.runSync(
      'rclone',
      ['config', 'delete', remoteName],
      runInShell: true,
    );
  }

  /// Runs `rclone authorize drive` — browser-only, completely non-interactive.
  ///
  /// stdin is closed immediately (EOF). Output is monitored for interactive
  /// prompts; if any are detected the process is killed and init aborts.
  /// Returns the raw OAuth token JSON string extracted from rclone's output.
  static Future<String> _obtainOAuthTokenViaBrowser() async {
    Logger.step('Opening browser for Google sign-in...');

    final process = await Process.start(
      'rclone',
      ['authorize', 'drive'],
      runInShell: Platform.isWindows,
    );

    // Send EOF to rclone's stdin immediately — prevents any blocking read.
    process.stdin.close().ignore();

    Logger.step('Waiting for Google authorization (up to 5 minutes)...');

    final buffer = StringBuffer();

    // Capture output only — do not forward raw rclone output to the terminal.
    final stdoutSub =
        process.stdout.transform(systemEncoding.decoder).listen((chunk) {
      buffer.write(chunk);
      if (_hasInteractivePrompt(chunk)) process.kill();
    });

    final stderrSub =
        process.stderr.transform(systemEncoding.decoder).listen((chunk) {
      buffer.write(chunk);
      if (_hasInteractivePrompt(chunk)) process.kill();
    });

    late final int exitCode;
    try {
      exitCode = await process.exitCode.timeout(const Duration(minutes: 5));
    } on TimeoutException {
      process.kill();
      await stdoutSub.cancel();
      await stderrSub.cancel();
      stderr.writeln(
        '\n  ❌  OAuth timed out after 5 minutes.\n'
        '      Re-run: flutter_release_manager init\n',
      );
      exit(1);
    }

    await stdoutSub.cancel();
    await stderrSub.cancel();

    if (exitCode != 0) {
      stderr.writeln(
        '\n  ❌  rclone authorize failed (exit $exitCode).\n'
        '      Re-run: flutter_release_manager init\n',
      );
      exit(1);
    }

    final output = buffer.toString();
    final match = RegExp(r'---+>\s*([\s\S]*?)\s*<---').firstMatch(output);
    final tokenJson = match?.group(1)?.trim();

    if (tokenJson == null || tokenJson.isEmpty) {
      stderr.writeln(
        '\n  ❌  Could not extract OAuth token from rclone output.\n'
        '      Re-run: flutter_release_manager init\n',
      );
      exit(1);
    }

    return tokenJson;
  }

  /// Creates the rclone remote with the OAuth token pre-embedded.
  /// Uses runInShell: false so the token JSON is never shell-interpreted.
  static void _createRemoteWithToken(String tokenJson) {
    final result = Process.runSync(
      'rclone',
      [
        'config',
        'create',
        remoteName,
        'drive',
        'scope',
        'drive',
        'token',
        tokenJson,
      ],
      runInShell: false,
    );
    if (result.exitCode != 0) {
      stderr.writeln(
        '  ❌  Failed to create rclone remote: ${result.stderr}',
      );
      exit(1);
    }
  }

  /// Returns true if [text] contains any pattern that indicates rclone is
  /// waiting for interactive input. The process must be killed immediately.
  static bool _hasInteractivePrompt(String text) {
    return RegExp(
      r'y\) Yes|n\) No|Already have a token|Choose a number from below|\[y/n\]',
      caseSensitive: false,
    ).hasMatch(text);
  }

  // ── Verification ───────────────────────────────────────────────────────────

  /// Verifies the remote can reach Google Drive and prints quota info.
  static Future<void> verifyRemote() async {
    Logger.step('Verifying Google Drive connection...');

    final result = Process.runSync(
      'rclone',
      ['about', '$remoteName:'],
      runInShell: true,
    );

    if (result.exitCode != 0) {
      stderr.writeln(
        '\n  ❌  Could not connect to Google Drive.\n'
        '      Re-run: flutter_release_manager init\n',
      );
      exit(1);
    }

    Logger.ok('Google Drive — connected');
    for (final line in (result.stdout as String).trim().split('\n')) {
      if (line.trim().isNotEmpty) Logger.info(line.trim());
    }
  }

  // ── Folder listing ─────────────────────────────────────────────────────────

  static List<String> listTopLevelFolders() {
    final result = Process.runSync(
      'rclone',
      ['lsf', '$remoteName:', '--dirs-only'],
      runInShell: true,
    );
    if (result.exitCode != 0) return [];
    return (result.stdout as String)
        .split('\n')
        .map((s) => s.trim().replaceAll('/', ''))
        .where((s) => s.isNotEmpty)
        .toList();
  }

  static bool folderExists(String folderName) {
    return listTopLevelFolders().contains(folderName);
  }
}
