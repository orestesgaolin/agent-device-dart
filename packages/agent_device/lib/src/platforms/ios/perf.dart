// Port of agent-device/src/platforms/ios/perf.ts — simulator slice.
//
// Samples CPU% and resident memory for a specific bundle id on a booted
// iOS simulator. Resolves the app's `CFBundleExecutable` out of its
// Info.plist (via `plutil -extract`), then spawns `ps -axo pid,%cpu,rss,
// command` inside the sim and filters rows by executable basename.
//
// Physical-device sampling (xctrace activity-monitor-process-live +
// .trace XML parsing) is deferred — the TS port is ~500 LOC of XML
// heuristics and needs a trace-export orchestration step.
library;

import 'package:agent_device/src/utils/errors.dart';
import 'package:agent_device/src/utils/exec.dart';
import 'package:path/path.dart' as p;

import '../perf_utils.dart';
import 'simctl.dart';

const String appleCpuSampleMethod = 'ps-process-snapshot';
const String appleMemorySampleMethod = 'ps-process-snapshot';

const int _applePerfTimeoutMs = 15000;

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
