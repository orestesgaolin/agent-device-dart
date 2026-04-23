// Port of agent-device/src/platforms/android/index.ts

import 'package:agent_device/src/backend/backend.dart';
import 'package:agent_device/src/core/device_rotation.dart';
import 'package:agent_device/src/snapshot/snapshot.dart';

import 'app_lifecycle.dart';
import 'device_input_state.dart';
import 'devices.dart';
import 'input_actions.dart';
import 'screenshot.dart';
import 'snapshot.dart';

/// Android platform backend.
///
/// Delegates to the Wave A/B/C1/C2 Android module functions. Only methods
/// the TS Android platform actually exposes are wired; the rest inherit
/// the `unsupported` default from [Backend].
///
/// The TS source (`src/platforms/android/index.ts`) is a barrel of function
/// exports, not a class — `src/core/dispatch.ts` calls them directly based
/// on `device.platform`. The Dart port wraps the same functions behind a
/// [Backend] subclass so the runtime dispatcher (Phase 4) can treat all
/// platforms uniformly.
///
/// Device serial resolution: Wave C Android functions take a `String serial`
/// as first argument. The Dart-port-specific [BackendCommandContext.deviceSerial]
/// field carries it; Phase 4 runtime populates it from session state.
class AndroidBackend extends Backend {
  const AndroidBackend();

  @override
  AgentDeviceBackendPlatform get platform => AgentDeviceBackendPlatform.android;

  String _serial(BackendCommandContext ctx) {
    final serial = ctx.deviceSerial;
    if (serial == null || serial.isEmpty) {
      unsupported(
        'operation requires ctx.deviceSerial populated by the runtime',
      );
    }
    return serial;
  }

  // =========================================================================
  // Snapshot and Screenshot
  // =========================================================================

  @override
  Future<BackendSnapshotResult> captureSnapshot(
    BackendCommandContext ctx,
    BackendSnapshotOptions? options,
  ) async {
    final opts = SnapshotOptions(
      interactiveOnly: options?.interactiveOnly,
      compact: options?.compact,
      depth: options?.depth,
      scope: options?.scope,
      raw: options?.raw,
    );
    final result = await snapshotAndroid(_serial(ctx), options: opts);
    return BackendSnapshotResult(
      nodes: result.nodes,
      truncated: result.truncated,
      analysis: BackendSnapshotAnalysis(
        rawNodeCount: result.analysis.rawNodeCount,
        maxDepth: result.analysis.maxDepth,
      ),
    );
  }

  @override
  Future<BackendScreenshotResult?> captureScreenshot(
    BackendCommandContext ctx,
    String outPath,
    BackendScreenshotOptions? options,
  ) async {
    await screenshotAndroid(_serial(ctx), outPath);
    return BackendScreenshotResult(path: outPath);
  }

  // =========================================================================
  // Interaction
  // =========================================================================

  @override
  Future<BackendActionResult> tap(
    BackendCommandContext ctx,
    Point point,
    BackendTapOptions? options,
  ) async {
    await pressAndroid(_serial(ctx), point.x.round(), point.y.round());
    return null;
  }

  @override
  Future<BackendActionResult> fill(
    BackendCommandContext ctx,
    Point point,
    String text,
    BackendFillOptions? options,
  ) async {
    await fillAndroid(
      _serial(ctx),
      point.x.round(),
      point.y.round(),
      text,
      options?.delayMs ?? 0,
    );
    return null;
  }

  @override
  Future<BackendActionResult> typeText(
    BackendCommandContext ctx,
    String text, [
    Map<String, Object?>? options,
  ]) async {
    final delayMs = (options?['delayMs'] as int?) ?? 0;
    await typeAndroid(_serial(ctx), text, delayMs);
    return null;
  }

  @override
  Future<BackendActionResult> focus(
    BackendCommandContext ctx,
    Point point,
  ) async {
    await focusAndroid(_serial(ctx), point.x.round(), point.y.round());
    return null;
  }

  @override
  Future<BackendActionResult> longPress(
    BackendCommandContext ctx,
    Point point,
    BackendLongPressOptions? options,
  ) async {
    await longPressAndroid(
      _serial(ctx),
      point.x.round(),
      point.y.round(),
      options?.durationMs ?? 800,
    );
    return null;
  }

  @override
  Future<BackendActionResult> swipe(
    BackendCommandContext ctx,
    Point from,
    Point to,
    BackendSwipeOptions? options,
  ) async {
    await swipeAndroid(
      _serial(ctx),
      from.x.round(),
      from.y.round(),
      to.x.round(),
      to.y.round(),
      options?.durationMs ?? 250,
    );
    return null;
  }

  // =========================================================================
  // Navigation
  // =========================================================================

  @override
  Future<BackendActionResult> pressBack(
    BackendCommandContext ctx,
    BackendBackOptions? options,
  ) async {
    await backAndroid(_serial(ctx));
    return null;
  }

  @override
  Future<BackendActionResult> pressHome(BackendCommandContext ctx) async {
    await homeAndroid(_serial(ctx));
    return null;
  }

  @override
  Future<BackendActionResult> rotate(
    BackendCommandContext ctx,
    BackendDeviceOrientation orientation,
  ) async {
    await rotateAndroid(_serial(ctx), _toDeviceRotation(orientation));
    return null;
  }

  @override
  Future<BackendActionResult> openAppSwitcher(BackendCommandContext ctx) async {
    await appSwitcherAndroid(_serial(ctx));
    return null;
  }

  // =========================================================================
  // Clipboard
  // =========================================================================

  @override
  Future<String> getClipboard(BackendCommandContext ctx) =>
      readAndroidClipboardText(_serial(ctx));

  @override
  Future<BackendActionResult> setClipboard(
    BackendCommandContext ctx,
    String text,
  ) async {
    await writeAndroidClipboardText(_serial(ctx), text);
    return null;
  }

  // =========================================================================
  // App Management
  // =========================================================================

  @override
  Future<BackendActionResult> openApp(
    BackendCommandContext ctx,
    BackendOpenTarget target,
    BackendOpenOptions? options,
  ) async {
    final app = target.app ?? target.appId ?? target.packageName ?? target.url;
    if (app == null || app.isEmpty) {
      unsupported(
        'openApp requires target.app/appId/packageName/url on Android',
      );
    }
    await openAndroidApp(_serial(ctx), app);
    return null;
  }

  @override
  Future<BackendActionResult> closeApp(
    BackendCommandContext ctx, [
    String? app,
  ]) async {
    if (app == null || app.isEmpty) {
      unsupported('closeApp requires an app id on Android');
    }
    await closeAndroidApp(_serial(ctx), app);
    return null;
  }

  @override
  Future<BackendAppState> getAppState(
    BackendCommandContext ctx,
    String app,
  ) async {
    final state = await getAndroidAppState(_serial(ctx));
    return BackendAppState(
      appId: state.package,
      packageName: state.package,
      activity: state.activity,
      state: state.package == null ? 'unknown' : 'foreground',
    );
  }

  // =========================================================================
  // Device Management
  // =========================================================================

  @override
  Future<List<BackendDeviceInfo>> listDevices(
    BackendCommandContext ctx, [
    BackendDeviceFilter? filter,
  ]) => listAndroidDevices();
}

DeviceRotation _toDeviceRotation(BackendDeviceOrientation o) => switch (o) {
  BackendDeviceOrientation.portrait => DeviceRotation.portrait,
  BackendDeviceOrientation.portraitUpsideDown =>
    DeviceRotation.portraitUpsideDown,
  BackendDeviceOrientation.landscapeLeft => DeviceRotation.landscapeLeft,
  BackendDeviceOrientation.landscapeRight => DeviceRotation.landscapeRight,
};
