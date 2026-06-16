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
    Logger.step('Uploading to Diawi...');

    // Step 1: upload
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('https://upload.diawi.com/'),
    )
      ..fields['token'] = config.diawiToken!
      ..files.add(await http.MultipartFile.fromPath('file', ipaFile.path));

    http.StreamedResponse streamed;
    try {
      streamed = await request.send();
    } catch (e) {
      Logger.error('Upload request failed: $e');
      return null;
    }

    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      Logger.error('Upload failed (HTTP ${streamed.statusCode}): $body');
      return null;
    }

    late Map<String, dynamic> uploadData;
    try {
      uploadData = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      Logger.error('Invalid response from Diawi: $body');
      return null;
    }

    final jobToken = uploadData['job'] as String?;
    if (jobToken == null) {
      Logger.error('Upload failed. Diawi response: $body');
      return null;
    }

    Logger.ok('Upload received. Job token: $jobToken');
    Logger.step('Waiting for Diawi to process the IPA...');

    // Step 2: poll for completion
    String? diawiHash;
    for (var i = 0; i < 20; i++) {
      await Future.delayed(const Duration(seconds: 3));

      final statusUri = Uri.parse('https://upload.diawi.com/status').replace(
        queryParameters: {'token': config.diawiToken, 'job': jobToken},
      );
      final statusRes = await http.get(statusUri);
      final statusData = jsonDecode(statusRes.body) as Map<String, dynamic>;
      final status = statusData['status'] as int?;

      if (status == 2000) {
        diawiHash = statusData['hash'] as String?;
        break;
      } else if (status == 4000) {
        Logger.error('Diawi processing failed: ${statusData['message'] ?? 'unknown'}');
        return null;
      }
      Logger.info('Processing... (attempt ${i + 1}/20, status: $status)');
    }

    if (diawiHash == null) {
      Logger.error('Diawi processing timed out after 60 seconds.');
      return null;
    }

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

  String _fileSize(File file) {
    final bytes = file.lengthSync();
    return bytes < 1024 * 1024
        ? '${(bytes / 1024).toStringAsFixed(1)} KB'
        : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
