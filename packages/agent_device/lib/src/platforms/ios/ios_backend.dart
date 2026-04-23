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
import 'package:path/path.dart' as p;

import 'app_lifecycle.dart';
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
    await openIosApp(_udid(ctx), bundleId);
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
    await closeIosApp(_udid(ctx), app);
    return null;
  }

  @override
  Future<List<BackendAppInfo>> listApps(
    BackendCommandContext ctx, [
    BackendAppListFilter? filter,
  ]) async {
    final userOnly = filter == BackendAppListFilter.userInstalled;
    final apps = await listIosApps(_udid(ctx), userOnly: userOnly);
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
  ]) => listAppleSimulators();
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
