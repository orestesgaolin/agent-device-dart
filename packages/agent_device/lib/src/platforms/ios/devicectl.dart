// Port of agent-device/src/platforms/ios/devicectl.ts (subset).
//
// Physical iOS devices are driven via `xcrun devicectl`. This module
// covers the shape we need for the Phase 8C polish: list physical
// devices, list apps on a physical device, launch/terminate processes.
// App install/uninstall/reinstall of .ipa files is deferred — that chain
// depends on the install-artifact port which is a larger piece of work.
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
