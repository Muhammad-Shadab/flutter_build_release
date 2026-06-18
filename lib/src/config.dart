class Config {
  final String platform;
  final String appDir;
  final String appName;
  final bool uploadDrive;
  final String rcloneRemote;
  final String? driveFolderName;
  final String? teamId;
  final String scheme;
  final String exportMethod;
  final String? diawiToken;
  final bool skipBuild;

  const Config({
    required this.platform,
    required this.appDir,
    required this.appName,
    required this.uploadDrive,
    this.rcloneRemote = 'flutter_release_manager',
    this.driveFolderName,
    this.teamId,
    required this.scheme,
    required this.exportMethod,
    this.diawiToken,
    this.skipBuild = false,
  });

  bool get buildAndroid => platform == 'android' || platform == 'both';
  bool get buildIos => platform == 'ios' || platform == 'both';
}
