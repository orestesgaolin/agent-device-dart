library;

import 'package:agent_device/src/backend/backend.dart';
import 'package:agent_device/src/platforms/android/android_backend.dart';
import 'package:agent_device/src/platforms/ios/ios_backend.dart';
import 'package:agent_device/src/runtime/agent_device.dart';

import '../base_command.dart';

class DevicesCommand extends AgentDeviceCommand {
  @override
  String get name => 'devices';

  @override
  String get description => 'List visible devices.';

  @override
  Future<int> run() async {
    final platform = argResults?['platform'] as String?;

    List<BackendDeviceInfo> devices;
    if (platform != null) {
      final backend = resolveBackend();
      devices = await AgentDevice.listDevices(backend);
    } else {
      devices = await _listAllPlatforms();
    }

    emitResult(
      devices.map((d) => d.toJson()).toList(),
      humanFormat: (data) {
        if (devices.isEmpty) return '(no devices)';
        final lines = StringBuffer();
        for (final d in devices) {
          final status = d.booted == true
              ? '  (booted)'
              : d.booted == false
              ? '  (shutdown)'
              : '';
          lines.writeln(
            '${d.id.padRight(20)}  ${d.name}  [${d.platform.name}]$status',
          );
        }
        return lines.toString().trimRight();
      },
    );
    return 0;
  }

  Future<List<BackendDeviceInfo>> _listAllPlatforms() async {
    final results = await Future.wait([
      _tryListDevices(const AndroidBackend()),
      _tryListDevices(const IosBackend()),
    ]);
    return [...results[0], ...results[1]];
  }

  static Future<List<BackendDeviceInfo>> _tryListDevices(
    Backend backend,
  ) async {
    try {
      return await AgentDevice.listDevices(backend);
    } catch (_) {
      return const [];
    }
  }
}
