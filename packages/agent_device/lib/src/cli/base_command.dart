// Base Command type shared by all agent-device CLI subcommands.
library;

import 'package:agent_device/src/backend/backend.dart';
import 'package:agent_device/src/platforms/android/android_backend.dart';
import 'package:agent_device/src/platforms/platform_selector.dart';
import 'package:agent_device/src/runtime/agent_device.dart';
import 'package:agent_device/src/runtime/contract.dart';
import 'package:agent_device/src/utils/errors.dart';
import 'package:args/command_runner.dart';

import 'output.dart';

/// Base class that adds the common flags every CLI command accepts:
/// `--session`, `--platform`, `--serial`, `--json`, `--verbose` /
/// `--debug`. Subclasses call [openAgentDevice] to construct a fresh
/// [AgentDevice] bound to the selected device.
abstract class AgentDeviceCommand extends Command<int> {
  AgentDeviceCommand() {
    argParser
      ..addOption(
        'session',
        help: 'Session name (default: "default").',
        defaultsTo: 'default',
      )
      ..addOption(
        'platform',
        help:
            'Device platform selector (ios | android | macos | linux | apple).',
        allowed: ['ios', 'android', 'macos', 'linux', 'apple'],
      )
      ..addOption('serial', help: 'Explicit device serial / udid to target.')
      ..addOption('device', help: 'Device name to target.')
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
  }

  /// True if `--json` was passed on this command (or any parent).
  bool get asJson => _boolFlag('json');

  /// True if `--verbose` or `--debug` was passed.
  bool get verbose => _boolFlag('verbose') || _boolFlag('debug');

  String get sessionName => argResults?['session'] as String? ?? 'default';

  /// Resolve the device selector from CLI flags.
  DeviceSelector get selectorFromFlags {
    final platform = argResults?['platform'] as String?;
    final serial = argResults?['serial'] as String?;
    final name = argResults?['device'] as String?;
    return DeviceSelector(
      platform: platform == null ? null : parsePlatformSelector(platform),
      serial: serial,
      name: name,
    );
  }

  /// Resolve the concrete [Backend] for the selected platform. For now
  /// only Android is wired; iOS / macOS / Linux will land in Phase 8/9.
  Backend resolveBackend() {
    final platform = argResults?['platform'] as String?;
    if (platform == 'android') {
      return const AndroidBackend();
    }
    // Auto-detect: try Android first since it's the only ported backend.
    if (platform == null) {
      return const AndroidBackend();
    }
    throw AppError(
      AppErrorCodes.unsupportedPlatform,
      'Platform "$platform" is not yet implemented in the Dart port.',
      details: {
        'hint':
            'Only --platform android is currently supported; '
            'iOS / macOS / Linux are tracked in Phases 8–9 of the port.',
      },
    );
  }

  /// Open an [AgentDevice] bound to the session and selector from the
  /// command-line flags. Callers are responsible for `await device.close()`.
  Future<AgentDevice> openAgentDevice({CommandSessionStore? sessions}) async {
    return AgentDevice.open(
      backend: resolveBackend(),
      selector: selectorFromFlags,
      sessionName: sessionName,
      sessions: sessions,
    );
  }

  /// Positional arguments remaining after flag parsing.
  List<String> get positionals => argResults?.rest ?? const [];

  /// Helper for subclasses to uniformly print a command result.
  void emitResult(Object? data, {String Function(Object? data)? humanFormat}) =>
      printResult(data, asJson: asJson, humanFormat: humanFormat);

  /// Helper for subclasses to uniformly print a short "ok" message in
  /// human mode after a successful mutating command (open, close, tap,
  /// fill, etc.). JSON mode is silent because the envelope already
  /// signals success.
  void emitAck(String message) => printAck(message, asJson: asJson);

  /// Check either the top-level runner's results or this command's own
  /// results for a bool flag — so both `agent-device --json snapshot` and
  /// `agent-device snapshot --json` work.
  bool _boolFlag(String name) {
    final results = argResults;
    if (results != null && results.options.contains(name)) {
      final v = results[name];
      if (v is bool && v) return true;
    }
    final global = globalResults;
    if (global != null && global.options.contains(name)) {
      final v = global[name];
      if (v is bool && v) return true;
    }
    return false;
  }
}
