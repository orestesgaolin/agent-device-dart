// `agent-device runner stop` — gracefully tear down a cached XCUITest
// runner. The runner is intentionally kept alive between CLI
// invocations so subsequent commands skip the ~14s xcodebuild
// cold-start; this command exists for when you actually want it gone
// (end of session, swap devices, etc.).
//
// `IosBackend.shutdownRunnerFor` does the gentle path: POST
// `{command:'shutdown'}` so XCTest fulfils its expectation and tears
// down cleanly, then SIGKILLs the xcodebuild driver as fallback, then
// removes the disk record.
library;

import 'dart:io';

import 'package:agent_device/src/platforms/ios/ios_backend.dart';
import 'package:agent_device/src/runtime/paths.dart';
import 'package:agent_device/src/utils/errors.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../base_command.dart';

class RunnerCommand extends Command<int> {
  RunnerCommand() {
    addSubcommand(RunnerStopCommand());
  }

  @override
  String get name => 'runner';

  @override
  String get description => 'Manage the cached XCUITest runner (iOS only).';
}

class RunnerStopCommand extends AgentDeviceCommand {
  RunnerStopCommand() {
    argParser.addFlag(
      'all',
      help: 'Shut down every cached iOS runner across all devices.',
      negatable: false,
    );
  }

  @override
  String get name => 'stop';

  @override
  String get description =>
      'Gracefully shut down the cached iOS runner. Without --all, '
      'targets the runner for --serial (or the active session\'s device).';

  @override
  Future<int> run() async {
    final all = argResults?['all'] as bool? ?? false;
    final udids = all
        ? _allCachedRunnerUdids()
        : <String>[await _resolveSingleUdid()];

    if (udids.isEmpty) {
      emitResult({
        'stopped': <String>[],
        'count': 0,
      }, humanFormat: (_) => 'no cached runners');
      return 0;
    }

    for (final udid in udids) {
      await IosBackend.shutdownRunnerFor(udid);
    }
    emitResult(
      {'stopped': udids, 'count': udids.length},
      humanFormat: (_) => udids.length == 1
          ? 'stopped runner for ${udids.single}'
          : 'stopped ${udids.length} runners: ${udids.join(', ')}',
    );
    return 0;
  }

  Future<String> _resolveSingleUdid() async {
    final explicit = argResults?['serial'] as String?;
    if (explicit != null && explicit.isNotEmpty) return explicit;
    // Fall back to the active session's stored device serial.
    final store = resolveSessionStore();
    final session = await store.get(sessionName);
    final serial = session?.deviceSerial;
    if (serial != null && serial.isNotEmpty) return serial;
    throw AppError(
      AppErrorCodes.invalidArgs,
      'No device serial available — pass --serial <udid> or --all.',
    );
  }

  List<String> _allCachedRunnerUdids() {
    final paths = resolveStatePaths();
    final dir = Directory(p.join(paths.baseDir, 'ios-runners'));
    if (!dir.existsSync()) return const [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .map((f) => p.basenameWithoutExtension(f.path))
        .toList()
      ..sort();
  }
}
