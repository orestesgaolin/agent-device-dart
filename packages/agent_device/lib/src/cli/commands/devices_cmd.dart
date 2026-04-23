library;

import 'package:agent_device/src/runtime/agent_device.dart';

import '../base_command.dart';

class DevicesCommand extends AgentDeviceCommand {
  @override
  String get name => 'devices';

  @override
  String get description => 'List visible devices.';

  @override
  Future<int> run() async {
    final backend = resolveBackend();
    final devices = await AgentDevice.listDevices(backend);
    emitResult(
      devices.map((d) => d.toJson()).toList(),
      humanFormat: (data) {
        if (devices.isEmpty) return '(no devices)';
        final lines = StringBuffer();
        for (final d in devices) {
          lines.writeln(
            '${d.id.padRight(20)}  ${d.name}  [${d.platform.name}]',
          );
        }
        return lines.toString().trimRight();
      },
    );
    return 0;
  }
}
