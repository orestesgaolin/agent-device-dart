// Base Command type shared by all agent-device CLI subcommands.
library;

import 'package:agent_device/src/backend/backend.dart';
import 'package:agent_device/src/platforms/android/android_backend.dart';
import 'package:agent_device/src/platforms/ios/ios_backend.dart';
import 'package:agent_device/src/platforms/platform_selector.dart';
import 'package:agent_device/src/runtime/agent_device.dart';
import 'package:agent_device/src/runtime/contract.dart';
import 'package:agent_device/src/runtime/file_session_store.dart';
import 'package:agent_device/src/runtime/paths.dart';
import 'package:agent_device/src/runtime/session_store.dart';
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
      ..addOption(
        'state-dir',
        help:
            'Override the agent-device state directory '
            '(default: \$AGENT_DEVICE_STATE_DIR or ~/.agent-device/).',
      )
      ..addFlag(
        'ephemeral-session',
        help:
            'Use an in-memory session store for this invocation (do not '
            'touch ~/.agent-device/sessions/).',
        negatable: false,
      )
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

  /// Resolve the concrete [Backend] for the selected platform. Android
  /// and iOS are both fully wired (iOS goes through the Phase 8B
  /// XCUITest-runner bridge for snapshot + interaction; simulator device
  /// operations go through `simctl`, physical devices through
  /// `devicectl`). macOS / Linux are Phase 9.
  Backend resolveBackend() {
    final platform =
        _stringOption('platform') ?? argResults?['platform'] as String?;
    switch (platform) {
      case 'android':
        return const AndroidBackend();
      case 'ios':
      case 'apple': // Phase 8A: treat `apple` as iOS.
        return const IosBackend();
      case null:
        // Auto-detect: Android first because it's the fuller backend.
        return const AndroidBackend();
    }
    throw AppError(
      AppErrorCodes.unsupportedPlatform,
      'Platform "$platform" is not yet implemented in the Dart port.',
      details: {
        'hint':
            '--platform android and --platform ios are supported. '
            'macOS / Linux are tracked in Phase 9.',
      },
    );
  }

  /// The [CommandSessionStore] this CLI invocation should use. Defaults to
  /// a [FileSessionStore] rooted at `<state-dir>/sessions/` so subsequent
  /// CLI invocations share session state. `--ephemeral-session` falls back
  /// to an in-memory store for one-shot commands. Both flags are honored
  /// whether passed at the root (`agent-device --state-dir X cmd`) or on
  /// the subcommand (`agent-device cmd --state-dir X`).
  CommandSessionStore resolveSessionStore() {
    if (_boolFlag('ephemeral-session')) return createMemorySessionStore();
    final paths = resolveStatePaths(_stringOption('state-dir'));
    return FileSessionStore(paths.sessionsDir);
  }

  /// Same lookup logic as [_boolFlag] but for string-valued options.
  String? _stringOption(String name) {
    final results = argResults;
    if (results != null && results.options.contains(name)) {
      final v = results[name];
      if (v is String && v.isNotEmpty) return v;
    }
    final global = globalResults;
    if (global != null && global.options.contains(name)) {
      final v = global[name];
      if (v is String && v.isNotEmpty) return v;
    }
    return null;
  }

  /// Open an [AgentDevice] bound to the session and selector from the
  /// command-line flags. Callers are responsible for `await device.close()`
  /// only when they want the session deleted — for persistent sessions
  /// (the default), leave `close()` unpinned so subsequent CLI runs can
  /// reuse the record.
  Future<AgentDevice> openAgentDevice({CommandSessionStore? sessions}) async {
    if (verbose) agentDeviceVerbose = true;
    final store = sessions ?? resolveSessionStore();
    // Prefer a device serial already stored for this session if the user
    // hasn't narrowed down via --serial / --device. This is what lets
    // `agent-device open` in shell A and `agent-device snapshot` in shell
    // B land on the same device.
    final base = selectorFromFlags;
    DeviceSelector selector = base;
    if (base.serial == null && base.name == null) {
      final existing = await store.get(sessionName);
      final remembered = existing?.deviceSerial;
      if (remembered != null && remembered.isNotEmpty) {
        selector = DeviceSelector(
          platform: base.platform,
          serial: remembered,
          name: null,
        );
      }
    }
    return AgentDevice.open(
      backend: resolveBackend(),
      selector: selector,
      sessionName: sessionName,
      sessions: store,
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
