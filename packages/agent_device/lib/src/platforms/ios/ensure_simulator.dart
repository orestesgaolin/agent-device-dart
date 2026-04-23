// Port of agent-device/src/platforms/ios/ensure-simulator.ts.
//
// Finds or creates an iOS simulator by name, optionally boots it, and
// returns the UDID + runtime + a created/booted flag.
library;

import 'dart:convert';
import 'dart:io';

import 'package:agent_device/src/utils/errors.dart';
import 'package:agent_device/src/utils/exec.dart';

import 'simctl.dart';

class EnsureSimulatorResult {
  final String udid;
  final String device;
  final String runtime;
  final bool created;
  final bool booted;
  const EnsureSimulatorResult({
    required this.udid,
    required this.device,
    required this.runtime,
    required this.created,
    required this.booted,
  });

  Map<String, Object?> toJson() => {
    'udid': udid,
    'device': device,
    'runtime': runtime,
    'created': created,
    'booted': booted,
  };
}

/// Resolve [deviceName] (optionally pinned to [runtime]) to a simulator UDID.
/// Creates a new sim if [reuseExisting] is true and nothing matches, or
/// unconditionally when [reuseExisting] is false. When [boot] is true,
/// ensures the simulator is in the `Booted` state on return (via
/// `xcrun simctl boot` + a short ready probe).
Future<EnsureSimulatorResult> ensureSimulator({
  required String deviceName,
  String? runtime,
  bool reuseExisting = true,
  bool boot = true,
}) async {
  if (!Platform.isMacOS) {
    throw AppError(
      AppErrorCodes.unsupportedPlatform,
      'ensure-simulator is only available on macOS.',
    );
  }

  String udid;
  String resolvedRuntime;
  bool created;

  if (reuseExisting) {
    final existing = await _findExisting(
      deviceName: deviceName,
      runtime: runtime,
    );
    if (existing != null) {
      udid = existing.udid;
      resolvedRuntime = existing.runtime;
      created = false;
    } else {
      udid = await _createSimulator(deviceName: deviceName, runtime: runtime);
      resolvedRuntime = await _resolveRuntime(udid);
      created = true;
    }
  } else {
    udid = await _createSimulator(deviceName: deviceName, runtime: runtime);
    resolvedRuntime = await _resolveRuntime(udid);
    created = true;
  }

  var wasBooted = false;
  if (boot) {
    await _ensureBooted(udid);
    wasBooted = true;
  }

  return EnsureSimulatorResult(
    udid: udid,
    device: deviceName,
    runtime: resolvedRuntime,
    created: created,
    booted: wasBooted,
  );
}

class _Existing {
  final String udid;
  final String runtime;
  _Existing(this.udid, this.runtime);
}

Future<_Existing?> _findExisting({
  required String deviceName,
  String? runtime,
}) async {
  final r = await runCmd(
    'xcrun',
    buildSimctlArgs(['list', 'devices', '-j']),
    const ExecOptions(timeoutMs: 15000, allowFailure: true),
  );
  if (r.exitCode != 0) return null;
  Map<String, Object?> payload;
  try {
    payload = jsonDecode(r.stdout) as Map<String, Object?>;
  } on FormatException {
    return null;
  }
  final byRuntime = (payload['devices'] as Map?) ?? const {};
  final wantName = deviceName.toLowerCase();
  final wantRuntime = runtime == null ? null : _normalizeRuntime(runtime);
  for (final entry in byRuntime.entries) {
    final key = entry.key.toString();
    if (wantRuntime != null && !_normalizeRuntime(key).contains(wantRuntime)) {
      continue;
    }
    final list = entry.value;
    if (list is! List) continue;
    for (final d in list) {
      if (d is! Map) continue;
      if (d['isAvailable'] != true) continue;
      final name = (d['name'] as String?)?.toLowerCase();
      if (name != wantName) continue;
      final udid = d['udid'] as String?;
      if (udid != null) return _Existing(udid, key);
    }
  }
  return null;
}

Future<String> _createSimulator({
  required String deviceName,
  String? runtime,
}) async {
  final args = runtime != null
      ? ['create', deviceName, deviceName, runtime]
      : ['create', deviceName, deviceName];
  final r = await runCmd(
    'xcrun',
    buildSimctlArgs(args),
    const ExecOptions(allowFailure: true),
  );
  if (r.exitCode != 0) {
    throw AppError(
      AppErrorCodes.commandFailed,
      'Failed to create iOS simulator.',
      details: {
        'deviceName': deviceName,
        'runtime': runtime,
        'stdout': r.stdout,
        'stderr': r.stderr,
        'exitCode': r.exitCode,
        'hint':
            'Run `xcrun simctl list devicetypes` and `xcrun simctl list runtimes` '
            'to check available identifiers.',
      },
    );
  }
  final udid = r.stdout.trim();
  if (udid.isEmpty) {
    throw AppError(
      AppErrorCodes.commandFailed,
      'simctl create returned no UDID.',
      details: {'stdout': r.stdout, 'stderr': r.stderr},
    );
  }
  return udid;
}

Future<String> _resolveRuntime(String udid) async {
  final r = await runCmd(
    'xcrun',
    buildSimctlArgs(['list', 'devices', '-j']),
    const ExecOptions(timeoutMs: 15000, allowFailure: true),
  );
  if (r.exitCode != 0) return '';
  try {
    final payload = jsonDecode(r.stdout) as Map<String, Object?>;
    final byRuntime = (payload['devices'] as Map?) ?? const {};
    for (final entry in byRuntime.entries) {
      final list = entry.value;
      if (list is! List) continue;
      for (final d in list) {
        if (d is Map && d['udid'] == udid) return entry.key.toString();
      }
    }
    return '';
  } on FormatException {
    return '';
  }
}

Future<void> _ensureBooted(String udid) async {
  final state = await _deviceState(udid);
  if (state == 'Booted') return;
  final boot = await runCmd(
    'xcrun',
    buildSimctlArgs(['boot', udid]),
    const ExecOptions(allowFailure: true),
  );
  if (boot.exitCode != 0 &&
      !(boot.stderr.contains(
        'Unable to boot device in current state: Booted',
      ))) {
    throw AppError(
      AppErrorCodes.commandFailed,
      'Failed to boot simulator $udid.',
      details: {
        'stdout': boot.stdout,
        'stderr': boot.stderr,
        'exitCode': boot.exitCode,
      },
    );
  }
  // Wait up to 30s for the sim to report Booted.
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    if (await _deviceState(udid) == 'Booted') return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw AppError(
    AppErrorCodes.commandFailed,
    'Simulator $udid did not reach Booted state within 30s.',
  );
}

Future<String?> _deviceState(String udid) async {
  final r = await runCmd(
    'xcrun',
    buildSimctlArgs(['list', 'devices', '-j']),
    const ExecOptions(timeoutMs: 15000, allowFailure: true),
  );
  if (r.exitCode != 0) return null;
  try {
    final payload = jsonDecode(r.stdout) as Map<String, Object?>;
    final byRuntime = (payload['devices'] as Map?) ?? const {};
    for (final list in byRuntime.values) {
      if (list is! List) continue;
      for (final d in list) {
        if (d is Map && d['udid'] == udid) return d['state'] as String?;
      }
    }
  } on FormatException {
    return null;
  }
  return null;
}

String _normalizeRuntime(String runtime) =>
    runtime.toLowerCase().replaceAll(RegExp(r'[._\-]'), '');
