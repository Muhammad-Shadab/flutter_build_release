import 'dart:convert';
import 'dart:io';

/// Machine-level config at ~/.config/flutter_release_manager/config.json.
/// Stores: rclone remote name, Drive folder, Diawi token, project directory,
/// upload preferences. No OAuth credentials — rclone owns authentication.
class AppConfig {
  static const remoteName = 'flutter_release_manager';

  static String get _dir {
    if (Platform.isLinux) {
      final xdg = Platform.environment['XDG_CONFIG_HOME'];
      if (xdg != null && xdg.isNotEmpty) return '$xdg/flutter_release_manager';
    }
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return '$appData/flutter_release_manager';
      }
    }
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return '$home/.config/flutter_release_manager';
  }

  static String get _oldDir {
    if (Platform.isLinux) {
      final xdg = Platform.environment['XDG_CONFIG_HOME'];
      if (xdg != null && xdg.isNotEmpty) return '$xdg/flutter_build_release';
    }
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return '$appData/flutter_build_release';
      }
    }
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return '$home/.config/flutter_build_release';
  }

  static String get path => '$_dir/config.json';

  static Map<String, dynamic> load() {
    final file = File(path);
    if (!file.existsSync()) return {};
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  static void _write(Map<String, dynamic> data) {
    final dir = Directory(_dir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File(path);
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
    if (!Platform.isWindows) {
      Process.runSync('chmod', ['700', dir.path]);
      Process.runSync('chmod', ['600', file.path]);
    }
  }

  static void save(Map<String, dynamic> values) {
    final current = load();
    current.addAll(values);
    _write(current);
  }

  // ── Getters ────────────────────────────────────────────────────────────────

  static String? get folderName {
    final v = load()['folderName'];
    return v is String && v.isNotEmpty ? v : null;
  }

  static String? get diawiToken {
    final v = load()['diawiToken'];
    return v is String && v.isNotEmpty ? v : null;
  }

  static String? get projectDirectory {
    final v = load()['projectDirectory'];
    return v is String && v.isNotEmpty ? v : null;
  }

  /// null = not set (will ask). true/false = remembered preference.
  static bool? get autoUploadDrive {
    final v = load()['autoUploadDrive'];
    return v is bool ? v : null;
  }

  /// null = not set (will ask). true/false = remembered preference.
  static bool? get autoUploadDiawi {
    final v = load()['autoUploadDiawi'];
    return v is bool ? v : null;
  }

  static String? get driveEmail {
    final v = load()['driveEmail'];
    return v is String && v.isNotEmpty ? v : null;
  }

  static bool get isConfigured => folderName != null;
  static bool get hasDiawiToken => diawiToken != null;

  // ── Setters ────────────────────────────────────────────────────────────────

  static void saveDriveEmail(String email) => save({'driveEmail': email});

  static void clearDriveEmail() {
    final current = load();
    current.remove('driveEmail');
    _write(current);
  }

  static void saveFolderName(String folder) =>
      save({'folderName': folder, 'remote': remoteName});

  static void saveDiawiToken(String token) => save({'diawiToken': token});

  static void saveProjectDirectory(String dir) =>
      save({'projectDirectory': dir});

  static void saveAutoUploadDrive(bool value) =>
      save({'autoUploadDrive': value});

  static void saveAutoUploadDiawi(bool value) =>
      save({'autoUploadDiawi': value});

  static void clearProjectDirectory() {
    final current = load();
    current.remove('projectDirectory');
    _write(current);
  }

  static void clearDiawiToken() {
    final current = load();
    current.remove('diawiToken');
    _write(current);
  }

  static void clearUploadPreferences() {
    final current = load();
    current.remove('autoUploadDrive');
    current.remove('autoUploadDiawi');
    _write(current);
  }

  /// Wipes all config. The rclone remote itself is NOT deleted.
  static void resetAll() => _write({});

  // ── Migration ──────────────────────────────────────────────────────────────

  static void migrateFromOldPackageName() {
    if (Directory(_dir).existsSync()) return;
    final oldConfig = File('$_oldDir/config.json');
    if (!oldConfig.existsSync()) return;
    try {
      final data = jsonDecode(oldConfig.readAsStringSync());
      if (data is! Map<String, dynamic>) return;
      _write(data);
      stdout.writeln(
        '  Existing flutter_build_release configuration migrated to '
        'flutter_release_manager.',
      );
    } catch (_) {}
  }

  static void migrateFromCredentialsJson() {
    for (final dir in [_dir, _oldDir]) {
      final oldFile = File('$dir/credentials.json');
      if (!oldFile.existsSync()) continue;
      try {
        final old = jsonDecode(oldFile.readAsStringSync());
        if (old is! Map<String, dynamic>) continue;
        final token = old['diawiToken'];
        if (token is String && token.isNotEmpty && !hasDiawiToken) {
          saveDiawiToken(token);
        }
      } catch (_) {}
    }
  }
}
