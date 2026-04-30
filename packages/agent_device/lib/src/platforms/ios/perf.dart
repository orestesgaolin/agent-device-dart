// Port of agent-device/src/platforms/ios/perf.ts.
//
// Simulator sampling uses `simctl spawn /bin/ps`. Physical-device
// sampling records a 1-second `xctrace` activity-monitor trace, exports
// the `activity-monitor-process-live` table as XML, and extracts the
// target app's row.
//
// Frame-health sampling records a 2-second `xctrace` Animation Hitches trace,
// exports the `hitches`, `hitches-frame-lifetimes`, and optional
// `device-display-info` tables, and delegates parsing to perf_frame.dart.
library;

import 'dart:io';

import 'package:agent_device/src/utils/errors.dart';
import 'package:agent_device/src/utils/exec.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../perf_utils.dart';
import 'devicectl.dart';
import 'perf_frame.dart';
import 'simctl.dart';

const String appleCpuSampleMethod = 'ps-process-snapshot';
const String appleMemorySampleMethod = 'ps-process-snapshot';
const String iosDeviceCpuSampleMethod = 'xctrace-activity-monitor';
const String iosDeviceMemorySampleMethod = 'xctrace-activity-monitor';

const int _applePerfTimeoutMs = 15000;
// Physical-device xctrace captures take materially longer than the
// sample window itself to initialize.
const int _iosDevicePerfRecordTimeoutMs = 60000;
const int _iosDevicePerfExportTimeoutMs = 15000;
const String _iosDevicePerfTraceDuration = '1s';
const String _iosDeviceFrameTraceDuration = '2s';
const int _iosDeviceTraceRecordMaxAttempts = 3;
const int _iosDeviceTraceRecordRetryDelayMs = 1500;

/// CPU performance sample from `simctl spawn ps`.
class AppleCpuPerfSample {
  final double usagePercent;
  final String measuredAt;
  final String method;
  final List<String> matchedProcesses;

  const AppleCpuPerfSample({
    required this.usagePercent,
    required this.measuredAt,
    required this.method,
    required this.matchedProcesses,
  });
}

/// Memory performance sample (resident set size, kB) from the same
/// `ps` call that sourced the CPU sample.
class AppleMemoryPerfSample {
  final int residentMemoryKb;
  final String measuredAt;
  final String method;
  final List<String> matchedProcesses;

  const AppleMemoryPerfSample({
    required this.residentMemoryKb,
    required this.measuredAt,
    required this.method,
    required this.matchedProcesses,
  });
}

/// One parsed row from `ps -axo pid,%cpu,rss,command`.
class AppleProcessSample {
  final int pid;
  final double cpuPercent;
  final int rssKb;
  final String command;
  const AppleProcessSample({
    required this.pid,
    required this.cpuPercent,
    required this.rssKb,
    required this.command,
  });
}

/// Sample CPU + memory for [appBundleId] on the iOS simulator [udid].
/// Throws [AppError] with [AppErrorCodes.commandFailed] if the process
/// can't be found or if `simctl` / `plutil` failures bubble up.
Future<({AppleCpuPerfSample cpu, AppleMemoryPerfSample memory})>
sampleIosSimulatorPerfMetrics(String udid, String appBundleId) async {
  final executable = await _resolveIosSimulatorExecutable(udid, appBundleId);
  final processes = await _readSimulatorProcessSamples(udid, executable);
  if (processes.isEmpty) {
    throw AppError(
      AppErrorCodes.commandFailed,
      'No running process found for $appBundleId',
      details: {
        'appBundleId': appBundleId,
        'hint':
            'Run `agent-device open $appBundleId` so the app is foregrounded, '
            'then retry perf.',
      },
    );
  }
  final measuredAt = DateTime.now().toIso8601String();
  // We already filtered the ps output to rows whose executable suffix
  // matched. All survivors share the same executable name, so report
  // that rather than re-splitting the full path (which is fragile
  // against paths containing spaces like the iOS simruntime bundle).
  final matchedProcesses = <String>[executable];
  final totalCpu = processes.fold<double>(
    0,
    (acc, proc) => acc + proc.cpuPercent,
  );
  final totalRss = processes.fold<int>(0, (acc, proc) => acc + proc.rssKb);
  return (
    cpu: AppleCpuPerfSample(
      usagePercent: roundPercent(totalCpu),
      measuredAt: measuredAt,
      method: appleCpuSampleMethod,
      matchedProcesses: matchedProcesses,
    ),
    memory: AppleMemoryPerfSample(
      residentMemoryKb: totalRss,
      measuredAt: measuredAt,
      method: appleMemorySampleMethod,
      matchedProcesses: matchedProcesses,
    ),
  );
}

/// Parse `ps -axo pid,%cpu,rss,command` output into individual samples.
/// Exposed for unit tests — the parser is the risky bit.
List<AppleProcessSample> parseApplePsOutput(String stdout) {
  final rows = <AppleProcessSample>[];
  final re = RegExp(r'^(\d+)\s+([0-9]+(?:\.[0-9]+)?)\s+(\d+)\s+(.+)$');
  for (final raw in stdout.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final m = re.firstMatch(line);
    if (m == null) continue;
    final pid = int.tryParse(m.group(1) ?? '');
    final cpuPercent = double.tryParse(m.group(2) ?? '');
    final rssKb = int.tryParse(m.group(3) ?? '');
    final command = m.group(4)?.trim() ?? '';
    if (pid == null ||
        cpuPercent == null ||
        !cpuPercent.isFinite ||
        rssKb == null) {
      continue;
    }
    rows.add(
      AppleProcessSample(
        pid: pid,
        cpuPercent: cpuPercent,
        rssKb: rssKb,
        command: command,
      ),
    );
  }
  return rows;
}

/// Whether a `ps` [command] line belongs to an app whose executable
/// basename is [executableName]. Exposed for tests.
///
/// The naive split-on-whitespace approach from the TS port doesn't
/// survive simulator runtime paths like `.../iOS 26.2.simruntime/...`
/// that contain spaces inside the executable path itself. Instead we
/// look for the executable name as a path-suffix segment: either at
/// the end of the string, or followed by a space (indicating trailing
/// args). Both guard with a leading `/` so we don't false-match a
/// bare substring inside an argv.
bool matchesAppleExecutableProcess(String command, String executableName) {
  final trimmed = command.trim();
  final needle = '/$executableName';
  if (trimmed.endsWith(needle)) return true;
  final idx = trimmed.indexOf('$needle ');
  return idx >= 0;
}

Future<String> _resolveIosSimulatorExecutable(
  String udid,
  String appBundleId,
) async {
  final containerResult = await runCmd(
    'xcrun',
    buildSimctlArgs(['get_app_container', udid, appBundleId, 'app']),
    const ExecOptions(allowFailure: true, timeoutMs: _applePerfTimeoutMs),
  );
  if (containerResult.exitCode != 0) {
    throw AppError(
      AppErrorCodes.commandFailed,
      'Failed to resolve iOS simulator app container for $appBundleId',
      details: {
        'appBundleId': appBundleId,
        'stdout': containerResult.stdout,
        'stderr': containerResult.stderr,
        'exitCode': containerResult.exitCode,
        'hint':
            'Ensure the iOS simulator app is installed and booted, then retry '
            'perf.',
      },
    );
  }
  final appPath = containerResult.stdout.trim();
  if (appPath.isEmpty) {
    throw AppError(
      AppErrorCodes.appNotInstalled,
      'No iOS simulator app container found for $appBundleId',
      details: {'appBundleId': appBundleId},
    );
  }
  final plistPath = p.join(appPath, 'Info.plist');
  final plutilResult = await runCmd('plutil', [
    '-extract',
    'CFBundleExecutable',
    'raw',
    '-o',
    '-',
    plistPath,
  ], const ExecOptions(allowFailure: true, timeoutMs: _applePerfTimeoutMs));
  if (plutilResult.exitCode != 0) {
    throw AppError(
      AppErrorCodes.commandFailed,
      'Failed to read CFBundleExecutable from $plistPath',
      details: {
        'appBundleId': appBundleId,
        'stdout': plutilResult.stdout,
        'stderr': plutilResult.stderr,
        'exitCode': plutilResult.exitCode,
      },
    );
  }
  final executableName = plutilResult.stdout.trim();
  if (executableName.isEmpty) {
    throw AppError(
      AppErrorCodes.commandFailed,
      'CFBundleExecutable is empty in $plistPath',
    );
  }
  return executableName;
}

Future<List<AppleProcessSample>> _readSimulatorProcessSamples(
  String udid,
  String executableName,
) async {
  final r = await runCmd(
    'xcrun',
    buildSimctlArgs([
      'spawn',
      udid,
      // Use the absolute path — simctl spawn doesn't search a user PATH
      // inside the simulator and fails with ENOENT on a bare `ps`.
      '/bin/ps',
      '-axo',
      'pid=,%cpu=,rss=,command=',
    ]),
    const ExecOptions(timeoutMs: _applePerfTimeoutMs),
  );
  return parseApplePsOutput(r.stdout)
      .where(
        (proc) => matchesAppleExecutableProcess(proc.command, executableName),
      )
      .toList();
}

// =========================================================================
// Physical-device perf via xctrace
// =========================================================================

/// One process row pulled out of an xctrace
/// `activity-monitor-process-live` XML dump.
class IosDeviceProcessSample {
  final int pid;
  final String processName;
  final int? cpuTimeNs;
  final int? residentMemoryBytes;
  final int? durationNs;
  const IosDeviceProcessSample({
    required this.pid,
    required this.processName,
    this.cpuTimeNs,
    this.residentMemoryBytes,
    this.durationNs,
  });
}

/// Record a 1-second `Activity Monitor` trace on [udid] and extract
/// every `activity-monitor-process-live` row. Caller filters by
/// process name. Cleans up the temp .trace bundle on return.
Future<List<IosDeviceProcessSample>> sampleIosDevicePerfSnapshot(
  String udid,
) async {
  final tmp = await Directory.systemTemp.createTemp('ad-ios-xctrace-');
  final tracePath = p.join(tmp.path, 'perf.trace');
  final exportPath = p.join(tmp.path, 'activity-monitor-process-live.xml');
  try {
    await _recordIosDeviceTrace(
      udid: udid,
      tracePath: tracePath,
      template: 'Activity Monitor',
      duration: _iosDevicePerfTraceDuration,
      allProcesses: true,
      failureMessage: 'Failed to record iOS device Activity Monitor sample',
    );
    await _exportIosDevicePerfTable(
      udid: udid,
      tracePath: tracePath,
      schema: 'activity-monitor-process-live',
      outputPath: exportPath,
      appBundleId: '',
    );
    final xml = await File(exportPath).readAsString();
    return parseIosDevicePerfXml(xml);
  } finally {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  }
}

// =========================================================================
// iOS device frame-health perf via xctrace Animation Hitches
// =========================================================================

/// Resolve the running processes belonging to [appBundleId] on the physical
/// iOS device [udid] via `devicectl device info apps` + `info processes`.
/// Throws [AppError] with [AppErrorCodes.appNotInstalled] when the bundle is
/// not found, or [AppErrorCodes.commandFailed] when no matching process is
/// running.
Future<List<IosDeviceProcessInfo>> resolveIosDevicePerfTarget(
  String udid,
  String appBundleId,
) async {
  final apps = await listIosDeviceApps(udid);
  final app = apps.firstWhere(
    (a) => a.bundleId == appBundleId,
    orElse: () => const IosDeviceAppInfo(bundleId: '', name: '', url: null),
  );
  if (app.bundleId.isEmpty) {
    throw AppError(
      AppErrorCodes.appNotInstalled,
      'No iOS device app found for $appBundleId',
      details: {'appBundleId': appBundleId, 'deviceId': udid},
    );
  }
  if (app.url == null || app.url!.isEmpty) {
    throw AppError(
      AppErrorCodes.commandFailed,
      'Missing app bundle URL for $appBundleId',
      details: {'appBundleId': appBundleId, 'deviceId': udid},
    );
  }
  // Normalize: strip trailing slash so prefix matching is consistent.
  final appBundleUrl = app.url!.replaceFirst(RegExp(r'/$'), '');
  final allProcesses = await listIosDeviceProcesses(udid);
  final processes = allProcesses
      .where((proc) => proc.executable.startsWith('$appBundleUrl/'))
      .toList();
  if (processes.isEmpty) {
    throw AppError(
      AppErrorCodes.commandFailed,
      'No running process found for $appBundleId',
      details: {
        'appBundleId': appBundleId,
        'deviceId': udid,
        'hint':
            'Run open <app> for this session again to ensure the iOS app is '
            'active, then retry perf.',
      },
    );
  }
  return processes;
}

/// Sample iOS frame-drop metrics for [appBundleId] on the physical iOS
/// device identified by [udid]. Records a 2-second Animation Hitches trace,
/// exports the hitches / frame-lifetimes / display-info tables, and delegates
/// parsing to [parseAppleFramePerfSample].
///
/// Only supported on connected physical iOS devices. Throws [AppError] with
/// [AppErrorCodes.commandFailed] for simulators or unsupported platforms.
Future<AppleFramePerfSample> sampleAppleFramePerf(
  String udid,
  String appBundleId, {
  required List<int> targetPids,
  required List<String> targetProcessNames,
}) async {
  final capture = await _captureIosDeviceFramePerf(
    udid: udid,
    appBundleId: appBundleId,
    targetPids: targetPids,
  );
  return parseAppleFramePerfSample(
    hitchesXml: capture.hitchesXml,
    frameLifetimesXml: capture.frameLifetimesXml,
    displayInfoXml: capture.displayInfoXml,
    processIds: targetPids,
    processNames: targetProcessNames,
    windowStartedAt: capture.windowStartedAt,
    windowEndedAt: capture.windowEndedAt,
    measuredAt: capture.windowEndedAt,
  );
}

typedef _FramePerfCapture = ({
  String windowStartedAt,
  String windowEndedAt,
  String hitchesXml,
  String frameLifetimesXml,
  String? displayInfoXml,
});

Future<_FramePerfCapture> _captureIosDeviceFramePerf({
  required String udid,
  required String appBundleId,
  required List<int> targetPids,
}) async {
  final tmp = await Directory.systemTemp.createTemp(
    'ad-ios-frame-perf-',
  );
  final tracePath = p.join(tmp.path, 'animation-hitches.trace');
  final hitchesPath = p.join(tmp.path, 'hitches.xml');
  final frameLifetimesPath = p.join(tmp.path, 'frame-lifetimes.xml');
  final displayInfoPath = p.join(tmp.path, 'display-info.xml');
  try {
    final targetArgs = targetPids
        .expand((pid) => ['--attach', '$pid'])
        .toList();
    final record = await _recordIosDeviceTrace(
      udid: udid,
      tracePath: tracePath,
      template: 'Animation Hitches',
      duration: _iosDeviceFrameTraceDuration,
      targetArgs: targetArgs,
      validateTraceOutput: true,
      failureMessage:
          'Failed to record iOS frame-health sample for $appBundleId',
      appBundleId: appBundleId,
    );
    await _exportIosDevicePerfTable(
      udid: udid,
      tracePath: tracePath,
      schema: 'hitches',
      outputPath: hitchesPath,
      appBundleId: appBundleId,
    );
    await _exportIosDevicePerfTable(
      udid: udid,
      tracePath: tracePath,
      schema: 'hitches-frame-lifetimes',
      outputPath: frameLifetimesPath,
      appBundleId: appBundleId,
    );
    final hasDisplayInfo = await _exportOptionalIosDevicePerfTable(
      udid: udid,
      tracePath: tracePath,
      schema: 'device-display-info',
      outputPath: displayInfoPath,
      appBundleId: appBundleId,
    );
    return (
      windowStartedAt: record.startedAt,
      windowEndedAt: record.endedAt,
      hitchesXml: await File(hitchesPath).readAsString(),
      frameLifetimesXml: await File(frameLifetimesPath).readAsString(),
      displayInfoXml:
          hasDisplayInfo ? await File(displayInfoPath).readAsString() : null,
    );
  } finally {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  }
}

// =========================================================================
// Shared xctrace record / export helpers
// =========================================================================

typedef _TraceRecord = ({String startedAt, String endedAt, int capturedAtMs});
typedef _TraceRecordAttempt = ({
  String startedAt,
  String endedAt,
  int capturedAtMs,
  RunCmdResult result,
});

Future<_TraceRecord> _recordIosDeviceTrace({
  required String udid,
  required String tracePath,
  required String template,
  required String duration,
  List<String> targetArgs = const [],
  bool allProcesses = false,
  bool validateTraceOutput = false,
  required String failureMessage,
  String appBundleId = '',
}) async {
  final recordArgs = [
    'xctrace',
    'record',
    '--template',
    template,
    '--device',
    udid,
    if (allProcesses) '--all-processes',
    ...targetArgs,
    '--time-limit',
    duration,
    '--output',
    tracePath,
    '--quiet',
    '--no-prompt',
  ];
  final attempt = await _runIosDeviceTraceRecord(recordArgs, tracePath);
  if (attempt.result.exitCode == 0) {
    if (validateTraceOutput) {
      await _assertUsableTraceOutput(
        tracePath: tracePath,
        appBundleId: appBundleId,
        failureMessage: failureMessage,
        stdout: attempt.result.stdout,
        stderr: attempt.result.stderr,
      );
    }
    return (
      startedAt: attempt.startedAt,
      endedAt: attempt.endedAt,
      capturedAtMs: attempt.capturedAtMs,
    );
  }
  throw AppError(
    AppErrorCodes.commandFailed,
    failureMessage,
    details: {
      'cmd': 'xcrun',
      'exitCode': attempt.result.exitCode,
      'stdout': attempt.result.stdout,
      'stderr': attempt.result.stderr,
      if (appBundleId.isNotEmpty) 'appBundleId': appBundleId,
      'deviceId': udid,
    },
  );
}

Future<_TraceRecordAttempt> _runIosDeviceTraceRecord(
  List<String> recordArgs,
  String tracePath,
) async {
  _TraceRecordAttempt? lastAttempt;
  for (var attempt = 1;
      attempt <= _iosDeviceTraceRecordMaxAttempts;
      attempt += 1) {
    if (attempt > 1) {
      // Clean up any partial trace from the failed attempt.
      try {
        final f = FileSystemEntity.typeSync(tracePath);
        if (f == FileSystemEntityType.directory) {
          await Directory(tracePath).delete(recursive: true);
        } else if (f == FileSystemEntityType.file) {
          await File(tracePath).delete();
        }
      } catch (_) {}
      await Future<void>.delayed(
        const Duration(milliseconds: _iosDeviceTraceRecordRetryDelayMs),
      );
    }
    final startedAt = DateTime.now().toUtc().toIso8601String();
    final result = await runCmd(
      'xcrun',
      recordArgs,
      const ExecOptions(
        allowFailure: true,
        timeoutMs: _iosDevicePerfRecordTimeoutMs,
      ),
    );
    lastAttempt = (
      result: result,
      startedAt: startedAt,
      endedAt: DateTime.now().toUtc().toIso8601String(),
      capturedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (result.exitCode == 0 ||
        !_isRetryableTraceRecordFailure(result.stdout, result.stderr)) {
      return lastAttempt;
    }
  }
  return lastAttempt!;
}

bool _isRetryableTraceRecordFailure(String stdout, String stderr) {
  final text = '$stdout\n$stderr'.toLowerCase();
  return text.contains('_lockkperf') ||
      text.contains('could not lock kperf') ||
      text.contains('likely another session just started');
}

Future<void> _assertUsableTraceOutput({
  required String tracePath,
  required String appBundleId,
  required String failureMessage,
  required String stdout,
  required String stderr,
}) async {
  final entityType = await FileSystemEntity.type(tracePath);
  bool hasTrace;
  if (entityType == FileSystemEntityType.directory) {
    hasTrace = (await Directory(tracePath).list().length) > 0;
  } else {
    final stat = await File(tracePath).stat().catchError((_) => FileStat.statSync('/dev/null'));
    hasTrace = stat.size > 0;
  }
  if (hasTrace) return;
  throw AppError(
    AppErrorCodes.commandFailed,
    '$failureMessage: xctrace produced no trace data',
    details: {
      'tracePath': tracePath,
      if (appBundleId.isNotEmpty) 'appBundleId': appBundleId,
      'stdout': stdout,
      'stderr': stderr,
      'hint':
          'Keep the iOS device unlocked and connected by cable, keep the app '
          'active, then retry perf.',
    },
  );
}

Future<void> _exportIosDevicePerfTable({
  required String udid,
  required String tracePath,
  required String schema,
  required String outputPath,
  required String appBundleId,
}) async {
  final exportArgs = [
    'xctrace',
    'export',
    '--input',
    tracePath,
    '--xpath',
    '/trace-toc/run/data/table[@schema="$schema"]',
    '--output',
    outputPath,
  ];
  final result = await runCmd(
    'xcrun',
    exportArgs,
    const ExecOptions(
      allowFailure: true,
      timeoutMs: _iosDevicePerfExportTimeoutMs,
    ),
  );
  if (result.exitCode == 0) return;
  throw AppError(
    AppErrorCodes.commandFailed,
    'Failed to export iOS device $schema data',
    details: {
      'cmd': 'xcrun',
      'exitCode': result.exitCode,
      'stdout': result.stdout,
      'stderr': result.stderr,
      if (appBundleId.isNotEmpty) 'appBundleId': appBundleId,
      'deviceId': udid,
    },
  );
}

Future<bool> _exportOptionalIosDevicePerfTable({
  required String udid,
  required String tracePath,
  required String schema,
  required String outputPath,
  required String appBundleId,
}) async {
  try {
    await _exportIosDevicePerfTable(
      udid: udid,
      tracePath: tracePath,
      schema: schema,
      outputPath: outputPath,
      appBundleId: appBundleId,
    );
    return true;
  } catch (_) {
    return false;
  }
}

/// Parse the XML dump of `activity-monitor-process-live` into one
/// entry per row. Exposed for unit tests — the schema handling is
/// fragile. `<sentinel />` cells collapse to null so rows that didn't
/// sample a given metric don't poison the output.
List<IosDeviceProcessSample> parseIosDevicePerfXml(String xmlText) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xmlText);
  } on XmlException {
    return const [];
  }
  final schema = doc.findAllElements('schema').firstOrNull;
  if (schema == null) return const [];
  final mnemonics = <String>[
    for (final col in schema.findElements('col'))
      col.findElements('mnemonic').firstOrNull?.innerText ?? '',
  ];
  final pidIndex = mnemonics.indexOf('pid');
  final processIndex = mnemonics.indexOf('process');
  final cpuTotalIndex = mnemonics.indexOf('cpu-total');
  final memoryRealIndex = mnemonics.indexOf('memory-real');
  final durationIndex = mnemonics.indexOf('duration');
  if (pidIndex < 0 ||
      processIndex < 0 ||
      cpuTotalIndex < 0 ||
      memoryRealIndex < 0) {
    return const [];
  }

  // Build id → element map for ref lookup.
  final elementsById = <String, XmlElement>{};
  for (final el in doc.descendants.whereType<XmlElement>()) {
    final id = el.getAttribute('id');
    if (id != null) elementsById[id] = el;
  }

  final samples = <IosDeviceProcessSample>[];
  final rows = doc.findAllElements('row').toList();
  for (final row in rows) {
    final cells = row.childElements.toList();
    if (cells.length <= memoryRealIndex) continue;
    final processName = _resolveProcessName(cells[processIndex], elementsById);
    if (processName == null || processName.isEmpty) continue;
    final pid = _resolveIntCell(cells[pidIndex], elementsById);
    if (pid == null) continue;
    samples.add(
      IosDeviceProcessSample(
        pid: pid,
        processName: processName,
        cpuTimeNs: _resolveIntCell(cells[cpuTotalIndex], elementsById),
        residentMemoryBytes: _resolveIntCell(
          cells[memoryRealIndex],
          elementsById,
        ),
        durationNs: durationIndex >= 0 && cells.length > durationIndex
            ? _resolveIntCell(cells[durationIndex], elementsById)
            : null,
      ),
    );
  }
  return samples;
}

int? _resolveIntCell(XmlElement el, Map<String, XmlElement> elementsById) {
  if (el.localName == 'sentinel') return null;
  final ref = el.getAttribute('ref');
  final text = ref != null ? elementsById[ref]?.innerText : el.innerText;
  if (text == null || text.isEmpty) return null;
  return int.tryParse(text.trim());
}

String? _resolveProcessName(
  XmlElement el,
  Map<String, XmlElement> elementsById,
) {
  // Prefer fmt ("AppName (1234)"), resolving ref first if present.
  final ref = el.getAttribute('ref');
  final target = ref != null ? elementsById[ref] : el;
  final fmt = target?.getAttribute('fmt');
  if (fmt != null && fmt.isNotEmpty) return fmt;
  return null;
}

/// Sample physical-device CPU + memory. Records two consecutive
/// xctrace activity-monitor traces and diffs `cpu-total` per matched
/// pid to produce a real CPU%. The wall-clock window is the time
/// between the two captures (each xctrace invocation takes a few
/// seconds, so the natural pacing is enough — no explicit sleep).
/// Memory is the resident-set sum of the second snapshot.
Future<({AppleCpuPerfSample cpu, AppleMemoryPerfSample memory})>
sampleIosDevicePerfMetrics(
  String udid, {
  required bool Function(String processName) processMatcher,
  required String matcherLabel,
}) async {
  final firstSamples = await sampleIosDevicePerfSnapshot(udid);
  final firstAt = DateTime.now();
  final secondSamples = await sampleIosDevicePerfSnapshot(udid);
  final secondAt = DateTime.now();
  return computeIosDevicePerfDelta(
    firstSamples: firstSamples,
    secondSamples: secondSamples,
    firstCapturedAt: firstAt,
    secondCapturedAt: secondAt,
    processMatcher: processMatcher,
    matcherLabel: matcherLabel,
  );
}

/// Pure aggregator: given two xctrace snapshots and their capture
/// timestamps, compute the CPU% delta + resident-memory snapshot for
/// processes matching [processMatcher]. Exposed for unit tests — the
/// per-pid bookkeeping is the risky bit.
({AppleCpuPerfSample cpu, AppleMemoryPerfSample memory})
computeIosDevicePerfDelta({
  required List<IosDeviceProcessSample> firstSamples,
  required List<IosDeviceProcessSample> secondSamples,
  required DateTime firstCapturedAt,
  required DateTime secondCapturedAt,
  required bool Function(String processName) processMatcher,
  required String matcherLabel,
}) {
  final matchedSecond = secondSamples
      .where((s) => processMatcher(s.processName))
      .toList();
  if (matchedSecond.isEmpty) {
    throw AppError(
      AppErrorCodes.commandFailed,
      'xctrace returned no running process matching "$matcherLabel"',
      details: {
        'hint':
            'Ensure the app is foregrounded on the device before sampling. '
            'Available processes (first 20): '
            '${secondSamples.map((s) => s.processName).take(20).toList()}',
      },
    );
  }
  final elapsedMs = secondCapturedAt.difference(firstCapturedAt).inMilliseconds;
  if (elapsedMs <= 0) {
    throw AppError(
      AppErrorCodes.commandFailed,
      'Invalid xctrace sample window for "$matcherLabel" (elapsed ${elapsedMs}ms)',
    );
  }
  final priorByPid = <int, IosDeviceProcessSample>{
    for (final s in firstSamples) s.pid: s,
  };
  final processNames = <String>{
    for (final s in matchedSecond) s.processName,
  }.toList();
  // Per-pid CPU delta in ns. Skip pids we don't have a baseline for —
  // their `cpu-total` is lifetime, so without a prior reading the delta
  // is meaningless.
  double totalDeltaCpuNs = 0;
  bool anyCpuMatched = false;
  for (final s in matchedSecond) {
    final prior = priorByPid[s.pid];
    if (s.cpuTimeNs == null || prior?.cpuTimeNs == null) continue;
    final delta = s.cpuTimeNs! - prior!.cpuTimeNs!;
    if (delta > 0) totalDeltaCpuNs += delta;
    anyCpuMatched = true;
  }
  // CPU% over wall window. Multi-core processes can exceed 100% — same
  // semantics as `top` shows.
  final cpuPercent = anyCpuMatched
      ? (totalDeltaCpuNs / (elapsedMs * 1e6)) * 100
      : 0.0;
  int totalResidentBytes = 0;
  for (final s in matchedSecond) {
    if (s.residentMemoryBytes != null) {
      totalResidentBytes += s.residentMemoryBytes!;
    }
  }
  final measuredAt = secondCapturedAt.toIso8601String();
  return (
    cpu: AppleCpuPerfSample(
      usagePercent: roundPercent(cpuPercent),
      measuredAt: measuredAt,
      method: iosDeviceCpuSampleMethod,
      matchedProcesses: processNames,
    ),
    memory: AppleMemoryPerfSample(
      residentMemoryKb: (totalResidentBytes / 1024).round(),
      measuredAt: measuredAt,
      method: iosDeviceMemorySampleMethod,
      matchedProcesses: processNames,
    ),
  );
}
