import 'dart:io';

import 'package:flutter_release_manager/src/android_builder.dart';
import 'package:flutter_release_manager/src/config_command.dart';
import 'package:flutter_release_manager/src/doctor_command.dart';
import 'package:flutter_release_manager/src/init_command.dart';
import 'package:flutter_release_manager/src/ios_builder.dart';
import 'package:flutter_release_manager/src/logger.dart';
import 'package:flutter_release_manager/src/wizard.dart';

Future<void> main(List<String> args) async {
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
