// Entry point for the `agent-device` CLI.
library;

import 'dart:io';

import 'package:args/command_runner.dart';

import 'commands/completion_cmd.dart';
import 'commands/devices_cmd.dart';
import 'commands/ensure_simulator_cmd.dart';
import 'commands/install_cmd.dart';
import 'commands/logs_cmd.dart';
import 'commands/network_cmd.dart';
import 'commands/perf_cmd.dart';
import 'commands/record_cmd.dart';
import 'commands/replay_cmd.dart';
import 'commands/runner_cmd.dart';
import 'commands/screenshot_cmd.dart';
import 'commands/selector_cmds.dart';
import 'commands/session_cmd.dart';
import 'commands/simple_action_cmds.dart';
import 'commands/snapshot_cmd.dart';
import 'output.dart';

/// Build the [CommandRunner] used by both the live CLI and the
/// `completion` subcommand (which introspects `runner.commands` to
/// emit a static script). Adding new top-level subcommands here
/// auto-extends shell completion.
CommandRunner<int> buildCliRunner({String executableName = 'agent-device'}) {
  final runner = CommandRunner<int>(
    executableName,
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
    ..addFlag('debug', help: 'Alias for --verbose.', negatable: false)
    ..addOption(
      'state-dir',
      help:
          'Override the agent-device state directory '
          '(default: \$AGENT_DEVICE_STATE_DIR or ~/.agent-device/).',
    )
    ..addFlag(
      'ephemeral-session',
      help: 'Use an in-memory session store for this invocation.',
      negatable: false,
    );

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
    ..addCommand(RotateCommand())
    ..addCommand(SwipeCommand())
    ..addCommand(ScrollCommand())
    ..addCommand(LongPressCommand())
    ..addCommand(PinchCommand())
    ..addCommand(AppStateCommand())
    ..addCommand(AppsCommand())
    ..addCommand(ClipboardCommand())
    ..addCommand(PressCommand())
    ..addCommand(FindCommand())
    ..addCommand(GetCommand())
    ..addCommand(IsCommand())
    ..addCommand(WaitCommand())
    ..addCommand(EnsureSimulatorCommand())
    ..addCommand(InstallCommand())
    ..addCommand(UninstallCommand())
    ..addCommand(ReinstallCommand())
    ..addCommand(LogsCommand())
    ..addCommand(NetworkCommand())
    ..addCommand(PerfCommand())
    ..addCommand(RecordCommand())
    ..addCommand(RunnerCommand())
    ..addCommand(ReplayCommand())
    ..addCommand(TestCommand())
    ..addCommand(SessionCommand())
    ..addCommand(CompletionCommand());
  return runner;
}

/// Run the CLI with [argv]. Returns the exit code (0 = ok, 1 = error,
/// 64 = usage error — matching sysexits.h semantics).
///
/// [executableName] customises the program name in `--help` output —
/// pass `'ad'` when invoked through the short alias, `'agent-device'`
/// otherwise. The default falls back to detecting the invoked binary
/// from `Platform.executable`.
Future<int> runCli(List<String> argv, {String? executableName}) async {
  final name = executableName ?? _detectExecutableName();
  final runner = buildCliRunner(executableName: name);

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

/// Best-effort guess at the program name the user typed. When invoked
/// through a `dart compile exe` binary `Platform.executable` ends in
/// `agent-device` or `ad`; when `dart run` driving the `bin/` script
/// it ends in `dart`, in which case we fall back to the canonical
/// long name.
String _detectExecutableName() {
  final exe = _basename(Platform.executable);
  if (exe == 'agent-device' || exe == 'ad') return exe;
  return 'agent-device';
}

String _basename(String path) {
  final i = path.lastIndexOf(Platform.pathSeparator);
  return i < 0 ? path : path.substring(i + 1);
}
