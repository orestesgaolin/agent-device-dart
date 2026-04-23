// Port of agent-device/src/platforms/ios/apps.ts (MVP subset — install
// paths, bundled runner integration, and backend-session tracking land in
// Phase 8B alongside the XCUITest runner).
library;

import 'dart:convert';

import 'package:agent_device/src/utils/errors.dart';
import 'package:agent_device/src/utils/exec.dart';

import 'simctl.dart';

/// A brief view of an installed iOS app, extracted from `simctl listapps`.
class IosAppInfo {
  final String bundleId;
  final String? name;
  final String? bundleName;
  final String? applicationType; // "User" | "System"

  const IosAppInfo({
    required this.bundleId,
    this.name,
    this.bundleName,
    this.applicationType,
  });
}

/// `xcrun simctl listapps <udid>` outputs an old-style NeXTSTEP plist
/// (not JSON and not `-j`-capable). Pipe through `plutil -convert json`
/// for a clean structured parse.
Future<List<IosAppInfo>> listIosApps(
  String udid, {
  bool userOnly = true,
}) async {
  final result = await runCmd('sh', [
    '-c',
    'xcrun simctl listapps ${_sh(udid)} | plutil -convert json -r -o - -',
  ], const ExecOptions(timeoutMs: 30000));
  final Map<String, Object?> raw;
  try {
    raw = jsonDecode(result.stdout) as Map<String, Object?>;
  } on FormatException catch (e) {
    throw AppError(
      AppErrorCodes.commandFailed,
      'Could not parse `simctl listapps` output: ${e.message}',
      details: {'udid': udid, 'stderr': result.stderr},
    );
  }
  final apps = <IosAppInfo>[];
  raw.forEach((bundleId, value) {
    if (value is! Map) return;
    final appType = value['ApplicationType']?.toString();
    if (userOnly && appType != 'User') return;
    apps.add(
      IosAppInfo(
        bundleId: bundleId,
        name:
            value['CFBundleDisplayName']?.toString() ??
            value['CFBundleName']?.toString(),
        bundleName: value['CFBundleName']?.toString(),
        applicationType: appType,
      ),
    );
  });
  apps.sort((a, b) => a.bundleId.compareTo(b.bundleId));
  return apps;
}

/// Launch an app by bundle id on [udid]. Returns the PID reported by
/// `simctl launch`.
Future<int?> openIosApp(String udid, String bundleId) async {
  final result = await runCmd(
    'xcrun',
    buildSimctlArgs(['launch', udid, bundleId]),
    const ExecOptions(timeoutMs: 30000),
  );
  // Output format: "<bundleId>: <pid>"
  final match = RegExp(r':\s*(\d+)').firstMatch(result.stdout);
  if (match != null) {
    return int.tryParse(match.group(1)!);
  }
  return null;
}

/// Terminate an app by bundle id on [udid]. Succeeds even if the app
/// isn't running.
Future<void> closeIosApp(String udid, String bundleId) async {
  await runCmd(
    'xcrun',
    buildSimctlArgs(['terminate', udid, bundleId]),
    const ExecOptions(allowFailure: true, timeoutMs: 15000),
  );
}

/// Foreground process state. `simctl` doesn't expose the foreground app
/// directly; we approximate by listing running processes and returning
/// whatever is most recently launched. Real-device foreground tracking
/// lands with `devicectl` in Phase 8B.
Future<({String? bundleId, String? pid})> getIosForeground(String udid) async {
  final result = await runCmd(
    'xcrun',
    buildSimctlArgs(['spawn', udid, 'launchctl', 'list']),
    const ExecOptions(allowFailure: true, timeoutMs: 15000),
  );
  if (result.exitCode != 0) return (bundleId: null, pid: null);
  // Rows: "<pid>\t<status>\t<label>"
  String? best;
  String? bestPid;
  for (final line in result.stdout.split('\n')) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 3) continue;
    final pid = parts[0];
    final label = parts[2];
    if (pid == '-') continue;
    if (!label.startsWith('UIKitApplication:')) continue;
    // UIKitApplication:com.example.MyApp[…]
    final m = RegExp(r'UIKitApplication:([^\[]+)').firstMatch(label);
    if (m != null) {
      best = m.group(1);
      bestPid = pid;
    }
  }
  return (bundleId: best, pid: bestPid);
}

/// Minimal shell-quote for a UDID (alphanum + dashes).
String _sh(String s) => "'${s.replaceAll("'", r"'\''")}'";
