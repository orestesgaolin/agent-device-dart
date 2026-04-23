/// Port of `agent-device/src/utils/exec.ts`.
///
/// Process execution wrapper for subcommand invocation. Provides async/sync
/// command running with stdout/stderr capture, exit code checking, timeout
/// handling, and signal-based cancellation.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'errors.dart';

/// Result of a process execution.
class RunCmdResult {
  final String stdout;
  final String stderr;
  final int exitCode;
  final List<int>? stdoutBuffer;

  RunCmdResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    this.stdoutBuffer,
  });
}

/// Options for process execution.
class ExecOptions {
  final String? cwd;
  final Map<String, String>? env;
  final bool allowFailure;
  final bool binaryStdout;
  final String? stdin;
  final int? timeoutMs;
  final bool detached;

  const ExecOptions({
    this.cwd,
    this.env,
    this.allowFailure = false,
    this.binaryStdout = false,
    this.stdin,
    this.timeoutMs,
    this.detached = false,
  });
}

/// Options for streaming process execution.
class ExecStreamOptions extends ExecOptions {
  final void Function(String chunk)? onStdoutChunk;
  final void Function(String chunk)? onStderrChunk;
  final void Function(Process process)? onSpawn;

  const ExecStreamOptions({
    super.cwd,
    super.env,
    super.allowFailure = false,
    super.binaryStdout = false,
    super.stdin,
    super.timeoutMs,
    super.detached = false,
    this.onStdoutChunk,
    this.onStderrChunk,
    this.onSpawn,
  });
}

/// Options for detached process execution.
class ExecDetachedOptions extends ExecOptions {
  const ExecDetachedOptions({
    super.cwd,
    super.env,
    super.allowFailure = false,
    super.binaryStdout = false,
    super.stdin,
    super.timeoutMs,
    super.detached = true,
  });
}

/// Result of background process execution.
class ExecBackgroundResult {
  final Process process;
  final Future<RunCmdResult> wait;

  ExecBackgroundResult({required this.process, required this.wait});
}

final RegExp _bareCommandRegex = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._+-]*$');
final List<String> _windowsPathExtensions = ['.com', '.exe', '.bat', '.cmd'];

/// Asynchronously run a command with the given arguments.
///
/// Spawns a process, captures stdout/stderr, and returns the result.
/// Times out after [options.timeoutMs] if specified, throwing [AppError]
/// with code 'COMMAND_FAILED'.
Future<RunCmdResult> runCmd(
  String cmd,
  List<String> args, [
  ExecOptions options = const ExecOptions(),
]) {
  final executable = _normalizeExecutableCommand(cmd);
  return _runCmdAsync(executable, args, options, streaming: false);
}

/// Synchronously run a command with the given arguments.
///
/// Note: Dart's [Process.runSync] does not support timeouts.
/// Timeouts are silently ignored for sync execution.
RunCmdResult runCmdSync(
  String cmd,
  List<String> args, [
  ExecOptions options = const ExecOptions(),
]) {
  final executable = _normalizeExecutableCommand(cmd);

  late ProcessResult result;
  try {
    result = Process.runSync(
      executable,
      args,
      workingDirectory: options.cwd,
      environment: options.env,
      runInShell: false,
    );
  } on ProcessException catch (e) {
    if (e.toString().toLowerCase().contains('no such file') || _isEnoent(e)) {
      throw AppError(
        AppErrorCodes.toolMissing,
        '$executable not found in PATH',
        details: {'cmd': cmd},
        cause: e,
      );
    }
    throw AppError(
      AppErrorCodes.commandFailed,
      'Failed to run $executable',
      details: {'cmd': cmd, 'args': args},
      cause: e,
    );
  }

  final stdout = options.binaryStdout ? '' : _decodeOutput(result.stdout);
  final stderr = _decodeOutput(result.stderr);
  final exitCode = result.exitCode;

  if (exitCode != 0 && !options.allowFailure) {
    throw AppError(
      AppErrorCodes.commandFailed,
      '$executable exited with code $exitCode',
      details: {
        'cmd': cmd,
        'args': args,
        'stdout': stdout,
        'stderr': stderr,
        'exitCode': exitCode,
        'processExitError': true,
      },
    );
  }

  final stdoutBuffer = options.binaryStdout && result.stdout is List<int>
      ? result.stdout as List<int>
      : null;

  return RunCmdResult(
    stdout: stdout,
    stderr: stderr,
    exitCode: exitCode,
    stdoutBuffer: stdoutBuffer,
  );
}

/// Run a command with streaming stdout/stderr callbacks.
///
/// Invokes [options.onStdoutChunk] and [options.onStderrChunk] as data arrives.
Future<RunCmdResult> runCmdStreaming(
  String cmd,
  List<String> args, [
  ExecStreamOptions options = const ExecStreamOptions(),
]) {
  final executable = _normalizeExecutableCommand(cmd);
  return _runCmdAsync(
    executable,
    args,
    options,
    streaming: true,
    streamOptions: options,
  );
}

/// Check whether a command exists in PATH.
Future<bool> whichCmd(String cmd) async {
  final candidate = _normalizeExecutableLookup(cmd);
  if (candidate == null) return false;

  if (p.isAbsolute(candidate)) {
    return _isExecutablePath(candidate);
  }

  final pathValue = Platform.environment['PATH'];
  if (pathValue == null || pathValue.isEmpty) return false;

  final pathExtensions = _resolvePathExtensions();
  final pathDelimiter = Platform.isWindows ? ';' : ':';
  for (final dir in pathValue.split(pathDelimiter)) {
    final trimmedDir = dir.trim();
    if (trimmedDir.isEmpty) continue;
    for (final entry in _resolveExecutableCandidates(
      candidate,
      pathExtensions,
    )) {
      if (await _isExecutablePath(p.join(trimmedDir, entry))) {
        return true;
      }
    }
  }

  return false;
}

/// Resolve an executable path override from an environment variable.
///
/// Validates that the path is absolute and executable.
Future<String?> resolveExecutableOverridePath(
  String? rawPath,
  String envName,
) async {
  final candidate = _normalizeOverridePath(rawPath, envName, 'executable');
  if (candidate == null) return null;
  if (!await _isExecutablePath(candidate)) {
    throw AppError(
      AppErrorCodes.toolMissing,
      '$envName points to a missing or non-executable file: $candidate',
      details: {'envName': envName, 'path': candidate},
    );
  }
  return candidate;
}

/// Resolve a file path override from an environment variable.
///
/// Validates that the path is absolute and a file.
Future<String?> resolveFileOverridePath(String? rawPath, String envName) async {
  final candidate = _normalizeOverridePath(rawPath, envName, 'file');
  if (candidate == null) return null;
  if (!await _isFilePath(candidate)) {
    throw AppError(
      AppErrorCodes.toolMissing,
      '$envName points to a missing or non-file path: $candidate',
      details: {'envName': envName, 'path': candidate},
    );
  }
  return candidate;
}

/// Spawn [cmd] with [args] detached from the parent process.
///
/// TS-source counterpart: `runCmdDetached`. The TS version returns the child's
/// `pid` synchronously; Dart's `Process.start` is async, so this returns a
/// `Future<Process>`. Awaiting the future yields the live handle — the caller
/// owns its lifecycle (kill / exitCode) and can read `process.pid`.
Future<Process> runCmdDetached(
  String cmd,
  List<String> args, [
  ExecDetachedOptions options = const ExecDetachedOptions(),
]) async {
  final executable = _normalizeExecutableCommand(cmd);
  try {
    final process = await Process.start(
      executable,
      args,
      workingDirectory: options.cwd,
      environment: options.env,
      mode: ProcessStartMode.detached,
    );
    return process;
  } on ProcessException catch (e) {
    throw _translateSpawnFailure(e, executable, cmd, args);
  }
}

/// Spawn [cmd] with [args] as a long-lived background process.
///
/// TS-source counterpart: `runCmdBackground`. Returns both the live [Process]
/// handle and a `wait` future that resolves when the process exits (or
/// rejects with an [AppError] matching TS semantics: `TOOL_MISSING` for spawn
/// failures, `COMMAND_FAILED` with `processExitError: true` on non-zero exit
/// when [ExecOptions.allowFailure] is false). stdin is closed immediately;
/// stdout/stderr are captured as UTF-8 strings.
Future<ExecBackgroundResult> runCmdBackground(
  String cmd,
  List<String> args, [
  ExecOptions options = const ExecOptions(),
]) async {
  final executable = _normalizeExecutableCommand(cmd);
  final Process process;
  try {
    process = await Process.start(
      executable,
      args,
      workingDirectory: options.cwd,
      environment: options.env,
      mode: ProcessStartMode.normal,
    );
  } on ProcessException catch (e) {
    throw _translateSpawnFailure(e, executable, cmd, args);
  }

  await process.stdin.close();

  var stdout = '';
  var stderr = '';
  final stdoutFuture = process.stdout
      .transform(utf8.decoder)
      .forEach((chunk) => stdout += chunk);
  final stderrFuture = process.stderr
      .transform(utf8.decoder)
      .forEach((chunk) => stderr += chunk);

  final wait = () async {
    final exitCode = await process.exitCode;
    await stdoutFuture;
    await stderrFuture;
    if (exitCode != 0 && !options.allowFailure) {
      throw AppError(
        AppErrorCodes.commandFailed,
        '$executable exited with code $exitCode',
        details: {
          'cmd': cmd,
          'args': args,
          'stdout': stdout,
          'stderr': stderr,
          'exitCode': exitCode,
          'processExitError': true,
        },
      );
    }
    return RunCmdResult(stdout: stdout, stderr: stderr, exitCode: exitCode);
  }();

  return ExecBackgroundResult(process: process, wait: wait);
}

AppError _translateSpawnFailure(
  ProcessException e,
  String executable,
  String cmd,
  List<String> args,
) {
  final message = e.message;
  final isNotFound =
      e.errorCode == 2 || // ENOENT on POSIX
      message.contains('No such file or directory') ||
      message.contains('cannot find');
  if (isNotFound) {
    return AppError(
      AppErrorCodes.toolMissing,
      '$executable not found in PATH',
      details: {'cmd': cmd},
      cause: e,
    );
  }
  return AppError(
    AppErrorCodes.commandFailed,
    'Failed to run $executable',
    details: {'cmd': cmd, 'args': args},
    cause: e,
  );
}

// ============================================================================
// Private helpers
// ============================================================================

Future<RunCmdResult> _runCmdAsync(
  String executable,
  List<String> args,
  ExecOptions baseOptions, {
  bool streaming = false,
  ExecStreamOptions? streamOptions,
}) async {
  late Process process;
  final timeoutMs = _normalizeTimeoutMs(baseOptions.timeoutMs);
  bool didTimeout = false;

  try {
    process = await Process.start(
      executable,
      args,
      workingDirectory: baseOptions.cwd,
      environment: baseOptions.env,
      runInShell: false,
    );
  } on ProcessException catch (e) {
    if (e.toString().toLowerCase().contains('no such file') || _isEnoent(e)) {
      throw AppError(
        AppErrorCodes.toolMissing,
        '$executable not found in PATH',
        details: {'cmd': executable, 'args': args},
        cause: e,
      );
    }
    throw AppError(
      AppErrorCodes.commandFailed,
      'Failed to run $executable',
      details: {'cmd': executable, 'args': args},
      cause: e,
    );
  }

  // Set up timeout if needed
  Timer? timeoutTimer;
  if (timeoutMs != null && timeoutMs > 0) {
    timeoutTimer = Timer(Duration(milliseconds: timeoutMs), () {
      didTimeout = true;
      process.kill(ProcessSignal.sigkill);
    });
  }

  // Set up input
  if (baseOptions.stdin != null) {
    process.stdin.write(baseOptions.stdin);
  }
  await process.stdin.close();

  // Capture stdout/stderr
  final stdoutBuffer = <int>[];
  String stdout = '';
  String stderr = '';

  final stdoutFuture = baseOptions.binaryStdout
      ? process.stdout.forEach((chunk) {
          stdoutBuffer.addAll(chunk);
        })
      : process.stdout.transform(utf8.decoder).forEach((chunk) {
          stdout += chunk;
          if (streaming && streamOptions?.onStdoutChunk != null) {
            streamOptions!.onStdoutChunk!(chunk);
          }
        });

  final stderrFuture = process.stderr.transform(utf8.decoder).forEach((chunk) {
    stderr += chunk;
    if (streaming && streamOptions?.onStderrChunk != null) {
      streamOptions!.onStderrChunk!(chunk);
    }
  });

  // Invoke onSpawn callback if provided
  if (streaming) {
    streamOptions?.onSpawn?.call(process);
  }

  // Wait for process completion
  try {
    await Future.wait([stdoutFuture, stderrFuture]);
  } catch (e) {
    timeoutTimer?.cancel();
    rethrow;
  }

  final exitCode = await process.exitCode;
  timeoutTimer?.cancel();

  if (didTimeout && timeoutMs != null) {
    throw AppError(
      AppErrorCodes.commandFailed,
      '$executable timed out after ${timeoutMs}ms',
      details: {
        'cmd': executable,
        'args': args,
        'stdout': stdout,
        'stderr': stderr,
        'exitCode': exitCode,
        'timeoutMs': timeoutMs,
      },
    );
  }

  if (exitCode != 0 && !baseOptions.allowFailure) {
    throw AppError(
      AppErrorCodes.commandFailed,
      '$executable exited with code $exitCode',
      details: {
        'cmd': executable,
        'args': args,
        'stdout': stdout,
        'stderr': stderr,
        'exitCode': exitCode,
        'processExitError': true,
      },
    );
  }

  return RunCmdResult(
    stdout: stdout,
    stderr: stderr,
    exitCode: exitCode,
    stdoutBuffer: baseOptions.binaryStdout ? stdoutBuffer : null,
  );
}

String _normalizeExecutableCommand(String cmd) {
  final candidate = _normalizeExecutableLookup(cmd);
  if (candidate == null) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'Invalid executable command: ${jsonEncode(cmd)}',
      details: {
        'cmd': cmd,
        'hint':
            'Use a bare command name from PATH or an absolute executable path.',
      },
    );
  }
  return candidate;
}

String? _normalizeExecutableLookup(String cmd) {
  final candidate = cmd.trim();
  if (candidate.isEmpty || candidate.contains('\x00')) return null;
  if (p.isAbsolute(candidate)) return candidate;
  if (candidate.contains('/') || candidate.contains('\\')) return null;
  return _bareCommandRegex.hasMatch(candidate) ? candidate : null;
}

String? _normalizeOverridePath(String? rawPath, String envName, String kind) {
  final candidate = rawPath?.trim();
  if (candidate == null || candidate.isEmpty) return null;
  if (!p.isAbsolute(candidate) || candidate.contains('\x00')) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      '$envName must be an absolute $kind path, not ${jsonEncode(rawPath)}',
      details: {'envName': envName, 'path': rawPath},
    );
  }
  return candidate;
}

List<String> _resolvePathExtensions() {
  if (!Platform.isWindows) return [''];
  final rawPathExt = Platform.environment['PATHEXT'];
  if (rawPathExt == null || rawPathExt.isEmpty) {
    return _windowsPathExtensions;
  }
  final extensions = rawPathExt
      .split(';')
      .map((v) => v.trim().toLowerCase())
      .where((v) => v.isNotEmpty)
      .toList();
  return extensions.isNotEmpty ? extensions : _windowsPathExtensions;
}

List<String> _resolveExecutableCandidates(
  String cmd,
  List<String> pathExtensions,
) {
  if (!Platform.isWindows) return [cmd];
  final lowered = cmd.toLowerCase();
  if (pathExtensions.any((ext) => lowered.endsWith(ext))) {
    return [cmd];
  }
  return pathExtensions.map((ext) => '$cmd$ext').toList();
}

Future<bool> _isExecutablePath(String filePath) async {
  try {
    if (!await _isFilePath(filePath)) return false;
    final stat = await File(filePath).stat();
    // On Windows, just check if it exists. On Unix, check execute bit.
    if (Platform.isWindows) return stat.type == FileSystemEntityType.file;
    // Unix: check if executable bit is set
    final mode = stat.mode;
    return (mode & 73) != 0; // 73 = 0o111 (octal)
  } catch (e) {
    return false;
  }
}

Future<bool> _isFilePath(String filePath) async {
  try {
    final stat = await File(filePath).stat();
    return stat.type == FileSystemEntityType.file;
  } catch (e) {
    return false;
  }
}

int? _normalizeTimeoutMs(int? value) {
  if (value == null) return null;
  if (!value.isFinite) return null;
  if (value <= 0) return null;
  return value;
}

String _decodeOutput(Object? output) {
  if (output is String) return output;
  if (output is List<int>) {
    return utf8.decode(output, allowMalformed: true);
  }
  return '';
}

bool _isEnoent(ProcessException e) {
  // Check if it's ENOENT (errno 2)
  return e.toString().toLowerCase().contains('enoent') ||
      e.toString().toLowerCase().contains('no such file');
}
