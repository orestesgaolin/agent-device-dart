// Port of agent-device/src/core/batch.ts + a thin runner inspired by
// daemon/handlers/session-batch.ts. Runs an ordered list of CLI-style
// commands as one atomic sequence — same dispatch surface as `.ad`
// replay, just sourced from a JSON document.
//
// The TS daemon variant supports `batchOnError: 'stop' | 'continue' |
// 'fail'` but only `'stop'` is actually wired upstream; we match that.
// Nested `batch` and `replay` are blocked: batches don't recurse, and
// replay scripts have their own top-level entry point.
library;

import 'dart:async';
import 'dart:convert';

import 'package:agent_device/src/runtime/agent_device.dart';
import 'package:agent_device/src/utils/errors.dart';

import 'replay_runtime.dart' show dispatchReplayAction;
import 'session_action.dart';

/// Maximum number of steps a batch may carry by default. The runner
/// also caps at [batchMaxStepsCeiling] regardless of caller request,
/// matching the upstream's safety net.
const int defaultBatchMaxSteps = 100;
const int batchMaxStepsCeiling = 1000;

const Set<String> _batchBlockedCommands = {'batch', 'replay'};
const Set<String> _batchAllowedStepKeys = {
  'command',
  'positionals',
  'flags',
  'runtime',
};

/// One step in a batch — already validated and normalised.
class BatchStep {
  final String command;
  final List<String> positionals;
  final Map<String, Object?> flags;
  final Object? runtime;

  const BatchStep({
    required this.command,
    this.positionals = const [],
    this.flags = const {},
    this.runtime,
  });
}

/// Per-step result emitted on success.
class BatchStepResult {
  final int step;
  final String command;
  final int durationMs;
  final List<String> artifactPaths;

  const BatchStepResult({
    required this.step,
    required this.command,
    required this.durationMs,
    this.artifactPaths = const [],
  });

  Map<String, Object?> toJson() => {
    'step': step,
    'command': command,
    'ok': true,
    'durationMs': durationMs,
    if (artifactPaths.isNotEmpty) 'artifactPaths': artifactPaths,
  };
}

/// Aggregate result of running a batch.
class BatchRunResult {
  final int total;
  final int executed;
  final int totalDurationMs;
  final List<BatchStepResult> results;
  final BatchStepFailure? failure;

  const BatchRunResult({
    required this.total,
    required this.executed,
    required this.totalDurationMs,
    required this.results,
    this.failure,
  });

  bool get ok => failure == null;

  Map<String, Object?> toJson() => {
    'ok': ok,
    'total': total,
    'executed': executed,
    'totalDurationMs': totalDurationMs,
    'results': results.map((r) => r.toJson()).toList(),
    if (failure != null) 'failure': failure!.toJson(),
  };
}

/// Recorded failure context — the failing step plus everything that
/// completed before it. Mirrors the TS daemon error envelope.
class BatchStepFailure {
  final int step;
  final String command;
  final List<String> positionals;
  final String code;
  final String message;

  const BatchStepFailure({
    required this.step,
    required this.command,
    required this.positionals,
    required this.code,
    required this.message,
  });

  Map<String, Object?> toJson() => {
    'step': step,
    'command': command,
    'positionals': positionals,
    'code': code,
    'message': message,
  };
}

/// Parse and validate a JSON-encoded array of steps. Used by the CLI
/// to decode the `batch` command's positional / stdin payload.
List<BatchStep> parseBatchStepsJson(String raw) {
  Object? parsed;
  try {
    parsed = jsonDecode(raw);
  } on FormatException {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'Batch steps must be valid JSON.',
    );
  }
  if (parsed is! List || parsed.isEmpty) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'Batch steps must be a non-empty JSON array.',
    );
  }
  return validateAndNormalizeBatchSteps(parsed, defaultBatchMaxSteps);
}

/// Validate + coerce raw step data (typically from JSON) into typed
/// [BatchStep] records. Throws [AppError] with [AppErrorCodes.invalidArgs]
/// for any malformed step.
List<BatchStep> validateAndNormalizeBatchSteps(Object? steps, int maxSteps) {
  if (steps is! List || steps.isEmpty) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'batch requires a non-empty batchSteps array.',
    );
  }
  if (steps.length > maxSteps) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'batch has ${steps.length} steps; max allowed is $maxSteps.',
    );
  }

  final normalized = <BatchStep>[];
  for (var index = 0; index < steps.length; index++) {
    final raw = steps[index];
    if (raw is! Map) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'Invalid batch step at index $index.',
      );
    }
    final unknownKeys = raw.keys
        .map((k) => k.toString())
        .where((k) => !_batchAllowedStepKeys.contains(k))
        .toList();
    if (unknownKeys.isNotEmpty) {
      final fields = unknownKeys.map((k) => '"$k"').join(', ');
      throw AppError(
        AppErrorCodes.invalidArgs,
        'Batch step ${index + 1} has unknown field(s): $fields. '
        'Allowed fields: command, positionals, flags, runtime.',
      );
    }
    final commandRaw = raw['command'];
    final command = commandRaw is String ? commandRaw.trim().toLowerCase() : '';
    if (command.isEmpty) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'Batch step ${index + 1} requires command.',
      );
    }
    if (_batchBlockedCommands.contains(command)) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'Batch step ${index + 1} cannot run $command.',
      );
    }
    final positionalsRaw = raw['positionals'];
    if (positionalsRaw != null && positionalsRaw is! List) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'Batch step ${index + 1} positionals must be an array.',
      );
    }
    final positionals =
        (positionalsRaw as List?)
            ?.map(
              (v) => v is String
                  ? v
                  : throw AppError(
                      AppErrorCodes.invalidArgs,
                      'Batch step ${index + 1} positionals must contain '
                      'only strings.',
                    ),
            )
            .toList() ??
        const <String>[];
    final flagsRaw = raw['flags'];
    if (flagsRaw != null && (flagsRaw is! Map)) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'Batch step ${index + 1} flags must be an object.',
      );
    }
    final flags = <String, Object?>{};
    if (flagsRaw is Map) {
      flagsRaw.forEach((k, v) => flags[k.toString()] = v);
    }
    final runtimeRaw = raw['runtime'];
    if (runtimeRaw != null && (runtimeRaw is! Map)) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'Batch step ${index + 1} runtime must be an object.',
      );
    }
    normalized.add(
      BatchStep(
        command: command,
        positionals: positionals,
        flags: flags,
        runtime: runtimeRaw,
      ),
    );
  }
  return normalized;
}

/// Run a normalised list of [steps] against [device]. Stops at the
/// first failing step (the only on-error mode upstream wires through).
/// [maxSteps] is clamped against [batchMaxStepsCeiling] regardless of
/// caller request.
Future<BatchRunResult> runBatch({
  required AgentDevice device,
  required List<BatchStep> steps,
  String? artifactDir,
  int maxSteps = defaultBatchMaxSteps,
}) async {
  if (maxSteps < 1 || maxSteps > batchMaxStepsCeiling) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'Invalid batch max-steps: $maxSteps '
      '(must be between 1 and $batchMaxStepsCeiling).',
    );
  }
  if (steps.length > maxSteps) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'batch has ${steps.length} steps; max allowed is $maxSteps.',
    );
  }
  final overallStarted = DateTime.now();
  final results = <BatchStepResult>[];
  for (var index = 0; index < steps.length; index++) {
    final step = steps[index];
    final stepNum = index + 1;
    final stepStarted = DateTime.now();
    final action = SessionAction(
      ts: stepStarted.millisecondsSinceEpoch,
      command: step.command,
      positionals: step.positionals,
      flags: step.flags,
    );
    try {
      final artifacts = await dispatchReplayAction(
        action: action,
        device: device,
        artifactDir: artifactDir,
        index: index,
      );
      results.add(
        BatchStepResult(
          step: stepNum,
          command: step.command,
          durationMs: DateTime.now().difference(stepStarted).inMilliseconds,
          artifactPaths: artifacts,
        ),
      );
    } catch (e) {
      final code = e is AppError ? e.code : AppErrorCodes.commandFailed;
      final message = e is AppError ? e.message : e.toString();
      return BatchRunResult(
        total: steps.length,
        executed: index,
        totalDurationMs: DateTime.now()
            .difference(overallStarted)
            .inMilliseconds,
        results: results,
        failure: BatchStepFailure(
          step: stepNum,
          command: step.command,
          positionals: step.positionals,
          code: code,
          message:
              'Batch failed at step $stepNum (${step.command}): '
              '$message',
        ),
      );
    }
  }
  return BatchRunResult(
    total: steps.length,
    executed: steps.length,
    totalDurationMs: DateTime.now().difference(overallStarted).inMilliseconds,
    results: results,
  );
}
