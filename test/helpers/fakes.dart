import 'package:flutter_release_manager/src/interfaces.dart';

class FakeMachineConfig implements MachineConfigStore {
  Map<String, dynamic> data;
  bool resetAllCalled = false;
  int saveCallCount = 0;

  FakeMachineConfig([Map<String, dynamic>? initial])
      : data = Map.from(initial ?? {});

  @override
  Map<String, dynamic> load() => Map.from(data);

  @override
  void save(Map<String, dynamic> values) {
    saveCallCount++;
    data.addAll(values);
  }

  @override
  void resetAll() {
    resetAllCalled = true;
    data.clear();
  }

  @override
  String get configPath =>
      '/fake/.config/flutter_release_manager/config.json';
}

class FakeDriveRemote implements DriveRemote {
  bool _exists;
  bool deleteCalled = false;

  FakeDriveRemote({bool exists = false}) : _exists = exists;

  @override
  bool exists() => _exists;

  @override
  void delete() {
    deleteCalled = true;
    _exists = false;
  }
}

/// Returns a `readLine` function that replays [lines] in order.
/// Returns null once all lines are exhausted.
String? Function() fakeReadLine(List<String> lines) {
  var index = 0;
  return () => index < lines.length ? lines[index++] : null;
}
