// Port of agent-device/src/platforms/android/snapshot-helper-install.ts

import 'package:meta/meta.dart' show visibleForTesting;

import '../../utils/errors.dart';
import 'snapshot_helper_artifact.dart';
import 'snapshot_helper_types.dart';

// In-memory cache: avoids shelling out to `adb shell pm list packages` on
// every snapshot when the helper is already known to be installed at the
// right version. Keyed by `<deviceKey>\0<packageName>\0<versionCode>`.
final _installedSnapshotHelpers = <String, int>{};

/// Forget a cached install for a specific device + helper version.
/// Called when helper capture fails so the next attempt re-checks.
void forgetAndroidSnapshotHelperInstall({
  required String? deviceKey,
  required String packageName,
  required int versionCode,
}) {
  final key = _installCacheKey(deviceKey, packageName, versionCode);
  if (key != null) _installedSnapshotHelpers.remove(key);
}

/// Clear the entire install cache. Useful in tests.
@visibleForTesting
void resetAndroidSnapshotHelperInstallCache() {
  _installedSnapshotHelpers.clear();
}

String? _installCacheKey(String? deviceKey, String packageName, int versionCode) {
  return deviceKey != null ? '$deviceKey\x00$packageName\x00$versionCode' : null;
}

/// Ensure the snapshot helper APK is installed on the device and up to date.
///
/// Port of `ensureAndroidSnapshotHelper` in `snapshot-helper-install.ts`.
Future<AndroidSnapshotHelperInstallResult> ensureAndroidSnapshotHelper({
  required AndroidAdbExecutor adb,
  required AndroidSnapshotHelperArtifact artifact,
  AndroidSnapshotHelperInstallPolicy installPolicy =
      AndroidSnapshotHelperInstallPolicy.missingOrOutdated,
  String? deviceKey,
  int? timeoutMs,
}) async {
  final packageName = artifact.manifest.packageName;
  final versionCode = artifact.manifest.versionCode;

  if (installPolicy == AndroidSnapshotHelperInstallPolicy.never) {
    return AndroidSnapshotHelperInstallResult(
      packageName: packageName,
      versionCode: versionCode,
      installed: false,
      reason: 'skipped',
    );
  }

  // Check in-memory cache first.
  final cacheKey = _installCacheKey(deviceKey, packageName, versionCode);
  if (cacheKey != null &&
      installPolicy != AndroidSnapshotHelperInstallPolicy.always) {
    final cached = _installedSnapshotHelpers[cacheKey];
    if (cached != null) {
      return AndroidSnapshotHelperInstallResult(
        packageName: packageName,
        versionCode: versionCode,
        installedVersionCode: cached,
        installed: false,
        reason: 'current',
      );
    }
  }

  final installedVersionCode = await _readInstalledVersionCode(
    adb,
    packageName,
    timeoutMs,
  );
  final reason = _getInstallReason(
    installPolicy,
    installedVersionCode,
    versionCode,
  );

  if (reason == 'current') {
    if (installedVersionCode != null) {
      _rememberInstall(cacheKey, installedVersionCode);
    }
    return AndroidSnapshotHelperInstallResult(
      packageName: packageName,
      versionCode: versionCode,
      installedVersionCode: installedVersionCode,
      installed: false,
      reason: reason,
    );
  }

  await verifyAndroidSnapshotHelperArtifact(artifact);
  final installArgs = [
    ...readAndroidSnapshotHelperInstallArgs(artifact.manifest),
    artifact.apkPath,
  ];
  final result = await _installAndroidSnapshotHelper(
    adb,
    installArgs,
    packageName: packageName,
    timeoutMs: timeoutMs,
  );

  if (result.exitCode != 0) {
    _forgetInstall(cacheKey);
    throw AppError(
      AppErrorCodes.commandFailed,
      'Failed to install Android snapshot helper',
      details: {
        'packageName': packageName,
        'versionCode': versionCode,
        'stdout': result.stdout,
        'stderr': result.stderr,
        'exitCode': result.exitCode,
      },
    );
  }

  _rememberInstall(cacheKey, versionCode);
  return AndroidSnapshotHelperInstallResult(
    packageName: packageName,
    versionCode: versionCode,
    installedVersionCode: installedVersionCode,
    installed: true,
    reason: reason,
  );
}

void _rememberInstall(String? cacheKey, int versionCode) {
  if (cacheKey != null) _installedSnapshotHelpers[cacheKey] = versionCode;
}

void _forgetInstall(String? cacheKey) {
  if (cacheKey != null) _installedSnapshotHelpers.remove(cacheKey);
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

Future<int?> _readInstalledVersionCode(
  AndroidAdbExecutor adb,
  String packageName,
  int? timeoutMs,
) async {
  final result = await adb(
    [
      'shell',
      'cmd',
      'package',
      'list',
      'packages',
      '--show-versioncode',
      packageName,
    ],
    allowFailure: true,
    timeoutMs: timeoutMs,
  );

  if (result.exitCode == 0) {
    return _parsePackageListVersionCode(
      '${result.stdout}\n${result.stderr}',
      packageName,
    );
  }
  return null;
}

Future<AdbResult> _installAndroidSnapshotHelper(
  AndroidAdbExecutor adb,
  List<String> installArgs, {
  required String packageName,
  int? timeoutMs,
}) async {
  final result = await adb(
    installArgs,
    allowFailure: true,
    timeoutMs: timeoutMs,
  );
  if (result.exitCode == 0 || !_isInstallUpdateIncompatible(result)) {
    return result;
  }

  // Signature mismatch: uninstall and retry.
  final uninstall = await adb(
    ['uninstall', packageName],
    allowFailure: true,
    timeoutMs: timeoutMs,
  );
  final retry = await adb(
    installArgs,
    allowFailure: true,
    timeoutMs: timeoutMs,
  );
  if (retry.exitCode == 0) return retry;

  final extraStderr = uninstall.stderr.isNotEmpty
      ? 'Previous uninstall stderr after INSTALL_FAILED_UPDATE_INCOMPATIBLE: ${uninstall.stderr}'
      : '';
  final mergedStderr = [
    retry.stderr,
    extraStderr,
  ].where((s) => s.isNotEmpty).join('\n');

  return AdbResult(
    exitCode: retry.exitCode,
    stdout: retry.stdout,
    stderr: mergedStderr,
  );
}

int? _parsePackageListVersionCode(String output, String packageName) {
  final packagePrefix = 'package:$packageName';
  for (final line in output.split(RegExp(r'\r?\n'))) {
    if (!line.startsWith(packagePrefix)) continue;
    if (line.length > packagePrefix.length &&
        !RegExp(r'\s').hasMatch(line[packagePrefix.length])) {
      continue;
    }
    final match = RegExp(r'(?:^|\s)versionCode:(\d+)(?:\s|$)').firstMatch(line);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
  }
  return null;
}

bool _isInstallUpdateIncompatible(AdbResult result) {
  return '${result.stdout}\n${result.stderr}'.contains(
    'INSTALL_FAILED_UPDATE_INCOMPATIBLE',
  );
}

String _getInstallReason(
  AndroidSnapshotHelperInstallPolicy installPolicy,
  int? installedVersionCode,
  int requiredVersionCode,
) {
  if (installPolicy == AndroidSnapshotHelperInstallPolicy.never) {
    return 'skipped';
  }
  if (installPolicy == AndroidSnapshotHelperInstallPolicy.always) {
    return 'forced';
  }
  if (installedVersionCode == null) return 'missing';
  return installedVersionCode < requiredVersionCode ? 'outdated' : 'current';
}
