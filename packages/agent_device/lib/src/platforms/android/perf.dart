// Port of agent-device/src/platforms/android/perf.ts

import '../../utils/errors.dart';
import '../../utils/exec.dart';
import '../perf_utils.dart';
import 'adb.dart';

const String androidCpuSampleMethod = 'adb-shell-dumpsys-cpuinfo';
const String androidCpuSampleDescription =
    'Aggregated CPU usage for app processes matched from adb shell dumpsys cpuinfo.';
const String androidMemorySampleMethod = 'adb-shell-dumpsys-meminfo';
const String androidMemorySampleDescription =
    'Memory snapshot from adb shell dumpsys meminfo <package>. Values are reported in kilobytes.';

const int _androidPerfTimeoutMs = 15000;

/// CPU performance sample from adb dumpsys cpuinfo.
class AndroidCpuPerfSample {
  final double usagePercent;
  final String measuredAt;
  final String method;
  final List<String> matchedProcesses;

  const AndroidCpuPerfSample({
    required this.usagePercent,
    required this.measuredAt,
    required this.method,
    required this.matchedProcesses,
  });
}

/// Memory performance sample from adb dumpsys meminfo.
class AndroidMemoryPerfSample {
  final int totalPssKb;
  final int? totalRssKb;
  final String measuredAt;
  final String method;

  const AndroidMemoryPerfSample({
    required this.totalPssKb,
    this.totalRssKb,
    required this.measuredAt,
    required this.method,
  });
}

/// Samples CPU performance for [packageName] on device with [serial].
Future<AndroidCpuPerfSample> sampleAndroidCpuPerf(
  String serial,
  String packageName,
) async {
  try {
    final result = await runCmd(
      'adb',
      adbArgs(serial, ['shell', 'dumpsys', 'cpuinfo']),
      const ExecOptions(timeoutMs: _androidPerfTimeoutMs),
    );
    return parseAndroidCpuInfoSample(
      result.stdout,
      packageName,
      DateTime.now().toIso8601String(),
    );
  } catch (error) {
    throw _annotateAndroidPerfSamplingError('cpu', packageName, error);
  }
}

/// Samples memory performance for [packageName] on device with [serial].
Future<AndroidMemoryPerfSample> sampleAndroidMemoryPerf(
  String serial,
  String packageName,
) async {
  try {
    final result = await runCmd(
      'adb',
      adbArgs(serial, ['shell', 'dumpsys', 'meminfo', packageName]),
      const ExecOptions(timeoutMs: _androidPerfTimeoutMs),
    );
    return parseAndroidMemInfoSample(
      result.stdout,
      packageName,
      DateTime.now().toIso8601String(),
    );
  } catch (error) {
    throw _annotateAndroidPerfSamplingError('memory', packageName, error);
  }
}

/// Parses CPU info from `adb shell dumpsys cpuinfo` output.
AndroidCpuPerfSample parseAndroidCpuInfoSample(
  String stdout,
  String packageName,
  String measuredAt,
) {
  final matchedProcesses = <String>{};
  double usagePercent = 0;

  for (final rawLine in stdout.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;

    final match = RegExp(
      r'^([0-9]+(?:\.[0-9]+)?)%\s+\d+\/([^\s]+):\s',
    ).firstMatch(line);
    if (match == null) continue;

    final percent = double.tryParse(match.group(1) ?? '');
    final processName = match.group(2);

    if (percent == null ||
        !percent.isFinite ||
        processName == null ||
        !_matchesAndroidPackageProcess(processName, packageName)) {
      continue;
    }

    usagePercent += percent;
    matchedProcesses.add(processName);
  }

  return AndroidCpuPerfSample(
    usagePercent: roundPercent(usagePercent),
    measuredAt: measuredAt,
    method: androidCpuSampleMethod,
    matchedProcesses: matchedProcesses.toList(),
  );
}

/// Parses memory info from `adb shell dumpsys meminfo <package>` output.
AndroidMemoryPerfSample parseAndroidMemInfoSample(
  String stdout,
  String packageName,
  String measuredAt,
) {
  if (RegExp(r'no process found for:', caseSensitive: false).hasMatch(stdout)) {
    throw AppError(
      AppErrorCodes.commandFailed,
      'Android meminfo did not find a running process for $packageName',
      details: {
        'metric': 'memory',
        'package': packageName,
        'hint':
            'Run open <app> for this session again to ensure the Android app is '
            'active, then retry perf.',
      },
    );
  }

  final totalPssKb =
      _matchLabeledNumber(stdout, 'TOTAL PSS') ?? _matchTotalRowPss(stdout);
  if (totalPssKb == null) {
    throw AppError(
      AppErrorCodes.commandFailed,
      'Failed to parse Android meminfo output for $packageName',
      details: {
        'metric': 'memory',
        'package': packageName,
        'hint':
            'Retry perf after reopening the app session. If the problem persists, '
            'capture adb shell dumpsys meminfo output for debugging.',
      },
    );
  }

  return AndroidMemoryPerfSample(
    totalPssKb: totalPssKb,
    totalRssKb: _matchLabeledNumber(stdout, 'TOTAL RSS'),
    measuredAt: measuredAt,
    method: androidMemorySampleMethod,
  );
}

AppError _annotateAndroidPerfSamplingError(
  String metric,
  String packageName,
  Object? error,
) {
  if (error is AppError &&
      (error.code == AppErrorCodes.toolMissing ||
          error.code == AppErrorCodes.commandFailed)) {
    return AppError(
      error.code,
      error.message,
      details: <String, Object?>{
        ...(error.details ?? {}),
        'metric': metric,
        'package': packageName,
      },
      cause: error,
    );
  }

  if (error is AppError) {
    return error;
  }

  return AppError(
    AppErrorCodes.commandFailed,
    'Failed to sample Android $metric for $packageName',
    details: {'metric': metric, 'package': packageName},
    cause: error,
  );
}

bool _matchesAndroidPackageProcess(String processName, String packageName) {
  return processName == packageName || processName.startsWith('$packageName:');
}

int? _matchLabeledNumber(String text, String label) {
  final escapedLabel = RegExp.escape(label);
  final match = RegExp(
    '$escapedLabel:\\s*([0-9][0-9,]*)',
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) return null;
  return _parseNumericToken(match.group(1));
}

int? _matchTotalRowPss(String text) {
  for (final rawLine in text.split('\n')) {
    final line = rawLine.trim();
    if (!RegExp(r'^TOTAL\b(?!\s+PSS:)').hasMatch(line)) continue;
    final firstValue = line
        .split(RegExp(r'\s+'))
        .skip(1)
        .firstWhere(
          (token) => _parseNumericToken(token) != null,
          orElse: () => '',
        );
    if (firstValue.isEmpty) return null;
    return _parseNumericToken(firstValue);
  }
  return null;
}

int? _parseNumericToken(String? token) {
  if (token == null) return null;
  final cleaned = token.replaceAll(',', '');
  final match = RegExp(r'^-?\d+(?:\.\d+)?').firstMatch(cleaned);
  if (match == null) return null;
  final value = double.tryParse(match.group(0) ?? '');
  if (value == null || !value.isFinite) return null;
  return value.toInt();
}
