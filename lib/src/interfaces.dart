abstract class MachineConfigStore {
  Map<String, dynamic> load();
  void save(Map<String, dynamic> values);
  void resetAll();
  String get configPath;
}

abstract class DriveRemote {
  bool exists();
  void delete();
}
