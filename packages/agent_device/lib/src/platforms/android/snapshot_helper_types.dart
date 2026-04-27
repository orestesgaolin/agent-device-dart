// Port of agent-device/src/platforms/android/snapshot-helper-types.ts

import '../../snapshot/snapshot.dart';
import 'ui_hierarchy.dart';

const androidSnapshotHelperName = 'android-snapshot-helper';
const androidSnapshotHelperPackage = 'com.callstack.agentdevice.snapshothelper';
const androidSnapshotHelperRunner =
    'com.callstack.agentdevice.snapshothelper/.SnapshotInstrumentation';
const androidSnapshotHelperProtocol = 'android-snapshot-helper-v1';
const androidSnapshotHelperOutputFormat = 'uiautomator-xml';
const androidSnapshotHelperWaitForIdleTimeoutMs = 500;
const androidSnapshotHelperCommandOverheadMs = 5000;

/// Result of a single adb command invocation.
class AdbResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  const AdbResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });
}

/// Function type for executing adb commands.
///
/// Mirrors [AndroidAdbExecutor] in TS: takes positional args and optional
/// flags, returns exit code + captured stdout/stderr.
typedef AndroidAdbExecutor = Future<AdbResult> Function(
  List<String> args, {
  bool allowFailure,
  int? timeoutMs,
});

/// Parsed manifest describing the helper APK artifact.
class AndroidSnapshotHelperManifest {
  final String name;
  final String version;
  final String? releaseTag;
  final String? assetName;
  final String? apkUrl;
  final String sha256;
  final String? checksumName;
  final String packageName;
  final int versionCode;
  final String instrumentationRunner;
  final int minSdk;
  final int? targetSdk;
  final String outputFormat;
  final String statusProtocol;
  final List<String> installArgs;

  const AndroidSnapshotHelperManifest({
    required this.name,
    required this.version,
    this.releaseTag,
    this.assetName,
    required this.apkUrl,
    required this.sha256,
    this.checksumName,
    required this.packageName,
    required this.versionCode,
    required this.instrumentationRunner,
    required this.minSdk,
    this.targetSdk,
    required this.outputFormat,
    required this.statusProtocol,
    required this.installArgs,
  });
}

/// A resolved helper APK path + its manifest.
class AndroidSnapshotHelperArtifact {
  final String apkPath;
  final AndroidSnapshotHelperManifest manifest;

  const AndroidSnapshotHelperArtifact({
    required this.apkPath,
    required this.manifest,
  });
}

/// Install policy for the snapshot helper.
enum AndroidSnapshotHelperInstallPolicy {
  missingOrOutdated,
  always,
  never,
}

/// Result of an ensure-install attempt.
class AndroidSnapshotHelperInstallResult {
  final String packageName;
  final int versionCode;
  final int? installedVersionCode;
  final bool installed;
  final String reason; // 'missing'|'outdated'|'forced'|'current'|'skipped'

  const AndroidSnapshotHelperInstallResult({
    required this.packageName,
    required this.versionCode,
    this.installedVersionCode,
    required this.installed,
    required this.reason,
  });
}

/// Options for the snapshot capture call.
class AndroidSnapshotHelperCaptureOptions {
  final AndroidAdbExecutor adb;
  final String? packageName;
  final String? instrumentationRunner;
  final int? waitForIdleTimeoutMs;
  final int? timeoutMs;
  final int? commandTimeoutMs;
  final int? maxDepth;
  final int? maxNodes;

  const AndroidSnapshotHelperCaptureOptions({
    required this.adb,
    this.packageName,
    this.instrumentationRunner,
    this.waitForIdleTimeoutMs,
    this.timeoutMs,
    this.commandTimeoutMs,
    this.maxDepth,
    this.maxNodes,
  });
}

/// Metadata returned by the helper instrumentation run.
class AndroidSnapshotHelperMetadata {
  final String? helperApiVersion;
  final String outputFormat;
  final int? waitForIdleTimeoutMs;
  final int? timeoutMs;
  final int? maxDepth;
  final int? maxNodes;
  final bool? rootPresent;
  final String? captureMode; // 'interactive-windows'|'active-window'
  final int? windowCount;
  final int? nodeCount;
  final bool? truncated;
  final int? elapsedMs;

  const AndroidSnapshotHelperMetadata({
    this.helperApiVersion,
    required this.outputFormat,
    this.waitForIdleTimeoutMs,
    this.timeoutMs,
    this.maxDepth,
    this.maxNodes,
    this.rootPresent,
    this.captureMode,
    this.windowCount,
    this.nodeCount,
    this.truncated,
    this.elapsedMs,
  });
}

/// XML output + metadata from a successful helper run.
class AndroidSnapshotHelperOutput {
  final String xml;
  final AndroidSnapshotHelperMetadata metadata;

  const AndroidSnapshotHelperOutput({required this.xml, required this.metadata});
}

/// Parsed snapshot nodes + metadata from the helper.
class AndroidSnapshotHelperParsedSnapshot {
  final List<RawSnapshotNode> nodes;
  final bool? truncated;
  final AndroidSnapshotAnalysis analysis;
  final AndroidSnapshotHelperMetadata metadata;

  const AndroidSnapshotHelperParsedSnapshot({
    required this.nodes,
    this.truncated,
    required this.analysis,
    required this.metadata,
  });
}
