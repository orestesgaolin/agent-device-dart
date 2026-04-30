// Port of agent-device/src/platforms/android/perf-frame.ts

import '../../utils/errors.dart';
import '../../utils/exec.dart';
import 'adb.dart';
import 'perf_frame_parser.dart';

export 'perf_frame_parser.dart'
    show
        androidFrameSampleDescription,
        androidFrameSampleMethod,
        parseAndroidFramePerfSample,
        AndroidFrameDropWindow,
        AndroidFramePerfSample;

const int _androidFramePerfTimeoutMs = 15000;
const int _androidFrameResetTimeoutMs = 3000;

/// Samples Android frame health metrics for [packageName] on device [serial].
///
/// Runs `adb shell dumpsys gfxinfo <package> framestats`, parses the output,
/// resets stats on the device, then returns the analysis result.
Future<AndroidFramePerfSample> sampleAndroidFramePerf(
  String serial,
  String packageName,
) async {
  try {
    final result = await runCmd(
      'adb',
      adbArgs(serial, ['shell', 'dumpsys', 'gfxinfo', packageName, 'framestats']),
      const ExecOptions(timeoutMs: _androidFramePerfTimeoutMs),
    );
    final sample = parseAndroidFramePerfSample(
      result.stdout,
      packageName,
      DateTime.now().toUtc().toIso8601String(),
    );
    await resetAndroidFramePerfStats(serial, packageName);
    return sample;
  } catch (error) {
    throw _annotateAndroidFramePerfSamplingError(packageName, error);
  }
}

/// Resets Android gfxinfo frame stats for [packageName] on device [serial].
///
/// This is best-effort; failures are silently swallowed so that sampling and
/// open operations still succeed when adb times out or disappears.
Future<void> resetAndroidFramePerfStats(
  String serial,
  String packageName,
) async {
  try {
    await runCmd(
      'adb',
      adbArgs(serial, ['shell', 'dumpsys', 'gfxinfo', packageName, 'reset']),
      const ExecOptions(
        allowFailure: true,
        timeoutMs: _androidFrameResetTimeoutMs,
      ),
    );
  } catch (_) {
    // Reset is best-effort; sampling/open should still succeed if adb times
    // out or disappears.
  }
}

AppError _annotateAndroidFramePerfSamplingError(
  String packageName,
  Object? error,
) {
  if (error is AppError) {
    return AppError(
      error.code,
      error.message,
      details: <String, Object?>{
        ...(error.details ?? {}),
        'metric': 'fps',
        'package': packageName,
      },
      cause: error,
    );
  }

  return AppError(
    AppErrorCodes.commandFailed,
    'Failed to sample Android fps for $packageName',
    details: {'metric': 'fps', 'package': packageName},
    cause: error,
  );
}
