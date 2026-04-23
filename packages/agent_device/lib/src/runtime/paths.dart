// Port of agent-device/src/daemon/config.ts (paths only).
//
// Resolves `~/.agent-device/` and its subpaths used by the Dart CLI for
// cross-invocation session persistence (Phase 6A) and, later, the daemon
// process (Phase 6B).
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../utils/path_resolution.dart';

/// Paths the CLI / daemon read and write under a state directory.
class StatePaths {
  /// The state directory itself (typically `~/.agent-device/`).
  final String baseDir;

  /// Info file written by the daemon so clients can discover its port+token.
  /// Consumed in Phase 6B; already computed here so callers use one resolver.
  final String infoPath;

  /// Lockfile the daemon acquires to prove singleton.
  final String lockPath;

  /// Daemon log file.
  final String logPath;

  /// Directory where each session is stored as a `<safeName>.json` file.
  final String sessionsDir;

  const StatePaths({
    required this.baseDir,
    required this.infoPath,
    required this.lockPath,
    required this.logPath,
    required this.sessionsDir,
  });
}

/// Resolve the runtime state directory. Priority:
///   1. [stateDir] if explicitly provided (supports `~/` expansion).
///   2. `AGENT_DEVICE_STATE_DIR` env var.
///   3. `~/.agent-device/`.
StatePaths resolveStatePaths([String? stateDir]) {
  final raw = (stateDir?.trim().isNotEmpty ?? false)
      ? stateDir!.trim()
      : (Platform.environment['AGENT_DEVICE_STATE_DIR']?.trim() ?? '');
  final base = raw.isEmpty
      ? p.join(resolveHomeDirectory(), '.agent-device')
      : expandUserHomePath(raw);
  return StatePaths(
    baseDir: base,
    infoPath: p.join(base, 'daemon.json'),
    lockPath: p.join(base, 'daemon.lock'),
    logPath: p.join(base, 'daemon.log'),
    sessionsDir: p.join(base, 'sessions'),
  );
}
