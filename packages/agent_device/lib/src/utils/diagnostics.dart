// Port of `agent-device/src/utils/diagnostics.ts`.
//
// Diagnostics scope management, event emission, and session logging.
// Uses Dart [Zone] for async-local storage of scope context, replacing
// Node's AsyncLocalStorage.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, FileMode, Platform, stderr;
import 'dart:math';
import 'package:path/path.dart' as p;
import 'redaction.dart';

/// Diagnostic event severity level.
enum DiagnosticLevel {
  info('info'),
  warn('warn'),
  error('error'),
  debug('debug');

  final String value;
  const DiagnosticLevel(this.value);
}

/// A single diagnostic event.
class DiagnosticEvent {
  final String ts;
  final String level;
  final String phase;
  final String? session;
  final String? requestId;
  final String? command;
  final int? durationMs;
  final Map<String, Object?>? data;

  DiagnosticEvent({
    required this.ts,
    required this.level,
    required this.phase,
    this.session,
    this.requestId,
    this.command,
    this.durationMs,
    this.data,
  });

  Map<String, Object?> toJson() => {
    'ts': ts,
    'level': level,
    'phase': phase,
    if (session != null) 'session': session,
    if (requestId != null) 'requestId': requestId,
    if (command != null) 'command': command,
    if (durationMs != null) 'durationMs': durationMs,
    if (data != null) 'data': data,
  };
}

/// Options for a diagnostics scope.
class DiagnosticsScopeOptions {
  final String? session;
  final String? requestId;
  final String? command;
  final bool debug;
  final String? logPath;
  final String? traceLogPath;

  DiagnosticsScopeOptions({
    this.session,
    this.requestId,
    this.command,
    this.debug = false,
    this.logPath,
    this.traceLogPath,
  });
}

/// Internal scope state.
class _DiagnosticsScope implements DiagnosticsScopeOptions {
  @override
  final String? session;
  @override
  final String? requestId;
  @override
  final String? command;
  @override
  final bool debug;
  @override
  final String? logPath;
  @override
  final String? traceLogPath;

  final String diagnosticId;
  final List<DiagnosticEvent> events;

  _DiagnosticsScope({
    required this.session,
    required this.requestId,
    required this.command,
    required this.debug,
    required this.logPath,
    required this.traceLogPath,
    required this.diagnosticId,
    required this.events,
  });
}

const Symbol _scopeKey = #diagnosticsScope;

/// Retrieves the current diagnostics scope from the zone, if present.
_DiagnosticsScope? _getCurrentScope() {
  return Zone.current[_scopeKey] as _DiagnosticsScope?;
}

/// Generates a request ID using cryptographically secure randomness.
String createRequestId() {
  final random = Random.secure();
  const hexChars = '0123456789abcdef';
  final bytes = List<int>.generate(8, (_) => random.nextInt(256));
  return bytes.map((b) => hexChars[b >> 4] + hexChars[b & 0xf]).join();
}

/// Generates a unique diagnostic ID.
String _createDiagnosticId() {
  final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final random = Random.secure();
  const hexChars = '0123456789abcdef';
  final bytes = List<int>.generate(4, (_) => random.nextInt(256));
  final randomPart = bytes
      .map((b) => hexChars[b >> 4] + hexChars[b & 0xf])
      .join();
  return '$timestamp-$randomPart';
}

/// Executes [fn] within a diagnostics scope with the given [options].
///
/// The scope is available to [emitDiagnostic], [getDiagnosticsMeta], and
/// [withDiagnosticTimer] within [fn] and any async tasks spawned from it.
Future<T> withDiagnosticsScope<T>(
  DiagnosticsScopeOptions options,
  Future<T> Function() fn,
) async {
  final scope = _DiagnosticsScope(
    session: options.session,
    requestId: options.requestId,
    command: options.command,
    debug: options.debug,
    logPath: options.logPath,
    traceLogPath: options.traceLogPath,
    diagnosticId: _createDiagnosticId(),
    events: [],
  );

  return runZoned(fn, zoneValues: {_scopeKey: scope});
}

/// Metadata about the current diagnostics scope.
class DiagnosticsMetadata {
  final String? diagnosticId;
  final String? requestId;
  final String? session;
  final String? command;
  final bool debug;

  DiagnosticsMetadata({
    this.diagnosticId,
    this.requestId,
    this.session,
    this.command,
    this.debug = false,
  });
}

/// Returns metadata about the current diagnostics scope, or an empty object
/// if no scope is active.
DiagnosticsMetadata getDiagnosticsMeta() {
  final scope = _getCurrentScope();
  if (scope == null) {
    return DiagnosticsMetadata();
  }
  return DiagnosticsMetadata(
    diagnosticId: scope.diagnosticId,
    requestId: scope.requestId,
    session: scope.session,
    command: scope.command,
    debug: scope.debug,
  );
}

/// Options for a diagnostic event.
class EmitDiagnosticOptions {
  final DiagnosticLevel level;
  final String phase;
  final int? durationMs;
  final Map<String, Object?>? data;

  EmitDiagnosticOptions({
    this.level = DiagnosticLevel.info,
    required this.phase,
    this.durationMs,
    this.data,
  });
}

/// Emits a diagnostic event to the current scope.
///
/// If no scope is active, this is a no-op.
void emitDiagnostic(EmitDiagnosticOptions options) {
  final scope = _getCurrentScope();
  if (scope == null) return;

  final data = options.data != null
      ? redactDiagnosticData(options.data) as Map<String, Object?>?
      : null;
  final event = DiagnosticEvent(
    ts: DateTime.now().toUtc().toIso8601String(),
    level: options.level.value,
    phase: options.phase,
    session: scope.session,
    requestId: scope.requestId,
    command: scope.command,
    durationMs: options.durationMs,
    data: data,
  );

  scope.events.add(event);

  if (!scope.debug) return;

  final line = '[agent-device][diag] ${jsonEncode(event)}\n';
  try {
    if (scope.logPath != null) {
      File(scope.logPath!).writeAsStringSync(line, mode: FileMode.append);
    }
    if (scope.traceLogPath != null) {
      File(scope.traceLogPath!).writeAsStringSync(line, mode: FileMode.append);
    }
    if (scope.logPath == null && scope.traceLogPath == null) {
      stderr.write(line);
    }
  } catch (_) {
    // Best-effort diagnostics should not break request flow.
  }
}

/// Executes [fn] and emits a diagnostic event with timing information.
///
/// On success, emits an 'info' event with the elapsed time.
/// On error, emits an 'error' event and re-throws the exception.
Future<T> withDiagnosticTimer<T>(
  String phase,
  Future<T> Function() fn, [
  Map<String, Object?>? data,
]) async {
  final start = DateTime.now().millisecondsSinceEpoch;
  try {
    final result = await fn();
    emitDiagnostic(
      EmitDiagnosticOptions(
        level: DiagnosticLevel.info,
        phase: phase,
        durationMs: DateTime.now().millisecondsSinceEpoch - start,
        data: data,
      ),
    );
    return result;
  } catch (error) {
    emitDiagnostic(
      EmitDiagnosticOptions(
        level: DiagnosticLevel.error,
        phase: phase,
        durationMs: DateTime.now().millisecondsSinceEpoch - start,
        data: {
          ...(data ?? {}),
          'error': error is Exception ? error.toString() : error.toString(),
        },
      ),
    );
    rethrow;
  }
}

/// Flushes accumulated diagnostic events to a session-specific log file.
///
/// Returns the file path if events were written, null otherwise.
/// By default, only writes if the scope has [DiagnosticsScopeOptions.debug]
/// enabled; pass [force] = true to override.
String? flushDiagnosticsToSessionFile({bool force = false}) {
  final scope = _getCurrentScope();
  if (scope == null) return null;
  if (!force && !scope.debug) return null;
  if (scope.events.isEmpty) return null;

  try {
    final sessionDir = _sanitizePathPart(scope.session ?? 'default');
    final dayDir = DateTime.now().toUtc().toString().substring(0, 10);
    final homeDir = Platform.environment['HOME'] ?? '';
    final baseDir = p.join(
      homeDir,
      '.agent-device',
      'logs',
      sessionDir,
      dayDir,
    );
    Directory(baseDir).createSync(recursive: true);

    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[:.Z]'),
      '-',
    );
    final filePath = p.join(baseDir, '$timestamp-${scope.diagnosticId}.ndjson');

    final lines = scope.events
        .map((event) => jsonEncode(redactDiagnosticData(event.toJson())))
        .toList();
    File(filePath).writeAsStringSync('${lines.join('\n')}\n');

    scope.events.clear();
    return filePath;
  } catch (_) {
    return null;
  }
}

/// Sanitizes a path component by replacing disallowed characters with underscores.
String _sanitizePathPart(String value) {
  return value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
}
