import 'dart:io';

/// Runs [executable] with [args], streaming stdout/stderr live.
/// Returns the exit code.
Future<int> runLive(
  String executable,
  List<String> args, {
  String? workingDirectory,
}) async {
  final process = await Process.start(
    executable,
    args,
    workingDirectory: workingDirectory,
  );
  await Future.wait([
    stdout.addStream(process.stdout),
    stderr.addStream(process.stderr),
  ]);
  return process.exitCode;
}