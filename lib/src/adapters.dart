import 'app_config.dart';
import 'interfaces.dart';
import 'rclone_manager.dart';

class AppConfigAdapter implements MachineConfigStore {
  @override
  Map<String, dynamic> load() => AppConfig.load();

  @override
  void save(Map<String, dynamic> values) => AppConfig.save(values);

  @override
  void resetAll() => AppConfig.resetAll();

  @override
  String get configPath => AppConfig.path;
}

class RcloneAdapter implements DriveRemote {
  @override
  bool exists() => RcloneManager.remoteExists();

  @override
  void delete() => RcloneManager.deleteRemote();
}
