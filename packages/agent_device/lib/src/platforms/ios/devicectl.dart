// Port of agent-device/src/platforms/ios/devicectl.ts (subset).
//
// Physical iOS devices are driven via `xcrun devicectl`. This module
// covers the shape we need: list physical devices, list apps on a
// physical device, launch/terminate processes, install/uninstall apps.
library;

import 'dart:convert';
import 'dart:io';

import 'package:agent_device/src/backend/device_info.dart';
import 'package:agent_device/src/backend/platform.dart';
import 'package:agent_device/src/utils/errors.dart';
import 'package:agent_device/src/utils/exec.dart';
import 'package:path/path.dart' as p;

/// One app record returned by `xcrun devicectl device info apps`.
class IosDeviceAppInfo {
  final String bundleId;
  final String name;
  final String? url;
  const IosDeviceAppInfo({
    required this.bundleId,
    required this.name,
    this.url,
  });
}

/// One process entry returned by `xcrun devicectl device info processes`.
/// [executable] is a `file://` URL; [pid] is the host-visible PID.
class IosDeviceProcessInfo {
  final String executable;
  final int pid;
  const IosDeviceProcessInfo({required this.executable, required this.pid});
}

/// Invoke `xcrun devicectl <args>` with the shared action/deviceId error
/// envelope. Throws [AppError] with [AppErrorCodes.commandFailed] on
/// non-zero exit.
Future<void> runIosDevicectl(
  List<String> args, {
  required String action,
  required String deviceId,
  int timeoutMs = 60000,
}) async {
  final fullArgs = ['devicectl', ...args];
  final r = await runCmd(
    'xcrun',
    fullArgs,
    ExecOptions(allowFailure: true, timeoutMs: timeoutMs),
  );
  if (r.exitCode == 0) return;
  throw AppError(
    AppErrorCodes.commandFailed,
    'Failed to $action.',
    details: {
      'cmd': 'xcrun',
      'args': fullArgs,
      'exitCode': r.exitCode,
      'stdout': r.stdout,
      'stderr': r.stderr,
      'deviceId': deviceId,
      'hint':
          _resolveDevicectlHint(r.stdout, r.stderr) ?? _devicectlDefaultHint,
    },
  );
}

/// List apps installed on a physical iOS device via
/// `xcrun devicectl device info apps --json-output`.
Future<List<IosDeviceAppInfo>> listIosDeviceApps(
  String udid, {
  bool userOnly = false,
}) async {
  final tmp = File(
    p.join(
      Directory.systemTemp.path,
      'agent-device-ios-apps-$pid-${DateTime.now().microsecondsSinceEpoch}.json',
    ),
  );
  final args = [
    'devicectl',
    'device',
    'info',
    'apps',
    '--device',
    udid,
    '--include-all-apps',
    '--json-output',
    tmp.path,
  ];
  try {
    final r = await runCmd(
      'xcrun',
      args,
      const ExecOptions(allowFailure: true, timeoutMs: 60000),
    );
    if (r.exitCode != 0) {
      throw AppError(
        AppErrorCodes.commandFailed,
        'Failed to list iOS apps.',
        details: {
          'cmd': 'xcrun',
          'args': args,
          'exitCode': r.exitCode,
          'stdout': r.stdout,
          'stderr': r.stderr,
          'deviceId': udid,
          'hint':
              _resolveDevicectlHint(r.stdout, r.stderr) ??
              _devicectlDefaultHint,
        },
      );
    }
    final text = await tmp.readAsString();
    final parsed = parseIosDeviceAppsPayload(jsonDecode(text));
    if (!userOnly) return parsed;
    return parsed.where((a) => !a.bundleId.startsWith('com.apple.')).toList();
  } finally {
    if (await tmp.exists()) {
      try {
        await tmp.delete();
      } catch (_) {}
    }
  }
}

/// List running processes on a physical iOS device via
/// `xcrun devicectl device info processes --json-output`.
Future<List<IosDeviceProcessInfo>> listIosDeviceProcesses(String udid) async {
  final tmp = File(
    p.join(
      Directory.systemTemp.path,
      'agent-device-ios-processes-$pid-${DateTime.now().microsecondsSinceEpoch}.json',
    ),
  );
  final args = [
    'devicectl',
    'device',
    'info',
    'processes',
    '--device',
    udid,
    '--json-output',
    tmp.path,
  ];
  try {
    final r = await runCmd(
      'xcrun',
      args,
      const ExecOptions(allowFailure: true, timeoutMs: 60000),
    );
    if (r.exitCode != 0) {
      throw AppError(
        AppErrorCodes.commandFailed,
        'Failed to list iOS processes.',
        details: {
          'cmd': 'xcrun',
          'args': args,
          'exitCode': r.exitCode,
          'stdout': r.stdout,
          'stderr': r.stderr,
          'deviceId': udid,
          'hint':
              _resolveDevicectlHint(r.stdout, r.stderr) ??
              _devicectlDefaultHint,
        },
      );
    }
    final text = await tmp.readAsString();
    return parseIosDeviceProcessesPayload(jsonDecode(text));
  } finally {
    if (await tmp.exists()) {
      try {
        await tmp.delete();
      } catch (_) {}
    }
  }
}

/// Parse the JSON payload from `xcrun devicectl device info processes`.
List<IosDeviceProcessInfo> parseIosDeviceProcessesPayload(Object? payload) {
  if (payload is! Map) return const [];
  final result = payload['result'];
  if (result is! Map) return const [];
  final processes = result['runningProcesses'];
  if (processes is! List) return const [];
  final out = <IosDeviceProcessInfo>[];
  for (final entry in processes) {
    if (entry is! Map) continue;
    final executable =
        entry['executable'] is String
            ? (entry['executable'] as String).trim()
            : '';
    final pidRaw = entry['processIdentifier'];
    final entryPid =
        pidRaw is int
            ? pidRaw
            : (pidRaw is double && pidRaw.isFinite ? pidRaw.toInt() : null);
    if (executable.isEmpty || entryPid == null) continue;
    out.add(IosDeviceProcessInfo(executable: executable, pid: entryPid));
  }
  return out;
}

/// Launch [bundleId] on a physical iOS device. `payloadUrl` forwards a
/// deep link.
Future<void> launchIosDeviceProcess(
  String udid,
  String bundleId, {
  String? payloadUrl,
}) async {
  final args = [
    'device',
    'process',
    'launch',
    '--device',
    udid,
    bundleId,
    ?payloadUrl,
  ];
  await runIosDevicectl(
    args,
    action: 'launch iOS app $bundleId',
    deviceId: udid,
  );
}

/// Terminate a running process for [bundleId] on a physical device.
Future<void> terminateIosDeviceProcess(String udid, String bundleId) async {
  await runIosDevicectl(
    ['device', 'process', 'terminate', '--device', udid, bundleId],
    action: 'terminate iOS app $bundleId',
    deviceId: udid,
  );
}

/// Install [installablePath] (a `.app` bundle directory — `.ipa`
/// archives must be unpacked first; see
/// `prepareIosInstallArtifact`) on a physical iOS device.
Future<void> installIosDeviceApp(String udid, String installablePath) async {
  await runIosDevicectl(
    ['device', 'install', 'app', '--device', udid, installablePath],
    action: 'install iOS app',
    deviceId: udid,
    timeoutMs: 180000,
  );
}

/// Uninstall [bundleId] from a physical iOS device. Returns true if
/// the app was actually uninstalled, false if the device reported it
/// wasn't installed in the first place (matches simctl's tolerant
/// shape so callers don't have to special-case missing apps).
Future<bool> uninstallIosDeviceApp(String udid, String bundleId) async {
  final args = [
    'devicectl',
    'device',
    'uninstall',
    'app',
    '--device',
    udid,
    bundleId,
  ];
  final r = await runCmd(
    'xcrun',
    args,
    const ExecOptions(allowFailure: true, timeoutMs: 60000),
  );
  if (r.exitCode == 0) return true;
  final combined = '${r.stdout}\n${r.stderr}'.toLowerCase();
  if (_isMissingAppErrorOutput(combined)) return false;
  throw AppError(
    AppErrorCodes.commandFailed,
    'Failed to uninstall iOS app $bundleId.',
    details: {
      'cmd': 'xcrun',
      'args': args,
      'exitCode': r.exitCode,
      'stdout': r.stdout,
      'stderr': r.stderr,
      'deviceId': udid,
      'hint':
          _resolveDevicectlHint(r.stdout, r.stderr) ?? _devicectlDefaultHint,
    },
  );
}

/// True for the messages devicectl/simctl emit when an app isn't
/// installed — lets uninstall callers treat "not installed" as a
/// no-op success.
bool _isMissingAppErrorOutput(String lowercased) {
  return lowercased.contains('not installed') ||
      lowercased.contains('could not be found') ||
      lowercased.contains('no such application') ||
      lowercased.contains('the application is missing') ||
      lowercased.contains('matching application not found');
}

/// Enumerate physical iOS/tvOS devices visible to `devicectl`. Returns an
/// empty list on any failure so callers (device enumeration) can fall
/// back to simulators without surfacing errors.
Future<List<BackendDeviceInfo>> listApplePhysicalDevicesViaDevicectl() async {
  final tmp = File(
    p.join(
      Directory.systemTemp.path,
      'agent-device-devicectl-$pid-${DateTime.now().microsecondsSinceEpoch}.json',
    ),
  );
  try {
    final r = await runCmd('xcrun', [
      'devicectl',
      'list',
      'devices',
      '--json-output',
      tmp.path,
    ], const ExecOptions(allowFailure: true, timeoutMs: 8000));
    if (r.exitCode != 0) return const [];
    if (!await tmp.exists()) return const [];
    final raw = await tmp.readAsString();
    final payload = jsonDecode(raw);
    return _mapDevicectlAppleDevices(payload);
  } on FormatException {
    return const [];
  } on AppError {
    return const [];
  } finally {
    if (await tmp.exists()) {
      try {
        await tmp.delete();
      } catch (_) {}
    }
  }
}

List<IosDeviceAppInfo> parseIosDeviceAppsPayload(Object? payload) {
  if (payload is! Map) return const [];
  final result = payload['result'];
  if (result is! Map) return const [];
  final apps = result['apps'];
  if (apps is! List) return const [];
  final out = <IosDeviceAppInfo>[];
  for (final entry in apps) {
    if (entry is! Map) continue;
    final bundleId = entry['bundleIdentifier'] is String
        ? (entry['bundleIdentifier'] as String).trim()
        : '';
    if (bundleId.isEmpty) continue;
    final name =
        entry['name'] is String && (entry['name'] as String).trim().isNotEmpty
        ? (entry['name'] as String).trim()
        : bundleId;
    final url =
        entry['url'] is String && (entry['url'] as String).trim().isNotEmpty
        ? (entry['url'] as String).trim()
        : null;
    out.add(IosDeviceAppInfo(bundleId: bundleId, name: name, url: url));
  }
  return out;
}

List<BackendDeviceInfo> _mapDevicectlAppleDevices(Object? payload) {
  if (payload is! Map) return const [];
  final result = payload['result'];
  if (result is! Map) return const [];
  final devices = result['devices'];
  if (devices is! List) return const [];
  final out = <BackendDeviceInfo>[];
  for (final d in devices) {
    if (d is! Map) continue;
    final hw = d['hardwareProperties'];
    final dp = d['deviceProperties'];
    final platform = hw is Map ? _str(hw['platform']) : '';
    if (!_isSupportedApplePlatform(platform)) continue;
    final id = hw is Map ? _str(hw['udid']) : '';
    final fallbackId = d['identifier'] is String
        ? (d['identifier'] as String).trim()
        : '';
    final finalId = id.isNotEmpty ? id : fallbackId;
    if (finalId.isEmpty) continue;
    final name = d['name'] is String && (d['name'] as String).trim().isNotEmpty
        ? (d['name'] as String).trim()
        : (dp is Map && dp['name'] is String
              ? (dp['name'] as String).trim()
              : finalId);
    final productType = hw is Map ? _str(hw['productType']) : '';
    final target =
        _tvPattern.hasMatch(platform) || _tvPattern.hasMatch(productType)
        ? 'tv'
        : 'mobile';
    out.add(
      BackendDeviceInfo(
        id: finalId,
        name: name,
        platform: AgentDeviceBackendPlatform.ios,
        target: target,
        kind: 'device',
        booted: true,
        details: {'platform': platform, 'productType': productType},
      ),
    );
  }
  return out;
}

String _str(Object? v) => v is String ? v.trim() : '';

bool _isSupportedApplePlatform(String platform) {
  final n = platform.toLowerCase();
  return n.contains('ios') || n.contains('tvos');
}

final RegExp _tvPattern = RegExp(r'tvos|appletv', caseSensitive: false);

const String _devicectlDefaultHint =
    'Ensure the iOS device is unlocked, trusted, and available in Xcode > '
    'Devices, then retry.';

String? _resolveDevicectlHint(String stdout, String stderr) {
  final text = '$stdout\n$stderr'.toLowerCase();
  if (text.contains('device is busy') && text.contains('connecting')) {
    return 'iOS device is still connecting. Keep it unlocked and connected by '
        'cable until it is fully available in Xcode Devices, then retry.';
  }
  if (text.contains('coredeviceservice') && text.contains('timed out')) {
    return 'CoreDevice service timed out. Reconnect the device and retry; if '
        'it persists restart Xcode and the iOS device.';
  }
  return null;
}
