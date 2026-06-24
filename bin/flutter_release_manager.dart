import 'dart:io';

import 'package:flutter_release_manager/src/android_builder.dart';
import 'package:flutter_release_manager/src/config_command.dart';
import 'package:flutter_release_manager/src/doctor_command.dart';
import 'package:flutter_release_manager/src/init_command.dart';
import 'package:flutter_release_manager/src/ios_builder.dart';
import 'package:flutter_release_manager/src/logger.dart';
import 'package:flutter_release_manager/src/reset_command.dart';
import 'package:flutter_release_manager/src/version.dart';
import 'package:flutter_release_manager/src/wizard.dart';

Future<void> main(List<String> args) async {
  // When running from a JIT snapshot, Platform.script returns the snapshot
  // path. If the lock file (rewritten by every `dart pub global activate`) is
  // newer than the snapshot, the snapshot was compiled before this activation
  // and may contain stale code.
  //
  // We relaunch directly from source (dart run <entrypoint>) instead of
  // exiting with code 253. Exit 253 causes the pub launcher to fall back to
  // `dart pub -v global run`, which floods output with FINE/SLVR/IO/MSG logs.
  // Relaunching via Process.start bypasses pub entirely — zero verbose output.
  if (await _relaunchIfSnapshotStale(args)) return;

  if (args.isNotEmpty &&
      (args.first == 'version' ||
          args.first == '--version' ||
          args.first == '-v')) {
    _printVersion();
    return;
  }

  if (args.isNotEmpty && args.first == 'init') {
    await InitCommand().run();
    return;
  }

  if (args.isNotEmpty && args.first == 'doctor') {
    await DoctorCommand().run();
    return;
  }

  if (args.isNotEmpty && args.first == 'config') {
    await ConfigCommand().run();
    return;
  }

  if (args.isNotEmpty && args.first == 'reset') {
    await ResetCommand.production().run(args.sublist(1));
    return;
  }

  // Default: build + upload.
  final config = await Wizard().run(args);

  String? driveUrl;
  String? diawiUrl;

  if (config.buildAndroid) driveUrl = await AndroidBuilder(config).build();
  if (config.buildIos) diawiUrl = await IosBuilder(config).build();

  Logger.header('Build complete');

  if (driveUrl != null || diawiUrl != null) {
    stdout.writeln('');
    if (driveUrl != null) {
      stdout.writeln('  Android APK:');
      stdout.writeln('  $driveUrl');
      stdout.writeln('');
    }
    if (diawiUrl != null) {
      stdout.writeln('  iOS IPA (Diawi):');
      stdout.writeln('  $diawiUrl');
      stdout.writeln('');
    }
  }
}

/// Ensures the bin/ JIT snapshot is current and relaunches from it when needed.
///
/// The pub launcher script checks for a snapshot at:
///   `<sourcePath>/bin/<executable>.dart-<sdkVersion>.snapshot`
/// If that file exists, it runs it directly — no pub overhead. If it does not
/// exist, the launcher falls back to `dart pub global run`, which resolves
/// dependencies on every invocation and outputs "Resolving dependencies..."
/// plus package update notices regardless of whether anything changed.
///
/// This function fires in two cases that both require recompiling to bin/:
///   1. bin/ snapshot is MISSING — first run after activation, launcher used
///      `dart pub global run` to reach us via .dart_tool/; recompile so the
///      next run bypasses pub entirely.
///   2. bin/ snapshot is STALE — lock file is newer than bin/ snapshot,
///      meaning a new `dart pub global activate` ran since the last compile.
///      Rather than exiting 253 (which triggers `dart pub -v global run` and
///      floods output with FINE/SLVR/IO/MSG logs), we recompile directly.
///
/// Only applies to path-sourced packages (`source: path` in the lock file).
/// Pub.dev installs always produce a fresh snapshot on activation.
///
/// Returns true if the process was relaunched (caller should return
/// immediately); false if the bin/ snapshot is current or the check does not
/// apply.
Future<bool> _relaunchIfSnapshotStale(List<String> args) async {
  final scriptPath = Platform.script.toFilePath();
  if (!scriptPath.endsWith('.snapshot')) return false;

  if (!File(scriptPath).existsSync()) return false;

  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '';
  final lockFile =
      File('$home/.pub-cache/global_packages/$packageName/pubspec.lock');
  if (!lockFile.existsSync()) return false;

  // Only relaunch for path-sourced packages; pub.dev installs are always fresh.
  final sourcePath = _extractPathSource(lockFile);
  if (sourcePath == null) return false;

  final entryPoint = '$sourcePath/bin/$packageName.dart';
  if (!File(entryPoint).existsSync()) return false;

  // The snapshot filename is the same across bin/ and .dart_tool/pub/bin/…/,
  // so extract it from Platform.script to derive the correct bin/ target.
  final snapshotName = scriptPath.split('/').last;
  final targetSnapshot = '$sourcePath/bin/$snapshotName';

  final lockMs = lockFile.lastModifiedSync().millisecondsSinceEpoch;
  final binFile = File(targetSnapshot);
  final binMs =
      binFile.existsSync() ? binFile.lastModifiedSync().millisecondsSinceEpoch : 0;

  // bin/ snapshot is current — nothing to do.
  if (binMs >= lockMs) return false;

  // bin/ snapshot is missing or stale — recompile to bin/ and run.
  // `dart --snapshot=path --snapshot-kind=app-jit` runs the program normally
  // (output straight to terminal, zero pub overhead) while saving a
  // JIT-trained snapshot so future runs bypass pub entirely.
  final process = await Process.start(
    Platform.resolvedExecutable,
    ['--snapshot=$targetSnapshot', '--snapshot-kind=app-jit', entryPoint, ...args],
    mode: ProcessStartMode.inheritStdio,
  );
  exit(await process.exitCode);
}

/// Extracts the `path:` value from a pub global lock file for path-sourced
/// packages. Returns null when the lock file does not describe a path source.
String? _extractPathSource(File lockFile) {
  try {
    final content = lockFile.readAsStringSync();
    if (!content.contains('source: path')) return null;
    final match = RegExp(r'path:\s+"([^"]+)"').firstMatch(content);
    return match?.group(1);
  } catch (_) {
    return null;
  }
}

void _printVersion() {
  stdout.writeln('');
  stdout.writeln('  $packageName $packageVersion');
  stdout.writeln('');
  stdout.writeln('  Build · Archive · Distribute');
  stdout.writeln('');
  stdout.writeln('  Package: $packageName');
  stdout.writeln('  Version: $packageVersion');
  stdout.writeln('');
}
