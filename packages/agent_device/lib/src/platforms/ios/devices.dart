// Port of agent-device/src/platforms/ios/devices.ts.
//
// Enumerates iOS devices — simulators via `simctl list devices -j` plus
// physical iOS/tvOS devices via `xcrun devicectl list devices`. Physical
// device failures are swallowed so the list still returns simulators
// even when no device is connected.
library;

import 'dart:convert';

import 'package:agent_device/src/backend/device_info.dart';
import 'package:agent_device/src/backend/platform.dart';
import 'package:agent_device/src/utils/errors.dart';
import 'package:agent_device/src/utils/exec.dart';

import 'devicectl.dart';
import 'simctl.dart';

/// Enumerate iOS (/tvOS) simulators via `xcrun simctl list devices -j`.
///
/// Returns one [BackendDeviceInfo] per simulator (available + unavailable).
/// Physical iOS devices are omitted in the MVP.
Future<List<BackendDeviceInfo>> listAppleSimulators() async {
  final result = await runCmd(
    'xcrun',
    buildSimctlArgs(['list', 'devices', '-j']),
    const ExecOptions(timeoutMs: 15000),
  );
  final Map<String, Object?> raw;
  try {
    raw = jsonDecode(result.stdout) as Map<String, Object?>;
  } on FormatException catch (e) {
    throw AppError(
      AppErrorCodes.commandFailed,
      'Could not parse `simctl list devices -j` output: ${e.message}',
      details: {'stdout': result.stdout, 'stderr': result.stderr},
    );
  }

  final devicesByRuntime =
      (raw['devices'] as Map?) ?? const <String, Object?>{};
  final out = <BackendDeviceInfo>[];
  devicesByRuntime.forEach((runtimeKey, value) {
    if (value is! List) return;
    final runtime = _runtimeLabel(runtimeKey.toString());
    for (final entry in value) {
      if (entry is! Map) continue;
      final udid = entry['udid']?.toString();
      final name = entry['name']?.toString();
      if (udid == null || name == null) continue;
      final state = entry['state']?.toString() ?? 'Unknown';
      final isAvailable = entry['isAvailable'] == true;
      final typeId = entry['deviceTypeIdentifier']?.toString() ?? '';
      out.add(
        BackendDeviceInfo(
          id: udid,
          name: name,
          platform: _platformFromRuntime(runtimeKey.toString()),
          target: _targetFromDeviceType(typeId),
          kind: 'simulator',
          booted: state == 'Booted',
          details: <String, Object?>{
            'runtime': runtime,
            'state': state,
            'isAvailable': isAvailable,
            'deviceTypeIdentifier': typeId,
          },
        ),
      );
    }
  });
  return out;
}

/// Enumerate every iOS-family device visible to Xcode tooling —
/// simulators from `simctl` plus physical devices from `devicectl`.
/// Physical-device lookups fail silently so a missing iOS device doesn't
/// hide simulators.
Future<List<BackendDeviceInfo>> listAppleDevices() async {
  final simulators = await listAppleSimulators();
  final physical = await listApplePhysicalDevicesViaDevicectl();
  // Deduplicate on id (very rare but possible if a physical device shares
  // a UDID with a simulator set entry).
  final seen = <String>{for (final d in simulators) d.id};
  final merged = <BackendDeviceInfo>[...simulators];
  for (final d in physical) {
    if (seen.add(d.id)) merged.add(d);
  }
  return merged;
}

/// Pick the first booted simulator whose `udid` or `name` optionally
/// matches a filter. Returns null when nothing matches.
BackendDeviceInfo? pickBootedSimulator(
  List<BackendDeviceInfo> devices, {
  String? udid,
  String? name,
}) {
  for (final d in devices) {
    if (d.booted != true) continue;
    if (udid != null && d.id != udid) continue;
    if (name != null && d.name != name) continue;
    return d;
  }
  return null;
}

String _runtimeLabel(String key) {
  // com.apple.CoreSimulator.SimRuntime.iOS-26-2 → iOS 26.2
  final parts = key.split('.');
  if (parts.length < 2) return key;
  final tail = parts.last;
  return tail
      .replaceAll('-', ' ')
      .replaceFirstMapped(
        RegExp(r'(\w+) (\d+) (\d+)'),
        (m) => '${m.group(1)} ${m.group(2)}.${m.group(3)}',
      );
}

AgentDeviceBackendPlatform _platformFromRuntime(String key) {
  if (key.contains('tvOS')) return AgentDeviceBackendPlatform.ios;
  if (key.contains('watchOS')) return AgentDeviceBackendPlatform.ios;
  if (key.contains('iOS')) return AgentDeviceBackendPlatform.ios;
  if (key.contains('macOS')) return AgentDeviceBackendPlatform.macos;
  // Unknown — default to ios so the device surfaces to the user who can
  // inspect the details map.
  return AgentDeviceBackendPlatform.ios;
}

String? _targetFromDeviceType(String typeId) {
  if (typeId.contains('Apple-TV')) return 'tv';
  if (typeId.contains('Watch')) return 'watch';
  return 'mobile';
}
