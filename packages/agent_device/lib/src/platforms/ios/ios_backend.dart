// Phase 8B iOS backend — adds XCUITest-runner-backed methods on top of
// the Phase 8A simctl subset. The runner is launched once per
// BackendCommandContext (keyed on deviceSerial + session name via
// metadata stored in ctx.metadata['iosRunner'] by the runtime layer);
// subsequent commands reuse the live port. When the session closes the
// runtime issues a `shutdown` command via [shutdownRunner].
library;

import 'dart:convert';
import 'dart:io';

import 'package:agent_device/src/backend/backend.dart';
import 'package:agent_device/src/runtime/paths.dart';
import 'package:agent_device/src/snapshot/snapshot.dart';
import 'package:agent_device/src/utils/errors.dart';
import 'package:agent_device/src/utils/exec.dart';
import 'package:path/path.dart' as p;

import 'app_lifecycle.dart';
import 'devicectl.dart';
import 'devices.dart';
import 'runner_client.dart';
import 'screenshot.dart';

class IosBackend extends Backend {
  const IosBackend();

  @override
  AgentDeviceBackendPlatform get platform => AgentDeviceBackendPlatform.ios;

  /// Phase 8A/B treats `BackendCommandContext.deviceSerial` as the iOS
  /// simulator UDID — same plumbing as Android's `serial`.
  String _udid(BackendCommandContext ctx) {
    final udid = ctx.deviceSerial;
    if (udid == null || udid.isEmpty) {
      unsupported('operation requires ctx.deviceSerial (simulator UDID)');
    }
    return udid;
  }

  // =========================================================================
  // Runner session lookup / launch.
  // =========================================================================

  /// Get a live runner for the ctx's UDID. Reuses a runner recorded on
  /// disk under `<stateDir>/ios-runners/<udid>.json` (and verified with a
  /// port probe) across CLI invocations; falls back to launching a fresh
  /// detached runner via `xcodebuild test-without-building`. The cache
  /// key is the UDID since one simulator can only host one runner at a
  /// time.
  Future<IosRunnerSession> _runner(BackendCommandContext ctx) async {
    final udid = _udid(ctx);
    final inProc = _IosRunnerCache.instance.get(udid);
    if (inProc != null && await IosRunnerClient.isAlive(inProc)) return inProc;

    final diskRecord = await _readRunnerRecord(udid);
    if (diskRecord != null && await IosRunnerClient.isAlive(diskRecord)) {
      _IosRunnerCache.instance.set(udid, diskRecord);
      return diskRecord;
    }
    // Stale or missing — clear the record and launch fresh.
    await _deleteRunnerRecord(udid);
    final session = await IosRunnerClient.launch(udid: udid);
    _IosRunnerCache.instance.set(udid, session);
    await _writeRunnerRecord(session);
    return session;
  }

  /// Shut down the cached runner for [udid] (if any). Called by the
  /// runtime layer on session close. Safe to call repeatedly.
  static Future<void> shutdownRunnerFor(String udid) async {
    final inProc = _IosRunnerCache.instance.pop(udid);
    if (inProc != null) await IosRunnerClient.stop(inProc);
    final disk = await _readRunnerRecord(udid);
    if (disk != null) {
      await IosRunnerClient.stop(disk);
      await _deleteRunnerRecord(udid);
    }
  }

  /// `<stateDir>/ios-runners/<udid>.json` holds the last-known
  /// `{udid, port, xcodebuildPid, xctestrunPath, logPath}` for the runner
  /// driving [udid].
  static File _runnerRecordFile(String udid) {
    final paths = resolveStatePaths();
    return File(p.join(paths.baseDir, 'ios-runners', '$udid.json'));
  }

  static Future<IosRunnerSession?> _readRunnerRecord(String udid) async {
    final file = _runnerRecordFile(udid);
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      return IosRunnerSession.fromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  static Future<void> _writeRunnerRecord(IosRunnerSession s) async {
    final file = _runnerRecordFile(s.udid);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(s.toJson()));
  }

  static Future<void> _deleteRunnerRecord(String udid) async {
    final file = _runnerRecordFile(udid);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  // =========================================================================
  // Snapshot + Screenshot
  // =========================================================================

  @override
  Future<BackendSnapshotResult> captureSnapshot(
    BackendCommandContext ctx,
    BackendSnapshotOptions? options,
  ) async {
    final session = await _runner(ctx);
    final body = <String, Object?>{
      'command': 'snapshot',
      if (options?.interactiveOnly != null)
        'interactiveOnly': options!.interactiveOnly,
      if (options?.compact != null) 'compact': options!.compact,
      if (options?.depth != null) 'depth': options!.depth,
      if (options?.scope != null) 'scope': options!.scope,
      if (options?.raw != null) 'raw': options!.raw,
    };
    final res = await IosRunnerClient.send(session, body);
    if (!res.ok) {
      throw AppError(
        AppErrorCodes.commandFailed,
        'iOS runner snapshot failed: ${res.errorMessage ?? 'unknown error'}',
      );
    }
    final data = res.data;
    if (data is! Map) {
      throw AppError(
        AppErrorCodes.commandFailed,
        'iOS runner returned unexpected shape for snapshot.',
      );
    }
    final rawNodes = (data['nodes'] as List?) ?? const [];
    final snapshotNodes = attachRefs(
      rawNodes.map(_rawNodeFromJson).whereType<RawSnapshotNode>().toList(),
    );
    return BackendSnapshotResult(
      nodes: snapshotNodes,
      truncated: data['truncated'] == true,
      analysis: BackendSnapshotAnalysis(
        rawNodeCount: snapshotNodes.length,
        maxDepth: snapshotNodes.fold<int>(
          0,
          (m, n) => (n.depth ?? 0) > m ? (n.depth ?? 0) : m,
        ),
      ),
    );
  }

  /// Phase 8A kept screenshot on simctl. Keep it there — simctl is
  /// reliable for full-screen captures and doesn't need the runner.
  @override
  Future<BackendScreenshotResult?> captureScreenshot(
    BackendCommandContext ctx,
    String outPath,
    BackendScreenshotOptions? options,
  ) async {
    await screenshotIos(_udid(ctx), outPath);
    return BackendScreenshotResult(path: outPath);
  }

  // =========================================================================
  // Interaction
  // =========================================================================

  @override
  Future<BackendActionResult> tap(
    BackendCommandContext ctx,
    Point point,
    BackendTapOptions? options,
  ) async {
    final session = await _runner(ctx);
    await _sendOrThrow(session, {'command': 'tap', 'x': point.x, 'y': point.y});
    return null;
  }

  @override
  Future<BackendActionResult> longPress(
    BackendCommandContext ctx,
    Point point,
    BackendLongPressOptions? options,
  ) async {
    final session = await _runner(ctx);
    await _sendOrThrow(session, {
      'command': 'longPress',
      'x': point.x,
      'y': point.y,
      if (options?.durationMs != null) 'durationMs': options!.durationMs,
    });
    return null;
  }

  @override
  Future<BackendActionResult> swipe(
    BackendCommandContext ctx,
    Point from,
    Point to,
    BackendSwipeOptions? options,
  ) async {
    final session = await _runner(ctx);
    await _sendOrThrow(session, {
      'command': 'drag',
      'x': from.x,
      'y': from.y,
      'x2': to.x,
      'y2': to.y,
      if (options?.durationMs != null) 'durationMs': options!.durationMs,
    });
    return null;
  }

  @override
  Future<BackendActionResult> typeText(
    BackendCommandContext ctx,
    String text, [
    Map<String, Object?>? options,
  ]) async {
    final session = await _runner(ctx);
    await _sendOrThrow(session, {'command': 'type', 'text': text});
    return null;
  }

  @override
  Future<BackendActionResult> pressHome(BackendCommandContext ctx) async {
    final session = await _runner(ctx);
    await _sendOrThrow(session, {'command': 'home'});
    return null;
  }

  @override
  Future<BackendActionResult> pressBack(
    BackendCommandContext ctx,
    BackendBackOptions? options,
  ) async {
    final session = await _runner(ctx);
    await _sendOrThrow(session, {'command': 'backInApp'});
    return null;
  }

  @override
  Future<BackendActionResult> openAppSwitcher(BackendCommandContext ctx) async {
    final session = await _runner(ctx);
    await _sendOrThrow(session, {'command': 'appSwitcher'});
    return null;
  }

  @override
  Future<BackendActionResult> rotate(
    BackendCommandContext ctx,
    BackendDeviceOrientation orientation,
  ) async {
    final session = await _runner(ctx);
    await _sendOrThrow(session, {
      'command': 'rotate',
      'orientation': _orientationToken(orientation),
    });
    return null;
  }

  // =========================================================================
  // Recording
  // =========================================================================

  @override
  Future<BackendRecordingResult> startRecording(
    BackendCommandContext ctx,
    BackendRecordingOptions? options,
  ) async {
    final session = await _runner(ctx);
    final bundleId = ctx.appBundleId ?? ctx.appId;
    if (bundleId == null || bundleId.isEmpty) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'iOS recording requires an open app. Run `agent-device open <bundleId>` '
        'first so the runner knows which app to capture.',
      );
    }
    final outPath = options?.outPath;
    if (outPath == null || outPath.isEmpty) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'iOS startRecording requires options.outPath.',
      );
    }
    // The runner writes into its own NSTemporaryDirectory inside the
    // simulator; only the basename of `outPath` matters over the wire.
    // We pull the file out on stop using the runner log's
    // `resolvedOutPath=` trace line.
    final fileName = p.basename(outPath);
    RunnerResponse res = await IosRunnerClient.send(session, {
      'command': 'recordStart',
      'outPath': fileName,
      'appBundleId': bundleId,
      if (options?.fps != null) 'fps': options!.fps,
      if (options?.quality != null) 'quality': options!.quality,
    });
    // If the runner still had a stale recording from a prior invocation,
    // clear it with one recordStop and retry — matches TS
    // `isRunnerRecordingAlreadyInProgressError` recovery.
    if (!res.ok &&
        (res.errorMessage ?? '').contains('recording already in progress')) {
      await IosRunnerClient.send(session, {
        'command': 'recordStop',
        'appBundleId': bundleId,
      });
      res = await IosRunnerClient.send(session, {
        'command': 'recordStart',
        'outPath': fileName,
        'appBundleId': bundleId,
        if (options?.fps != null) 'fps': options!.fps,
        if (options?.quality != null) 'quality': options!.quality,
      });
    }
    if (!res.ok) {
      throw AppError(
        AppErrorCodes.commandFailed,
        'iOS runner recordStart failed: ${res.errorMessage ?? 'unknown'}',
      );
    }
    return BackendRecordingResult(path: outPath);
  }

  @override
  Future<BackendRecordingResult> stopRecording(
    BackendCommandContext ctx,
    BackendRecordingOptions? options,
  ) async {
    final session = await _runner(ctx);
    final bundleId = ctx.appBundleId ?? ctx.appId;
    final outPath = options?.outPath;
    if (outPath == null || outPath.isEmpty) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'iOS stopRecording requires options.outPath (the same path passed to '
        'startRecording).',
      );
    }
    final res = await IosRunnerClient.send(session, {
      'command': 'recordStop',
      if (bundleId != null) 'appBundleId': bundleId,
    });
    if (!res.ok) {
      throw AppError(
        AppErrorCodes.commandFailed,
        'iOS runner recordStop failed: ${res.errorMessage ?? 'unknown'}',
      );
    }
    // Runner logs `resolvedOutPath=<abs>` — use the most recent match
    // for this session's log so we can pull the file off the sim.
    final resolved = await _findLatestResolvedRecordingPath(session.logPath);
    if (resolved == null) {
      return BackendRecordingResult(
        path: outPath,
        warning:
            'Runner log did not report a resolvedOutPath. Recording file '
            'location is unknown; check ${session.logPath}.',
      );
    }
    final src = File(resolved);
    if (!await src.exists()) {
      return BackendRecordingResult(
        path: outPath,
        warning:
            'Recording file did not appear on host at $resolved. The runner '
            'may still be finalizing.',
      );
    }
    final dst = File(outPath);
    await dst.parent.create(recursive: true);
    await src.copy(dst.path);
    return BackendRecordingResult(path: outPath);
  }

  static Future<String?> _findLatestResolvedRecordingPath(
    String logPath,
  ) async {
    final file = File(logPath);
    if (!await file.exists()) return null;
    try {
      final text = await file.readAsString();
      final re = RegExp(
        r'AGENT_DEVICE_RUNNER_RECORD_START\b[^\n]*\bresolvedOutPath=(\S+)',
      );
      final matches = re.allMatches(text).toList();
      if (matches.isEmpty) return null;
      return matches.last.group(1);
    } catch (_) {
      return null;
    }
  }

  // =========================================================================
  // Diagnostics: Logs (one-shot)
  // =========================================================================

  /// Dump recent os_log output filtered to the session's app bundle id.
  /// Simulator only — shells out to `xcrun simctl spawn [udid] log show
  /// --predicate ...`. Physical-device logs (`xcrun devicectl device log
  /// stream`) are deferred until streaming lands.
  @override
  Future<BackendReadLogsResult> readLogs(
    BackendCommandContext ctx,
    BackendReadLogsOptions? options,
  ) async {
    final udid = _udid(ctx);
    final kind = await _resolveKind(udid);
    if (kind == 'device') {
      throw AppError(
        AppErrorCodes.unsupportedOperation,
        'iOS physical-device log capture is not yet wired. Use a simulator '
        'or stream via `xcrun devicectl device log stream --device $udid`.',
      );
    }
    final bundleId = ctx.appBundleId ?? ctx.appId;
    if (bundleId == null || bundleId.isEmpty) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'iOS readLogs requires an open app. Run `agent-device open <bundleId>` '
        'first so we know which app\'s logs to filter to.',
      );
    }
    final predicate = [
      'subsystem == "$bundleId"',
      'processImagePath ENDSWITH[c] "/$bundleId"',
      'senderImagePath ENDSWITH[c] "/$bundleId"',
    ].join(' OR ');
    final args = <String>[
      'simctl',
      'spawn',
      udid,
      'log',
      'show',
      '--style',
      'compact',
      '--info',
      '--predicate',
      predicate,
    ];
    final since = options?.since?.trim();
    // `--last` values are of the form <digits><s|m|h|d>. Anything else we
    // pass through as `--start` so callers can hand in `@<epoch>` or an
    // ISO timestamp.
    if (since != null && since.isNotEmpty) {
      if (RegExp(r'^\d+[smhd]$').hasMatch(since)) {
        args.addAll(['--last', since]);
      } else {
        args.addAll(['--start', since]);
      }
    } else {
      args.addAll(['--last', '5m']);
    }
    final r = await runCmd(
      'xcrun',
      args,
      const ExecOptions(allowFailure: true, timeoutMs: 15000),
    );
    if (r.exitCode != 0) {
      throw AppError(
        AppErrorCodes.commandFailed,
        'simctl log show failed (exit ${r.exitCode}).',
        details: {
          'stderr': r.stderr,
          'stdout': r.stdout,
          'exitCode': r.exitCode,
        },
      );
    }
    final rawLines = r.stdout.split('\n');
    final entries = <BackendLogEntry>[];
    for (final raw in rawLines) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) continue;
      // `log show --style compact` prints a fixed header line once; skip it.
      if (line.startsWith('Timestamp               Ty Process[PID:TID]')) {
        continue;
      }
      entries.add(BackendLogEntry(message: line));
    }
    final limit = options?.limit;
    final trimmed = (limit != null && limit > 0 && entries.length > limit)
        ? entries.sublist(entries.length - limit)
        : entries;
    return BackendReadLogsResult(entries: trimmed, backend: 'ios-simulator');
  }

  @override
  Future<BackendActionResult> pinch(
    BackendCommandContext ctx,
    BackendPinchOptions options,
  ) async {
    final session = await _runner(ctx);
    await _sendOrThrow(session, {
      'command': 'pinch',
      'scale': options.scale,
      if (options.center != null) 'x': options.center!.x.round(),
      if (options.center != null) 'y': options.center!.y.round(),
    });
    return null;
  }

  @override
  Future<String> getClipboard(BackendCommandContext ctx) async {
    final udid = _udid(ctx);
    final r = await Process.run(
      'xcrun',
      ['simctl', 'pbpaste', udid],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (r.exitCode != 0) {
      throw AppError(
        AppErrorCodes.commandFailed,
        'Failed to read iOS simulator clipboard.',
        details: {
          'stdout': r.stdout,
          'stderr': r.stderr,
          'exitCode': r.exitCode,
        },
      );
    }
    final text = (r.stdout as String).replaceAll('\r\n', '\n');
    return text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
  }

  @override
  Future<BackendActionResult> setClipboard(
    BackendCommandContext ctx,
    String text,
  ) async {
    final udid = _udid(ctx);
    final proc = await Process.start('xcrun', ['simctl', 'pbcopy', udid]);
    proc.stdin.add(utf8.encode(text));
    await proc.stdin.close();
    final exitCode = await proc.exitCode;
    if (exitCode != 0) {
      final err = await proc.stderr.transform(utf8.decoder).join();
      throw AppError(
        AppErrorCodes.commandFailed,
        'Failed to write iOS simulator clipboard.',
        details: {'stderr': err, 'exitCode': exitCode},
      );
    }
    return null;
  }

  // =========================================================================
  // App Management (from Phase 8A)
  // =========================================================================

  @override
  Future<BackendActionResult> openApp(
    BackendCommandContext ctx,
    BackendOpenTarget target,
    BackendOpenOptions? options,
  ) async {
    final bundleId = target.bundleId ?? target.appId ?? target.app;
    if (bundleId == null || bundleId.isEmpty) {
      unsupported(
        'openApp on iOS requires target.bundleId / appId / app (a bundle id)',
      );
    }
    final udid = _udid(ctx);
    final kind = await _resolveKind(udid);
    if (kind == 'device') {
      await launchIosDeviceProcess(udid, bundleId);
    } else {
      await openIosApp(udid, bundleId);
    }
    return null;
  }

  @override
  Future<BackendActionResult> closeApp(
    BackendCommandContext ctx, [
    String? app,
  ]) async {
    if (app == null || app.isEmpty) {
      unsupported('closeApp on iOS requires a bundle id');
    }
    final udid = _udid(ctx);
    final kind = await _resolveKind(udid);
    if (kind == 'device') {
      await terminateIosDeviceProcess(udid, app);
    } else {
      await closeIosApp(udid, app);
    }
    return null;
  }

  @override
  Future<List<BackendAppInfo>> listApps(
    BackendCommandContext ctx, [
    BackendAppListFilter? filter,
  ]) async {
    final userOnly = filter == BackendAppListFilter.userInstalled;
    final udid = _udid(ctx);
    final kind = await _resolveKind(udid);
    if (kind == 'device') {
      final apps = await listIosDeviceApps(udid, userOnly: userOnly);
      return apps
          .map(
            (a) => BackendAppInfo(
              id: a.bundleId,
              name: a.name,
              bundleId: a.bundleId,
            ),
          )
          .toList();
    }
    final apps = await listIosApps(udid, userOnly: userOnly);
    return apps
        .map(
          (a) => BackendAppInfo(
            id: a.bundleId,
            name: a.name,
            bundleId: a.bundleId,
          ),
        )
        .toList();
  }

  @override
  Future<BackendAppState> getAppState(
    BackendCommandContext ctx,
    String app,
  ) async {
    final fg = await getIosForeground(_udid(ctx));
    return BackendAppState(
      appId: fg.bundleId,
      bundleId: fg.bundleId,
      state: fg.bundleId == null ? 'unknown' : 'foreground',
    );
  }

  @override
  Future<List<BackendDeviceInfo>> listDevices(
    BackendCommandContext ctx, [
    BackendDeviceFilter? filter,
  ]) => listAppleDevices();

  /// Resolve whether [udid] is a simulator or a physical device. Physical
  /// iOS devices go through `devicectl`; simulators go through `simctl`.
  /// Cached for the process lifetime to avoid repeat enumeration on every
  /// action. Unknown UDIDs default to `simulator` to preserve the
  /// pre-devicectl behaviour.
  Future<String> _resolveKind(String udid) async {
    final cached = _IosKindCache.instance.get(udid);
    if (cached != null) return cached;
    final devices = await listAppleDevices();
    final match = devices.firstWhere(
      (d) => d.id == udid,
      orElse: () => BackendDeviceInfo(
        id: udid,
        name: udid,
        platform: AgentDeviceBackendPlatform.ios,
        kind: 'simulator',
      ),
    );
    final kind = match.kind ?? 'simulator';
    _IosKindCache.instance.set(udid, kind);
    return kind;
  }
}

Future<void> _sendOrThrow(
  IosRunnerSession session,
  Map<String, Object?> body,
) async {
  final res = await IosRunnerClient.send(session, body);
  if (!res.ok) {
    throw AppError(
      AppErrorCodes.commandFailed,
      'iOS runner ${body['command']} failed: '
      '${res.errorMessage ?? 'unknown error'}',
      details: {'command': body['command']},
    );
  }
}

String _orientationToken(BackendDeviceOrientation o) => switch (o) {
  BackendDeviceOrientation.portrait => 'portrait',
  BackendDeviceOrientation.portraitUpsideDown => 'portrait-upside-down',
  BackendDeviceOrientation.landscapeLeft => 'landscape-left',
  BackendDeviceOrientation.landscapeRight => 'landscape-right',
};

RawSnapshotNode? _rawNodeFromJson(Object? entry) {
  if (entry is! Map) return null;
  final index = entry['index'] as int? ?? -1;
  if (index < 0) return null;
  final rectJson = entry['rect'];
  Rect? rect;
  if (rectJson is Map) {
    final x = (rectJson['x'] as num?)?.toDouble();
    final y = (rectJson['y'] as num?)?.toDouble();
    final w = (rectJson['width'] as num?)?.toDouble();
    final h = (rectJson['height'] as num?)?.toDouble();
    if (x != null && y != null && w != null && h != null) {
      rect = Rect(x: x, y: y, width: w, height: h);
    }
  }
  return RawSnapshotNode(
    index: index,
    type: entry['type'] as String?,
    role: entry['role'] as String?,
    subrole: entry['subrole'] as String?,
    label: entry['label'] as String?,
    value: entry['value'] as String?,
    identifier: entry['identifier'] as String?,
    rect: rect,
    enabled: entry['enabled'] as bool?,
    selected: entry['selected'] as bool?,
    hittable: entry['hittable'] as bool?,
    depth: entry['depth'] as int?,
    parentIndex: entry['parentIndex'] as int?,
    pid: entry['pid'] as int?,
    bundleId: entry['bundleId'] as String?,
    appName: entry['appName'] as String?,
    windowTitle: entry['windowTitle'] as String?,
    surface: entry['surface'] as String?,
    hiddenContentAbove: entry['hiddenContentAbove'] as bool?,
    hiddenContentBelow: entry['hiddenContentBelow'] as bool?,
  );
}

/// Module-level cache so multiple [IosBackend] calls in the same process
/// reuse the same runner. Cross-process caching is a future improvement
/// that requires Phase 6B's disk store to carry the runner `{pid, port}`
/// on the session record.
class _IosRunnerCache {
  _IosRunnerCache._();
  static final _IosRunnerCache instance = _IosRunnerCache._();

  final Map<String, IosRunnerSession> _sessions = {};

  IosRunnerSession? get(String udid) => _sessions[udid];
  void set(String udid, IosRunnerSession session) => _sessions[udid] = session;
  IosRunnerSession? pop(String udid) => _sessions.remove(udid);
}

/// Per-process cache of UDID → kind (`simulator` | `device`). Avoids a
/// full `simctl list` + `devicectl list` round-trip on every app action.
class _IosKindCache {
  _IosKindCache._();
  static final _IosKindCache instance = _IosKindCache._();

  final Map<String, String> _kinds = {};

  String? get(String udid) => _kinds[udid];
  void set(String udid, String kind) => _kinds[udid] = kind;
}
