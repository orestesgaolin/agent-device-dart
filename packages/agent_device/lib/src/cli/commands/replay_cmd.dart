// `agent-device replay <script>` — execute an .ad replay script end to
// end. Phase 10 MVP slice: no healing, no record-trace, no runtime-hint
// session bootstrapping. Failure mode stops at the first failing step
// and emits the failure context.
library;

import 'dart:async';
import 'dart:io';

import 'package:agent_device/src/replay/replay_runtime.dart';
import 'package:agent_device/src/replay/script.dart' as script;
import 'package:agent_device/src/utils/errors.dart';
import 'package:path/path.dart' as p;

import '../base_command.dart';

class ReplayCommand extends AgentDeviceCommand {
  ReplayCommand() {
    argParser
      ..addOption(
        'artifact-dir',
        help:
            'Directory to write per-step artifacts (screenshots, snapshot '
            'dumps). Defaults to <state-dir>/test-artifacts/<script-name>/'
            '<timestamp>/.',
      )
      ..addFlag(
        'replay-update',
        help:
            'When a selector-backed step fails, attempt to heal it against '
            'a fresh snapshot and, on success, rewrite the .ad file so '
            'the next run uses the healed selectors.',
        negatable: false,
      )
      ..addMultiOption(
        'env',
        abbr: 'e',
        help:
            r'Override a replay variable (KEY=VALUE). Highest precedence; '
            r'overrides AD_VAR_* shell env, file env directives, and '
            r'built-ins. Repeat to set multiple. Reserved AD_* keys are '
            r'rejected.',
        valueHelp: 'KEY=VALUE',
      );
  }

  @override
  String get name => 'replay';

  @override
  String get description => 'Replay an .ad script against a live device.';

  @override
  Future<int> run() async {
    if (positionals.isEmpty) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'replay requires a script path.',
      );
    }
    final scriptPath = positionals.first;
    if (!await File(scriptPath).exists()) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'replay script not found: $scriptPath',
      );
    }
    final device = await openAgentDevice();
    final artifactDir = _resolveArtifactDir(scriptPath);
    final replayUpdate = argResults?['replay-update'] == true;
    final cliEnv =
        argResults?['env'] as List<String>? ?? const <String>[];
    final result = await runReplayScript(
      scriptPath: scriptPath,
      device: device,
      artifactDir: artifactDir,
      replayUpdate: replayUpdate,
      cliEnv: cliEnv,
      sessionName: sessionName,
      platform: argResults?['platform'] as String?,
      deviceLabel: argResults?['device'] as String?,
      onStep: (step) {
        if (!asJson) {
          final marker = step.ok ? 'ok' : 'FAIL';
          stdout.writeln(
            '  [$marker] step ${step.index + 1} ${step.action.command} '
            '(${step.durationMs}ms)${step.errorMessage == null ? '' : ' — ${step.errorMessage}'}',
          );
        }
      },
    );
    emitResult(
      result.toJson(),
      humanFormat: (_) =>
          '${result.ok ? '✓' : '✗'} ${result.passed}/${result.steps.length} '
          'steps passed in ${result.durationMs}ms',
    );
    return result.ok ? 0 : 1;
  }

  String? _resolveArtifactDir(String scriptPath) {
    final explicit = argResults?['artifact-dir'] as String?;
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final home =
        Platform.environment['AGENT_DEVICE_STATE_DIR'] ??
        '${Platform.environment['HOME']}/.agent-device';
    final scriptName = p.basenameWithoutExtension(scriptPath);
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    return p.join(home, 'test-artifacts', scriptName, ts);
  }
}

class TestCommand extends AgentDeviceCommand {
  TestCommand() {
    argParser
      ..addOption(
        'retries',
        help: 'Number of retry attempts per script on failure.',
        defaultsTo: '0',
      )
      ..addOption(
        'artifact-dir',
        help:
            'Root directory for per-script artifacts. Defaults to '
            '<state-dir>/test-artifacts/.',
      )
      ..addFlag(
        'replay-update',
        help:
            'Self-heal failing selector steps on a fresh snapshot and '
            'write healed actions back to the .ad file.',
        negatable: false,
      )
      ..addMultiOption(
        'env',
        abbr: 'e',
        help:
            r'Override a replay variable (KEY=VALUE). Repeat to set '
            r'multiple. Reserved AD_* keys are rejected.',
        valueHelp: 'KEY=VALUE',
      )
      ..addFlag(
        'fail-fast',
        help:
            'Stop running additional scripts after the first failure. '
            'Each script still exhausts its own retries before failing.',
        negatable: false,
      )
      ..addOption(
        'timeout-ms',
        help:
            'Per-script wall-clock timeout in milliseconds. The active '
            'attempt is cancelled and recorded as a failure when the '
            'budget is exhausted; remaining retries are still tried. '
            'Per-script `context timeout=` overrides this CLI value.',
      )
      ..addOption(
        'report-junit',
        help:
            'Write a JUnit XML report to the given path summarising every '
            'script + attempt. Suitable for CI consumers (GitHub Actions, '
            'Jenkins, etc.).',
        valueHelp: 'PATH',
      );
  }

  @override
  String get name => 'test';

  @override
  String get description =>
      'Run one or more .ad scripts. Accepts paths or a glob.';

  @override
  Future<int> run() async {
    if (positionals.isEmpty) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'test requires at least one script path or glob.',
      );
    }
    final cliRetries =
        int.tryParse(argResults?['retries'] as String? ?? '0') ?? 0;
    final rootDir = argResults?['artifact-dir'] as String?;
    final replayUpdate = argResults?['replay-update'] == true;
    final cliEnv =
        argResults?['env'] as List<String>? ?? const <String>[];
    final failFast = argResults?['fail-fast'] == true;
    final cliTimeoutMs = int.tryParse(
      argResults?['timeout-ms'] as String? ?? '',
    );
    if (cliTimeoutMs != null && cliTimeoutMs <= 0) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        '--timeout-ms must be a positive integer.',
      );
    }
    final junitPath = argResults?['report-junit'] as String?;

    final scripts = await _resolveScripts(positionals);
    if (scripts.isEmpty) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'test: no .ad scripts matched ${positionals.join(' ')}.',
      );
    }

    final results = <Map<String, Object?>>[];
    int passed = 0;
    int failed = 0;

    for (final scriptPath in scripts) {
      if (!asJson) stdout.writeln('› ${p.basename(scriptPath)}');
      // Per-script context header can override retries + timeout (TS parity).
      final text = await File(scriptPath).readAsString();
      final meta = script.readReplayScriptMetadata(text);
      final retries = meta.retries ?? cliRetries;
      final timeoutMs = meta.timeoutMs ?? cliTimeoutMs;
      final device = await openAgentDevice();
      Object? finalResult;
      bool ok = false;
      final scriptStartedAt = DateTime.now();
      for (int attempt = 0; attempt <= retries; attempt++) {
        final artifactDir = _artifactDirFor(rootDir, scriptPath, attempt);
        try {
          final attemptFuture = runReplayScript(
            scriptPath: scriptPath,
            device: device,
            artifactDir: artifactDir,
            replayUpdate: replayUpdate,
            cliEnv: cliEnv,
            sessionName: sessionName,
            platform: argResults?['platform'] as String?,
            deviceLabel: argResults?['device'] as String?,
            onStep: (step) {
              if (!asJson) {
                final marker = step.ok ? 'ok' : 'FAIL';
                stdout.writeln(
                  '  [$marker] step ${step.index + 1} ${step.action.command}'
                  '${step.errorMessage == null ? '' : ' — ${step.errorMessage}'}',
                );
              }
            },
          );
          final res = timeoutMs == null
              ? await attemptFuture
              : await attemptFuture.timeout(
                  Duration(milliseconds: timeoutMs),
                  onTimeout: () => throw TimeoutException(
                    'replay timed out after ${timeoutMs}ms',
                    Duration(milliseconds: timeoutMs),
                  ),
                );
          finalResult = {...res.toJson(), 'attempts': attempt + 1};
          ok = res.ok;
          if (ok) break;
        } on TimeoutException catch (e) {
          finalResult = {
            'scriptPath': scriptPath,
            'attempts': attempt + 1,
            'ok': false,
            'errorCode': 'TIMEOUT',
            'errorMessage': e.message ?? 'replay timed out',
            'timeoutMs': timeoutMs,
          };
          if (attempt == retries) break;
        } catch (e) {
          finalResult = {
            'scriptPath': scriptPath,
            'attempts': attempt + 1,
            'ok': false,
            'errorMessage': e.toString(),
          };
          if (attempt == retries) break;
        }
      }
      final scriptDurationMs =
          DateTime.now().difference(scriptStartedAt).inMilliseconds;
      final entry = {
        ...finalResult! as Map<String, Object?>,
        'scriptDurationMs': scriptDurationMs,
        'scriptName': p.basename(scriptPath),
      };
      results.add(entry);
      if (ok) {
        passed++;
      } else {
        failed++;
        if (failFast) {
          if (!asJson) stdout.writeln('› stopping (--fail-fast)');
          break;
        }
      }
    }

    final attempted = results.length;
    final summary = {
      'passed': passed,
      'failed': failed,
      'total': scripts.length,
      'attempted': attempted,
      if (failFast && attempted < scripts.length) 'stoppedEarly': true,
      'results': results,
    };

    if (junitPath != null && junitPath.isNotEmpty) {
      try {
        final file = File(junitPath);
        await file.parent.create(recursive: true);
        await file.writeAsString(buildJUnitReport(results));
      } on Object catch (e) {
        stderr.writeln(
          'warning: failed to write JUnit report to $junitPath: $e',
        );
      }
    }

    emitResult(
      summary,
      humanFormat: (_) => failed == 0
          ? '✓ $passed/${scripts.length} scripts passed'
          : '✗ $failed/$attempted scripts failed, $passed passed',
    );
    return failed == 0 ? 0 : 1;
  }

  String _artifactDirFor(String? root, String script, int attempt) {
    final base =
        root ??
        p.join(
          Platform.environment['AGENT_DEVICE_STATE_DIR'] ??
              '${Platform.environment['HOME']}/.agent-device',
          'test-artifacts',
        );
    final name = p.basenameWithoutExtension(script);
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    return p.join(base, name, '$ts-attempt-${attempt + 1}');
  }

  Future<List<String>> _resolveScripts(List<String> inputs) async {
    final out = <String>[];
    for (final raw in inputs) {
      final entity = await _resolveOne(raw);
      out.addAll(entity);
    }
    // Dedup while preserving order.
    final seen = <String>{};
    return out.where(seen.add).toList();
  }

  Future<List<String>> _resolveOne(String raw) async {
    if (await File(raw).exists()) return [File(raw).absolute.path];
    if (await Directory(raw).exists()) {
      final dir = Directory(raw);
      final hits = <String>[];
      await for (final e in dir.list(recursive: true)) {
        if (e is File && e.path.endsWith('.ad')) {
          hits.add(e.absolute.path);
        }
      }
      hits.sort();
      return hits;
    }
    // Treat as glob.
    return _expandGlob(raw);
  }

  Future<List<String>> _expandGlob(String pattern) async {
    final slash = pattern.indexOf('/');
    final baseSegment = slash >= 0 ? pattern.substring(0, slash) : '.';
    final rest = slash >= 0 ? pattern.substring(slash + 1) : pattern;
    final base = Directory(baseSegment.isEmpty ? '.' : baseSegment);
    if (!await base.exists()) return const [];
    // Very small glob: only supports `**/*.ad` or `*.ad` within base.
    final recursive = rest.contains('**');
    final hits = <String>[];
    await for (final e in base.list(recursive: recursive)) {
      if (e is File && e.path.endsWith('.ad')) hits.add(e.absolute.path);
    }
    hits.sort();
    return hits;
  }
}

/// Serialise the per-script results from `agent-device test` into a
/// JUnit-XML `<testsuite>` document. Each result map is expected to
/// carry `scriptName` (or `scriptPath`), `scriptDurationMs`, `ok`,
/// and on failure `errorCode` + `errorMessage`. Pure function so it
/// can be unit-tested without spinning up a device.
String buildJUnitReport(List<Map<String, Object?>> results) {
  final buf = StringBuffer();
  buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  final totalTime = results.fold<int>(
    0,
    (acc, r) => acc + ((r['scriptDurationMs'] as int?) ?? 0),
  );
  final failures = results.where((r) => r['ok'] != true).length;
  buf.writeln(
    '<testsuite name="agent-device" tests="${results.length}" '
    'failures="$failures" time="${(totalTime / 1000).toStringAsFixed(3)}">',
  );
  for (final r in results) {
    final name = (r['scriptName'] ?? r['scriptPath'] ?? 'unknown') as String;
    final timeSec = ((r['scriptDurationMs'] as int?) ?? 0) / 1000;
    final ok = r['ok'] == true;
    buf.write(
      '  <testcase name="${_xmlAttr(name)}" '
      'time="${timeSec.toStringAsFixed(3)}"',
    );
    if (ok) {
      buf.writeln(' />');
    } else {
      buf.writeln('>');
      final code = (r['errorCode'] as String?) ?? 'FAIL';
      final msg = (r['errorMessage'] as String?) ?? 'replay failed';
      buf.writeln(
        '    <failure type="${_xmlAttr(code)}" '
        'message="${_xmlAttr(msg)}"></failure>',
      );
      buf.writeln('  </testcase>');
    }
  }
  buf.writeln('</testsuite>');
  return buf.toString();
}

String _xmlAttr(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
