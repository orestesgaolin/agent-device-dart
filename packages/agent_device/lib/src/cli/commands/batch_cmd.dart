// `agent-device batch <stepsJson|->` — execute an ordered list of
// commands as one atomic sequence. Same dispatch surface as `.ad`
// replay, sourced from a JSON document. Stops at the first failing
// step (the upstream's only wired on-error mode); the rest of the
// steps stay un-executed and the failure context surfaces in the
// result envelope.
library;

import 'dart:convert';
import 'dart:io';

import 'package:agent_device/src/replay/batch.dart';
import 'package:agent_device/src/utils/errors.dart';

import '../base_command.dart';

class BatchCommand extends AgentDeviceCommand {
  BatchCommand() {
    argParser
      ..addOption(
        'max-steps',
        help:
            'Cap the number of steps allowed in this batch. Defaults to '
            '$defaultBatchMaxSteps; the runner refuses anything above '
            '$batchMaxStepsCeiling regardless.',
        valueHelp: 'N',
      )
      ..addOption(
        'from-file',
        help:
            'Read the steps JSON array from <path> instead of the '
            'first positional argument.',
        valueHelp: 'PATH',
      );
  }

  @override
  String get name => 'batch';

  @override
  String get description =>
      'Run an ordered list of commands as one atomic sequence. Steps '
      'are a JSON array of {command, positionals?, flags?, runtime?} '
      'objects. Pass the JSON as the positional argument, "-" to read '
      'from stdin, or use --from-file <path>.';

  @override
  Future<int> run() async {
    final fromFile = argResults?['from-file'] as String?;
    final maxStepsRaw = argResults?['max-steps'] as String?;
    final maxSteps = maxStepsRaw == null
        ? defaultBatchMaxSteps
        : int.tryParse(maxStepsRaw);
    if (maxSteps == null) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        '--max-steps must be an integer.',
      );
    }

    final raw = await _readStepsJson(fromFile);
    final steps = validateAndNormalizeBatchSteps(jsonDecode(raw), maxSteps);
    final device = await openAgentDevice();
    final result = await runBatch(
      device: device,
      steps: steps,
      maxSteps: maxSteps,
    );
    emitResult(
      result.toJson(),
      humanFormat: (_) {
        if (result.ok) {
          return '✓ ${result.executed}/${result.total} steps in '
              '${result.totalDurationMs}ms';
        }
        final f = result.failure!;
        return '✗ failed at step ${f.step} (${f.command}): ${f.message}';
      },
    );
    return result.ok ? 0 : 1;
  }

  Future<String> _readStepsJson(String? fromFile) async {
    if (fromFile != null && fromFile.isNotEmpty) {
      final file = File(fromFile);
      if (!await file.exists()) {
        throw AppError(
          AppErrorCodes.invalidArgs,
          'batch --from-file path not found: $fromFile',
        );
      }
      return file.readAsString();
    }
    if (positionals.isEmpty) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'batch requires a JSON array of steps as the positional argument, '
        '"-" to read from stdin, or --from-file <path>.',
      );
    }
    final first = positionals.first;
    if (first == '-') {
      final buf = StringBuffer();
      await for (final chunk in stdin.transform(utf8.decoder)) {
        buf.write(chunk);
      }
      return buf.toString();
    }
    return first;
  }
}
