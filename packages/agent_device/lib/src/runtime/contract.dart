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
/// backend escape-hatch capabilities unless the consumer opts in. Mirrors
/// the TS `localCommandPolicy()` values.
const CommandPolicy localCommandPolicy = CommandPolicy(
  allowLocalInputPaths: true,
  allowLocalOutputPaths: true,
  maxImagePixels: 20_000_000,
  allowNamedBackendCapabilities: [],
);

/// Restricted policy for untrusted callers (remote daemon, CLI with
/// `--session-isolation`): no local path access, no escape-hatches. Mirrors
/// the TS `restrictedCommandPolicy()` values.
const CommandPolicy restrictedCommandPolicy = CommandPolicy(
  allowLocalInputPaths: false,
  allowLocalOutputPaths: false,
  maxImagePixels: 20_000_000,
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

  /// Returns a copy with any subset of fields replaced. To clear a nullable
  /// field to `null`, include its name in [clearFields] (passing `null` as
  /// the value is indistinguishable from "not specified" in Dart's optional
  /// named-parameter semantics — verifier finding from 2026-04-23).
  ///
  /// Example: `record.copyWith(clearFields: {'appId', 'appBundleId'})`.
  CommandSessionRecord copyWith({
    String? appId,
    String? appBundleId,
    String? appName,
    String? backendSessionId,
    SnapshotState? snapshot,
    String? deviceSerial,
    Map<String, Object?>? metadata,
    Set<String> clearFields = const {},
  }) {
    return CommandSessionRecord(
      name: name,
      appId: clearFields.contains('appId') ? null : (appId ?? this.appId),
      appBundleId: clearFields.contains('appBundleId')
          ? null
          : (appBundleId ?? this.appBundleId),
      appName: clearFields.contains('appName')
          ? null
          : (appName ?? this.appName),
      backendSessionId: clearFields.contains('backendSessionId')
          ? null
          : (backendSessionId ?? this.backendSessionId),
      snapshot: clearFields.contains('snapshot')
          ? null
          : (snapshot ?? this.snapshot),
      deviceSerial: clearFields.contains('deviceSerial')
          ? null
          : (deviceSerial ?? this.deviceSerial),
      metadata: clearFields.contains('metadata')
          ? null
          : (metadata ?? this.metadata),
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
    // Note: [snapshot] is NOT persisted — it contains live [SnapshotState]
    // with file-path references that are only meaningful within one CLI
    // invocation. Callers should re-capture via `snapshot` after reloading
    // a session from disk.
  };

  /// Deserialise from the shape produced by [toJson]. The `snapshot` field
  /// is never re-hydrated (see [toJson] note); callers re-capture it.
  factory CommandSessionRecord.fromJson(Map<String, Object?> json) {
    final name = json['name'];
    if (name is! String || name.isEmpty) {
      throw const FormatException(
        'CommandSessionRecord.fromJson: missing name',
      );
    }
    Map<String, Object?>? readMetadata(Object? raw) {
      if (raw is Map) {
        return <String, Object?>{
          for (final e in raw.entries) e.key.toString(): e.value,
        };
      }
      return null;
    }

    return CommandSessionRecord(
      name: name,
      appId: json['appId'] as String?,
      appBundleId: json['appBundleId'] as String?,
      appName: json['appName'] as String?,
      backendSessionId: json['backendSessionId'] as String?,
      deviceSerial: json['deviceSerial'] as String?,
      metadata: readMetadata(json['metadata']),
    );
  }
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
