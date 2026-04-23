/// Port of agent-device/src/platforms/android/devices.ts.
///
/// Android device/emulator enumeration, status probing, and boot management.
/// Interfaces with adb to discover connected devices and emulators, resolve
/// their names and boot states, and coordinate emulator boot-up.
/// TODO(port): device-isolation.ts, boot-diagnostics.ts not yet ported (Wave C).
library;

import 'dart:async';

import '../../backend/device_info.dart';
import '../../backend/platform.dart';
import '../../utils/errors.dart';
import '../../utils/exec.dart';
import 'adb.dart';
import 'sdk.dart';

const String _emulatorSerialPrefix = 'emulator-';
const int _androidBootPollMs = 1000;
const int _androidEmulatorBootPollMs = 1000;
const int _androidEmulatorBootTimeoutMs = 120_000;
const int _androidEmulatorAvdNameTimeoutMs = 10_000;

const List<String> _androidTvFeatures = [
  'android.software.leanback',
  'android.software.leanback_only',
  'android.hardware.type.television',
];

/// Result of running an adb command.
class _ExecResult {
  final String stdout;
  final String stderr;
  final int exitCode;

  _ExecResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });
}

/// Combine stdout and stderr for error messages.
String _commandOutput(_ExecResult result) {
  return '${result.stdout}\n${result.stderr}';
}

/// Check if a device serial identifies an emulator.
bool _isEmulatorSerial(String serial) {
  return serial.startsWith(_emulatorSerialPrefix);
}

/// Normalize an Android device name for comparison.
String _normalizeAndroidName(String value) {
  return value
      .toLowerCase()
      .replaceAll('_', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Parse emulator AVD name from shell output.
String? parseAndroidEmulatorAvdNameOutput(String rawOutput) {
  var lines = rawOutput
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  if (lines.isEmpty) return null;
  if (lines.last == 'OK') {
    lines = lines.sublist(0, lines.length - 1);
  }

  return lines.join('\n').trim().isEmpty ? null : lines.join('\n').trim();
}

/// Read boot_completed property from device.
Future<_ExecResult> _readAndroidBootProp(
  String serial, [
  int timeoutMs = 30_000, // Default timeout
]) async {
  final result = await runCmd(
    'adb',
    adbArgs(serial, ['shell', 'getprop', 'sys.boot_completed']),
    ExecOptions(allowFailure: true, timeoutMs: timeoutMs),
  );

  return _ExecResult(
    stdout: result.stdout,
    stderr: result.stderr,
    exitCode: result.exitCode,
  );
}

/// Resolve device name from model and serial.
Future<String> _resolveAndroidDeviceName(String serial, String rawModel) async {
  final modelName = rawModel.replaceAll('_', ' ').trim();
  if (!_isEmulatorSerial(serial)) return modelName.isEmpty ? serial : modelName;

  final avdName = await resolveAndroidEmulatorAvdName(serial);
  if (avdName != null) return avdName.replaceAll('_', ' ');

  return modelName.isEmpty ? serial : modelName;
}

/// Best-effort probe for emulator AVD name (tolerates timeouts).
Future<_ExecResult?> _runBestEffortAndroidEmulatorNameProbe(
  String serial,
  List<String> args,
) async {
  try {
    final result = await runCmd(
      'adb',
      adbArgs(serial, args),
      const ExecOptions(
        allowFailure: true,
        timeoutMs: _androidEmulatorAvdNameTimeoutMs,
      ),
    );

    return _ExecResult(
      stdout: result.stdout,
      stderr: result.stderr,
      exitCode: result.exitCode,
    );
  } catch (error) {
    // Friendly-name lookup is optional; only timeout is acceptable.
    // TODO(port): Implement proper timeout detection.
    return null;
  }
}

/// Resolve AVD name for an emulator serial.
Future<String?> resolveAndroidEmulatorAvdName(
  String serial, [
  Future<RunCmdResult> Function(String, List<String>, ExecOptions)?
  runAdbOverride,
]) async {
  final avdPropKeys = ['ro.boot.qemu.avd_name', 'persist.sys.avd_name'];

  for (final prop in avdPropKeys) {
    final result = await _runBestEffortAndroidEmulatorNameProbe(serial, [
      'shell',
      'getprop',
      prop,
    ]);

    if (result == null) continue;
    final value = result.stdout.trim();

    if (result.exitCode == 0 && value.isNotEmpty) {
      return value;
    }
  }

  final emuResult = await _runBestEffortAndroidEmulatorNameProbe(serial, [
    'emu',
    'avd',
    'name',
  ]);

  if (emuResult == null) return null;

  final emuValue = parseAndroidEmulatorAvdNameOutput(emuResult.stdout);
  if (emuResult.exitCode == 0 && emuValue != null) {
    return emuValue;
  }

  return null;
}

/// Classify device target from characteristics output.
String? parseAndroidTargetFromCharacteristics(String rawOutput) {
  final normalized = rawOutput.toLowerCase();
  if (normalized.contains('tv') || normalized.contains('leanback')) {
    return 'tv';
  }
  return null;
}

/// Check if feature list output indicates TV device.
bool parseAndroidFeatureListForTv(String rawOutput) {
  return RegExp(
    r'feature:android\.(software\.leanback(_only)?|hardware\.type\.television)\b',
    caseSensitive: false,
  ).hasMatch(rawOutput);
}

/// Probe device for specific feature.
Future<bool?> _probeAndroidFeature(String serial, String feature) async {
  final result = await runCmd(
    'adb',
    adbArgs(serial, ['shell', 'cmd', 'package', 'has-feature', feature]),
    const ExecOptions(
      allowFailure: true,
      timeoutMs: 30_000, // Default timeout
    ),
  );

  final output = _commandOutput(
    _ExecResult(
      stdout: result.stdout,
      stderr: result.stderr,
      exitCode: result.exitCode,
    ),
  ).toLowerCase();

  if (output.contains('true')) return true;
  if (output.contains('false')) return false;
  return null;
}

/// Check if device has any TV features.
Future<bool> _hasAnyAndroidTvFeature(String serial) async {
  final checks = await Future.wait(
    _androidTvFeatures.map((feature) => _probeAndroidFeature(serial, feature)),
  );

  return checks.any((value) => value == true);
}

/// Determine device target: mobile or TV.
Future<String> _resolveAndroidTarget(String serial) async {
  final characteristicsResult = await runCmd(
    'adb',
    adbArgs(serial, ['shell', 'getprop', 'ro.build.characteristics']),
    const ExecOptions(allowFailure: true, timeoutMs: 30_000),
  );

  final characteristicsTarget = parseAndroidTargetFromCharacteristics(
    _commandOutput(
      _ExecResult(
        stdout: characteristicsResult.stdout,
        stderr: characteristicsResult.stderr,
        exitCode: characteristicsResult.exitCode,
      ),
    ),
  );

  if (characteristicsTarget == 'tv') {
    return 'tv';
  }

  if (await _hasAnyAndroidTvFeature(serial)) {
    return 'tv';
  }

  final featureListResult = await runCmd(
    'adb',
    adbArgs(serial, ['shell', 'pm', 'list', 'features']),
    const ExecOptions(allowFailure: true, timeoutMs: 30_000),
  );

  if (parseAndroidFeatureListForTv(
    _commandOutput(
      _ExecResult(
        stdout: featureListResult.stdout,
        stderr: featureListResult.stderr,
        exitCode: featureListResult.exitCode,
      ),
    ),
  )) {
    return 'tv';
  }

  return 'mobile';
}

/// Device entry from adb devices -l output.
class _AndroidDeviceEntry {
  final String serial;
  final String rawModel;

  _AndroidDeviceEntry({required this.serial, required this.rawModel});
}

/// Parse device list from adb devices -l output.
List<_AndroidDeviceEntry> _parseAndroidDeviceEntries(String rawOutput) {
  final lines = rawOutput.split('\n').map((line) => line.trim()).toList();

  return lines
      .where((line) => line.isNotEmpty && !line.startsWith('List of devices'))
      .map((line) => line.split(RegExp(r'\s+')))
      .where((parts) => parts.length > 1 && parts[1] == 'device')
      .map((parts) {
        final modelEntry = parts.firstWhere(
          (entry) => entry.startsWith('model:'),
          orElse: () => '',
        );

        return _AndroidDeviceEntry(
          serial: parts[0],
          rawModel: modelEntry.replaceAll('model:', ''),
        );
      })
      .toList();
}

/// List device entries via adb devices -l.
Future<List<_AndroidDeviceEntry>> _listAndroidDeviceEntries() async {
  final result = await runCmd('adb', [
    'devices',
    '-l',
  ], const ExecOptions(timeoutMs: 30_000));

  return _parseAndroidDeviceEntries(result.stdout);
}

/// List connected Android devices and emulators.
Future<List<BackendDeviceInfo>> listAndroidDevices() async {
  await ensureAndroidSdkPathConfigured();
  final adbAvailable = await whichCmd('adb');

  if (!adbAvailable) {
    throw AppError(AppErrorCodes.toolMissing, 'adb not found in PATH');
  }

  final entries = await _listAndroidDeviceEntries();

  final devices = await Future.wait(
    entries.map((entry) async {
      final [name, target] = await Future.wait([
        _resolveAndroidDeviceName(entry.serial, entry.rawModel),
        _resolveAndroidTarget(entry.serial),
      ]);

      final booted = await _isAndroidBooted(entry.serial);

      return BackendDeviceInfo(
        id: entry.serial,
        name: name,
        platform: AgentDeviceBackendPlatform.android,
        target: target,
        kind: _isEmulatorSerial(entry.serial) ? 'emulator' : 'device',
        booted: booted,
      );
    }),
  );

  return devices;
}

/// Parse AVD names from emulator -list-avds output.
List<String> parseAndroidAvdList(String rawOutput) {
  return rawOutput
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
}

/// Resolve an AVD name from a list (case-insensitive, normalized).
String? resolveAndroidAvdName(List<String> avdNames, String requestedName) {
  final direct = avdNames.firstWhere(
    (name) => name == requestedName,
    orElse: () => '',
  );

  if (direct.isNotEmpty) return direct;

  final target = _normalizeAndroidName(requestedName);
  return avdNames
          .firstWhere(
            (name) => _normalizeAndroidName(name) == target,
            orElse: () => '',
          )
          .isEmpty
      ? null
      : avdNames.firstWhere((name) => _normalizeAndroidName(name) == target);
}

/// List available AVD names via emulator -list-avds.
Future<List<String>> _listAndroidAvdNames() async {
  final result = await runCmd('emulator', [
    '-list-avds',
  ], const ExecOptions(allowFailure: true, timeoutMs: 30_000));

  if (result.exitCode != 0) {
    throw AppError(
      AppErrorCodes.commandFailed,
      'Failed to list Android emulator AVDs',
      details: {
        'stdout': result.stdout,
        'stderr': result.stderr,
        'exitCode': result.exitCode,
      },
    );
  }

  return parseAndroidAvdList(result.stdout);
}

/// Find emulator by AVD name in device list.
BackendDeviceInfo? _findAndroidEmulatorByAvdName(
  List<BackendDeviceInfo> devices,
  String avdName,
  String? serial,
) {
  final target = _normalizeAndroidName(avdName);
  return devices
          .firstWhere(
            (device) {
              if (device.platform != AgentDeviceBackendPlatform.android ||
                  device.kind != 'emulator') {
                return false;
              }
              if (serial != null && device.id != serial) return false;
              return _normalizeAndroidName(device.name) == target;
            },
            orElse: () => const BackendDeviceInfo(
              id: '',
              name: '',
              platform: AgentDeviceBackendPlatform.android,
            ),
          )
          .id
          .isEmpty
      ? null
      : devices.firstWhere((device) {
          if (device.platform != AgentDeviceBackendPlatform.android ||
              device.kind != 'emulator') {
            return false;
          }
          if (serial != null && device.id != serial) return false;
          return _normalizeAndroidName(device.name) == target;
        });
}

/// Check if device is booted (sys.boot_completed == 1).
Future<bool> _isAndroidBooted(String serial) async {
  try {
    final result = await _readAndroidBootProp(serial);
    return result.stdout.trim() == '1';
  } catch (_) {
    return false;
  }
}

/// Find emulator serial by AVD name.
Future<String?> _findAndroidEmulatorSerialByAvdName(
  String avdName,
  String? serial,
) async {
  final target = _normalizeAndroidName(avdName);
  final entries = await _listAndroidDeviceEntries();

  final candidates = entries.where((entry) {
    if (serial != null && entry.serial != serial) return false;
    return _isEmulatorSerial(entry.serial);
  }).toList();

  for (final entry in candidates) {
    if (_normalizeAndroidName(entry.rawModel) == target) {
      return entry.serial;
    }

    final resolvedName = await _resolveAndroidDeviceName(
      entry.serial,
      entry.rawModel,
    );
    if (_normalizeAndroidName(resolvedName) == target) {
      return entry.serial;
    }
  }

  return null;
}

/// Wait for emulator to appear by AVD name (within timeout).
Future<BackendDeviceInfo> _waitForAndroidEmulatorByAvdName({
  required String avdName,
  String? serial,
  required int timeoutMs,
}) async {
  final startedAt = DateTime.now();

  while (DateTime.now().difference(startedAt).inMilliseconds < timeoutMs) {
    try {
      final foundSerial = await _findAndroidEmulatorSerialByAvdName(
        avdName,
        serial,
      );
      if (foundSerial != null) {
        return BackendDeviceInfo(
          id: foundSerial,
          name: avdName,
          platform: AgentDeviceBackendPlatform.android,
          kind: 'emulator',
          target: 'mobile',
          booted: false,
        );
      }
    } catch (_) {
      // Best-effort polling while adb/emulator process settles.
    }

    await Future<void>.delayed(
      const Duration(milliseconds: _androidEmulatorBootPollMs),
    );
  }

  throw AppError(
    AppErrorCodes.commandFailed,
    'Android emulator did not appear in time',
    details: {'avdName': avdName, 'serial': serial, 'timeoutMs': timeoutMs},
  );
}

/// Ensure an Android emulator is booted (boot if needed).
Future<BackendDeviceInfo> ensureAndroidEmulatorBooted({
  required String avdName,
  String? serial,
  int? timeoutMs,
  bool? headless,
}) async {
  await ensureAndroidSdkPathConfigured();

  final requestedAvdName = avdName.trim();
  if (requestedAvdName.isEmpty) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'Android emulator boot requires a non-empty AVD name.',
    );
  }

  final bootTimeoutMs = timeoutMs ?? _androidEmulatorBootTimeoutMs;

  if (!await whichCmd('adb')) {
    throw AppError(AppErrorCodes.toolMissing, 'adb not found in PATH');
  }

  if (!await whichCmd('emulator')) {
    throw AppError(AppErrorCodes.toolMissing, 'emulator not found in PATH');
  }

  final avdNames = await _listAndroidAvdNames();
  final resolvedAvdName = resolveAndroidAvdName(avdNames, requestedAvdName);

  if (resolvedAvdName == null) {
    throw AppError(
      AppErrorCodes.deviceNotFound,
      'No Android emulator AVD named $avdName',
      details: {
        'requestedAvdName': requestedAvdName,
        'availableAvds': avdNames,
      },
    );
  }

  final startedAt = DateTime.now();
  final existingDevices = await listAndroidDevices();
  final existing = _findAndroidEmulatorByAvdName(
    existingDevices,
    resolvedAvdName,
    serial,
  );

  if (existing == null) {
    final launchArgs = ['-avd', resolvedAvdName];
    if (headless ?? false) {
      launchArgs.addAll(['-no-window', '-no-audio']);
    }

    await runCmdDetached('emulator', launchArgs);
  }

  final discovered =
      existing ??
      await _waitForAndroidEmulatorByAvdName(
        avdName: resolvedAvdName,
        serial: serial,
        timeoutMs: bootTimeoutMs,
      );

  final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
  final remainingMs = (bootTimeoutMs - elapsedMs).clamp(1_000, bootTimeoutMs);

  await waitForAndroidBoot(discovered.id, remainingMs);

  final refreshedDevices = await listAndroidDevices();
  final refreshed = refreshedDevices.firstWhere(
    (d) => d.id == discovered.id,
    orElse: () {
      return const BackendDeviceInfo(
        id: '',
        name: '',
        platform: AgentDeviceBackendPlatform.android,
      );
    },
  );

  if (refreshed.id.isNotEmpty) {
    return BackendDeviceInfo(
      id: refreshed.id,
      name: resolvedAvdName,
      platform: refreshed.platform,
      target: refreshed.target,
      kind: refreshed.kind,
      booted: true,
      details: refreshed.details,
    );
  }

  return BackendDeviceInfo(
    id: discovered.id,
    name: resolvedAvdName,
    platform: discovered.platform,
    target: discovered.target,
    kind: discovered.kind,
    booted: true,
    details: discovered.details,
  );
}

/// Wait for an Android device to finish booting.
///
/// Polls sys.boot_completed property with retries until device reports 1
/// or timeout expires. Throws [AppError] if boot fails.
Future<void> waitForAndroidBoot(String serial, [int timeoutMs = 60_000]) async {
  // TODO(port): boot-diagnostics.ts not yet ported (Wave C).
  // For now, use simple retry logic.

  final startedAt = DateTime.now();

  while (DateTime.now().difference(startedAt).inMilliseconds < timeoutMs) {
    try {
      final result = await _readAndroidBootProp(serial, 10_000);

      if (result.stdout.trim() == '1') {
        return;
      }
    } catch (_) {
      // Continue polling.
    }

    await Future<void>.delayed(
      const Duration(milliseconds: _androidBootPollMs),
    );
  }

  throw AppError(
    AppErrorCodes.commandFailed,
    'Android device did not finish booting in time',
    details: {'serial': serial, 'timeoutMs': timeoutMs},
  );
}
