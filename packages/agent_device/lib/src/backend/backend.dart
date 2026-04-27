// Port of agent-device/src/backend.ts
library;

import 'package:agent_device/src/snapshot/snapshot.dart';
import 'package:agent_device/src/utils/errors.dart';

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
///
/// TS-source counterpart: `BackendCommandContext` in `src/backend.ts`. The
/// [deviceSerial] field is a Dart-port-only addition; the TS runtime resolves
/// the device from session state inside each dispatcher, but the Dart port's
/// Wave A/B/C platform functions take a `String serial` directly, so the
/// runtime (Phase 4) populates this field before calling the backend.
class BackendCommandContext {
  final String? session;
  final String? requestId;
  final String? appId;
  final String? appBundleId;
  final String? deviceSerial;
  final Map<String, Object?>? metadata;

  const BackendCommandContext({
    this.session,
    this.requestId,
    this.appId,
    this.appBundleId,
    this.deviceSerial,
    this.metadata,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    if (session != null) 'session': session,
    if (requestId != null) 'requestId': requestId,
    if (appId != null) 'appId': appId,
    if (appBundleId != null) 'appBundleId': appBundleId,
    if (deviceSerial != null) 'deviceSerial': deviceSerial,
    if (metadata != null) 'metadata': metadata,
  };
}

// ============================================================================
// Action Result Type
// ============================================================================

/// Result type for generic actions (may be void or a map of properties).
typedef BackendActionResult = Object?;

// ============================================================================
// Backend
// ============================================================================

/// Platform-abstract backend.
///
/// Every method has a default implementation that throws
/// [AppErrorCodes.unsupportedOperation]. Subclasses (e.g. `AndroidBackend`)
/// override only the methods the platform supports. This mirrors the TS
/// source, where `AgentDeviceBackend` is a structural type and consumers
/// construct partial objects declaring only the methods they need.
///
/// The only abstract member is [platform] — every backend must declare
/// which platform it targets.
abstract class Backend {
  const Backend();

  /// The platform this backend targets. Every subclass must declare this.
  AgentDeviceBackendPlatform get platform;

  /// Capabilities that this backend reports as supported. Defaults to `null`.
  BackendCapabilitySet? get capabilities => null;

  /// Throws [AppError] with [AppErrorCodes.unsupportedOperation] to indicate
  /// the concrete backend does not support [method]. Used as the default
  /// implementation for every non-overridden method below.
  Never unsupported(String method) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      '$method is not supported on ${platform.name} backend',
    );
  }

  // =========================================================================
  // Snapshot and Screenshot
  // =========================================================================

  /// Capture a snapshot of the current screen.
  Future<BackendSnapshotResult> captureSnapshot(
    BackendCommandContext ctx,
    BackendSnapshotOptions? options,
  ) async => unsupported('captureSnapshot');

  /// Take a screenshot and save it to the given path.
  Future<BackendScreenshotResult?> captureScreenshot(
    BackendCommandContext ctx,
    String outPath,
    BackendScreenshotOptions? options,
  ) async => unsupported('captureScreenshot');

  // =========================================================================
  // Text Extraction
  // =========================================================================

  /// Read text from a snapshot node.
  Future<BackendReadTextResult> readText(
    BackendCommandContext ctx,
    Object node,
  ) async => unsupported('readText');

  /// Find text on screen (exact match).
  Future<BackendFindTextResult> findText(
    BackendCommandContext ctx,
    String text,
  ) async => unsupported('findText');

  // =========================================================================
  // Interaction: Tap and Scroll
  // =========================================================================

  /// Tap at a point.
  Future<BackendActionResult> tap(
    BackendCommandContext ctx,
    Point point,
    BackendTapOptions? options,
  ) async => unsupported('tap');

  /// Tap to focus a text field and fill it.
  Future<BackendActionResult> fill(
    BackendCommandContext ctx,
    Point point,
    String text,
    BackendFillOptions? options,
  ) async => unsupported('fill');

  /// Type text (after a fill or manual focus).
  Future<BackendActionResult> typeText(
    BackendCommandContext ctx,
    String text, [
    Map<String, Object?>? options,
  ]) async => unsupported('typeText');

  /// Focus a text field without typing.
  Future<BackendActionResult> focus(
    BackendCommandContext ctx,
    Point point,
  ) async => unsupported('focus');

  /// Long-press at a point.
  Future<BackendActionResult> longPress(
    BackendCommandContext ctx,
    Point point,
    BackendLongPressOptions? options,
  ) async => unsupported('longPress');

  /// Swipe from one point to another.
  Future<BackendActionResult> swipe(
    BackendCommandContext ctx,
    Point from,
    Point to,
    BackendSwipeOptions? options,
  ) async => unsupported('swipe');

  /// Scroll in a direction on the viewport or at a point.
  Future<BackendActionResult> scroll(
    BackendCommandContext ctx,
    BackendScrollTarget target,
    BackendScrollOptions options,
  ) async => unsupported('scroll');

  /// Pinch to zoom.
  Future<BackendActionResult> pinch(
    BackendCommandContext ctx,
    BackendPinchOptions options,
  ) async => unsupported('pinch');

  // =========================================================================
  // Keyboard and Navigation
  // =========================================================================

  /// Press a key (e.g. 'Return', 'Escape').
  Future<BackendActionResult> pressKey(
    BackendCommandContext ctx,
    String key, [
    Map<String, Object?>? options,
  ]) async => unsupported('pressKey');

  /// Press the back button.
  Future<BackendActionResult> pressBack(
    BackendCommandContext ctx,
    BackendBackOptions? options,
  ) async => unsupported('pressBack');

  /// Press the home button.
  Future<BackendActionResult> pressHome(BackendCommandContext ctx) async =>
      unsupported('pressHome');

  /// Rotate the device.
  Future<BackendActionResult> rotate(
    BackendCommandContext ctx,
    BackendDeviceOrientation orientation,
  ) async => unsupported('rotate');

  /// Control the keyboard (show, hide, get status).
  Future<Object?> setKeyboard(
    BackendCommandContext ctx,
    BackendKeyboardOptions options,
  ) async => unsupported('setKeyboard');

  // =========================================================================
  // Clipboard and Alerts
  // =========================================================================

  /// Get the current clipboard content.
  Future<String> getClipboard(BackendCommandContext ctx) async =>
      unsupported('getClipboard');

  /// Set the clipboard content.
  Future<BackendActionResult> setClipboard(
    BackendCommandContext ctx,
    String text,
  ) async => unsupported('setClipboard');

  /// Handle an alert (get, accept, dismiss, wait).
  Future<BackendAlertResult> handleAlert(
    BackendCommandContext ctx,
    BackendAlertAction action, [
    Map<String, Object?>? options,
  ]) async => unsupported('handleAlert');

  // =========================================================================
  // App Management
  // =========================================================================

  /// Open system settings.
  Future<BackendActionResult> openSettings(
    BackendCommandContext ctx, [
    String? target,
  ]) async => unsupported('openSettings');

  /// Open the app switcher.
  Future<BackendActionResult> openAppSwitcher(
    BackendCommandContext ctx,
  ) async => unsupported('openAppSwitcher');

  /// Open an app or URL.
  Future<BackendActionResult> openApp(
    BackendCommandContext ctx,
    BackendOpenTarget target,
    BackendOpenOptions? options,
  ) async => unsupported('openApp');

  /// Close an app.
  Future<BackendActionResult> closeApp(
    BackendCommandContext ctx, [
    String? app,
  ]) async => unsupported('closeApp');

  /// List installed apps.
  Future<List<BackendAppInfo>> listApps(
    BackendCommandContext ctx, [
    BackendAppListFilter? filter,
  ]) async => unsupported('listApps');

  /// Get the current state of an app.
  Future<BackendAppState> getAppState(
    BackendCommandContext ctx,
    String app,
  ) async => unsupported('getAppState');

  // =========================================================================
  // File Operations and Events
  // =========================================================================

  /// Push a file to the device.
  Future<BackendActionResult> pushFile(
    BackendCommandContext ctx,
    BackendPushInput input,
    String target,
  ) async => unsupported('pushFile');

  /// Trigger an event on the app.
  Future<BackendActionResult> triggerAppEvent(
    BackendCommandContext ctx,
    BackendAppEvent event,
  ) async => unsupported('triggerAppEvent');

  // =========================================================================
  // Device Management
  // =========================================================================

  /// List available devices matching an optional filter.
  Future<List<BackendDeviceInfo>> listDevices(
    BackendCommandContext ctx, [
    BackendDeviceFilter? filter,
  ]) async => unsupported('listDevices');

  /// Boot a device.
  Future<BackendActionResult> bootDevice(
    BackendCommandContext ctx, [
    BackendDeviceTarget? target,
  ]) async => unsupported('bootDevice');

  /// Ensure a simulator exists and is ready.
  Future<BackendEnsureSimulatorResult> ensureSimulator(
    BackendCommandContext ctx,
    BackendEnsureSimulatorOptions options,
  ) async => unsupported('ensureSimulator');

  /// Resolve an install source to a concrete location (e.g. expand a URL).
  Future<BackendInstallSource> resolveInstallSource(
    BackendCommandContext ctx,
    BackendInstallSource source,
  ) async => unsupported('resolveInstallSource');

  /// Install an app on the device.
  Future<BackendInstallResult> installApp(
    BackendCommandContext ctx,
    BackendInstallTarget target,
  ) async => unsupported('installApp');

  /// Uninstall an app by bundle id / package name. Returns the
  /// resolved app identity even when the app wasn't installed (no-op
  /// success) so callers get consistent telemetry.
  Future<BackendInstallResult> uninstallApp(
    BackendCommandContext ctx,
    String app,
  ) async => unsupported('uninstallApp');

  /// Reinstall an app.
  Future<BackendInstallResult> reinstallApp(
    BackendCommandContext ctx,
    BackendInstallTarget target,
  ) async => unsupported('reinstallApp');

  /// Reset the device keychain (simulator only).
  Future<void> resetKeychain(BackendCommandContext ctx) async =>
      unsupported('resetKeychain');

  // =========================================================================
  // Recording and Tracing
  // =========================================================================

  /// Start recording video.
  Future<BackendRecordingResult> startRecording(
    BackendCommandContext ctx,
    BackendRecordingOptions? options,
  ) async => unsupported('startRecording');

  /// Stop recording and return the result.
  Future<BackendRecordingResult> stopRecording(
    BackendCommandContext ctx,
    BackendRecordingOptions? options,
  ) async => unsupported('stopRecording');

  /// Start a trace (profiling, system trace, etc.).
  Future<BackendTraceResult> startTrace(
    BackendCommandContext ctx,
    BackendTraceOptions? options,
  ) async => unsupported('startTrace');

  /// Stop tracing and return the result.
  Future<BackendTraceResult> stopTrace(
    BackendCommandContext ctx,
    BackendTraceOptions? options,
  ) async => unsupported('stopTrace');

  // =========================================================================
  // Diagnostics: Logs, Network, Performance
  // =========================================================================

  /// Read logs from the device.
  Future<BackendReadLogsResult> readLogs(
    BackendCommandContext ctx,
    BackendReadLogsOptions? options,
  ) async => unsupported('readLogs');

  /// Begin streaming device logs to a host file. Runs a background
  /// process (e.g. `adb logcat` / `simctl spawn log stream`) whose PID
  /// is persisted on disk so a later invocation can [stopLogStream].
  Future<BackendLogStreamResult> startLogStream(
    BackendCommandContext ctx,
    BackendLogStreamOptions options,
  ) async => unsupported('startLogStream');

  /// Stop the currently-running log stream for the ctx's device.
  /// Returns the final on-disk size + stop timestamp.
  Future<BackendLogStreamResult> stopLogStream(
    BackendCommandContext ctx,
  ) async => unsupported('stopLogStream');

  /// Dump network activity.
  Future<BackendDumpNetworkResult> dumpNetwork(
    BackendCommandContext ctx,
    BackendDumpNetworkOptions? options,
  ) async => unsupported('dumpNetwork');

  /// Measure performance metrics.
  Future<BackendMeasurePerfResult> measurePerf(
    BackendCommandContext ctx,
    BackendMeasurePerfOptions? options,
  ) async => unsupported('measurePerf');
}

// ============================================================================
// Utility Functions for Capabilities
// ============================================================================

/// Check if a backend has a capability.
bool hasBackendCapability(Backend backend, BackendCapabilityName capability) {
  final caps = backend.capabilities;
  return caps != null && caps.contains(capability);
}
