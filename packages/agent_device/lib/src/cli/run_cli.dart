// Entry point for the `agent-device` CLI.
library;

import 'dart:io';

import 'package:args/command_runner.dart';

import 'commands/devices_cmd.dart';
import 'commands/screenshot_cmd.dart';
import 'commands/simple_action_cmds.dart';
import 'commands/snapshot_cmd.dart';
import 'output.dart';

/// Run the CLI with [argv]. Returns the exit code (0 = ok, 1 = error,
/// 64 = usage error — matching sysexits.h semantics).
Future<int> runCli(List<String> argv) async {
  final runner = CommandRunner<int>(
    'agent-device',
    'Agent-driven CLI for mobile UI automation, network inspection, '
        'and performance diagnostics.',
    usageLineLength: stdout.hasTerminal ? stdout.terminalColumns : 80,
  );

  // Global flags that are also available on every command (subcommands
  // replicate these via AgentDeviceCommand).
  runner.argParser
    ..addFlag(
      'json',
      help: 'Emit machine-readable JSON output.',
      negatable: false,
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      help: 'Verbose output / include full error details.',
      negatable: false,
    )
    ..addFlag('debug', help: 'Alias for --verbose.', negatable: false);

  runner
    ..addCommand(DevicesCommand())
    ..addCommand(SnapshotCommand())
    ..addCommand(ScreenshotCommand())
    ..addCommand(OpenCommand())
    ..addCommand(CloseCommand())
    ..addCommand(TapCommand())
    ..addCommand(FillCommand())
    ..addCommand(TypeCommand())
    ..addCommand(FocusCommand())
    ..addCommand(BackCommand())
    ..addCommand(HomeCommand())
    ..addCommand(AppSwitcherCommand())
    ..addCommand(SwipeCommand())
    ..addCommand(ScrollCommand())
    ..addCommand(LongPressCommand())
    ..addCommand(AppStateCommand())
    ..addCommand(AppsCommand())
    ..addCommand(ClipboardCommand());

  // Decide JSON mode for top-level error reporting by peeking at argv —
  // the CommandRunner hasn't parsed yet when an exception escapes.
  final asJson = argv.contains('--json');
  final verbose =
      argv.contains('--verbose') ||
      argv.contains('-v') ||
      argv.contains('--debug');

  try {
    final result = await runner.run(argv);
    return result ?? 0;
  } on UsageException catch (e) {
    if (asJson) {
      printError(e.message, asJson: true);
    } else {
      stderr.writeln(e.message);
      stderr.writeln();
      stderr.writeln(e.usage);
    }
    return 64;
  } catch (err) {
    printError(err, asJson: asJson, showDetails: verbose);
    return 1;
  }
}
