class Config {
  final String platform;
  final String appDir;
  final String appName;
  final String? flavour;
  final bool uploadDrive;
  final String rcloneRemote;
  final String? driveFolderId;
  final String? teamId;
  final String scheme;
  final String exportMethod;
  final String? diawiToken;

  const Config({
    required this.platform,
    required this.appDir,
    required this.appName,
    this.flavour,
    required this.uploadDrive,
    required this.rcloneRemote,
    this.driveFolderId,
    this.teamId,
    required this.scheme,
    required this.exportMethod,
    this.diawiToken,
  });

  bool get buildAndroid => platform == 'android' || platform == 'both';
  bool get buildIos => platform == 'ios' || platform == 'both';
}