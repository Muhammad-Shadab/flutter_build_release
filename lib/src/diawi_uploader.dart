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
    Logger.info('IPA: $name  (${_fileSize(ipaFile)})');

    // ── Step 1: upload with retry ────────────────────────────────────────────
    final jobToken = await _uploadWithRetry(ipaFile);
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

  Future<String?> _uploadWithRetry(File ipaFile) async {
    const maxAttempts = 3;
    Exception? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        Logger.step(
          'Uploading to Diawi'
          '${maxAttempts > 1 ? " (attempt $attempt/$maxAttempts)" : ""}...',
        );

        final request = http.MultipartRequest(
          'POST',
          Uri.parse('https://upload.diawi.com/'),
        )
          ..fields['token'] = config.diawiToken!
          ..files.add(await http.MultipartFile.fromPath('file', ipaFile.path));

        final streamed = await request.send().timeout(
              const Duration(minutes: 20),
              onTimeout: () => throw TimeoutException(
                'Diawi upload timed out after 20 minutes.',
              ),
            );
        final body = await streamed.stream.bytesToString();

        if (streamed.statusCode != 200) {
          throw Exception('HTTP ${streamed.statusCode}: $body');
        }

        final data = jsonDecode(body) as Map<String, dynamic>;
        final jobToken = data['job'] as String?;
        if (jobToken == null) {
          throw Exception('No job token in Diawi response: $body');
        }
        return jobToken;
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
