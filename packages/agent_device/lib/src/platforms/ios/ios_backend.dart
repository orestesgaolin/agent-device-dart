// Phase 8A iOS backend — MVP subset that covers read-only/lifecycle
// commands without the XCUITest runner. Snapshot, tap, fill, scroll and
// other runner-dependent methods fall through to the Backend default
// `unsupported` and will be wired in Phase 8B once runner-transport /
// runner-session / runner-xctestrun are ported.
library;

import 'package:agent_device/src/backend/backend.dart';

import 'app_lifecycle.dart';
import 'devices.dart';
import 'screenshot.dart';

class IosBackend extends Backend {
  const IosBackend();

  @override
  AgentDeviceBackendPlatform get platform => AgentDeviceBackendPlatform.ios;

  /// Phase 8A treats `BackendCommandContext.deviceSerial` as the iOS
  /// simulator UDID — same plumbing as the Android `serial`.
  String _udid(BackendCommandContext ctx) {
    final udid = ctx.deviceSerial;
    if (udid == null || udid.isEmpty) {
      unsupported('operation requires ctx.deviceSerial (simulator UDID)');
    }
    return udid;
  }

  // =========================================================================
  // Snapshot & Screenshot — only screenshot is wired in Phase 8A.
  // =========================================================================

  @override
  Future<BackendScreenshotResult?> captureScreenshot(
    BackendCommandContext ctx,
    String outPath,
    BackendScreenshotOptions? options,
  ) async {
    await screenshotIos(_udid(ctx), outPath);
    return BackendScreenshotResult(path: outPath);
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
    final bundleId = target.bundleId ?? target.appId ?? target.app;
    if (bundleId == null || bundleId.isEmpty) {
      unsupported(
        'openApp on iOS requires target.bundleId / appId / app (a bundle id)',
      );
    }
    await openIosApp(_udid(ctx), bundleId);
    return null;
  }

  @override
  Future<BackendActionResult> closeApp(
    BackendCommandContext ctx, [
    String? app,
  ]) async {
    if (app == null || app.isEmpty) {
      unsupported('closeApp on iOS requires a bundle id');
    }
    await closeIosApp(_udid(ctx), app);
    return null;
  }

  @override
  Future<List<BackendAppInfo>> listApps(
    BackendCommandContext ctx, [
    BackendAppListFilter? filter,
  ]) async {
    // `userInstalled` -> skip system apps; otherwise include system too.
    final userOnly = filter == BackendAppListFilter.userInstalled;
    final apps = await listIosApps(_udid(ctx), userOnly: userOnly);
    return apps
        .map(
          (a) => BackendAppInfo(
            id: a.bundleId,
            name: a.name,
            bundleId: a.bundleId,
          ),
        )
        .toList();
  }

  @override
  Future<BackendAppState> getAppState(
    BackendCommandContext ctx,
    String app,
  ) async {
    final fg = await getIosForeground(_udid(ctx));
    return BackendAppState(
      appId: fg.bundleId,
      bundleId: fg.bundleId,
      state: fg.bundleId == null ? 'unknown' : 'foreground',
    );
  }

  // =========================================================================
  // Device Management
  // =========================================================================

  @override
  Future<List<BackendDeviceInfo>> listDevices(
    BackendCommandContext ctx, [
    BackendDeviceFilter? filter,
  ]) async {
    final simulators = await listAppleSimulators();
    if (filter == null) return simulators;
    // Filter by "booted" unless the caller explicitly asked for all.
    // (Android's filter honors `kind`; iOS's shape is similar.) For MVP
    // just return every simulator — callers that want booted only can
    // filter on the result in the runtime layer.
    return simulators;
  }
}
