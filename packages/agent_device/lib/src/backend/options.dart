// Port of agent-device/src/backend.ts
library;

import 'package:agent_device/src/snapshot/snapshot.dart';

// ============================================================================
// Keyboard and Navigation
// ============================================================================

/// Options for keyboard operations.
class BackendKeyboardOptions {
  final String action; // 'status' | 'get' | 'dismiss'

  const BackendKeyboardOptions({required this.action});
}

/// Result of a keyboard operation.
class BackendKeyboardResult {
  final String? platform;
  final String? action;
  final bool? visible;
  final String? inputType;
  final String? type;
  final bool? wasVisible;
  final bool? dismissed;
  final int? attempts;

  const BackendKeyboardResult({
    this.platform,
    this.action,
    this.visible,
    this.inputType,
    this.type,
    this.wasVisible,
    this.dismissed,
    this.attempts,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    if (platform != null) 'platform': platform,
    if (action != null) 'action': action,
    if (visible != null) 'visible': visible,
    if (inputType != null) 'inputType': inputType,
    if (type != null) 'type': type,
    if (wasVisible != null) 'wasVisible': wasVisible,
    if (dismissed != null) 'dismissed': dismissed,
    if (attempts != null) 'attempts': attempts,
  };
}

/// Options for back navigation.
class BackendBackOptions {
  final String? mode; // 'in-app' | 'system'

  const BackendBackOptions({this.mode});
}

// ============================================================================
// Tap and Interaction Options
// ============================================================================

/// Options for tap gestures.
class BackendTapOptions {
  final String? button;
  final int? count;
  final int? intervalMs;
  final int? holdMs;
  final int? jitterPx;
  final bool? doubleTap;

  const BackendTapOptions({
    this.button,
    this.count,
    this.intervalMs,
    this.holdMs,
    this.jitterPx,
    this.doubleTap,
  });
}

/// Options for text fill operations.
class BackendFillOptions {
  final int? delayMs;

  const BackendFillOptions({this.delayMs});
}

/// Options for long press gestures.
class BackendLongPressOptions {
  final int? durationMs;

  const BackendLongPressOptions({this.durationMs});
}

/// Options for swipe gestures.
class BackendSwipeOptions {
  final int? durationMs;

  const BackendSwipeOptions({this.durationMs});
}

/// Target for scroll operations (viewport or specific point).
sealed class BackendScrollTarget {
  const BackendScrollTarget();
}

class BackendScrollTargetViewport extends BackendScrollTarget {
  const BackendScrollTargetViewport();
}

class BackendScrollTargetPoint extends BackendScrollTarget {
  final Point point;

  const BackendScrollTargetPoint(this.point);
}

/// Options for scroll operations.
class BackendScrollOptions {
  final String direction; // 'up' | 'down' | 'left' | 'right'
  final int? amount;
  final int? pixels;

  const BackendScrollOptions({
    required this.direction,
    this.amount,
    this.pixels,
  });
}

/// Options for pinch gestures.
class BackendPinchOptions {
  final double scale;
  final Point? center;

  const BackendPinchOptions({required this.scale, this.center});
}

// ============================================================================
// Text and Clipboard
// ============================================================================

/// Result of reading text from a node.
class BackendReadTextResult {
  final String text;

  const BackendReadTextResult({required this.text});

  Map<String, Object?> toJson() => {'text': text};
}

/// Result of finding text.
class BackendFindTextResult {
  final bool found;

  const BackendFindTextResult({required this.found});

  Map<String, Object?> toJson() => {'found': found};
}

/// Result of getting clipboard text.
class BackendClipboardTextResult {
  final String text;

  const BackendClipboardTextResult({required this.text});

  Map<String, Object?> toJson() => {'text': text};
}

// ============================================================================
// Alerts
// ============================================================================

/// Alert action type.
enum BackendAlertAction {
  get('get'),
  accept('accept'),
  dismiss('dismiss'),
  wait('wait');

  final String value;

  const BackendAlertAction(this.value);

  static BackendAlertAction? fromString(String? value) {
    return switch (value) {
      'get' => BackendAlertAction.get,
      'accept' => BackendAlertAction.accept,
      'dismiss' => BackendAlertAction.dismiss,
      'wait' => BackendAlertAction.wait,
      _ => null,
    };
  }

  @override
  String toString() => value;
}

/// Information about an alert.
class BackendAlertInfo {
  final String? title;
  final String? message;
  final List<String>? buttons;

  const BackendAlertInfo({this.title, this.message, this.buttons});

  Map<String, Object?> toJson() => <String, Object?>{
    if (title != null) 'title': title,
    if (message != null) 'message': message,
    if (buttons != null) 'buttons': buttons,
  };
}

/// Result of an alert operation.
sealed class BackendAlertResult {
  const BackendAlertResult();
}

class BackendAlertStatusResult extends BackendAlertResult {
  final BackendAlertInfo? alert;

  const BackendAlertStatusResult({this.alert});

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'alertStatus',
    'alert': alert?.toJson(),
  };
}

class BackendAlertHandledResult extends BackendAlertResult {
  final bool handled;
  final BackendAlertInfo? alert;
  final String? button;

  const BackendAlertHandledResult({
    required this.handled,
    this.alert,
    this.button,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'alertHandled',
    'handled': handled,
    if (alert != null) 'alert': alert!.toJson(),
    if (button != null) 'button': button,
  };
}

class BackendAlertWaitResult extends BackendAlertResult {
  final BackendAlertInfo? alert;
  final int? waitedMs;
  final bool? timedOut;

  const BackendAlertWaitResult({this.alert, this.waitedMs, this.timedOut});

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'alertWait',
    'alert': alert?.toJson(),
    if (waitedMs != null) 'waitedMs': waitedMs,
    if (timedOut != null) 'timedOut': timedOut,
  };
}

// ============================================================================
// App Opening and Deep Links
// ============================================================================

/// Target specification for opening an app or URL.
class BackendOpenTarget {
  final String? app;
  final String? appId;
  final String? bundleId;
  final String? packageName;
  final String? url;
  final String? activity;

  const BackendOpenTarget({
    this.app,
    this.appId,
    this.bundleId,
    this.packageName,
    this.url,
    this.activity,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    if (app != null) 'app': app,
    if (appId != null) 'appId': appId,
    if (bundleId != null) 'bundleId': bundleId,
    if (packageName != null) 'packageName': packageName,
    if (url != null) 'url': url,
    if (activity != null) 'activity': activity,
  };
}

/// Options for opening an app.
class BackendOpenOptions {
  final bool? relaunch;

  const BackendOpenOptions({this.relaunch});
}

// ============================================================================
// File and Input Operations
// ============================================================================

/// Source for app installation.
sealed class BackendInstallSource {
  const BackendInstallSource();
}

class BackendInstallSourcePath extends BackendInstallSource {
  final String path;

  const BackendInstallSourcePath(this.path);
}

class BackendInstallSourceUploadedArtifact extends BackendInstallSource {
  final String id;

  const BackendInstallSourceUploadedArtifact(this.id);
}

class BackendInstallSourceUrl extends BackendInstallSource {
  final String url;

  const BackendInstallSourceUrl(this.url);
}

/// Input for push file operation.
sealed class BackendPushInput {
  const BackendPushInput();
}

class BackendPushInputJson extends BackendPushInput {
  final Map<String, Object?> payload;

  const BackendPushInputJson(this.payload);
}

class BackendPushInputFile extends BackendPushInput {
  final String path;

  const BackendPushInputFile(this.path);
}

// ============================================================================
// Snapshots and Screenshots
// ============================================================================

/// Options for capturing a snapshot.
class BackendSnapshotOptions {
  final bool? interactiveOnly;
  final bool? compact;
  final int? depth;
  final String? scope;
  final bool? raw;
  final String? outPath;

  const BackendSnapshotOptions({
    this.interactiveOnly,
    this.compact,
    this.depth,
    this.scope,
    this.raw,
    this.outPath,
  });
}

/// Options for capturing a screenshot.
class BackendScreenshotOptions {
  final bool? fullscreen;
  final bool? overlayRefs;
  final String? surface;

  /// When set, the captured PNG is downscaled to fit within
  /// [maxSize] pixels on its longest edge before returning. Useful
  /// for keeping artifact bundles small. Applied as a post-process
  /// step after the backend writes the file.
  final int? maxSize;

  const BackendScreenshotOptions({
    this.fullscreen,
    this.overlayRefs,
    this.surface,
    this.maxSize,
  });
}

/// Result of a screenshot operation.
class BackendScreenshotResult {
  final String? path;
  final List<Object?>? overlayRefs;

  const BackendScreenshotResult({this.path, this.overlayRefs});

  Map<String, Object?> toJson() => <String, Object?>{
    if (path != null) 'path': path,
    if (overlayRefs != null) 'overlayRefs': overlayRefs,
  };
}

/// Analysis of a snapshot.
class BackendSnapshotAnalysis {
  final int? rawNodeCount;
  final int? maxDepth;

  const BackendSnapshotAnalysis({this.rawNodeCount, this.maxDepth});

  Map<String, Object?> toJson() => <String, Object?>{
    if (rawNodeCount != null) 'rawNodeCount': rawNodeCount,
    if (maxDepth != null) 'maxDepth': maxDepth,
  };
}

/// Result of a snapshot operation.
class BackendSnapshotResult {
  final List<Object?>? nodes;
  final bool? truncated;
  final String? backend;
  final Object? snapshot;
  final BackendSnapshotAnalysis? analysis;
  final List<String>? warnings;
  final String? appName;
  final String? appBundleId;

  const BackendSnapshotResult({
    this.nodes,
    this.truncated,
    this.backend,
    this.snapshot,
    this.analysis,
    this.warnings,
    this.appName,
    this.appBundleId,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    if (nodes != null) 'nodes': nodes,
    if (truncated != null) 'truncated': truncated,
    if (backend != null) 'backend': backend,
    if (snapshot != null) 'snapshot': snapshot,
    if (analysis != null) 'analysis': analysis!.toJson(),
    if (warnings != null) 'warnings': warnings,
    if (appName != null) 'appName': appName,
    if (appBundleId != null) 'appBundleId': appBundleId,
  };
}


/// A command to run via runner.
class BackendRunnerCommand {
  final String command;
  final List<String>? args;
  final Map<String, Object?>? payload;

  const BackendRunnerCommand({required this.command, this.args, this.payload});

  Map<String, Object?> toJson() => <String, Object?>{
    'command': command,
    if (args != null) 'args': args,
    if (payload != null) 'payload': payload,
  };
}

/// Options for recording video.
class BackendRecordingOptions {
  final String? outPath;
  final int? fps;
  final int? quality;
  final bool? showTouches;

  const BackendRecordingOptions({
    this.outPath,
    this.fps,
    this.quality,
    this.showTouches,
  });
}

/// Result of a recording operation.
class BackendRecordingResult {
  final String? path;
  final String? telemetryPath;
  final String? warning;

  const BackendRecordingResult({this.path, this.telemetryPath, this.warning});

  Map<String, Object?> toJson() => <String, Object?>{
    if (path != null) 'path': path,
    if (telemetryPath != null) 'telemetryPath': telemetryPath,
    if (warning != null) 'warning': warning,
  };
}

/// Options for tracing.
class BackendTraceOptions {
  final String? outPath;

  const BackendTraceOptions({this.outPath});
}

/// Result of a trace operation.
class BackendTraceResult {
  final String? outPath;

  const BackendTraceResult({this.outPath});

  Map<String, Object?> toJson() => <String, Object?>{
    if (outPath != null) 'outPath': outPath,
  };
}
