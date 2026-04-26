// Phase 10 replay runner — execute a parsed `.ad` script against a live
// [AgentDevice], step by step. Ports the core of
// `agent-device/src/daemon/handlers/session-replay-runtime.ts`: dispatch
// actions, stop at the first failure, optionally self-heal + rewrite.
//
// The dispatch table keeps things explicit: each supported action maps
// to a concrete [AgentDevice] method. Unknown actions surface as a
// structured failure so scripts fail loud rather than silently no-op.
// When `replayUpdate` is true, selector-backed failures trigger a fresh
// snapshot + rewrite via `healReplayAction`, and the healed actions are
// serialized back to the source script.
//
// Still deferred: runtime-hint / metro session bootstrap (Phase 11),
// byte-for-byte CLI stdout parity with the TS Node CLI on a `.ad`
// corpus (Phase 12 release-polish item).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_device/src/backend/backend.dart';
import 'package:agent_device/src/runtime/agent_device.dart';
import 'package:agent_device/src/runtime/interaction_target.dart';
import 'package:agent_device/src/selectors/selectors.dart';
import 'package:agent_device/src/snapshot/snapshot.dart' show SnapshotNode;
import 'package:agent_device/src/utils/errors.dart';
import 'package:path/path.dart' as p;

import 'heal.dart';
import 'replay_vars.dart';
import 'script.dart'
    show
        parseReplayScriptDetailed,
        readReplayScriptMetadata,
        serializeReplayScript;
import 'script.dart' as script show ReplayScriptMetadata;
import 'session_action.dart';

/// Re-exposed for callers that want to inspect script-level metadata
/// alongside the run result.
typedef ReplayScriptMetadata = script.ReplayScriptMetadata;

/// One executed step.
class ReplayStepResult {
  final int index;
  final SessionAction action;
  final bool ok;
  final bool healed;
  final String? errorCode;
  final String? errorMessage;
  final List<String> artifactPaths;
  final int durationMs;

  const ReplayStepResult({
    required this.index,
    required this.action,
    required this.ok,
    required this.durationMs,
    this.healed = false,
    this.errorCode,
    this.errorMessage,
    this.artifactPaths = const [],
  });

  Map<String, Object?> toJson() => {
    'step': index + 1,
    'command': action.command,
    'positionals': action.positionals,
    'ok': ok,
    if (healed) 'healed': true,
    'durationMs': durationMs,
    if (errorCode != null) 'errorCode': errorCode,
    if (errorMessage != null) 'errorMessage': errorMessage,
    if (artifactPaths.isNotEmpty) 'artifactPaths': artifactPaths,
  };
}

/// Aggregate result of replaying one script.
class ReplayRunResult {
  final String scriptPath;
  final List<ReplayStepResult> steps;
  final bool ok;
  final int durationMs;
  final ReplayScriptMetadata? metadata;

  /// Number of steps that succeeded only after a heal rewrite.
  final int healed;

  /// True when `replayUpdate=true` was requested and the heal rewrites
  /// were persisted back to the source script.
  final bool rewritten;

  const ReplayRunResult({
    required this.scriptPath,
    required this.steps,
    required this.ok,
    required this.durationMs,
    this.metadata,
    this.healed = 0,
    this.rewritten = false,
  });

  int get passed => steps.where((s) => s.ok).length;
  int get failed => steps.where((s) => !s.ok).length;

  Map<String, Object?> toJson() => {
    'scriptPath': scriptPath,
    'ok': ok,
    'durationMs': durationMs,
    'passed': passed,
    'failed': failed,
    if (healed > 0) 'healed': healed,
    if (rewritten) 'rewritten': true,
    if (metadata != null) 'metadata': metadata!.toJson(),
    'steps': steps.map((s) => s.toJson()).toList(),
  };
}

/// Replay [scriptPath] against [device].
///
/// Default behavior stops at the first failing step (matches TS replay
/// default). When [replayUpdate] is `true`, selector-backed failing
/// steps (`click`/`press`/`fill`/`get`/`is`/`wait`) try to self-heal
/// against a fresh snapshot; on a successful heal the step is retried
/// once. If any heal succeeds, the rewritten actions are serialized
/// back to [scriptPath] so the next run uses the healed selectors.
Future<ReplayRunResult> runReplayScript({
  required String scriptPath,
  required AgentDevice device,
  String? artifactDir,
  bool replayUpdate = false,
  void Function(ReplayStepResult step)? onStep,
  List<String> cliEnv = const [],
  Map<String, String>? shellEnv,
  String? sessionName,
  String? platform,
  String? deviceLabel,
}) async {
  final sw = Stopwatch()..start();
  final resolved = File(scriptPath).absolute.path;
  final text = await File(resolved).readAsString();
  final firstChar = text.trimLeft().isEmpty ? '' : text.trimLeft()[0];
  if (firstChar == '{' || firstChar == '[') {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'replay accepts .ad script files. JSON payloads are not supported.',
      details: {'scriptPath': resolved},
    );
  }

  final metadata = readReplayScriptMetadata(text);
  final parsed = parseReplayScriptDetailed(text);
  final actions = parsed.actions;
  final actionLines = parsed.actionLines;

  // Guard `replay -u` against rewriting scripts whose env directives
  // or `${VAR}` substitutions would be silently dropped — the writer
  // doesn't yet round-trip those, so let the user fix them by hand
  // first rather than corrupt their script.
  if (replayUpdate && metadata.env != null && metadata.env!.isNotEmpty) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'replay -u does not yet preserve env directives. Temporarily remove '
      'the env lines, run replay -u, then restore them.',
    );
  }
  if (replayUpdate && actionsContainInterpolation(actions)) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      r'replay -u does not yet preserve ${VAR} substitutions. Resolve or '
      'inline the variables before running with -u.',
    );
  }

  // Build the variable scope: trusted built-ins + file env + AD_VAR_*
  // shell env + CLI -e overrides. Precedence is high → low in source
  // order, so later layers overwrite earlier ones.
  final builtins = _buildReplayBuiltins(
    sessionName: sessionName,
    platform: platform ?? metadata.platform,
    deviceLabel: deviceLabel,
    artifactsDir: artifactDir,
    scriptPath: resolved,
  );
  final scope = buildReplayVarScope(
    ReplayVarSources(
      builtins: builtins,
      fileEnv: metadata.env,
      shellEnv: collectReplayShellEnv(shellEnv ?? Platform.environment),
      cliEnv: parseReplayCliEnvEntries(cliEnv),
    ),
  );

  final steps = <ReplayStepResult>[];
  var ok = true;
  final effectiveArtifactDir = artifactDir;
  if (effectiveArtifactDir != null) {
    await Directory(effectiveArtifactDir).create(recursive: true);
  }

  int healed = 0;
  for (var i = 0; i < actions.length; i++) {
    var action = actions[i];
    if (action.command == 'replay') continue; // nested replay not supported
    // Resolve `${VAR}` references against the scope before dispatch so
    // each step sees the fully substituted positionals/flags/runtime.
    action = resolveReplayAction(
      action,
      scope,
      file: resolved,
      line: actionLines[i],
    );
    final stepSw = Stopwatch()..start();
    try {
      final artifacts = await dispatchReplayAction(
        action: action,
        device: device,
        artifactDir: effectiveArtifactDir,
        index: i,
      );
      stepSw.stop();
      final step = ReplayStepResult(
        index: i,
        action: action,
        ok: true,
        durationMs: stepSw.elapsedMilliseconds,
        artifactPaths: artifacts,
      );
      steps.add(step);
      if (onStep != null) onStep(step);
    } catch (e) {
      // If healing is off, fail fast. Otherwise try one heal + retry.
      final healedAction = replayUpdate
          ? await _tryHeal(action: action, device: device)
          : null;
      if (healedAction != null) {
        try {
          final artifacts = await dispatchReplayAction(
            action: healedAction,
            device: device,
            artifactDir: effectiveArtifactDir,
            index: i,
          );
          stepSw.stop();
          actions[i] = healedAction;
          action = healedAction;
          healed += 1;
          final step = ReplayStepResult(
            index: i,
            action: healedAction,
            ok: true,
            healed: true,
            durationMs: stepSw.elapsedMilliseconds,
            artifactPaths: artifacts,
          );
          steps.add(step);
          if (onStep != null) onStep(step);
          continue;
        } catch (e2) {
          stepSw.stop();
          final code = e2 is AppError ? e2.code : AppErrorCodes.commandFailed;
          final message = e2 is AppError ? e2.message : e2.toString();
          final step = ReplayStepResult(
            index: i,
            action: healedAction,
            ok: false,
            durationMs: stepSw.elapsedMilliseconds,
            errorCode: code,
            errorMessage: 'heal attempt also failed: $message',
          );
          steps.add(step);
          ok = false;
          if (onStep != null) onStep(step);
          break;
        }
      }
      stepSw.stop();
      final code = e is AppError ? e.code : AppErrorCodes.commandFailed;
      final message = e is AppError ? e.message : e.toString();
      // Best-effort app-log dump into the artifact dir on failure so
      // postmortem has something to chew on. Silently ignored if the
      // backend doesn't support readLogs (Android today) or there's no
      // open app.
      final failureArtifacts = <String>[];
      if (effectiveArtifactDir != null) {
        final logPath = await _dumpFailureLogs(
          device: device,
          artifactDir: effectiveArtifactDir,
          index: i,
        );
        if (logPath != null) failureArtifacts.add(logPath);
      }
      final step = ReplayStepResult(
        index: i,
        action: action,
        ok: false,
        durationMs: stepSw.elapsedMilliseconds,
        errorCode: code,
        errorMessage: message,
        artifactPaths: failureArtifacts,
      );
      steps.add(step);
      ok = false;
      if (onStep != null) onStep(step);
      break;
    }
  }

  var rewritten = false;
  if (replayUpdate && healed > 0) {
    final contextLine = _extractContextLine(text);
    await File(
      resolved,
    ).writeAsString(serializeReplayScript(actions, contextLine: contextLine));
    rewritten = true;
  }

  sw.stop();
  return ReplayRunResult(
    scriptPath: resolved,
    steps: steps,
    ok: ok,
    durationMs: sw.elapsedMilliseconds,
    metadata: metadata,
    healed: healed,
    rewritten: rewritten,
  );
}

/// First line of [text] if it's a `context ...` header, otherwise null.
/// Preserves the original context when we rewrite the script so users
/// don't lose their platform / retries / timeout metadata on heal.
/// Trusted built-ins exposed under the AD_* namespace. Values come
/// from the runtime caller (CLI flags + session lookup) — none are
/// derived from the script contents. Match the TS field set.
Map<String, String> _buildReplayBuiltins({
  String? sessionName,
  String? platform,
  String? deviceLabel,
  String? artifactsDir,
  required String scriptPath,
}) {
  final cwd = Directory.current.path;
  final relative = p.isWithin(cwd, scriptPath)
      ? p.relative(scriptPath, from: cwd)
      : scriptPath;
  final builtins = <String, String>{
    if (sessionName != null && sessionName.isNotEmpty)
      'AD_SESSION': sessionName,
    'AD_FILENAME': relative,
  };
  if (platform != null && platform.isNotEmpty) {
    builtins['AD_PLATFORM'] = platform;
  }
  if (deviceLabel != null && deviceLabel.isNotEmpty) {
    builtins['AD_DEVICE'] = deviceLabel;
  }
  if (artifactsDir != null && artifactsDir.isNotEmpty) {
    builtins['AD_ARTIFACTS'] = artifactsDir;
  }
  return builtins;
}

String? _extractContextLine(String text) {
  final firstLineEnd = text.indexOf('\n');
  final first = firstLineEnd == -1 ? text : text.substring(0, firstLineEnd);
  final trimmed = first.trim();
  return trimmed.startsWith('context ') ? trimmed : null;
}

/// Best-effort dump of the last ~30s of app logs into the artifact dir
/// for a failed step. Returns the output path on success, or null if the
/// backend doesn't support log capture (e.g. no app is open, or the
/// platform isn't wired).
Future<String?> _dumpFailureLogs({
  required AgentDevice device,
  required String artifactDir,
  required int index,
}) async {
  try {
    final res = await device.readLogs(since: '30s');
    final text = res.entries.map((e) => e.message).join('\n');
    final out = File(p.join(artifactDir, 'step-${index + 1}-logs.txt'));
    await out.parent.create(recursive: true);
    await out.writeAsString(text.isEmpty ? '' : '$text\n');
    return out.path;
  } catch (_) {
    return null;
  }
}

/// Take a fresh snapshot and try to rewrite [action] against the current
/// tree. Returns null if nothing healed or snapshot fails.
Future<SessionAction?> _tryHeal({
  required SessionAction action,
  required AgentDevice device,
}) async {
  try {
    final snap = await device.snapshot();
    final rawNodes = snap.nodes ?? const [];
    final nodes = rawNodes.whereType<SnapshotNode>().toList();
    if (nodes.isEmpty) return null;
    return healReplayAction(
      action: action,
      nodes: nodes,
      platform: device.backend.platform,
    );
  } catch (_) {
    return null;
  }
}

/// Dispatch a single [SessionAction] to its matching [AgentDevice] call.
/// Returns any artifact paths (screenshot files, snapshot JSON dumps)
/// created by the action so the caller can aggregate them per-test.
///
/// Public so the `batch` runner in `batch.dart` can reuse the same
/// command surface as `.ad` replay.
Future<List<String>> dispatchReplayAction({
  required SessionAction action,
  required AgentDevice device,
  required String? artifactDir,
  required int index,
}) async {
  final command = action.command;
  final positionals = action.positionals;
  final flags = action.flags;

  switch (command) {
    case 'open':
      if (positionals.isEmpty) {
        throw AppError(
          AppErrorCodes.invalidArgs,
          'replay "open" requires a target',
        );
      }
      await device.openApp(positionals.first);
      return const [];

    case 'close':
      await device.closeApp(positionals.isEmpty ? null : positionals.first);
      return const [];

    case 'appstate':
      // Read-only probe. Useful as an assertion step (human-readable diff
      // lands in the JSON envelope, no side effects on the device).
      await device.getAppState(positionals.isEmpty ? null : positionals.first);
      return const [];

    case 'home':
      await device.pressHome();
      return const [];

    case 'back':
      await device.pressBack();
      return const [];

    case 'app-switcher':
      await device.openAppSwitcher();
      return const [];

    case 'rotate':
      if (positionals.isEmpty) {
        throw AppError(
          AppErrorCodes.invalidArgs,
          'replay "rotate" requires an orientation',
        );
      }
      await device.rotate(_parseOrientation(positionals.first));
      return const [];

    case 'type':
      if (positionals.isEmpty) {
        throw AppError(
          AppErrorCodes.invalidArgs,
          'replay "type" requires text',
        );
      }
      await device.typeText(positionals.join(' '));
      return const [];

    case 'swipe':
      if (positionals.length < 4) {
        throw AppError(
          AppErrorCodes.invalidArgs,
          'replay "swipe" requires <x1> <y1> <x2> <y2>',
        );
      }
      final coords = positionals.map(num.parse).toList();
      await device.swipe(
        coords[0],
        coords[1],
        coords[2],
        coords[3],
        durationMs: flags['durationMs'] as int?,
      );
      return const [];

    case 'scroll':
      if (positionals.isEmpty) {
        throw AppError(
          AppErrorCodes.invalidArgs,
          'replay "scroll" requires a direction (up|down|left|right)',
        );
      }
      const validDirs = {'up', 'down', 'left', 'right'};
      final dir = positionals.first;
      if (!validDirs.contains(dir)) {
        throw AppError(
          AppErrorCodes.invalidArgs,
          'Unknown scroll direction "$dir".',
        );
      }
      await device.scroll(
        dir,
        amount: (flags['amount'] as num?)?.toInt(),
        pixels: (flags['pixels'] as num?)?.toInt(),
      );
      return const [];

    case 'longpress':
      if (positionals.length < 2) {
        throw AppError(
          AppErrorCodes.invalidArgs,
          'replay "longpress" requires <x> <y>',
        );
      }
      await device.longPress(
        num.parse(positionals[0]),
        num.parse(positionals[1]),
        durationMs: flags['durationMs'] as int?,
      );
      return const [];

    case 'pinch':
      final scale = (flags['scale'] as num?)?.toDouble();
      if (scale == null || scale <= 0) {
        throw AppError(
          AppErrorCodes.invalidArgs,
          'replay "pinch" requires --scale <positive-number>',
        );
      }
      await device.pinch(scale: scale);
      return const [];

    case 'click':
    case 'press':
    case 'tap':
      final target = InteractionTarget.parseArgs(positionals);
      if (target == null) {
        throw AppError(
          AppErrorCodes.invalidArgs,
          'replay "$command" could not resolve a target from $positionals',
        );
      }
      await device.tapTarget(target);
      return const [];

    case 'fill':
      if (positionals.length < 2) {
        throw AppError(
          AppErrorCodes.invalidArgs,
          'replay "fill" requires a target and text',
        );
      }
      final lead = positionals.first;
      if (lead.startsWith('@') || !_isNum(lead)) {
        final target = InteractionTarget.parseArgs([lead]);
        if (target == null) {
          throw AppError(
            AppErrorCodes.invalidArgs,
            'replay "fill" could not resolve target "$lead"',
          );
        }
        final text = positionals.sublist(1).join(' ');
        await device.fillTarget(target, text);
      } else {
        if (positionals.length < 3) {
          throw AppError(
            AppErrorCodes.invalidArgs,
            'replay coord-style "fill" requires <x> <y> <text>',
          );
        }
        await device.fill(
          num.parse(positionals[0]),
          num.parse(positionals[1]),
          positionals.sublist(2).join(' '),
        );
      }
      return const [];

    case 'find':
      if (positionals.isEmpty) {
        throw AppError(
          AppErrorCodes.invalidArgs,
          'replay "find" requires text to search for.',
        );
      }
      await device.find(positionals.join(' '));
      return const [];

    case 'get':
      if (positionals.isEmpty) {
        throw AppError(
          AppErrorCodes.invalidArgs,
          'replay "get" requires [<attr>] <selector | @ref>.',
        );
      }
      const knownAttrs = {
        'text',
        'label',
        'value',
        'identifier',
        'type',
        'role',
        'rect',
        'ref',
      };
      late final String attr;
      late final List<String> rest;
      if (knownAttrs.contains(positionals.first)) {
        attr = positionals.first;
        rest = positionals.sublist(1);
      } else {
        attr = 'text';
        rest = positionals;
      }
      final target = InteractionTarget.parseArgs(rest);
      if (target == null) {
        throw AppError(
          AppErrorCodes.invalidArgs,
          'replay "get" requires a selector or @ref target.',
        );
      }
      await device.getAttr(attr, target);
      return const [];

    case 'is':
      if (positionals.isEmpty) {
        throw AppError(
          AppErrorCodes.invalidArgs,
          'replay "is" requires <predicate> [args...] <selector | @ref>.',
        );
      }
      final parsedIs = splitIsSelectorArgs(positionals);
      final predicate = parsedIs.predicate;
      final split = parsedIs.split;
      if (!isSupportedPredicate(predicate) || split == null) {
        throw AppError(
          AppErrorCodes.invalidArgs,
          'replay "is" requires a supported predicate and selector target.',
        );
      }
      final target = InteractionTarget.parseArgs([split.selectorExpression]);
      if (target == null) {
        throw AppError(
          AppErrorCodes.invalidArgs,
          'replay "is" could not resolve target "${split.selectorExpression}"',
        );
      }
      final expectedText = predicate == 'text'
          ? split.rest.join(' ').trim()
          : null;
      final result = await device.isPredicate(
        predicate,
        target,
        expectedText: expectedText,
      );
      if (!result.pass) {
        throw AppError(
          AppErrorCodes.commandFailed,
          'replay "is $predicate" failed: ${result.details}',
          details: {
            'predicate': predicate,
            'target': split.selectorExpression,
            'actualText': result.actualText,
          },
        );
      }
      return const [];

    case 'wait':
      if (positionals.isEmpty) {
        throw AppError(
          AppErrorCodes.invalidArgs,
          'replay "wait" requires either <milliseconds> or '
          '<predicate> [args...] <selector> [timeoutMs].',
        );
      }
      final sleepMs = int.tryParse(positionals.first);
      if (sleepMs != null && positionals.length == 1) {
        await Future<void>.delayed(Duration(milliseconds: sleepMs));
        return const [];
      }
      if (isSupportedPredicate(positionals.first)) {
        final parsedWait = splitIsSelectorArgs(positionals);
        final waitPredicate = parsedWait.predicate;
        final waitSplit = parsedWait.split;
        if (waitSplit == null) {
          throw AppError(
            AppErrorCodes.invalidArgs,
            'replay "wait" requires a selector target.',
          );
        }
        final waitTarget = InteractionTarget.parseArgs([
          waitSplit.selectorExpression,
        ]);
        if (waitTarget == null) {
          throw AppError(
            AppErrorCodes.invalidArgs,
            'replay "wait" could not resolve target "${waitSplit.selectorExpression}"',
          );
        }
        final trailing = List<String>.from(waitSplit.rest);
        var timeoutMs = 10000;
        String? expectedText;
        if (waitPredicate == 'text') {
          if (trailing.isEmpty) {
            throw AppError(
              AppErrorCodes.invalidArgs,
              'replay "wait text" requires expected text before the optional timeout.',
            );
          }
          final maybeTimeout = int.tryParse(trailing.last);
          if (maybeTimeout != null && trailing.length >= 2) {
            timeoutMs = maybeTimeout;
            trailing.removeLast();
          }
          expectedText = trailing.join(' ').trim();
          if (expectedText.isEmpty) {
            throw AppError(
              AppErrorCodes.invalidArgs,
              'replay "wait text" requires non-empty expected text.',
            );
          }
        } else if (trailing.isNotEmpty) {
          final maybeTimeout = int.tryParse(trailing.last);
          if (maybeTimeout == null || trailing.length > 1) {
            throw AppError(
              AppErrorCodes.invalidArgs,
              'replay "wait $waitPredicate" only accepts an optional trailing timeout in milliseconds.',
            );
          }
          timeoutMs = maybeTimeout;
        }
        await device.wait(
          waitPredicate,
          waitTarget,
          timeout: Duration(milliseconds: timeoutMs),
          expectedText: expectedText,
        );
        return const [];
      }
      final legacyWait = parseSelectorWaitPositionals(positionals);
      if (legacyWait.selectorExpression != null) {
        final waitTarget = InteractionTarget.parseArgs([
          legacyWait.selectorExpression!,
        ]);
        if (waitTarget == null) {
          throw AppError(
            AppErrorCodes.invalidArgs,
            'replay "wait" could not resolve target "${legacyWait.selectorExpression}"',
          );
        }
        await device.wait(
          'exists',
          waitTarget,
          timeout: Duration(
            milliseconds:
                int.tryParse(legacyWait.selectorTimeout ?? '') ?? 10000,
          ),
        );
        return const [];
      }
      throw AppError(
        AppErrorCodes.invalidArgs,
        'replay "wait" requires either <milliseconds> or a supported predicate form.',
      );

    case 'snapshot':
      final res = await device.snapshot(
        interactiveOnly: flags['snapshotInteractiveOnly'] as bool?,
        compact: flags['snapshotCompact'] as bool?,
        depth: flags['snapshotDepth'] as int?,
        scope: flags['snapshotScope'] as String?,
        raw: flags['snapshotRaw'] as bool?,
      );
      if (artifactDir != null) {
        final out = File(
          p.join(artifactDir, 'step-${index + 1}-snapshot.json'),
        );
        await out.writeAsString(
          jsonEncode({
            'nodeCount': res.nodes?.length ?? 0,
            'truncated': res.truncated,
          }),
        );
        return [out.path];
      }
      return const [];

    case 'record':
      // Script-driven recording: first positional selects the sub-action
      // (`start <outPath>` / `stop <outPath>`). Mirrors the CLI's
      // `record start` / `record stop` split so a .ad script can fence
      // a segment of interactions with recording around it.
      if (positionals.isEmpty) {
        throw AppError(
          AppErrorCodes.invalidArgs,
          'replay "record" requires a sub-action (start <outPath> | stop <outPath>).',
        );
      }
      final sub = positionals.first;
      if (sub == 'start') {
        if (positionals.length < 2) {
          throw AppError(
            AppErrorCodes.invalidArgs,
            'replay "record start" requires <outPath>.',
          );
        }
        final recOutPath = positionals[1];
        await device.startRecording(
          recOutPath,
          fps: (flags['fps'] as num?)?.toInt(),
          quality: (flags['quality'] as num?)?.toInt(),
        );
        return const [];
      }
      if (sub == 'stop') {
        if (positionals.length < 2) {
          throw AppError(
            AppErrorCodes.invalidArgs,
            'replay "record stop" requires <outPath>.',
          );
        }
        final recOutPath = positionals[1];
        final res = await device.stopRecording(recOutPath);
        return res.path == null ? const [] : [res.path!];
      }
      throw AppError(
        AppErrorCodes.invalidArgs,
        'replay "record" sub-action must be "start" or "stop", got "$sub".',
      );

    case 'screenshot':
      final outPath = positionals.isNotEmpty
          ? positionals.first
          : (artifactDir == null
                ? p.join(
                    Directory.systemTemp.path,
                    'ad-step-${index + 1}-${DateTime.now().microsecondsSinceEpoch}.png',
                  )
                : p.join(artifactDir, 'step-${index + 1}.png'));
      await device.screenshot(
        outPath,
        fullscreen: flags['screenshotFullscreen'] == true ? true : null,
        maxSize: (flags['screenshotMaxSize'] as num?)?.toInt(),
      );
      return [outPath];

    case 'clipboard':
      final setText = flags['set']?.toString() ?? (positionals.isNotEmpty ? positionals.first : null);
      if (setText != null) {
        await device.setClipboard(setText);
      } else {
        await device.getClipboard();
      }
      return const [];

    case 'keyboard':
      if (positionals.isEmpty) {
        throw AppError(
          AppErrorCodes.invalidArgs,
          'replay "keyboard" requires an action (status | get | dismiss | hide).',
        );
      }
      await device.setKeyboard(positionals.first);
      return const [];

    case 'settings':
      await device.openSettings(positionals.isEmpty ? null : positionals.first);
      return const [];

    case 'trigger-app-event':
      if (positionals.isEmpty) {
        throw AppError(
          AppErrorCodes.invalidArgs,
          'replay "trigger-app-event" requires an event name.',
        );
      }
      Map<String, Object?>? payload;
      final payloadRaw = flags['payload'];
      if (payloadRaw is Map) {
        payload = {for (final e in payloadRaw.entries) e.key.toString(): e.value};
      }
      await device.triggerAppEvent(positionals.first, payload: payload);
      return const [];

    case 'alert':
      final sub = positionals.isNotEmpty ? positionals.first : 'get';
      final alertAction = BackendAlertAction.fromString(sub);
      if (alertAction == null) {
        throw AppError(
          AppErrorCodes.invalidArgs,
          'replay "alert" action must be get | accept | dismiss | wait, got "$sub".',
        );
      }
      await device.handleAlert(alertAction);
      return const [];

    case 'install':
      if (positionals.isEmpty) {
        throw AppError(
          AppErrorCodes.invalidArgs,
          'replay "install" requires a path.',
        );
      }
      await device.installApp(
        path: positionals.first,
        app: flags['app']?.toString(),
      );
      return const [];

    case 'push':
      if (positionals.isEmpty) {
        throw AppError(
          AppErrorCodes.invalidArgs,
          'replay "push" requires a target path.',
        );
      }
      final pushPayload = flags['payload'];
      final BackendPushInput input;
      if (pushPayload is Map) {
        input = BackendPushInputJson(
          {for (final e in pushPayload.entries) e.key.toString(): e.value},
        );
      } else if (positionals.length >= 2) {
        input = BackendPushInputFile(positionals[1]);
      } else {
        throw AppError(
          AppErrorCodes.invalidArgs,
          'replay "push" requires --payload <json> or <target> <source-path>.',
        );
      }
      await device.pushFile(input, positionals.first);
      return const [];

    case 'apps':
      await device.listApps();
      return const [];

    case 'boot':
      await device.bootDevice(
        name: positionals.isEmpty ? null : positionals.first,
      );
      return const [];

    default:
      throw AppError(
        AppErrorCodes.unsupportedOperation,
        'replay does not yet handle command "$command"',
        details: {'step': index + 1, 'command': command},
      );
  }
}

BackendDeviceOrientation _parseOrientation(String raw) => switch (raw) {
  'portrait' => BackendDeviceOrientation.portrait,
  'portrait-upside-down' ||
  'portraitUpsideDown' => BackendDeviceOrientation.portraitUpsideDown,
  'landscape-left' || 'landscapeLeft' => BackendDeviceOrientation.landscapeLeft,
  'landscape-right' ||
  'landscapeRight' => BackendDeviceOrientation.landscapeRight,
  _ => throw AppError(AppErrorCodes.invalidArgs, 'Unknown orientation "$raw".'),
};

bool _isNum(String s) => num.tryParse(s) != null;
