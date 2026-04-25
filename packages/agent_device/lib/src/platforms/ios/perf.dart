// Port of agent-device/src/platforms/ios/perf.ts.
//
// Simulator sampling uses `simctl spawn /bin/ps`. Physical-device
// sampling records a 1-second `xctrace` activity-monitor trace, exports
// the `activity-monitor-process-live` table as XML, and extracts the
// target app's row.
library;

import 'dart:io';

import 'package:agent_device/src/utils/errors.dart';
import 'package:agent_device/src/utils/exec.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../perf_utils.dart';
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
  try {
    final record = await runCmd(
      'xcrun',
      [
        'xctrace',
        'record',
        '--device',
        udid,
        '--template',
        'Activity Monitor',
        '--time-limit',
        _iosDevicePerfTraceDuration,
        '--all-processes',
        '--output',
        tracePath,
      ],
      const ExecOptions(
        allowFailure: true,
        timeoutMs: _iosDevicePerfRecordTimeoutMs,
      ),
    );
    if (record.exitCode != 0) {
      throw AppError(
        AppErrorCodes.commandFailed,
        'xctrace record failed (exit ${record.exitCode}).',
        details: {
          'stdout': record.stdout,
          'stderr': record.stderr,
          'hint':
              'Ensure the device is unlocked + trusted and Xcode has been '
              'opened at least once to warm up CoreDevice.',
        },
      );
    }
    final export = await runCmd(
      'xcrun',
      [
        'xctrace',
        'export',
        '--input',
        tracePath,
        '--xpath',
        '/trace-toc/run[1]/data/table[@schema="activity-monitor-process-live"]',
      ],
      const ExecOptions(
        allowFailure: true,
        timeoutMs: _iosDevicePerfExportTimeoutMs,
      ),
    );
    if (export.exitCode != 0) {
      throw AppError(
        AppErrorCodes.commandFailed,
        'xctrace export failed (exit ${export.exitCode}).',
        details: {'stderr': export.stderr},
      );
    }
    return parseIosDevicePerfXml(export.stdout);
  } finally {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
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
  final elapsedMs = secondCapturedAt
      .difference(firstCapturedAt)
      .inMilliseconds;
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
