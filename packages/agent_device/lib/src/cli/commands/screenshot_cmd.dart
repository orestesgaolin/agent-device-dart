library;

import 'package:agent_device/src/utils/errors.dart';

import '../base_command.dart';

class ScreenshotCommand extends AgentDeviceCommand {
  ScreenshotCommand() {
    argParser
      ..addFlag(
        'fullscreen',
        help:
            'Capture the full device screen (including system bars) '
            'instead of the active app frame, when the backend supports it.',
        negatable: false,
      )
      ..addOption(
        'max-size',
        help:
            'Downscale the captured PNG so its longest edge is at most '
            '<N> pixels (positive integer). Skipped if the image already '
            'fits.',
        valueHelp: 'N',
      );
  }

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
    final fullscreen = argResults?['fullscreen'] == true ? true : null;
    final maxSizeRaw = argResults?['max-size'] as String?;
    final maxSize = maxSizeRaw == null ? null : int.tryParse(maxSizeRaw);
    if (maxSizeRaw != null && (maxSize == null || maxSize < 1)) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        '--max-size must be a positive integer',
      );
    }
    final device = await openAgentDevice();
    final result = await device.screenshot(
      outPath,
      fullscreen: fullscreen,
      maxSize: maxSize,
    );
    emitResult({
      'path': result?.path ?? outPath,
    }, humanFormat: (_) => 'screenshot: ${result?.path ?? outPath}');
    return 0;
  }
}
