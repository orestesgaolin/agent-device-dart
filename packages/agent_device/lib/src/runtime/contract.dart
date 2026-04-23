// Port of agent-device/src/runtime-contract.ts
library;

import 'package:agent_device/src/backend/capabilities.dart';
import 'package:agent_device/src/snapshot/snapshot.dart';

/// Policy controls that gate what a runtime will allow a command to do.
class CommandPolicy {
  /// If false, commands must not read from caller-supplied filesystem paths.
  final bool allowLocalInputPaths;

  /// If false, commands must not write to caller-supplied filesystem paths.
  final bool allowLocalOutputPaths;

  /// Maximum pixel count for decoded images before we refuse to process.
  final int maxImagePixels;

  /// Backend capabilities the policy lets commands exercise.
  final List<BackendCapabilityName> allowNamedBackendCapabilities;

  const CommandPolicy({
    required this.allowLocalInputPaths,
    required this.allowLocalOutputPaths,
    required this.maxImagePixels,
    required this.allowNamedBackendCapabilities,
  });
}

/// Default policy for in-process programmatic use: allow local I/O, no
/// backend escape-hatch capabilities unless the consumer opts in.
const CommandPolicy localCommandPolicy = CommandPolicy(
  allowLocalInputPaths: true,
  allowLocalOutputPaths: true,
  maxImagePixels: 50_000_000,
  allowNamedBackendCapabilities: [],
);

/// Restricted policy for untrusted callers (remote daemon, CLI with
/// `--session-isolation`): no local path access, no escape-hatches.
const CommandPolicy restrictedCommandPolicy = CommandPolicy(
  allowLocalInputPaths: false,
  allowLocalOutputPaths: false,
  maxImagePixels: 25_000_000,
  allowNamedBackendCapabilities: [],
);

/// Snapshot of a single session, persisted by the runtime so subsequent
/// commands can reference the currently-opened app, last snapshot, etc.
///
/// Mirrors `CommandSessionRecord` in `src/runtime-contract.ts`. The
/// [deviceSerial] field is a Dart-port-only addition (see
/// [BackendCommandContext] doc).
class CommandSessionRecord {
  final String name;
  final String? appId;
  final String? appBundleId;
  final String? appName;
  final String? backendSessionId;
  final SnapshotState? snapshot;
  final String? deviceSerial;
  final Map<String, Object?>? metadata;

  const CommandSessionRecord({
    required this.name,
    this.appId,
    this.appBundleId,
    this.appName,
    this.backendSessionId,
    this.snapshot,
    this.deviceSerial,
    this.metadata,
  });

  /// Returns a copy with any subset of fields replaced.
  CommandSessionRecord copyWith({
    String? appId,
    String? appBundleId,
    String? appName,
    String? backendSessionId,
    SnapshotState? snapshot,
    String? deviceSerial,
    Map<String, Object?>? metadata,
  }) {
    return CommandSessionRecord(
      name: name,
      appId: appId ?? this.appId,
      appBundleId: appBundleId ?? this.appBundleId,
      appName: appName ?? this.appName,
      backendSessionId: backendSessionId ?? this.backendSessionId,
      snapshot: snapshot ?? this.snapshot,
      deviceSerial: deviceSerial ?? this.deviceSerial,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    if (appId != null) 'appId': appId,
    if (appBundleId != null) 'appBundleId': appBundleId,
    if (appName != null) 'appName': appName,
    if (backendSessionId != null) 'backendSessionId': backendSessionId,
    if (deviceSerial != null) 'deviceSerial': deviceSerial,
    if (metadata != null) 'metadata': metadata,
  };
}

/// Storage backend for [CommandSessionRecord]s keyed by session name.
///
/// Implementations shared across concurrent callers must serialise
/// per-session updates (or route through a transport that already does).
abstract class CommandSessionStore {
  /// Fetch a session by name, or null if none is stored.
  Future<CommandSessionRecord?> get(String name);

  /// Upsert a session record.
  Future<void> set(CommandSessionRecord record);

  /// Remove a session. Optional — returns normally if not supported.
  Future<void> delete(String name);

  /// List all stored sessions.
  Future<List<CommandSessionRecord>> list();
}

/// Optional structured diagnostics sink passed into the runtime. A no-op
/// default is used if none is provided.
abstract class DiagnosticsSink {
  void emit({
    required String level, // 'debug' | 'info' | 'warn' | 'error'
    required String message,
    Object? data,
  });
}

/// Clock abstraction for tests that need to replace `DateTime.now` and
/// sleeps.
abstract class CommandClock {
  int now();
  Future<void> sleep(Duration duration);
}

/// Real-wall-clock implementation.
class SystemClock implements CommandClock {
  const SystemClock();

  @override
  int now() => DateTime.now().millisecondsSinceEpoch;

  @override
  Future<void> sleep(Duration duration) => Future<void>.delayed(duration);
}
