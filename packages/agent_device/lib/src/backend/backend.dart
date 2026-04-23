// Port of agent-device/src/backend.ts
library;

import 'package:agent_device/src/snapshot/snapshot.dart';

import 'capabilities.dart';
import 'device_info.dart';
import 'diagnostics.dart';
import 'install_source.dart';
import 'options.dart';
import 'platform.dart';

export 'capabilities.dart';
export 'device_info.dart';
export 'diagnostics.dart';
export 'install_source.dart';
export 'options.dart';
export 'platform.dart';

// ============================================================================
// Command Context
// ============================================================================

/// Context information for a backend command.
class BackendCommandContext {
  final String? session;
  final String? requestId;
  final String? appId;
  final String? appBundleId;
  final Object? signal; // AbortSignal in TS, CancelToken equivalent in Dart
  final Map<String, Object?>? metadata;

  const BackendCommandContext({
    this.session,
    this.requestId,
    this.appId,
    this.appBundleId,
    this.signal,
    this.metadata,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    if (session != null) 'session': session,
    if (requestId != null) 'requestId': requestId,
    if (appId != null) 'appId': appId,
    if (appBundleId != null) 'appBundleId': appBundleId,
    if (metadata != null) 'metadata': metadata,
  };
}

// ============================================================================
// Escape Hatches
// ============================================================================

/// Callbacks for platform-specific functionality not exposed in the standard
/// backend interface.
abstract class BackendEscapeHatches {
  /// Execute an arbitrary adb command on Android. Only available if
  /// capabilities includes 'android.shell'.
  Future<BackendShellResult>? androidShell(
    BackendCommandContext context,
    List<String> args,
  );

  /// Execute a runner command on iOS. Only available if capabilities includes
  /// 'ios.runnerCommand'.
  Future<Object?>? iosRunnerCommand(
    BackendCommandContext context,
    BackendRunnerCommand command,
  );

  /// Take a screenshot on macOS desktop. Only available if capabilities
  /// includes 'macos.desktopScreenshot'.
  Future<BackendScreenshotResult?>? macosDesktopScreenshot(
    BackendCommandContext context,
    String outPath,
    BackendScreenshotOptions? options,
  );
}

// ============================================================================
// Action Result Type
// ============================================================================

/// Result type for generic actions (may be void or a map of properties).
typedef BackendActionResult = Object?;

// ============================================================================
// Backend Abstract Class
// ============================================================================

/// Abstract backend that each platform implementation must provide.
/// Defines the contract for interacting with a device.
abstract class Backend {
  /// The platform this backend targets.
  AgentDeviceBackendPlatform get platform;

  /// Capabilities that this backend reports as supported.
  BackendCapabilitySet? get capabilities;

  /// Platform-specific escape hatches for unsupported operations.
  BackendEscapeHatches? get escapeHatches;

  // =========================================================================
  // Snapshot and Screenshot
  // =========================================================================

  /// Capture a snapshot of the current screen.
  Future<BackendSnapshotResult> captureSnapshot(
    BackendCommandContext ctx,
    BackendSnapshotOptions? options,
  );

  /// Take a screenshot and save it to the given path.
  Future<BackendScreenshotResult?> captureScreenshot(
    BackendCommandContext ctx,
    String outPath,
    BackendScreenshotOptions? options,
  );

  // =========================================================================
  // Text Extraction
  // =========================================================================

  /// Read text from a snapshot node.
  Future<BackendReadTextResult> readText(
    BackendCommandContext ctx,
    Object node,
  );

  /// Find text on screen (exact match).
  Future<BackendFindTextResult> findText(
    BackendCommandContext ctx,
    String text,
  );

  // =========================================================================
  // Interaction: Tap and Scroll
  // =========================================================================

  /// Tap at a point.
  Future<BackendActionResult> tap(
    BackendCommandContext ctx,
    Point point,
    BackendTapOptions? options,
  );

  /// Tap to focus a text field and fill it.
  Future<BackendActionResult> fill(
    BackendCommandContext ctx,
    Point point,
    String text,
    BackendFillOptions? options,
  );

  /// Type text (after a fill or manual focus).
  Future<BackendActionResult> typeText(
    BackendCommandContext ctx,
    String text, [
    Map<String, Object?>? options,
  ]);

  /// Focus a text field without typing.
  Future<BackendActionResult> focus(BackendCommandContext ctx, Point point);

  /// Long-press at a point.
  Future<BackendActionResult> longPress(
    BackendCommandContext ctx,
    Point point,
    BackendLongPressOptions? options,
  );

  /// Swipe from one point to another.
  Future<BackendActionResult> swipe(
    BackendCommandContext ctx,
    Point from,
    Point to,
    BackendSwipeOptions? options,
  );

  /// Scroll in a direction on the viewport or at a point.
  Future<BackendActionResult> scroll(
    BackendCommandContext ctx,
    BackendScrollTarget target,
    BackendScrollOptions options,
  );

  /// Pinch to zoom.
  Future<BackendActionResult> pinch(
    BackendCommandContext ctx,
    BackendPinchOptions options,
  );

  // =========================================================================
  // Keyboard and Navigation
  // =========================================================================

  /// Press a key (e.g. 'Return', 'Escape').
  Future<BackendActionResult> pressKey(
    BackendCommandContext ctx,
    String key, [
    Map<String, Object?>? options,
  ]);

  /// Press the back button.
  Future<BackendActionResult> pressBack(
    BackendCommandContext ctx,
    BackendBackOptions? options,
  );

  /// Press the home button.
  Future<BackendActionResult> pressHome(BackendCommandContext ctx);

  /// Rotate the device.
  Future<BackendActionResult> rotate(
    BackendCommandContext ctx,
    BackendDeviceOrientation orientation,
  );

  /// Control the keyboard (show, hide, get status).
  Future<Object?> setKeyboard(
    BackendCommandContext ctx,
    BackendKeyboardOptions options,
  );

  // =========================================================================
  // Clipboard and Alerts
  // =========================================================================

  /// Get the current clipboard content.
  Future<String> getClipboard(BackendCommandContext ctx);

  /// Set the clipboard content.
  Future<BackendActionResult> setClipboard(
    BackendCommandContext ctx,
    String text,
  );

  /// Handle an alert (get, accept, dismiss, wait).
  Future<BackendAlertResult> handleAlert(
    BackendCommandContext ctx,
    BackendAlertAction action, [
    Map<String, Object?>? options,
  ]);

  // =========================================================================
  // App Management
  // =========================================================================

  /// Open system settings.
  Future<BackendActionResult> openSettings(
    BackendCommandContext ctx, [
    String? target,
  ]);

  /// Open the app switcher.
  Future<BackendActionResult> openAppSwitcher(BackendCommandContext ctx);

  /// Open an app or URL.
  Future<BackendActionResult> openApp(
    BackendCommandContext ctx,
    BackendOpenTarget target,
    BackendOpenOptions? options,
  );

  /// Close an app.
  Future<BackendActionResult> closeApp(
    BackendCommandContext ctx, [
    String? app,
  ]);

  /// List installed apps.
  Future<List<BackendAppInfo>> listApps(
    BackendCommandContext ctx, [
    BackendAppListFilter? filter,
  ]);

  /// Get the current state of an app.
  Future<BackendAppState> getAppState(BackendCommandContext ctx, String app);

  // =========================================================================
  // File Operations and Events
  // =========================================================================

  /// Push a file to the device.
  Future<BackendActionResult> pushFile(
    BackendCommandContext ctx,
    BackendPushInput input,
    String target,
  );

  /// Trigger an event on the app.
  Future<BackendActionResult> triggerAppEvent(
    BackendCommandContext ctx,
    BackendAppEvent event,
  );

  // =========================================================================
  // Device Management
  // =========================================================================

  /// List available devices matching an optional filter.
  Future<List<BackendDeviceInfo>> listDevices(
    BackendCommandContext ctx, [
    BackendDeviceFilter? filter,
  ]);

  /// Boot a device.
  Future<BackendActionResult> bootDevice(
    BackendCommandContext ctx, [
    BackendDeviceTarget? target,
  ]);

  /// Ensure a simulator exists and is ready.
  Future<BackendEnsureSimulatorResult> ensureSimulator(
    BackendCommandContext ctx,
    BackendEnsureSimulatorOptions options,
  );

  /// Resolve an install source to a concrete location (e.g. expand a URL).
  Future<BackendInstallSource> resolveInstallSource(
    BackendCommandContext ctx,
    BackendInstallSource source,
  );

  /// Install an app on the device.
  Future<BackendInstallResult> installApp(
    BackendCommandContext ctx,
    BackendInstallTarget target,
  );

  /// Reinstall an app.
  Future<BackendInstallResult> reinstallApp(
    BackendCommandContext ctx,
    BackendInstallTarget target,
  );

  // =========================================================================
  // Recording and Tracing
  // =========================================================================

  /// Start recording video.
  Future<BackendRecordingResult> startRecording(
    BackendCommandContext ctx,
    BackendRecordingOptions? options,
  );

  /// Stop recording and return the result.
  Future<BackendRecordingResult> stopRecording(
    BackendCommandContext ctx,
    BackendRecordingOptions? options,
  );

  /// Start a trace (profiling, system trace, etc.).
  Future<BackendTraceResult> startTrace(
    BackendCommandContext ctx,
    BackendTraceOptions? options,
  );

  /// Stop tracing and return the result.
  Future<BackendTraceResult> stopTrace(
    BackendCommandContext ctx,
    BackendTraceOptions? options,
  );

  // =========================================================================
  // Diagnostics: Logs, Network, Performance
  // =========================================================================

  /// Read logs from the device.
  Future<BackendReadLogsResult> readLogs(
    BackendCommandContext ctx,
    BackendReadLogsOptions? options,
  );

  /// Dump network activity.
  Future<BackendDumpNetworkResult> dumpNetwork(
    BackendCommandContext ctx,
    BackendDumpNetworkOptions? options,
  );

  /// Measure performance metrics.
  Future<BackendMeasurePerfResult> measurePerf(
    BackendCommandContext ctx,
    BackendMeasurePerfOptions? options,
  );
}

// ============================================================================
// Utility Functions for Capabilities
// ============================================================================

/// Check if a backend has a capability.
bool hasBackendCapability(Backend backend, BackendCapabilityName capability) {
  final caps = backend.capabilities;
  return caps != null && caps.contains(capability);
}

/// Check if a backend has an escape hatch method for a capability.
bool hasBackendEscapeHatch(Backend backend, BackendCapabilityName capability) {
  final hatches = backend.escapeHatches;
  if (hatches == null) return false;

  // Checking function types for presence (not null comparison).
  // ignore: unnecessary_null_comparison
  final hasAndroidShell = hatches.androidShell != null;
  // ignore: unnecessary_null_comparison
  final hasIosRunner = hatches.iosRunnerCommand != null;
  // ignore: unnecessary_null_comparison
  final hasMacosScreenshot = hatches.macosDesktopScreenshot != null;

  return switch (capability) {
    BackendCapabilityName.androidShell => hasAndroidShell,
    BackendCapabilityName.iosRunnerCommand => hasIosRunner,
    BackendCapabilityName.macosDesktopScreenshot => hasMacosScreenshot,
  };
}
