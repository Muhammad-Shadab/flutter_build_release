import 'dart:convert';
import 'dart:io';

/// Project-level settings stored inside the Flutter project directory.
/// Machine-level settings (Drive folder, Diawi token) live in AppConfig.
class ConfigStore {
  final String _path;

  ConfigStore(String appDir)
      : _path = '$appDir/.flutter_release_manager_config.json' {
    _migrateFromOldFilename(appDir);
  }

  String get path => _path;

  Map<String, dynamic> load() {
    final file = File(_path);
    if (!file.existsSync()) return {};
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  void save(Map<String, dynamic> values) {
    try {
      // Strip all credential and Drive-config keys — these live in AppConfig.
      values
        ..remove('diawiToken')
        ..remove('driveRefreshToken')
        ..remove('driveFolderId')
        ..remove('flavour')
        ..remove('rcloneRemote');

      File(_path).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(values),
      );
      _ensureGitignore();
    } catch (_) {}
  }

  // ── Migration ──────────────────────────────────────────────────────────────

  /// Copies the old flutter_build_release config file to the new name on first
  /// run after rename. Only runs if the new file does not yet exist.
  void _migrateFromOldFilename(String appDir) {
    if (File(_path).existsSync()) return;
    final oldFile = File('$appDir/.flutter_build_release_config.json');
    if (!oldFile.existsSync()) return;
    try {
      oldFile.copySync(_path);
      stdout.writeln(
        '  Project config migrated: .flutter_build_release_config.json '
        '→ .flutter_release_manager_config.json',
      );
    } catch (_) {}
  }

  // ── Gitignore ──────────────────────────────────────────────────────────────

  void _ensureGitignore() {
    final appDir = File(_path).parent.path;
    final gitignore = File('$appDir/.gitignore');
    const entry = '.flutter_release_manager_config.json';
    if (!gitignore.existsSync()) return;
    final content = gitignore.readAsStringSync();
    if (content.contains(entry)) return;
    final separator = content.endsWith('\n') ? '' : '\n';
    gitignore.writeAsStringSync('$content$separator$entry\n');
  }
}
