// Shared cross-invocation state for streaming log captures. iOS + Android
// both write one of these to `<stateDir>/log-streams/<deviceId>.json` on
// `startLogStream` so a later CLI invocation can call `stopLogStream`
// against the same background process.
library;

import 'dart:convert';
import 'dart:io';

import 'package:agent_device/src/runtime/paths.dart';
import 'package:path/path.dart' as p;

class LogStreamRecord {
  final String deviceId;
  final String platform;
  final int hostPid;
  final String outPath;
  final String startedAt;
  final String? appBundleId;

  const LogStreamRecord({
    required this.deviceId,
    required this.platform,
    required this.hostPid,
    required this.outPath,
    required this.startedAt,
    this.appBundleId,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'deviceId': deviceId,
    'platform': platform,
    'hostPid': hostPid,
    'outPath': outPath,
    'startedAt': startedAt,
    if (appBundleId != null) 'appBundleId': appBundleId,
  };

  static LogStreamRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final deviceId = raw['deviceId'];
    final platform = raw['platform'];
    final hostPid = raw['hostPid'];
    final outPath = raw['outPath'];
    final startedAt = raw['startedAt'];
    if (deviceId is! String ||
        platform is! String ||
        hostPid is! int ||
        outPath is! String ||
        startedAt is! String) {
      return null;
    }
    return LogStreamRecord(
      deviceId: deviceId,
      platform: platform,
      hostPid: hostPid,
      outPath: outPath,
      startedAt: startedAt,
      appBundleId: raw['appBundleId'] as String?,
    );
  }
}

File logStreamFile(String deviceId) {
  final paths = resolveStatePaths();
  return File(p.join(paths.baseDir, 'log-streams', '$deviceId.json'));
}

Future<LogStreamRecord?> readLogStreamRecord(String deviceId) async {
  final file = logStreamFile(deviceId);
  if (!await file.exists()) return null;
  try {
    return LogStreamRecord.fromJson(jsonDecode(await file.readAsString()));
  } on FormatException {
    return null;
  }
}

Future<void> writeLogStreamRecord(LogStreamRecord record) async {
  final file = logStreamFile(record.deviceId);
  await file.parent.create(recursive: true);
  await file.writeAsString(jsonEncode(record.toJson()));
}

Future<void> deleteLogStreamRecord(String deviceId) async {
  final file = logStreamFile(deviceId);
  if (await file.exists()) {
    try {
      await file.delete();
    } catch (_) {}
  }
}

/// Send SIGINT to [pid] so streamers (logcat, simctl log stream) get a
/// chance to flush their buffers before dying. Best-effort — swallows
/// all errors, returns true iff the signal appeared to land.
bool killLogStreamPid(int pid) {
  try {
    return Process.killPid(pid, ProcessSignal.sigint);
  } catch (_) {
    return false;
  }
}
