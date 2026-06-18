import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'logger.dart';

class DiawiUploader {
  final Config config;

  DiawiUploader(this.config);

  Future<String?> upload(File ipaFile) async {
    Logger.header('Uploading IPA to Diawi');

    if (!ipaFile.existsSync()) {
      Logger.error('IPA not found: ${ipaFile.path}');
      return null;
    }

    final name = ipaFile.uri.pathSegments.last;
    final totalBytes = ipaFile.lengthSync();
    Logger.info('IPA: $name  (${_fileSize(ipaFile)})');

    // ── Step 1: upload with retry ────────────────────────────────────────────
    final jobToken = await _uploadWithRetry(ipaFile, totalBytes);
    if (jobToken == null) return null;

    Logger.ok('Upload received. Job token: $jobToken');
    Logger.step('Waiting for Diawi to process the IPA...');

    // ── Step 2: poll for completion ───────────────────────────────────────────
    final diawiHash = await _pollForCompletion(jobToken);
    if (diawiHash == null) return null;

    final url = 'https://i.diawi.com/$diawiHash';

    stdout.writeln('\n╔══════════════════════════════════════════════╗');
    stdout.writeln('  Diawi Upload Successful');
    stdout.writeln('╚══════════════════════════════════════════════╝\n');
    stdout.writeln('  IPA Name:\n  $name\n');
    stdout.writeln('  Diawi Link:\n  $url\n');

    if (Platform.isMacOS) {
      final proc = await Process.start('pbcopy', []);
      proc.stdin.add(url.codeUnits);
      await proc.stdin.close();
      await proc.exitCode;
      Logger.ok('Link copied to clipboard');
    }

    return url;
  }

  Future<String?> _uploadWithRetry(File ipaFile, int totalBytes) async {
    const maxAttempts = 3;
    Exception? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        Logger.step(
          'Uploading to Diawi'
          '${maxAttempts > 1 ? " (attempt $attempt/$maxAttempts)" : ""}...',
        );

        final jobToken =
            await _uploadWithProgress(ipaFile, totalBytes);
        if (jobToken != null) return jobToken;
        throw Exception('No job token in Diawi response');
      } on Exception catch (e) {
        lastError = e;
        if (attempt < maxAttempts) {
          final delaySecs = attempt * 3;
          Logger.skip(
            'Upload failed (attempt $attempt/$maxAttempts): $e\n'
            '  Retrying in ${delaySecs}s...',
          );
          await Future<void>.delayed(Duration(seconds: delaySecs));
        }
      }
    }

    Logger.error('All upload attempts failed: $lastError');
    return null;
  }

  Future<String?> _uploadWithProgress(File ipaFile, int totalBytes) async {
    var bytesSent = 0;
    final startTime = DateTime.now();

    // Wrap the file stream to count bytes and display progress.
    final fileStream = ipaFile.openRead().transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (data, sink) {
          bytesSent += data.length;
          _printProgress(bytesSent, totalBytes, startTime);
          sink.add(data);
        },
        handleDone: (sink) {
          // Clear progress line and print completion.
          stdout.write('\r\x1B[K');
          Logger.ok(
            'Uploaded ${_bytesLabel(totalBytes)} in '
            '${_elapsed(startTime)}',
          );
          sink.close();
        },
      ),
    );

    final request = http.StreamedRequest('POST', Uri.parse('https://upload.diawi.com/'))
      ..headers['Content-Type'] =
          'multipart/form-data; boundary=flutter_release_manager';

    // Build multipart body manually with progress stream.
    final boundary = 'flutter_release_manager';
    final fieldPart = '--$boundary\r\n'
        'Content-Disposition: form-data; name="token"\r\n\r\n'
        '${config.diawiToken!}\r\n';
    final filePart = '--$boundary\r\n'
        'Content-Disposition: form-data; name="file"; '
        'filename="${ipaFile.uri.pathSegments.last}"\r\n'
        'Content-Type: application/octet-stream\r\n\r\n';
    final closing = '\r\n--$boundary--\r\n';

    request.headers['Content-Type'] =
        'multipart/form-data; boundary=$boundary';

    // Stream body: field + file (with progress) + closing.
    final controller = StreamController<List<int>>();
    unawaited(() async {
      controller.add(utf8.encode(fieldPart));
      controller.add(utf8.encode(filePart));
      await for (final chunk in fileStream) {
        controller.add(chunk);
      }
      controller.add(utf8.encode(closing));
      await controller.close();
    }());

    request.contentLength = fieldPart.length +
        filePart.length +
        totalBytes +
        closing.length;
    controller.stream.listen(request.sink.add, onDone: request.sink.close);

    final streamed = await request.send().timeout(
          const Duration(minutes: 20),
          onTimeout: () =>
              throw TimeoutException('Diawi upload timed out after 20 minutes.'),
        );

    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      throw Exception('HTTP ${streamed.statusCode}: $body');
    }

    final data = jsonDecode(body) as Map<String, dynamic>;
    return data['job'] as String?;
  }

  void _printProgress(int sent, int total, DateTime start) {
    if (total <= 0) return;
    final pct = (sent / total * 100).clamp(0, 100).toStringAsFixed(1);
    final elapsed = DateTime.now().difference(start).inSeconds;
    final speed = elapsed > 0 ? sent / elapsed : 0;
    final remaining =
        speed > 0 ? ((total - sent) / speed).round() : 0;
    final eta = remaining > 0 ? '  ETA ${_duration(remaining)}' : '';

    final bar = _progressBar(sent, total, width: 20);
    stdout.write(
      '\r\x1B[K  $bar  $pct%  '
      '${_bytesLabel(sent)} / ${_bytesLabel(total)}  '
      '${_speedLabel(speed.toDouble())}$eta',
    );
  }

  String _progressBar(int sent, int total, {int width = 20}) {
    if (total <= 0) return '[${' ' * width}]';
    final filled = (sent / total * width).round().clamp(0, width);
    return '[${'█' * filled}${' ' * (width - filled)}]';
  }

  String _bytesLabel(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  String _speedLabel(double bps) {
    if (bps < 1024) return '${bps.toStringAsFixed(0)}B/s';
    if (bps < 1024 * 1024) {
      return '${(bps / 1024).toStringAsFixed(1)}KB/s';
    }
    return '${(bps / (1024 * 1024)).toStringAsFixed(1)}MB/s';
  }

  String _elapsed(DateTime start) {
    final secs = DateTime.now().difference(start).inSeconds;
    return _duration(secs);
  }

  String _duration(int secs) {
    if (secs < 60) return '${secs}s';
    return '${secs ~/ 60}m ${secs % 60}s';
  }

  Future<String?> _pollForCompletion(String jobToken) async {
    const maxAttempts = 20;
    const pollInterval = Duration(seconds: 3);

    for (var i = 0; i < maxAttempts; i++) {
      await Future<void>.delayed(pollInterval);

      try {
        final uri = Uri.parse('https://upload.diawi.com/status').replace(
          queryParameters: {'token': config.diawiToken, 'job': jobToken},
        );
        final res = await http.get(uri).timeout(
              const Duration(seconds: 15),
              onTimeout: () =>
                  throw TimeoutException('Diawi status poll timed out.'),
            );
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final status = data['status'] as int?;

        if (status == 2000) {
          return data['hash'] as String?;
        } else if (status == 4000) {
          Logger.error(
            'Diawi processing failed: ${data['message'] ?? 'unknown error'}',
          );
          return null;
        }

        Logger.info(
          'Processing... (${i + 1}/$maxAttempts, status: $status)',
        );
      } catch (e) {
        Logger.skip('Status poll error (attempt ${i + 1}): $e');
      }
    }

    Logger.error(
        'Diawi processing timed out after ${maxAttempts * 3} seconds.');
    return null;
  }

  String _fileSize(File file) {
    final bytes = file.lengthSync();
    return bytes < 1024 * 1024
        ? '${(bytes / 1024).toStringAsFixed(1)} KB'
        : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
