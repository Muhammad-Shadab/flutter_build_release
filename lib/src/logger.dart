import 'dart:io';

class Logger {
  static const _reset = '\x1B[0m';
  static const _red = '\x1B[0;31m';
  static const _green = '\x1B[0;32m';
  static const _yellow = '\x1B[1;33m';
  static const _cyan = '\x1B[0;36m';
  static const _bold = '\x1B[1m';

  static void header(String text) {
    stdout.writeln('\n╔══════════════════════════════════════════════╗');
    stdout.writeln('  $text');
    stdout.writeln('╚══════════════════════════════════════════════╝');
  }

  static void step(String text) => stdout.writeln('  $_cyan→$_reset  $text');
  static void ok(String text) => stdout.writeln('  $_green✓$_reset  $text');
  static void skip(String text) => stdout.writeln('  $_yellow⚠$_reset  $text');
  static void error(String text) => stderr.writeln('  $_red✗$_reset  $text');
  static void info(String text) => stdout.writeln('  $_boldℹ$_reset  $text');
}