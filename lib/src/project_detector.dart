import 'dart:io';

class ProjectDetector {
  static String? detectAppDir() {
    final cwd = Directory.current.path;
    if (_isFlutterProject(cwd)) return cwd;
    return null;
  }

  static String? readAppName(String appDir) {
    final pubspec = File('$appDir/pubspec.yaml');
    if (!pubspec.existsSync()) return null;
    for (final line in pubspec.readAsLinesSync()) {
      // Only match a top-level name: key — no leading whitespace in the raw line.
      if (line.startsWith('name:')) {
        final raw =
            line.substring(5).trim().replaceAll('"', '').replaceAll("'", '');
        return _toPascalCase(raw);
      }
    }
    return null;
  }

  static bool _isFlutterProject(String dir) {
    final f = File('$dir/pubspec.yaml');
    if (!f.existsSync()) return false;
    final content = f.readAsStringSync();
    return content.contains('sdk: flutter') ||
        RegExp(r'^flutter:', multiLine: true).hasMatch(content);
  }

  static String _toPascalCase(String input) => input
      .split(RegExp(r'[_\-\s]+'))
      .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
      .join('');
}
