library;

import 'package:agent_device/src/utils/errors.dart';

import '../base_command.dart';

class ScreenshotCommand extends AgentDeviceCommand {
  @override
  String get name => 'screenshot';

  @override
  String get description => 'Capture a screenshot to a PNG file.';

  @override
  Future<int> run() async {
    final args = positionals;
    if (args.isEmpty) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'screenshot requires an output file path.',
      );
    }
    final outPath = args.first;
    final device = await openAgentDevice();
    final result = await device.screenshot(outPath);
    emitResult({
      'path': result?.path ?? outPath,
    }, humanFormat: (_) => 'screenshot: ${result?.path ?? outPath}');
    return 0;
  }
}
