// `agent-device ensure-simulator` — find or create an iOS simulator, boot
// it, and print its UDID. Wraps `IosBackend`'s `ensure_simulator.dart`.
library;

import 'package:agent_device/src/platforms/ios/ensure_simulator.dart';
import 'package:agent_device/src/utils/errors.dart';

import '../base_command.dart';

class EnsureSimulatorCommand extends AgentDeviceCommand {
  EnsureSimulatorCommand() {
    argParser
      ..addOption(
        'name',
        help:
            'Simulator device name (e.g. "iPhone 15", "iPhone 17"). '
            'Can also be passed as the positional argument.',
      )
      ..addOption(
        'runtime',
        help:
            'Runtime identifier to pin (e.g. '
            '"com.apple.CoreSimulator.SimRuntime.iOS-17-0"). Optional.',
      )
      ..addFlag(
        'create-new',
        help: 'Always create a new simulator (skip the reuse-existing path).',
        negatable: false,
      )
      ..addFlag(
        'no-boot',
        help: 'Just resolve/create — do not boot the simulator.',
        negatable: false,
      );
  }

  @override
  String get name => 'ensure-simulator';

  @override
  String get description =>
      'Find or create an iOS simulator by name, optionally boot it.';

  @override
  Future<int> run() async {
    final nameFlag = argResults?['name'] as String?;
    final deviceName = nameFlag ?? positionals.firstOrNull;
    if (deviceName == null || deviceName.isEmpty) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'ensure-simulator requires a device name '
        '(e.g. `ensure-simulator "iPhone 15"` or --name "iPhone 15").',
      );
    }
    final runtime = argResults?['runtime'] as String?;
    final createNew = argResults?['create-new'] == true;
    final noBoot = argResults?['no-boot'] == true;

    final result = await ensureSimulator(
      deviceName: deviceName,
      runtime: runtime,
      reuseExisting: !createNew,
      boot: !noBoot,
    );
    emitResult(
      result.toJson(),
      humanFormat: (_) {
        final action = result.created ? 'created' : 'reused';
        final booted = result.booted ? ', booted' : '';
        return '${result.udid}  ($action$booted)';
      },
    );
    return 0;
  }
}
