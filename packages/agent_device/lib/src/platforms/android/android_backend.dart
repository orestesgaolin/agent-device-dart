// Port of agent-device/src/platforms/android/index.ts

import 'dart:convert';
import 'dart:io';

import 'package:agent_device/src/backend/backend.dart';
import 'package:agent_device/src/core/device_rotation.dart';
import 'package:agent_device/src/core/scroll_gesture.dart';
import 'package:agent_device/src/diagnostics/log_stream_record.dart';
import 'package:agent_device/src/runtime/paths.dart';
import 'package:agent_device/src/snapshot/snapshot.dart';
import 'package:agent_device/src/utils/errors.dart';
import 'package:agent_device/src/utils/exec.dart';
import 'package:path/path.dart' as p;

import 'app_lifecycle.dart';
import 'device_input_state.dart';
import 'devices.dart';
import 'input_actions.dart';
import 'notifications.dart';
import 'perf.dart';
import 'screenshot.dart';
import 'snapshot.dart';

/// Android platform backend.
///
/// Delegates to the Wave A/B/C1/C2 Android module functions. Only methods
/// the TS Android platform actually exposes are wired; the rest inherit
/// the `unsupported` default from [Backend].
///
/// The TS source (`src/platforms/android/index.ts`) is a barrel of function
/// exports, not a class — `src/core/dispatch.ts` calls them directly based
/// on `device.platform`. The Dart port wraps the same functions behind a
/// [Backend] subclass so the runtime dispatcher (Phase 4) can treat all
/// platforms uniformly.
///
/// Device serial resolution: Wave C Android functions take a `String serial`
/// as first argument. The Dart-port-specific [BackendCommandContext.deviceSerial]
/// field carries it; Phase 4 runtime populates it from session state.
class AndroidBackend extends Backend {
  const AndroidBackend();

  @override
  AgentDeviceBackendPlatform get platform => AgentDeviceBackendPlatform.android;

  String _serial(BackendCommandContext ctx) {
    final serial = ctx.deviceSerial;
    if (serial == null || serial.isEmpty) {
      unsupported(
        'operation requires ctx.deviceSerial populated by the runtime',
      );
    }
    return serial;
  }

  // =========================================================================
  // Snapshot and Screenshot
  // =========================================================================

  @override
  Future<BackendSnapshotResult> captureSnapshot(
    BackendCommandContext ctx,
    BackendSnapshotOptions? options,
  ) async {
    final opts = SnapshotOptions(
      interactiveOnly: options?.interactiveOnly,
      compact: options?.compact,
      depth: options?.depth,
      scope: options?.scope,
      raw: options?.raw,
    );
    final result = await snapshotAndroid(_serial(ctx), options: opts);
    // Attach @e<N> refs so Phase 7's target resolution (`findNodeByRef`)
    // works against the snapshot.
    final withRefs = attachRefs(result.nodes);
    return BackendSnapshotResult(
      nodes: withRefs,
      truncated: result.truncated,
      analysis: BackendSnapshotAnalysis(
        rawNodeCount: result.analysis.rawNodeCount,
        maxDepth: result.analysis.maxDepth,
      ),
    );
  }

  @override
  Future<BackendScreenshotResult?> captureScreenshot(
    BackendCommandContext ctx,
    String outPath,
    BackendScreenshotOptions? options,
  ) async {
    await screenshotAndroid(_serial(ctx), outPath);
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
    await pressAndroid(_serial(ctx), point.x.round(), point.y.round());
    return null;
  }

  @override
  Future<BackendActionResult> fill(
    BackendCommandContext ctx,
    Point point,
    String text,
    BackendFillOptions? options,
  ) async {
    await fillAndroid(
      _serial(ctx),
      point.x.round(),
      point.y.round(),
      text,
      options?.delayMs ?? 0,
    );
    return null;
  }

  @override
  Future<BackendActionResult> typeText(
    BackendCommandContext ctx,
    String text, [
    Map<String, Object?>? options,
  ]) async {
    final delayMs = (options?['delayMs'] as int?) ?? 0;
    await typeAndroid(_serial(ctx), text, delayMs);
    return null;
  }

  @override
  Future<BackendActionResult> focus(
    BackendCommandContext ctx,
    Point point,
  ) async {
    await focusAndroid(_serial(ctx), point.x.round(), point.y.round());
    return null;
  }

  @override
  Future<BackendActionResult> longPress(
    BackendCommandContext ctx,
    Point point,
    BackendLongPressOptions? options,
  ) async {
    await longPressAndroid(
      _serial(ctx),
      point.x.round(),
      point.y.round(),
      options?.durationMs ?? 800,
    );
    return null;
  }

  @override
  Future<BackendActionResult> swipe(
    BackendCommandContext ctx,
    Point from,
    Point to,
    BackendSwipeOptions? options,
  ) async {
    await swipeAndroid(
      _serial(ctx),
      from.x.round(),
      from.y.round(),
      to.x.round(),
      to.y.round(),
      options?.durationMs ?? 250,
    );
    return null;
  }

  @override
  Future<BackendActionResult> scroll(
    BackendCommandContext ctx,
    BackendScrollTarget target,
    BackendScrollOptions options,
  ) async {
    final direction = parseScrollDirection(options.direction);
    return scrollAndroid(
      _serial(ctx),
      direction,
      amount: options.amount?.toDouble(),
      pixels: options.pixels?.toDouble(),
    );
  }

  // =========================================================================
  // Navigation
  // =========================================================================

  @override
  Future<BackendActionResult> pressBack(
    BackendCommandContext ctx,
    BackendBackOptions? options,
  ) async {
    await backAndroid(_serial(ctx));
    return null;
  }

  @override
  Future<BackendActionResult> pressHome(BackendCommandContext ctx) async {
    await homeAndroid(_serial(ctx));
    return null;
  }

  @override
  Future<BackendActionResult> rotate(
    BackendCommandContext ctx,
    BackendDeviceOrientation orientation,
  ) async {
    await rotateAndroid(_serial(ctx), _toDeviceRotation(orientation));
    return null;
  }

  @override
  Future<BackendActionResult> openAppSwitcher(BackendCommandContext ctx) async {
    await appSwitcherAndroid(_serial(ctx));
    return null;
  }

  @override
  Future<Object?> setKeyboard(
    BackendCommandContext ctx,
    BackendKeyboardOptions options,
  ) async {
    final serial = _serial(ctx);
    switch (options.action) {
      case 'dismiss':
      case 'hide':
        final r = await dismissAndroidKeyboard(serial);
        return <String, Object?>{
          'dismissed': r.dismissed,
          'visible': r.visible,
          'wasVisible': r.wasVisible,
          'attempts': r.attempts,
          if (r.inputType != null) 'inputType': r.inputType,
          if (r.type != null) 'type': r.type!.name,
        };
      case 'status':
      case 'get':
        final s = await getAndroidKeyboardState(serial);
        return <String, Object?>{
          'visible': s.visible,
          if (s.inputType != null) 'inputType': s.inputType,
          if (s.type != null) 'type': s.type!.name,
        };
    }
    unsupported("setKeyboard action '${options.action}'");
  }

  // =========================================================================
  // Clipboard
  // =========================================================================

  @override
  Future<String> getClipboard(BackendCommandContext ctx) =>
      readAndroidClipboardText(_serial(ctx));

  @override
  Future<BackendActionResult> setClipboard(
    BackendCommandContext ctx,
    String text,
  ) async {
    await writeAndroidClipboardText(_serial(ctx), text);
    return null;
  }

  // =========================================================================
  // App Management
  // =========================================================================

  @override
  Future<BackendActionResult> openApp(
    BackendCommandContext ctx,
    BackendOpenTarget target,
    BackendOpenOptions? options,
  ) async {
    final app = target.app ?? target.appId ?? target.packageName ?? target.url;
    if (app == null || app.isEmpty) {
      unsupported(
        'openApp requires target.app/appId/packageName/url on Android',
      );
    }
    await openAndroidApp(_serial(ctx), app);
    return null;
  }

  @override
  Future<BackendActionResult> closeApp(
    BackendCommandContext ctx, [
    String? app,
  ]) async {
    if (app == null || app.isEmpty) {
      unsupported('closeApp requires an app id on Android');
    }
    await closeAndroidApp(_serial(ctx), app);
    return null;
  }

  @override
  Future<BackendAppState> getAppState(
    BackendCommandContext ctx,
    String app,
  ) async {
    final state = await getAndroidAppState(_serial(ctx));
    return BackendAppState(
      appId: state.package,
      packageName: state.package,
      activity: state.activity,
      state: state.package == null ? 'unknown' : 'foreground',
    );
  }

  @override
  Future<List<BackendAppInfo>> listApps(
    BackendCommandContext ctx, [
    BackendAppListFilter? filter,
  ]) async {
    final raw = await listAndroidApps(
      _serial(ctx),
      filter: filter == BackendAppListFilter.userInstalled ? 'user' : 'all',
    );
    return raw
        .map(
          (e) => BackendAppInfo(
            id: e.package,
            name: e.name,
            packageName: e.package,
          ),
        )
        .toList();
  }

  @override
  Future<BackendActionResult> triggerAppEvent(
    BackendCommandContext ctx,
    BackendAppEvent event,
  ) async {
    if (event.name != 'notification') {
      unsupported("triggerAppEvent '${event.name}'");
    }
    final payload = event.payload ?? const <String, Object?>{};
    final packageName = (payload['package'] as String?) ?? ctx.appId ?? '';
    if (packageName.isEmpty) {
      unsupported(
        'triggerAppEvent notification requires payload.package or ctx.appId',
      );
    }
    final res = await pushAndroidNotification(
      _serial(ctx),
      packageName,
      AndroidBroadcastPayload(
        action: payload['action'] as String?,
        receiver: payload['receiver'] as String?,
        extras: payload['extras'] as Map<String, Object?>?,
      ),
    );
    return {'action': res.action, 'extrasCount': res.extrasCount};
  }

  // =========================================================================
  // Device Management
  // =========================================================================

  @override
  Future<List<BackendDeviceInfo>> listDevices(
    BackendCommandContext ctx, [
    BackendDeviceFilter? filter,
  ]) => listAndroidDevices();

  @override
  Future<BackendActionResult> bootDevice(
    BackendCommandContext ctx, [
    BackendDeviceTarget? target,
  ]) async {
    await openAndroidDevice(_serial(ctx));
    return null;
  }

  @override
  Future<BackendInstallResult> installApp(
    BackendCommandContext ctx,
    BackendInstallTarget target,
  ) async {
    final source = target.source;
    final path = source is BackendInstallSourcePath ? source.path : null;
    if (path == null || path.isEmpty) {
      unsupported('installApp requires a BackendInstallSourcePath on Android');
    }
    final packageName =
        await installAndroidInstallablePathAndResolvePackageName(
          _serial(ctx),
          path,
          packageNameHint: target.app,
        );
    return BackendInstallResult(appId: packageName, packageName: packageName);
  }

  // =========================================================================
  // Recording (screenrecord)
  // =========================================================================

  /// Start an on-device `screenrecord` session. Forks the recorder on
  /// the device (so the host-side adb call returns immediately) and
  /// captures the device-side PID into a cross-invocation record at
  /// `<stateDir>/android-recorders/<serial>.json`. `stopRecording` later
  /// kills that PID with SIGINT and pulls the resulting MP4.
  @override
  Future<BackendRecordingResult> startRecording(
    BackendCommandContext ctx,
    BackendRecordingOptions? options,
  ) async {
    final outPath = options?.outPath;
    if (outPath == null || outPath.isEmpty) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'Android startRecording requires options.outPath.',
      );
    }
    final serial = _serial(ctx);
    // If a previous recording is on disk, SIGINT the old PID so we don't
    // leak screenrecord processes on the device.
    final existing = await _readAndroidRecorder(serial);
    if (existing != null) {
      await runCmd('adb', [
        '-s',
        serial,
        'shell',
        'kill -2 ${existing.pid}',
      ], const ExecOptions(allowFailure: true, timeoutMs: 5000));
      await _deleteAndroidRecorder(serial);
    }
    final remotePath =
        '/sdcard/agent-device-recording-'
        '${DateTime.now().microsecondsSinceEpoch}.mp4';
    final cmd = <String>['screenrecord'];
    // Quality / fps would go here once we decide a mapping for Android's
    // `--bit-rate` / `--size` flags. Deferred.
    cmd.addAll([remotePath, '>/dev/null', '2>&1', '&', 'echo', r'$!']);
    final r = await runCmd('adb', [
      '-s',
      serial,
      'shell',
      cmd.join(' '),
    ], const ExecOptions(allowFailure: true, timeoutMs: 10000));
    if (r.exitCode != 0) {
      throw AppError(
        AppErrorCodes.commandFailed,
        'adb screenrecord failed to launch (exit ${r.exitCode}).',
        details: {'stdout': r.stdout, 'stderr': r.stderr},
      );
    }
    final pidStr = r.stdout.trim().split(RegExp(r'\s+')).last;
    final pid = int.tryParse(pidStr);
    if (pid == null || pid <= 0) {
      throw AppError(
        AppErrorCodes.commandFailed,
        'adb screenrecord did not echo a device PID '
        '(got ${r.stdout.length} bytes of stdout).',
        details: {'stdout': r.stdout, 'stderr': r.stderr},
      );
    }
    await _writeAndroidRecorder(
      _AndroidRecorderRecord(
        serial: serial,
        pid: pid,
        remotePath: remotePath,
        outPath: outPath,
      ),
    );
    return BackendRecordingResult(path: outPath);
  }

  @override
  Future<BackendRecordingResult> stopRecording(
    BackendCommandContext ctx,
    BackendRecordingOptions? options,
  ) async {
    final outPath = options?.outPath;
    if (outPath == null || outPath.isEmpty) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'Android stopRecording requires options.outPath (the same path '
        'passed to startRecording).',
      );
    }
    final serial = _serial(ctx);
    final record = await _readAndroidRecorder(serial);
    if (record == null) {
      throw AppError(
        AppErrorCodes.commandFailed,
        'No Android recording in progress for $serial.',
      );
    }
    // SIGINT so screenrecord finalizes the moov atom before exiting.
    await runCmd('adb', [
      '-s',
      serial,
      'shell',
      'kill -2 ${record.pid}',
    ], const ExecOptions(allowFailure: true, timeoutMs: 5000));
    // Brief grace period for finalization before we pull the file.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final dst = File(outPath);
    await dst.parent.create(recursive: true);
    final pull = await runCmd('adb', [
      '-s',
      serial,
      'pull',
      record.remotePath,
      outPath,
    ], const ExecOptions(allowFailure: true, timeoutMs: 60000));
    // Best-effort cleanup on-device even if pull failed.
    await runCmd('adb', [
      '-s',
      serial,
      'shell',
      'rm ${record.remotePath}',
    ], const ExecOptions(allowFailure: true, timeoutMs: 5000));
    await _deleteAndroidRecorder(serial);
    if (pull.exitCode != 0) {
      return BackendRecordingResult(
        path: outPath,
        warning:
            'adb pull ${record.remotePath} failed (exit ${pull.exitCode}). '
            'stderr: ${pull.stderr.trim()}',
      );
    }
    return BackendRecordingResult(path: outPath);
  }

  // =========================================================================
  // Diagnostics: Performance sampling (dumpsys)
  // =========================================================================

  /// Sample CPU% and memory (PSS kB) for the session's open app. Uses
  /// `adb shell dumpsys cpuinfo` + `adb shell dumpsys meminfo <package>`
  /// — both cheap one-shot snapshots; no sampling window.
  @override
  Future<BackendMeasurePerfResult> measurePerf(
    BackendCommandContext ctx,
    BackendMeasurePerfOptions? options,
  ) async {
    final serial = _serial(ctx);
    final packageName = ctx.appId;
    if (packageName == null || packageName.isEmpty) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'Android measurePerf requires an open app '
        '(run `agent-device open <package>` first).',
      );
    }
    final requested = options?.metrics?.map((e) => e.toLowerCase()).toSet();
    final wantCpu = requested == null || requested.contains('cpu');
    final wantMemory = requested == null || requested.contains('memory');

    final metrics = <BackendPerfMetric>[];
    String? startedAt;
    String? endedAt;

    if (wantCpu) {
      final cpu = await sampleAndroidCpuPerf(serial, packageName);
      metrics.add(
        BackendPerfMetric(
          name: 'cpu',
          value: cpu.usagePercent,
          unit: 'percent',
          status: 'ok',
          metadata: {
            'method': cpu.method,
            'description': androidCpuSampleDescription,
            'matchedProcesses': cpu.matchedProcesses,
            'measuredAt': cpu.measuredAt,
          },
        ),
      );
      startedAt ??= cpu.measuredAt;
      endedAt = cpu.measuredAt;
    }
    if (wantMemory) {
      final mem = await sampleAndroidMemoryPerf(serial, packageName);
      metrics.add(
        BackendPerfMetric(
          name: 'memory.totalPss',
          value: mem.totalPssKb.toDouble(),
          unit: 'kB',
          status: 'ok',
          metadata: {
            'method': mem.method,
            'description': androidMemorySampleDescription,
            if (mem.totalRssKb != null) 'totalRssKb': mem.totalRssKb,
            'measuredAt': mem.measuredAt,
          },
        ),
      );
      startedAt ??= mem.measuredAt;
      endedAt = mem.measuredAt;
    }

    return BackendMeasurePerfResult(
      metrics: metrics,
      startedAt: startedAt,
      endedAt: endedAt,
      backend: 'android-dumpsys',
    );
  }

  // =========================================================================
  // Diagnostics: Log streaming (background)
  // =========================================================================

  /// Start `adb -s <serial> logcat` in the background, writing to
  /// [options.outPath]. If the session has an open app we look up its
  /// PID via `adb shell pidof <pkg>` and narrow via `--pid`; otherwise
  /// the full logcat stream is captured. PID + outPath are persisted
  /// at `<stateDir>/log-streams/<serial>.json` so [stopLogStream] in a
  /// later invocation can find them.
  @override
  Future<BackendLogStreamResult> startLogStream(
    BackendCommandContext ctx,
    BackendLogStreamOptions options,
  ) async {
    final outPath = options.outPath;
    if (outPath == null || outPath.isEmpty) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'Android startLogStream requires options.outPath.',
      );
    }
    final serial = _serial(ctx);
    final appPackage = options.appBundleId ?? ctx.appId;

    // SIGINT any stale stream first so we don't leak logcat processes.
    final existing = await readLogStreamRecord(serial);
    if (existing != null) {
      killLogStreamPid(existing.hostPid);
      await deleteLogStreamRecord(serial);
    }

    int? pid;
    if (appPackage != null && appPackage.isNotEmpty) {
      final r = await runCmd('adb', [
        '-s',
        serial,
        'shell',
        'pidof',
        appPackage,
      ], const ExecOptions(allowFailure: true, timeoutMs: 5000));
      final lookedUp = int.tryParse(
        r.stdout.trim().split(RegExp(r'\s+')).first,
      );
      if (lookedUp != null && lookedUp > 0) pid = lookedUp;
    }

    final args = <String>[
      '-s',
      serial,
      'logcat',
      '-v',
      'time',
      if (pid != null) ...['--pid', '$pid'],
    ];

    final outFile = File(outPath);
    await outFile.parent.create(recursive: true);
    // `sh -c 'exec adb … > path 2>&1'` so we can background it cleanly.
    final quotedArgs = args.map((a) => _shellQuote(a)).join(' ');
    final script = 'exec adb $quotedArgs > ${_shellQuote(outPath)} 2>&1';
    final proc = await runCmdDetached('sh', [
      '-c',
      script,
    ], const ExecDetachedOptions());
    final startedAt = DateTime.now().toUtc().toIso8601String();
    await writeLogStreamRecord(
      LogStreamRecord(
        deviceId: serial,
        platform: 'android',
        hostPid: proc.pid,
        outPath: outPath,
        startedAt: startedAt,
        appBundleId: appPackage,
      ),
    );
    return BackendLogStreamResult(
      outPath: outPath,
      hostPid: proc.pid,
      backend: pid != null ? 'android-logcat-pid' : 'android-logcat',
      startedAt: startedAt,
    );
  }

  @override
  Future<BackendLogStreamResult> stopLogStream(
    BackendCommandContext ctx,
  ) async {
    final serial = _serial(ctx);
    final record = await readLogStreamRecord(serial);
    if (record == null) {
      throw AppError(
        AppErrorCodes.commandFailed,
        'No active log stream for Android device $serial.',
      );
    }
    final delivered = killLogStreamPid(record.hostPid);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await deleteLogStreamRecord(serial);
    int? bytes;
    final f = File(record.outPath);
    if (await f.exists()) bytes = await f.length();
    return BackendLogStreamResult(
      outPath: record.outPath,
      hostPid: record.hostPid,
      backend: 'android-logcat',
      startedAt: record.startedAt,
      stoppedAt: DateTime.now().toUtc().toIso8601String(),
      bytes: bytes,
      stale: !delivered,
    );
  }

  // =========================================================================
  // Diagnostics: Logs (one-shot)
  // =========================================================================

  /// Dump recent logcat output (all tags). Simulator & device alike.
  /// Uses `adb -s <serial> logcat -d -T <time>` so the call returns
  /// bounded output rather than streaming. Options.since accepts the same
  /// relative forms as the iOS backend (`30s`, `5m`, `1h`, `2d`) plus
  /// absolute `YYYY-MM-DD HH:MM:SS.mmm` for callers that want to pin an
  /// exact point. Filtering by app package is deferred — pull everything
  /// and let the caller grep. Default window: last 5 minutes.
  @override
  Future<BackendReadLogsResult> readLogs(
    BackendCommandContext ctx,
    BackendReadLogsOptions? options,
  ) async {
    final since = options?.since?.trim();
    final windowArg = resolveAdbLogcatTimeWindow(since);
    final args = <String>[
      '-s',
      _serial(ctx),
      'logcat',
      '-d',
      '-v',
      'time',
      if (windowArg != null) ...['-T', windowArg],
    ];
    final r = await runCmd(
      'adb',
      args,
      const ExecOptions(allowFailure: true, timeoutMs: 15000),
    );
    if (r.exitCode != 0) {
      throw AppError(
        AppErrorCodes.commandFailed,
        'adb logcat failed (exit ${r.exitCode}).',
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
      // logcat -v time emits a "--------- beginning of <buffer>" banner
      // per log buffer; drop it.
      if (line.startsWith('--------- beginning of ')) continue;
      entries.add(BackendLogEntry(message: line));
    }
    final limit = options?.limit;
    final trimmed = (limit != null && limit > 0 && entries.length > limit)
        ? entries.sublist(entries.length - limit)
        : entries;
    return BackendReadLogsResult(entries: trimmed, backend: 'android-logcat');
  }

  @override
  Future<BackendInstallResult> reinstallApp(
    BackendCommandContext ctx,
    BackendInstallTarget target,
  ) async {
    final source = target.source;
    final path = source is BackendInstallSourcePath ? source.path : null;
    if (path == null || path.isEmpty) {
      unsupported(
        'reinstallApp requires a BackendInstallSourcePath on Android',
      );
    }
    final app = target.app;
    if (app == null || app.isEmpty) {
      unsupported('reinstallApp requires target.app (package name) on Android');
    }
    final res = await reinstallAndroidApp(_serial(ctx), app, path);
    return BackendInstallResult(appId: res.package, packageName: res.package);
  }
}

String _shellQuote(String s) => "'${s.replaceAll("'", r"'\''")}'";

/// Convert iOS-flavoured `--since` inputs (`30s`, `5m`, `1h`, `2d`) into
/// the `MM-DD HH:MM:SS.mmm` timestamp adb's `logcat -T` expects. Absolute
/// timestamps are passed through unchanged. Null/empty defaults to a
/// 5-minute window. Returns null for unrecognizable input (caller may
/// choose to omit the `-T` flag entirely).
String? resolveAdbLogcatTimeWindow(String? since, {DateTime? now}) {
  Duration? duration;
  if (since == null || since.isEmpty) {
    duration = const Duration(minutes: 5);
  } else {
    final relative = RegExp(r'^(\d+)([smhd])$').firstMatch(since);
    if (relative != null) {
      final n = int.parse(relative.group(1)!);
      duration = switch (relative.group(2)) {
        's' => Duration(seconds: n),
        'm' => Duration(minutes: n),
        'h' => Duration(hours: n),
        'd' => Duration(days: n),
        _ => null,
      };
    } else {
      // Pass through absolute timestamps as-is.
      return since;
    }
  }
  if (duration == null) return null;
  final since0 = (now ?? DateTime.now()).subtract(duration);
  String two(int v) => v.toString().padLeft(2, '0');
  String three(int v) => v.toString().padLeft(3, '0');
  return '${two(since0.month)}-${two(since0.day)} ${two(since0.hour)}:'
      '${two(since0.minute)}:${two(since0.second)}.${three(since0.millisecond)}';
}

// =========================================================================
// Android recorder record (on-device screenrecord PID + paths)
// =========================================================================

class _AndroidRecorderRecord {
  final String serial;
  final int pid;
  final String remotePath;
  final String outPath;
  const _AndroidRecorderRecord({
    required this.serial,
    required this.pid,
    required this.remotePath,
    required this.outPath,
  });

  Map<String, Object?> toJson() => {
    'serial': serial,
    'pid': pid,
    'remotePath': remotePath,
    'outPath': outPath,
  };

  static _AndroidRecorderRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final serial = raw['serial'];
    final pid = raw['pid'];
    final remotePath = raw['remotePath'];
    final outPath = raw['outPath'];
    if (serial is! String ||
        pid is! int ||
        remotePath is! String ||
        outPath is! String) {
      return null;
    }
    return _AndroidRecorderRecord(
      serial: serial,
      pid: pid,
      remotePath: remotePath,
      outPath: outPath,
    );
  }
}

File _androidRecorderFile(String serial) {
  final paths = resolveStatePaths();
  return File(p.join(paths.baseDir, 'android-recorders', '$serial.json'));
}

Future<_AndroidRecorderRecord?> _readAndroidRecorder(String serial) async {
  final file = _androidRecorderFile(serial);
  if (!await file.exists()) return null;
  try {
    return _AndroidRecorderRecord.fromJson(
      jsonDecode(await file.readAsString()),
    );
  } on FormatException {
    return null;
  }
}

Future<void> _writeAndroidRecorder(_AndroidRecorderRecord record) async {
  final file = _androidRecorderFile(record.serial);
  await file.parent.create(recursive: true);
  await file.writeAsString(jsonEncode(record.toJson()));
}

Future<void> _deleteAndroidRecorder(String serial) async {
  final file = _androidRecorderFile(serial);
  if (await file.exists()) {
    try {
      await file.delete();
    } catch (_) {}
  }
}

DeviceRotation _toDeviceRotation(BackendDeviceOrientation o) => switch (o) {
  BackendDeviceOrientation.portrait => DeviceRotation.portrait,
  BackendDeviceOrientation.portraitUpsideDown =>
    DeviceRotation.portraitUpsideDown,
  BackendDeviceOrientation.landscapeLeft => DeviceRotation.landscapeLeft,
  BackendDeviceOrientation.landscapeRight => DeviceRotation.landscapeRight,
};
