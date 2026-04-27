// Port of agent-device/src/platforms/android/snapshot-types.ts

/// Maximum number of snapshot nodes returned by Android capture.
const androidSnapshotMaxNodes = 800;

/// Backend metadata attached to every Android snapshot result.
///
/// Indicates which capture path was taken (helper vs uiautomator dump) and
/// carries the relevant diagnostics from that path.
class AndroidSnapshotBackendMetadata {
  /// Which backend produced this snapshot.
  /// Either `'android-helper'` or `'uiautomator-dump'`.
  final String backend;

  /// Version string of the bundled helper APK (helper path only).
  final String? helperVersion;

  /// API version reported by the helper instrumentation (helper path only).
  final String? helperApiVersion;

  /// Reason the helper was skipped and uiautomator dump was used instead.
  final String? fallbackReason;

  /// Reason the helper was installed / skipped during this capture.
  final String? installReason;

  /// `waitForIdleTimeoutMs` reported by the helper.
  final int? waitForIdleTimeoutMs;

  /// `timeoutMs` reported by the helper.
  final int? timeoutMs;

  /// `maxDepth` reported by the helper.
  final int? maxDepth;

  /// `maxNodes` reported by the helper.
  final int? maxNodes;

  /// Whether the accessibility root was present (helper only).
  final bool? rootPresent;

  /// Capture mode used by the helper (`'interactive-windows'` or `'active-window'`).
  final String? captureMode;

  /// Number of windows captured by the helper.
  final int? windowCount;

  /// Number of nodes in the raw helper output.
  final int? nodeCount;

  /// Whether the helper truncated the node tree.
  final bool? helperTruncated;

  /// Elapsed milliseconds reported by the helper.
  final int? elapsedMs;

  const AndroidSnapshotBackendMetadata({
    required this.backend,
    this.helperVersion,
    this.helperApiVersion,
    this.fallbackReason,
    this.installReason,
    this.waitForIdleTimeoutMs,
    this.timeoutMs,
    this.maxDepth,
    this.maxNodes,
    this.rootPresent,
    this.captureMode,
    this.windowCount,
    this.nodeCount,
    this.helperTruncated,
    this.elapsedMs,
  });

  Map<String, Object?> toJson() => {
    'backend': backend,
    if (helperVersion != null) 'helperVersion': helperVersion,
    if (helperApiVersion != null) 'helperApiVersion': helperApiVersion,
    if (fallbackReason != null) 'fallbackReason': fallbackReason,
    if (installReason != null) 'installReason': installReason,
    if (waitForIdleTimeoutMs != null) 'waitForIdleTimeoutMs': waitForIdleTimeoutMs,
    if (timeoutMs != null) 'timeoutMs': timeoutMs,
    if (maxDepth != null) 'maxDepth': maxDepth,
    if (maxNodes != null) 'maxNodes': maxNodes,
    if (rootPresent != null) 'rootPresent': rootPresent,
    if (captureMode != null) 'captureMode': captureMode,
    if (windowCount != null) 'windowCount': windowCount,
    if (nodeCount != null) 'nodeCount': nodeCount,
    if (helperTruncated != null) 'helperTruncated': helperTruncated,
    if (elapsedMs != null) 'elapsedMs': elapsedMs,
  };
}
