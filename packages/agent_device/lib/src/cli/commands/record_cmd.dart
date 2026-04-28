// `agent-device record start <outPath>` / `record stop <outPath>` —
// drive the video recorder. iOS simulator goes through the XCUITest
// runner's recordStart/recordStop + sandbox-tmp pull. iOS physical
// devices use the same runner handlers + `devicectl device copy from
// --domain-type appDataContainer` to pull the mp4 out of the runner's
// sandbox. Android goes through `adb shell screenrecord` forked
// on-device with a PID cache at <stateDir>/android-recorders/
// <serial>.json + `adb pull` on stop.
library;

import 'dart:io';

import 'package:agent_device/src/utils/errors.dart';
import 'package:args/command_runner.dart';

import '../base_command.dart';

class RecordCommand extends Command<int> {
  RecordCommand() {
    addSubcommand(RecordStartCommand());
    addSubcommand(RecordStopCommand());
  }

  @override
  String get name => 'record';

  @override
  String get description =>
      'Start or stop a screen recording. Output is an mp4 file.';
}

class RecordStartCommand extends AgentDeviceCommand {
  RecordStartCommand() {
    argParser
      ..addOption('fps', help: 'Recording frame rate.')
      ..addOption(
        'quality',
        help: 'Recording quality (platform-dependent integer).',
      );
  }

  @override
  String get name => 'start';

  @override
  String get invocation => '${runner!.executableName} record start <outPath> [options]';

  @override
  String get description =>
      'Start recording the current app. The file lands at <outPath> on stop. '
      'iOS requires an open app (set via `agent-device open <bundleId>`).';

  @override
  Future<int> run() async {
    if (positionals.isEmpty) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'record start requires an <outPath> argument.',
      );
    }
    final outPath = File(positionals.first).absolute.path;
    final fps = int.tryParse(argResults?['fps'] as String? ?? '');
    final quality = int.tryParse(argResults?['quality'] as String? ?? '');
    final device = await openAgentDevice();
    final res = await device.startRecording(
      outPath,
      fps: fps,
      quality: quality,
    );
    emitResult(
      res.toJson(),
      humanFormat: (_) =>
          'recording started → ${res.path ?? outPath}. Call `record stop '
          '$outPath` when done.',
    );
    return 0;
  }
}

class RecordStopCommand extends AgentDeviceCommand {
  @override
  String get name => 'stop';

  @override
  String get invocation => '${runner!.executableName} record stop <outPath> [options]';

  @override
  String get description =>
      'Stop the in-progress recording and finalize the file. '
      'Pass the same <outPath> you passed to `record start`.';

  @override
  Future<int> run() async {
    if (positionals.isEmpty) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'record stop requires the <outPath> you passed to `record start`.',
      );
    }
    final outPath = File(positionals.first).absolute.path;
    final device = await openAgentDevice();
    final res = await device.stopRecording(outPath);
    emitResult(
      res.toJson(),
      humanFormat: (_) => res.warning == null
          ? 'recording saved → ${res.path ?? outPath}'
          : 'recording saved → ${res.path ?? outPath} (warning: ${res.warning})',
    );
    return 0;
  }
}
