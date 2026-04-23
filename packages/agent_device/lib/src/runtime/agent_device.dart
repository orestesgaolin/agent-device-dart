// Dart-native runtime façade over [Backend]. Not a direct TS port — the
// TS source uses `bindCommands` to dynamically attach ~40 methods onto a
// runtime object, which doesn't translate cleanly to Dart. This class
// exposes the same capabilities via typed Dart methods and is the library
// surface other Dart packages consume.
library;

import 'package:agent_device/src/backend/backend.dart';
import 'package:agent_device/src/platforms/platform_selector.dart';
import 'package:agent_device/src/snapshot/snapshot.dart';
import 'package:agent_device/src/utils/errors.dart';

import 'contract.dart';
import 'session_store.dart';

/// Selector filter used by [AgentDevice.open] to pick which connected
/// device to bind a session to. At least one of [serial], [name], or
/// [platform] should be provided to narrow down multi-device setups.
class DeviceSelector {
  final PlatformSelector? platform;
  final String? serial;
  final String? name;

  const DeviceSelector({this.platform, this.serial, this.name});

  bool _matches(BackendDeviceInfo device) {
    if (serial != null && device.id != serial) return false;
    if (name != null && device.name != name) return false;
    return true;
  }
}

/// The programmatic façade that SDK consumers drive. Construct one via
/// [AgentDevice.open]; every command call resolves the currently-bound
/// device from session state and dispatches to the underlying [Backend].
///
/// Example:
/// ```dart
/// final device = await AgentDevice.open(backend: const AndroidBackend());
/// await device.openApp('settings');
/// final snap = await device.snapshot();
/// print('captured ${snap.nodes.length} nodes');
/// await device.close();
/// ```
class AgentDevice {
  final Backend backend;
  final CommandSessionStore sessions;
  final CommandPolicy policy;
  final CommandClock clock;
  final DiagnosticsSink? diagnostics;

  /// Name of the session this façade is bound to (default: 'default').
  final String sessionName;

  /// Info about the device that was resolved when [open] ran. Read-only.
  final BackendDeviceInfo device;

  AgentDevice._({
    required this.backend,
    required this.sessions,
    required this.policy,
    required this.clock,
    required this.sessionName,
    required this.device,
    this.diagnostics,
  });

  /// Open a session, resolving one matching device via
  /// [Backend.listDevices] and caching it in the session store.
  ///
  /// If multiple devices match [selector] and none is explicitly
  /// identified by [DeviceSelector.serial] or [DeviceSelector.name],
  /// the first one returned is picked.
  ///
  /// Throws [AppError] with [AppErrorCodes.deviceNotFound] if no device
  /// matches.
  static Future<AgentDevice> open({
    required Backend backend,
    DeviceSelector selector = const DeviceSelector(),
    String sessionName = 'default',
    CommandSessionStore? sessions,
    CommandPolicy policy = localCommandPolicy,
    CommandClock clock = const SystemClock(),
    DiagnosticsSink? diagnostics,
  }) async {
    final store = sessions ?? createMemorySessionStore();
    final devices = await backend.listDevices(
      BackendCommandContext(session: sessionName),
      selector.platform == null
          ? null
          : BackendDeviceFilter(
              platform: _toBackendPlatform(selector.platform!),
            ),
    );
    final filtered = devices.where(selector._matches).toList();
    if (filtered.isEmpty) {
      throw AppError(
        AppErrorCodes.deviceNotFound,
        'No device matches the selector',
        details: {
          if (selector.platform != null)
            'platform': platformSelectorToString(selector.platform!),
          if (selector.serial != null) 'serial': selector.serial,
          if (selector.name != null) 'name': selector.name,
          'available': devices.map((d) => d.id).toList(),
        },
      );
    }
    final picked = filtered.first;
    // Preserve any existing session fields (appId, metadata, etc.) — we
    // only want to refresh the deviceSerial. Matters for cross-invocation
    // session sharing: without this merge, every CLI invocation would
    // reset the record to `{name, deviceSerial}` and lose the previously
    // opened app id.
    final existing = await store.get(sessionName);
    final merged = (existing ?? CommandSessionRecord(name: sessionName))
        .copyWith(deviceSerial: picked.id);
    await store.set(merged);
    return AgentDevice._(
      backend: backend,
      sessions: store,
      policy: policy,
      clock: clock,
      sessionName: sessionName,
      device: picked,
      diagnostics: diagnostics,
    );
  }

  /// Build a [BackendCommandContext] carrying this session's metadata
  /// plus the resolved device serial.
  Future<BackendCommandContext> _ctx() async {
    final record = await sessions.get(sessionName);
    return BackendCommandContext(
      session: sessionName,
      appId: record?.appId,
      appBundleId: record?.appBundleId,
      deviceSerial: record?.deviceSerial ?? device.id,
    );
  }

  /// Persist a session-state mutation. Merges onto the existing record
  /// with [CommandSessionRecord.copyWith] semantics. Pass field names in
  /// [clear] to reset them to `null` (Dart optional-named-parameters can't
  /// distinguish "null" from "not specified", so a sentinel set is needed).
  Future<void> _updateSession({
    String? appId,
    String? appBundleId,
    String? appName,
    SnapshotState? snapshot,
    Set<String> clear = const {},
  }) async {
    final current =
        await sessions.get(sessionName) ??
        CommandSessionRecord(name: sessionName, deviceSerial: device.id);
    await sessions.set(
      current.copyWith(
        appId: appId,
        appBundleId: appBundleId,
        appName: appName,
        snapshot: snapshot,
        clearFields: clear,
      ),
    );
  }

  // =========================================================================
  // Snapshot & Screenshot
  // =========================================================================

  /// Capture a snapshot of the current screen.
  Future<BackendSnapshotResult> snapshot({
    bool? interactiveOnly,
    bool? compact,
    int? depth,
    String? scope,
    bool? raw,
  }) async {
    return backend.captureSnapshot(
      await _ctx(),
      BackendSnapshotOptions(
        interactiveOnly: interactiveOnly,
        compact: compact,
        depth: depth,
        scope: scope,
        raw: raw,
      ),
    );
  }

  /// Capture a screenshot to [outPath]. Returns null if the backend
  /// declines (not all backends produce a file).
  Future<BackendScreenshotResult?> screenshot(
    String outPath, {
    bool? overlayRefs,
    bool? fullscreen,
  }) {
    return backend.captureScreenshot(
      BackendCommandContext(session: sessionName, deviceSerial: device.id),
      outPath,
      BackendScreenshotOptions(
        overlayRefs: overlayRefs,
        fullscreen: fullscreen,
      ),
    );
  }

  // =========================================================================
  // Interaction
  // =========================================================================

  Future<void> tap(num x, num y, {BackendTapOptions? options}) async {
    await backend.tap(
      await _ctx(),
      Point(x: x.toDouble(), y: y.toDouble()),
      options,
    );
  }

  Future<void> fill(num x, num y, String text, {int? delayMs}) async {
    await backend.fill(
      await _ctx(),
      Point(x: x.toDouble(), y: y.toDouble()),
      text,
      delayMs == null ? null : BackendFillOptions(delayMs: delayMs),
    );
  }

  Future<void> typeText(String text, {int? delayMs}) async {
    await backend.typeText(
      await _ctx(),
      text,
      delayMs == null ? null : {'delayMs': delayMs},
    );
  }

  Future<void> focus(num x, num y) async {
    await backend.focus(await _ctx(), Point(x: x.toDouble(), y: y.toDouble()));
  }

  Future<void> longPress(num x, num y, {int? durationMs}) async {
    await backend.longPress(
      await _ctx(),
      Point(x: x.toDouble(), y: y.toDouble()),
      durationMs == null
          ? null
          : BackendLongPressOptions(durationMs: durationMs),
    );
  }

  Future<void> swipe(num x1, num y1, num x2, num y2, {int? durationMs}) async {
    await backend.swipe(
      await _ctx(),
      Point(x: x1.toDouble(), y: y1.toDouble()),
      Point(x: x2.toDouble(), y: y2.toDouble()),
      durationMs == null ? null : BackendSwipeOptions(durationMs: durationMs),
    );
  }

  /// Pinch to zoom. `scale < 1` zooms out, `scale > 1` zooms in.
  Future<void> pinch({required double scale, Point? center}) async {
    await backend.pinch(
      await _ctx(),
      BackendPinchOptions(scale: scale, center: center),
    );
  }

  /// Scroll in a [direction] (`'up'`, `'down'`, `'left'`, `'right'`) on
  /// the viewport.
  Future<Object?> scroll(
    String direction, {
    int? amount,
    int? pixels,
    Point? at,
  }) async {
    final target = at == null
        ? const BackendScrollTargetViewport()
        : BackendScrollTargetPoint(at);
    return backend.scroll(
      await _ctx(),
      target,
      BackendScrollOptions(
        direction: direction,
        amount: amount,
        pixels: pixels,
      ),
    );
  }

  // =========================================================================
  // Navigation
  // =========================================================================

  Future<void> pressBack() async {
    await backend.pressBack(await _ctx(), null);
  }

  /// Press a named key (e.g. `'Return'`, `'Escape'`, `'Volume_Up'`).
  Future<void> pressKey(String key, {Map<String, Object?>? options}) async {
    await backend.pressKey(await _ctx(), key, options);
  }

  Future<void> pressHome() async {
    await backend.pressHome(await _ctx());
  }

  Future<void> openAppSwitcher() async {
    await backend.openAppSwitcher(await _ctx());
  }

  Future<void> rotate(BackendDeviceOrientation orientation) async {
    await backend.rotate(await _ctx(), orientation);
  }

  // =========================================================================
  // Clipboard & Keyboard
  // =========================================================================

  Future<String> getClipboard() async => backend.getClipboard(await _ctx());

  Future<void> setClipboard(String text) async {
    await backend.setClipboard(await _ctx(), text);
  }

  /// Control the keyboard. [action] is one of `'status'`, `'get'`,
  /// `'dismiss'`, `'hide'`.
  Future<Object?> setKeyboard(String action) async {
    return backend.setKeyboard(
      await _ctx(),
      BackendKeyboardOptions(action: action),
    );
  }

  // =========================================================================
  // Text Extraction & Alerts
  // =========================================================================

  /// Read accessible text from a snapshot node.
  Future<BackendReadTextResult> readText(Object node) async {
    return backend.readText(await _ctx(), node);
  }

  /// Search visible UI for [text] (exact match).
  Future<BackendFindTextResult> findText(String text) async {
    return backend.findText(await _ctx(), text);
  }

  /// Handle a system alert: `'get'`, `'accept'`, `'dismiss'`, `'wait'`.
  Future<BackendAlertResult> handleAlert(
    BackendAlertAction action, {
    Map<String, Object?>? options,
  }) async {
    return backend.handleAlert(await _ctx(), action, options);
  }

  /// Push a file (or JSON payload) to [target] on the device.
  Future<void> pushFile(BackendPushInput input, String target) async {
    await backend.pushFile(await _ctx(), input, target);
  }

  /// Open platform settings (optionally scoped to [target]).
  Future<void> openSettings([String? target]) async {
    await backend.openSettings(await _ctx(), target);
  }

  // =========================================================================
  // App Management
  // =========================================================================

  /// Open an app by id, package, bundle, URL, or intent alias. Updates
  /// the session with the resolved app id.
  Future<void> openApp(String target, {BackendOpenOptions? options}) async {
    await backend.openApp(
      await _ctx(),
      BackendOpenTarget(app: target),
      options,
    );
    await _updateSession(appId: target);
  }

  Future<void> closeApp([String? app]) async {
    final resolved = app ?? (await sessions.get(sessionName))?.appId;
    await backend.closeApp(await _ctx(), resolved);
    if (resolved != null &&
        resolved == (await sessions.get(sessionName))?.appId) {
      await _updateSession(clear: const {'appId'});
    }
  }

  Future<BackendAppState> getAppState([String? app]) async {
    final resolved = app ?? (await sessions.get(sessionName))?.appId ?? '';
    return backend.getAppState(await _ctx(), resolved);
  }

  Future<List<BackendAppInfo>> listApps({BackendAppListFilter? filter}) async {
    return backend.listApps(await _ctx(), filter);
  }

  Future<Object?> triggerAppEvent(
    String name, {
    Map<String, Object?>? payload,
  }) async {
    return backend.triggerAppEvent(
      await _ctx(),
      BackendAppEvent(name: name, payload: payload),
    );
  }

  // =========================================================================
  // Device Management
  // =========================================================================

  /// List all visible devices. Bypasses session state — callable before
  /// [open].
  static Future<List<BackendDeviceInfo>> listDevices(
    Backend backend, {
    PlatformSelector? platform,
  }) => backend.listDevices(
    const BackendCommandContext(),
    platform == null
        ? null
        : BackendDeviceFilter(platform: _toBackendPlatform(platform)),
  );

  Future<Object?> bootDevice({String? name}) async {
    return backend.bootDevice(
      await _ctx(),
      name == null ? null : BackendDeviceTarget(name: name),
    );
  }

  Future<BackendInstallResult> installApp({
    required String path,
    String? app,
  }) async {
    return backend.installApp(
      await _ctx(),
      BackendInstallTarget(app: app, source: BackendInstallSourcePath(path)),
    );
  }

  Future<BackendInstallResult> reinstallApp({
    required String path,
    required String app,
  }) async {
    return backend.reinstallApp(
      await _ctx(),
      BackendInstallTarget(app: app, source: BackendInstallSourcePath(path)),
    );
  }

  // =========================================================================
  // Lifecycle
  // =========================================================================

  /// Close the session. Clears the stored record; does not kill the
  /// currently-running app unless [closeCurrentApp] is true.
  Future<void> close({bool closeCurrentApp = false}) async {
    if (closeCurrentApp) {
      final appId = (await sessions.get(sessionName))?.appId;
      if (appId != null && appId.isNotEmpty) {
        try {
          await backend.closeApp(await _ctx(), appId);
        } on AppError {
          // Best-effort; the session teardown continues regardless.
        }
      }
    }
    await sessions.delete(sessionName);
  }
}

/// Bridge PlatformSelector (Dart port enum used by CLI / replay) to
/// [AgentDeviceBackendPlatform] (backend-layer enum, no `apple` variant).
/// The selector's `apple` value is mapped to iOS since Android's
/// [BackendDeviceFilter] only accepts concrete platforms.
AgentDeviceBackendPlatform _toBackendPlatform(PlatformSelector p) =>
    switch (p) {
      PlatformSelector.ios => AgentDeviceBackendPlatform.ios,
      PlatformSelector.android => AgentDeviceBackendPlatform.android,
      PlatformSelector.macos => AgentDeviceBackendPlatform.macos,
      PlatformSelector.linux => AgentDeviceBackendPlatform.linux,
      PlatformSelector.apple => AgentDeviceBackendPlatform.ios,
    };
