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
import 'package:agent_device/src/diagnostics/log_stream_record.dart';
import 'package:agent_device/src/runtime/paths.dart';
import 'package:agent_device/src/snapshot/snapshot.dart';
import 'package:agent_device/src/utils/errors.dart';
import 'package:agent_device/src/utils/exec.dart';
import 'package:path/path.dart' as p;

import 'app_lifecycle.dart';
import 'devicectl.dart';
import 'devices.dart';
import 'install_artifact.dart';
import 'perf.dart';
import 'runner_client.dart';
import 'screenshot.dart';
import 'simctl.dart';

/// Candidate container bundle ids used by `devicectl device copy from
/// --domain-type appDataContainer` when pulling a recording off a
/// physical iOS device. The UI-test runner process writes to the
/// *.xctrunner* container's tmp dir; we try that first, then fall
/// back to the main app container. Matches the TS port's
/// `IOS_RUNNER_CONTAINER_BUNDLE_IDS` ordering.
///
/// If the Xcode project ever renames these targets, update both lists
/// in lockstep. An environment override lets advanced users inject an
/// extra candidate without touching the source.
List<String> _iosRunnerContainerBundleIds() {
  final override =
      Platform.environment['AGENT_DEVICE_IOS_RUNNER_CONTAINER_BUNDLE_ID'];
  return <String>[
    if (override != null && override.trim().isNotEmpty) override.trim(),
    'dev.roszkowski.agentdevice.runner.uitests.xctrunner',
    'dev.roszkowski.agentdevice.runner',
  ];
}

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

  String? _appBundleId(BackendCommandContext ctx) {
    final bundleId = ctx.appBundleId ?? ctx.appId;
    if (bundleId == null || bundleId.isEmpty) {
      return null;
    }
    return bundleId;
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
    final kindStr = await _resolveKind(udid);
    final runnerKind = kindStr == 'device'
        ? IosRunnerKind.device
        : IosRunnerKind.simulator;
    final session = await IosRunnerClient.launch(udid: udid, kind: runnerKind);
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
    final bundleId = _appBundleId(ctx);
    final body = <String, Object?>{
      'command': 'snapshot',
      'appBundleId': ?bundleId,
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
    final bundleId = _appBundleId(ctx);
    await _sendOrThrow(session, {
      'command': 'tap',
      'x': point.x,
      'y': point.y,
      'appBundleId': ?bundleId,
    });
    return null;
  }

  @override
  Future<BackendActionResult> longPress(
    BackendCommandContext ctx,
    Point point,
    BackendLongPressOptions? options,
  ) async {
    final session = await _runner(ctx);
    final bundleId = _appBundleId(ctx);
    await _sendOrThrow(session, {
      'command': 'longPress',
      'x': point.x,
      'y': point.y,
      'appBundleId': ?bundleId,
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
    final bundleId = _appBundleId(ctx);
    await _sendOrThrow(session, {
      'command': 'drag',
      'x': from.x,
      'y': from.y,
      'x2': to.x,
      'y2': to.y,
      'appBundleId': ?bundleId,
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
    final bundleId = _appBundleId(ctx);
    await _sendOrThrow(session, {
      'command': 'type',
      'text': text,
      'appBundleId': ?bundleId,
    });
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
    // ScreenRecorder.start on a physical device can take 10-20s to
    // initialize AVAssetWriter + begin the display stream, much slower
    // than the simulator. Give it a generous window.
    final recordTimeout = session.kind == IosRunnerKind.device
        ? const Duration(seconds: 90)
        : const Duration(seconds: 30);
    RunnerResponse res = await IosRunnerClient.send(session, {
      'command': 'recordStart',
      'outPath': fileName,
      'appBundleId': bundleId,
      if (options?.fps != null) 'fps': options!.fps,
      if (options?.quality != null) 'quality': options!.quality,
    }, timeout: recordTimeout);
    // If the runner still had a stale recording from a prior invocation,
    // clear it with one recordStop and retry — matches TS
    // `isRunnerRecordingAlreadyInProgressError` recovery.
    if (!res.ok &&
        (res.errorMessage ?? '').contains('recording already in progress')) {
      await IosRunnerClient.send(session, {
        'command': 'recordStop',
        'appBundleId': bundleId,
      }, timeout: recordTimeout);
      res = await IosRunnerClient.send(session, {
        'command': 'recordStart',
        'outPath': fileName,
        'appBundleId': bundleId,
        if (options?.fps != null) 'fps': options!.fps,
        if (options?.quality != null) 'quality': options!.quality,
      }, timeout: recordTimeout);
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
    final stopTimeout = session.kind == IosRunnerKind.device
        ? const Duration(seconds: 60)
        : const Duration(seconds: 30);
    final res = await IosRunnerClient.send(session, {
      'command': 'recordStop',
      'appBundleId': ?bundleId,
    }, timeout: stopTimeout);
    if (!res.ok) {
      throw AppError(
        AppErrorCodes.commandFailed,
        'iOS runner recordStop failed: ${res.errorMessage ?? 'unknown'}',
      );
    }
    // Runner logs `resolvedOutPath=<abs>` — use the most recent match
    // for this session's log to locate the MP4. On simulator that path
    // is directly readable on the host FS; on device we pull it out via
    // `xcrun devicectl device copy from --domain-type appDataContainer`.
    final resolved = await _findLatestResolvedRecordingPath(session.logPath);
    if (resolved == null) {
      return BackendRecordingResult(
        path: outPath,
        warning:
            'Runner log did not report a resolvedOutPath. Recording file '
            'location is unknown; check ${session.logPath}.',
      );
    }
    final dst = File(outPath);
    await dst.parent.create(recursive: true);

    if (session.kind == IosRunnerKind.device) {
      // On device `resolved` is an on-device absolute path inside the
      // runner's sandbox (`/private/var/mobile/.../tmp/<file>.mp4`).
      // The app-data-container-relative form is `tmp/<basename>`. The
      // xctrunner bundle owns the UITest process's NSTemporaryDirectory
      // so we try it first, then fall back to the main app bundle.
      final remotePath = 'tmp/${p.basename(resolved)}';
      final bundles = _iosRunnerContainerBundleIds();
      int? lastExit;
      String lastStderr = '';
      String lastBundle = '';
      for (final bundleCandidate in bundles) {
        final pull = await runCmd('xcrun', [
          'devicectl',
          'device',
          'copy',
          'from',
          '--device',
          _udid(ctx),
          '--source',
          remotePath,
          '--destination',
          outPath,
          '--domain-type',
          'appDataContainer',
          '--domain-identifier',
          bundleCandidate,
        ], const ExecOptions(allowFailure: true, timeoutMs: 60000));
        if (pull.exitCode == 0) {
          return BackendRecordingResult(path: outPath);
        }
        lastExit = pull.exitCode;
        lastStderr = pull.stderr.trim();
        lastBundle = bundleCandidate;
      }
      return BackendRecordingResult(
        path: outPath,
        warning:
            'devicectl copy from $remotePath failed across ${bundles.length} '
            'container bundle(s). Last tried "$lastBundle" '
            '(exit $lastExit): $lastStderr',
      );
    }

    // Simulator: the runner wrote into its on-sim-host sandbox, which
    // is directly accessible on the host file system.
    final src = File(resolved);
    if (!await src.exists()) {
      return BackendRecordingResult(
        path: outPath,
        warning:
            'Recording file did not appear on host at $resolved. The runner '
            'may still be finalizing.',
      );
    }
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
  // Diagnostics: Log streaming (background)
  // =========================================================================

  /// Start tailing device logs for the ctx's iOS device into
  /// [options.outPath]. The PID is persisted at
  /// `<stateDir>/log-streams/<udid>.json` so a later invocation can
  /// [stopLogStream]. If an existing record is present we SIGINT its
  /// pid first so we don't leak tails.
  ///
  /// Simulator: `xcrun simctl spawn <udid> log stream --predicate …`
  /// filtered to the session's open app bundle id.
  ///
  /// Physical device: `xcrun devicectl device log stream --device <id>`.
  /// devicectl doesn't accept an os_log predicate, so the full stream
  /// is captured; filtering to a bundle id is a post-hoc grep job.
  @override
  Future<BackendLogStreamResult> startLogStream(
    BackendCommandContext ctx,
    BackendLogStreamOptions options,
  ) async {
    final udid = _udid(ctx);
    final kind = await _resolveKind(udid);
    final outPath = options.outPath;
    if (outPath == null || outPath.isEmpty) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'iOS startLogStream requires options.outPath.',
      );
    }

    // Stop any existing stream for this device so we don't duplicate.
    final existing = await readLogStreamRecord(udid);
    if (existing != null) {
      killLogStreamPid(existing.hostPid);
      await deleteLogStreamRecord(udid);
    }

    final outFile = File(outPath);
    await outFile.parent.create(recursive: true);

    final String script;
    final String backendLabel;
    final String? bundleId;
    if (kind == 'device') {
      // Xcode's `devicectl` has no `log stream` subcommand (at least
      // through Xcode 16.x), so we fall back to `idevicesyslog` from
      // libimobiledevice. Probe its presence early so the error is
      // helpful rather than a cryptic child-process exit.
      final which = await runCmd('which', const [
        'idevicesyslog',
      ], const ExecOptions(allowFailure: true, timeoutMs: 2000));
      if (which.exitCode != 0 || which.stdout.trim().isEmpty) {
        throw AppError(
          AppErrorCodes.toolMissing,
          'iOS physical-device log streaming needs `idevicesyslog` (not '
          'shipped with Xcode). Install libimobiledevice: '
          '`brew install libimobiledevice`, then retry.',
        );
      }
      final binPath = which.stdout.trim().split('\n').first;
      // idevicesyslog doesn't support predicate filtering; caller greps
      // post-hoc. appBundleId goes on the disk record for reference.
      bundleId = options.appBundleId ?? ctx.appBundleId ?? ctx.appId;
      script =
          'exec ${_shellQuote(binPath)} -u ${_shellQuote(udid)} '
          '> ${_shellQuote(outPath)} 2>&1';
      backendLabel = 'ios-device-log-stream-idevicesyslog';
    } else {
      bundleId = options.appBundleId ?? ctx.appBundleId ?? ctx.appId;
      if (bundleId == null || bundleId.isEmpty) {
        throw AppError(
          AppErrorCodes.invalidArgs,
          'iOS simulator startLogStream requires an open app (run '
          '`agent-device open <bundleId>` first).',
        );
      }
      final predicate = [
        'subsystem == "$bundleId"',
        'processImagePath ENDSWITH[c] "/$bundleId"',
        'senderImagePath ENDSWITH[c] "/$bundleId"',
      ].join(' OR ');
      script =
          'exec xcrun simctl spawn '
          '${_shellQuote(udid)} log stream '
          '--style compact --level info '
          '--predicate ${_shellQuote(predicate)} '
          '> ${_shellQuote(outPath)} 2>&1';
      backendLabel = 'ios-simulator-log-stream';
    }

    final proc = await runCmdDetached('sh', [
      '-c',
      script,
    ], const ExecDetachedOptions());
    final startedAt = DateTime.now().toUtc().toIso8601String();
    await writeLogStreamRecord(
      LogStreamRecord(
        deviceId: udid,
        platform: 'ios',
        hostPid: proc.pid,
        outPath: outPath,
        startedAt: startedAt,
        appBundleId: bundleId,
      ),
    );
    return BackendLogStreamResult(
      outPath: outPath,
      hostPid: proc.pid,
      backend: backendLabel,
      startedAt: startedAt,
    );
  }

  @override
  Future<BackendLogStreamResult> stopLogStream(
    BackendCommandContext ctx,
  ) async {
    final udid = _udid(ctx);
    final record = await readLogStreamRecord(udid);
    if (record == null) {
      throw AppError(
        AppErrorCodes.commandFailed,
        'No active log stream for iOS device $udid.',
      );
    }
    final delivered = killLogStreamPid(record.hostPid);
    // Give the tail a beat to flush any buffered lines.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await deleteLogStreamRecord(udid);
    int? bytes;
    final f = File(record.outPath);
    if (await f.exists()) bytes = await f.length();
    // Re-derive the backend label from the device kind so stop reports
    // the same variant that start recorded (simulator vs physical).
    final kind = await _resolveKind(udid);
    final backend = kind == 'device'
        ? 'ios-device-log-stream-idevicesyslog'
        : 'ios-simulator-log-stream';
    return BackendLogStreamResult(
      outPath: record.outPath,
      hostPid: record.hostPid,
      backend: backend,
      startedAt: record.startedAt,
      stoppedAt: DateTime.now().toUtc().toIso8601String(),
      bytes: bytes,
      stale: !delivered,
    );
  }

  // =========================================================================
  // Diagnostics: Performance sampling
  // =========================================================================

  /// Sample CPU + resident memory for the session's open app.
  ///
  /// Simulator path: `simctl spawn /bin/ps -axo pid,%cpu,rss,command`
  /// filtered by the app's `CFBundleExecutable`, reports aggregate
  /// `cpu` (percent) and `memory.resident` (kB).
  ///
  /// Physical-device path: two consecutive `xctrace record --template
  /// 'Activity Monitor' --time-limit 1s` traces + XML export. Filters
  /// rows whose process name contains the bundle id's last segment,
  /// diffs `cpu-total` per pid across the two captures, and reports
  /// aggregate `cpu` (percent) + `memory.resident` (kB) from the
  /// second snapshot. Multi-core processes can exceed 100%, matching
  /// `top` semantics. Total wall time is roughly two xctrace
  /// invocations (~15-20s).
  @override
  Future<BackendMeasurePerfResult> measurePerf(
    BackendCommandContext ctx,
    BackendMeasurePerfOptions? options,
  ) async {
    final udid = _udid(ctx);
    final kind = await _resolveKind(udid);
    final bundleId = ctx.appBundleId ?? ctx.appId;
    if (bundleId == null || bundleId.isEmpty) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'iOS measurePerf requires an open app '
        '(run `agent-device open <bundleId>` first).',
      );
    }
    final requested = options?.metrics?.map((e) => e.toLowerCase()).toSet();
    final wantCpu = requested == null || requested.contains('cpu');
    final wantMemory = requested == null || requested.contains('memory');

    // Physical device: xctrace 1s activity-monitor + XML parse. Match
    // rows by bundleId's last segment (typical CFBundleExecutable form)
    // and by full bundleId as a fallback.
    if (kind == 'device') {
      final lastSegment = bundleId.split('.').last.toLowerCase();
      final sample = await sampleIosDevicePerfMetrics(
        udid,
        matcherLabel: bundleId,
        processMatcher: (name) {
          final lower = name.toLowerCase();
          return lower.contains(lastSegment) ||
              lower.contains(bundleId.toLowerCase());
        },
      );
      final metrics = <BackendPerfMetric>[];
      if (wantCpu) {
        metrics.add(
          BackendPerfMetric(
            name: 'cpu',
            value: sample.cpu.usagePercent,
            unit: 'percent',
            status: 'ok',
            metadata: {
              'method': sample.cpu.method,
              'description':
                  'Per-core CPU% derived by diffing cpu-total across two '
                  'xctrace captures, aggregated across matched processes. '
                  'Multi-core processes can exceed 100%.',
              'matchedProcesses': sample.cpu.matchedProcesses,
              'measuredAt': sample.cpu.measuredAt,
            },
          ),
        );
      }
      if (wantMemory) {
        metrics.add(
          BackendPerfMetric(
            name: 'memory.resident',
            value: sample.memory.residentMemoryKb.toDouble(),
            unit: 'kB',
            status: 'ok',
            metadata: {
              'method': sample.memory.method,
              'description':
                  'memory-real bytes from the second xctrace capture, '
                  'aggregated across matched processes.',
              'matchedProcesses': sample.memory.matchedProcesses,
              'measuredAt': sample.memory.measuredAt,
            },
          ),
        );
      }
      return BackendMeasurePerfResult(
        metrics: metrics,
        startedAt: sample.cpu.measuredAt,
        endedAt: sample.cpu.measuredAt,
        backend: 'ios-device-xctrace',
      );
    }

    final sample = await sampleIosSimulatorPerfMetrics(udid, bundleId);
    final metrics = <BackendPerfMetric>[];
    if (wantCpu) {
      metrics.add(
        BackendPerfMetric(
          name: 'cpu',
          value: sample.cpu.usagePercent,
          unit: 'percent',
          status: 'ok',
          metadata: {
            'method': sample.cpu.method,
            'description':
                'Recent CPU usage snapshot aggregated across the bundle\'s '
                'processes inside the iOS simulator.',
            'matchedProcesses': sample.cpu.matchedProcesses,
            'measuredAt': sample.cpu.measuredAt,
          },
        ),
      );
    }
    if (wantMemory) {
      metrics.add(
        BackendPerfMetric(
          name: 'memory.resident',
          value: sample.memory.residentMemoryKb.toDouble(),
          unit: 'kB',
          status: 'ok',
          metadata: {
            'method': sample.memory.method,
            'description':
                'Resident memory snapshot aggregated across the bundle\'s '
                'processes inside the iOS simulator.',
            'matchedProcesses': sample.memory.matchedProcesses,
            'measuredAt': sample.memory.measuredAt,
          },
        ),
      );
    }
    return BackendMeasurePerfResult(
      metrics: metrics,
      startedAt: sample.cpu.measuredAt,
      endedAt: sample.cpu.measuredAt,
      backend: 'ios-simulator-ps',
    );
  }

  // =========================================================================
  // Diagnostics: Logs (one-shot)
  // =========================================================================

  /// Dump recent os_log output filtered to the session's app bundle id.
  /// Simulator only — shells out to `xcrun simctl spawn [udid] log show
  /// --predicate ...`. For physical devices there's no equivalent
  /// one-shot (Apple's `log show` only works on the host itself or on
  /// a simulator), so `readLogs` raises `UNSUPPORTED_OPERATION` there;
  /// use [startLogStream] / [stopLogStream] instead — that path works
  /// on physical iOS via `idevicesyslog`.
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
        'iOS physical-device one-shot `logs` isn\'t available — Apple\'s '
        '`log show` only targets the host or a simulator. Use '
        '`agent-device logs --stream --out <path>` / `logs --stop` '
        'instead (streams via idevicesyslog).',
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

  // =========================================================================
  // Install / uninstall / reinstall
  // =========================================================================

  /// Install a `.app` bundle or `.ipa` archive. Simulator paths shell
  /// out to `xcrun simctl install <udid> <path>`; physical-device paths
  /// go through `devicectl device install app`. `.ipa` archives are
  /// unzipped into a tmpdir first and the resolved `.app` is installed
  /// from there. Bundle id + display name are extracted from the
  /// bundle's `Info.plist` and surfaced on the result so the caller
  /// can `open` it without a separate lookup.
  @override
  Future<BackendInstallResult> installApp(
    BackendCommandContext ctx,
    BackendInstallTarget target,
  ) async {
    final source = target.source;
    if (source is! BackendInstallSourcePath) {
      unsupported('iOS installApp requires a path source');
    }
    final prepared = await prepareIosInstallArtifact(
      source.path,
      options: PrepareIosInstallArtifactOptions(
        appIdentifierHint: target.app,
      ),
    );
    try {
      final udid = _udid(ctx);
      final kind = await _resolveKind(udid);
      if (kind == 'device') {
        await installIosDeviceApp(udid, prepared.installablePath);
      } else {
        final r = await runCmd('xcrun', buildSimctlArgs([
          'install',
          udid,
          prepared.installablePath,
        ]), const ExecOptions(allowFailure: true, timeoutMs: 180000));
        if (r.exitCode != 0) {
          throw AppError(
            AppErrorCodes.commandFailed,
            'simctl install failed for ${prepared.installablePath}',
            details: {
              'stdout': r.stdout,
              'stderr': r.stderr,
              'exitCode': r.exitCode,
            },
          );
        }
      }
      return BackendInstallResult(
        appId: prepared.bundleId,
        bundleId: prepared.bundleId,
        appName: prepared.appName,
        launchTarget: prepared.bundleId,
        installablePath: prepared.installablePath,
        archivePath: prepared.archivePath,
      );
    } finally {
      await prepared.cleanup();
    }
  }

  /// Uninstall by bundle id. Returns the resolved bundle id even when
  /// the app wasn't installed — both simctl and devicectl are tolerant
  /// of "not installed" so the caller gets a no-op success rather than
  /// a generic failure.
  @override
  Future<BackendInstallResult> uninstallApp(
    BackendCommandContext ctx,
    String app,
  ) async {
    final bundleId = app.trim();
    if (bundleId.isEmpty) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'iOS uninstallApp requires a bundle id',
      );
    }
    final udid = _udid(ctx);
    final kind = await _resolveKind(udid);
    if (kind == 'device') {
      await uninstallIosDeviceApp(udid, bundleId);
    } else {
      final r = await runCmd('xcrun', buildSimctlArgs([
        'uninstall',
        udid,
        bundleId,
      ]), const ExecOptions(allowFailure: true, timeoutMs: 60000));
      if (r.exitCode != 0) {
        final combined = '${r.stdout}\n${r.stderr}'.toLowerCase();
        final missing = combined.contains('no such') ||
            combined.contains('not installed') ||
            combined.contains('found no app');
        if (!missing) {
          throw AppError(
            AppErrorCodes.commandFailed,
            'simctl uninstall failed for $bundleId',
            details: {
              'stdout': r.stdout,
              'stderr': r.stderr,
              'exitCode': r.exitCode,
            },
          );
        }
      }
    }
    return BackendInstallResult(
      appId: bundleId,
      bundleId: bundleId,
      launchTarget: bundleId,
    );
  }

  /// Uninstall + reinstall in one shot. The uninstall is best-effort
  /// — if the app isn't installed we still proceed with the install
  /// so the caller can use this as an "ensure installed" primitive.
  @override
  Future<BackendInstallResult> reinstallApp(
    BackendCommandContext ctx,
    BackendInstallTarget target,
  ) async {
    final hint = target.app?.trim();
    if (hint != null && hint.isNotEmpty) {
      await uninstallApp(ctx, hint);
    }
    return installApp(ctx, target);
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

String _shellQuote(String s) => "'${s.replaceAll("'", r"'\''")}'";

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
