import 'dart:async';
import 'dart:io';

/// Runs [executable] with [args], streaming stdout/stderr live.
/// Kills the process and throws [TimeoutException] if it exceeds [timeout].
/// Returns the exit code on success.
Future<int> runLive(
  String executable,
  List<String> args, {
  String? workingDirectory,
  Duration timeout = const Duration(minutes: 20),
}) async {
  final process = await Process.start(
    executable,
    args,
    workingDirectory: workingDirectory,
  );

  // Pipe output without blocking — exitCode drives the await.
  process.stdout.listen(stdout.add);
  process.stderr.listen(stderr.add);

  try {
    return await process.exitCode.timeout(timeout);
  } on TimeoutException {
    process.kill(ProcessSignal.sigterm);
    await Future<void>.delayed(const Duration(seconds: 3));
    process.kill(ProcessSignal.sigkill);
    throw TimeoutException(
      '$executable timed out after ${timeout.inMinutes} minutes and was killed.',
    );
  }
}
