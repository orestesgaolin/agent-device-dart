// Dart-native runtime façade over [Backend]. Not a direct TS port — the
// TS source uses `bindCommands` to dynamically attach ~40 methods onto a
// runtime object, which doesn't translate cleanly to Dart. This class
// exposes the same capabilities via typed Dart methods and is the library
// surface other Dart packages consume.
library;

import 'dart:io';

import 'package:agent_device/src/backend/backend.dart';
import 'package:agent_device/src/platforms/platform_selector.dart';
import 'package:agent_device/src/selectors/selectors.dart';
import 'package:agent_device/src/snapshot/snapshot.dart';
import 'package:agent_device/src/utils/errors.dart';
import 'package:agent_device/src/utils/png.dart' as png;

import 'contract.dart';
import 'interaction_target.dart';
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
  final CommandClock clock;

  /// Name of the session this façade is bound to (default: 'default').
  final String sessionName;

  /// Info about the device that was resolved when [open] ran. Read-only.
  final BackendDeviceInfo device;

  AgentDevice._({
    required this.backend,
    required this.sessions,
    required this.clock,
    required this.sessionName,
    required this.device,
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
    CommandClock clock = const SystemClock(),
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
      clock: clock,
      sessionName: sessionName,
      device: picked,
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
  ///
  /// When [maxSize] is set, the captured PNG is box-filter downscaled
  /// in place after the backend writes it so the longest edge fits
  /// within [maxSize] pixels. Skipped when the image already fits.
  Future<BackendScreenshotResult?> screenshot(
    String outPath, {
    bool? overlayRefs,
    bool? fullscreen,
    int? maxSize,
  }) async {
    if (maxSize != null && maxSize < 1) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'Screenshot max size must be a positive integer',
      );
    }
    final result = await backend.captureScreenshot(
      BackendCommandContext(session: sessionName, deviceSerial: device.id),
      outPath,
      BackendScreenshotOptions(
        overlayRefs: overlayRefs,
        fullscreen: fullscreen,
        maxSize: maxSize,
      ),
    );
    if (maxSize != null) {
      final path = result?.path ?? outPath;
      if (await File(path).exists()) {
        await png.resizePngFileToMaxSize(path, maxSize);
      }
    }
    return result;
  }

  // =========================================================================
  // Interaction
  // =========================================================================

  /// Resolve an [InteractionTarget] to an absolute screen [Point].
  ///
  /// [PointTarget]s are returned as-is. [RefTarget] and [SelectorTarget]
  /// trigger a snapshot (unless one is supplied via [snapshotOverride]) and
  /// look up the matching node, then return `centerOfRect(node.rect)`.
  /// Throws [AppError] with `AMBIGUOUS_MATCH` or `COMMAND_FAILED` when
  /// resolution fails.
  Future<Point> resolveTarget(
    InteractionTarget target, {
    BackendSnapshotResult? snapshotOverride,
  }) async {
    if (target is PointTarget) return target.point;
    final snap = snapshotOverride ?? await snapshot();
    final node = await _resolveNode(target, snap);
    final rect = node.rect;
    if (rect == null) {
      throw AppError(
        AppErrorCodes.commandFailed,
        'Resolved target has no rect; cannot derive a tap point.',
        details: {'target': target.toString()},
      );
    }
    return centerOfRect(rect);
  }

  Future<void> tap(num x, num y, {BackendTapOptions? options}) async {
    await backend.tap(
      await _ctx(),
      Point(x: x.toDouble(), y: y.toDouble()),
      options,
    );
  }

  /// Tap resolved from an [InteractionTarget] (point, `@ref`, or selector).
  Future<void> tapTarget(
    InteractionTarget target, {
    BackendTapOptions? options,
  }) async {
    final point = await resolveTarget(target);
    await backend.tap(await _ctx(), point, options);
  }

  Future<void> fill(num x, num y, String text, {int? delayMs}) async {
    await backend.fill(
      await _ctx(),
      Point(x: x.toDouble(), y: y.toDouble()),
      text,
      delayMs == null ? null : BackendFillOptions(delayMs: delayMs),
    );
  }

  /// Fill resolved from an [InteractionTarget].
  Future<void> fillTarget(
    InteractionTarget target,
    String text, {
    int? delayMs,
  }) async {
    final point = await resolveTarget(target);
    await backend.fill(
      await _ctx(),
      point,
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

  /// Focus resolved from an [InteractionTarget].
  Future<void> focusTarget(InteractionTarget target) async {
    final point = await resolveTarget(target);
    await backend.focus(await _ctx(), point);
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

  /// Long-press resolved from an [InteractionTarget].
  Future<void> longPressTarget(
    InteractionTarget target, {
    int? durationMs,
  }) async {
    final point = await resolveTarget(target);
    await backend.longPress(
      await _ctx(),
      point,
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
  // Diagnostics
  // =========================================================================

  /// Sample CPU and memory usage for the session's open app.
  /// `metrics` narrows the set (e.g. `['cpu']` or `['memory']`); null
  /// samples both. iOS simulator uses `simctl spawn ps`; Android uses
  /// `adb shell dumpsys cpuinfo|meminfo`.
  Future<BackendMeasurePerfResult> measurePerf({
    List<String>? metrics,
    int? sampleMs,
  }) async {
    return backend.measurePerf(
      await _ctx(),
      BackendMeasurePerfOptions(metrics: metrics, sampleMs: sampleMs),
    );
  }

  /// Begin streaming device logs to [outPath] as a detached background
  /// process. The PID is persisted under `<stateDir>/log-streams/` so a
  /// subsequent [stopLogStream] call (from any shell) can find it.
  /// iOS filters to the session's open app via os_log predicate;
  /// Android narrows with `logcat --pid <pidof(pkg)>` when an app is
  /// open, otherwise returns the full stream.
  Future<BackendLogStreamResult> startLogStream(
    String outPath, {
    String? appBundleId,
  }) async {
    return backend.startLogStream(
      await _ctx(),
      BackendLogStreamOptions(outPath: outPath, appBundleId: appBundleId),
    );
  }

  /// Stop the currently-active log stream for this session's device.
  Future<BackendLogStreamResult> stopLogStream() async {
    return backend.stopLogStream(await _ctx());
  }

  /// Dump recent device logs filtered to the session's current app.
  /// [since] can be `30s` / `5m` / `1h` for a relative window, or an
  /// absolute timestamp (`@<epoch>` or `YYYY-MM-DD HH:MM:SS`). iOS
  /// requires an open app; Android matches the backend's default.
  Future<BackendReadLogsResult> readLogs({String? since, int? limit}) async {
    return backend.readLogs(
      await _ctx(),
      BackendReadLogsOptions(since: since, limit: limit),
    );
  }

  // =========================================================================
  // Recording
  // =========================================================================

  /// Start recording video of the current app. The video file is written
  /// to [outPath] when [stopRecording] is called. On iOS the recording
  /// captures frames from the currently-open app (set via [openApp]); on
  /// Android the full screen is captured.
  Future<BackendRecordingResult> startRecording(
    String outPath, {
    int? fps,
    int? quality,
    bool? showTouches,
  }) async {
    return backend.startRecording(
      await _ctx(),
      BackendRecordingOptions(
        outPath: outPath,
        fps: fps,
        quality: quality,
        showTouches: showTouches,
      ),
    );
  }

  /// Stop the in-progress recording and finalize the file at [outPath].
  /// [outPath] must match the path passed to [startRecording].
  Future<BackendRecordingResult> stopRecording(String outPath) async {
    return backend.stopRecording(
      await _ctx(),
      BackendRecordingOptions(outPath: outPath),
    );
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

  Future<BackendInstallResult> uninstallApp({required String app}) async {
    return backend.uninstallApp(await _ctx(), app);
  }

  Future<BackendInstallResult> reinstallApp({
    required String path,
    required String app,
    bool resetKeychain = false,
  }) async {
    if (resetKeychain) {
      await backend.resetKeychain(await _ctx());
    }
    return backend.reinstallApp(
      await _ctx(),
      BackendInstallTarget(app: app, source: BackendInstallSourcePath(path)),
    );
  }

  /// Reset the simulator keychain (iOS simulator only).
  Future<void> resetKeychain() async {
    await backend.resetKeychain(await _ctx());
  }

  // =========================================================================
  // Query: find / get / is / wait
  // =========================================================================

  /// Search the current snapshot for nodes matching [text].
  ///
  /// Three modes are supported, tried in this order:
  ///
  /// * **Selector DSL** ([selectorChain] is provided): exact match via
  ///   [matchesSelector]. E.g. `text="Yes, Tap to select"` or `visible`.
  /// * **Locator** ([locator] ≠ `'any'`): case-insensitive substring match
  ///   restricted to the named field (`text`/`label`/`value`/`id`/`role`).
  /// * **Any** (default): case-insensitive substring match across `label`,
  ///   `value`, and `identifier`.
  ///
  /// Returns a list of `{ref, label, value, identifier, type, rect}` maps.
  /// Takes a fresh snapshot unless [snapshotOverride] is supplied.
  Future<List<Map<String, Object?>>> find(
    String text, {
    String locator = 'any',
    SelectorChain? selectorChain,
    BackendSnapshotResult? snapshotOverride,
  }) async {
    if (selectorChain == null && text.trim().isEmpty) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'find: query must be non-empty.',
      );
    }
    final snap = snapshotOverride ?? await snapshot();
    final nodes = _nodesOf(snap);
    final hits = <Map<String, Object?>>[];
    final platform = backend.platform.name;

    for (final n in nodes) {
      final bool hit;
      if (selectorChain != null) {
        hit = selectorChain.selectors.any(
          (sel) => matchesSelector(n, sel, platform),
        );
      } else {
        final needle = _normalizeFindText(text);
        final List<String?> haystacks;
        switch (locator) {
          case 'label':
            haystacks = [n.label];
          case 'value':
            haystacks = [n.value];
          case 'id':
            haystacks = [n.identifier];
          case 'role':
            haystacks = [_normalizeFindRole(n.type)];
          default:
            haystacks = [n.label, n.value, n.identifier];
        }
        hit = haystacks
            .whereType<String>()
            .map(_normalizeFindText)
            .any((s) => s.contains(needle));
      }
      if (!hit) continue;
      hits.add(<String, Object?>{
        'ref': n.ref,
        'label': n.label,
        'value': n.value,
        'identifier': n.identifier,
        'type': n.type,
        if (n.rect != null)
          'rect': {
            'x': n.rect!.x,
            'y': n.rect!.y,
            'width': n.rect!.width,
            'height': n.rect!.height,
          },
      });
    }
    return hits;
  }

  static String _normalizeFindText(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static String _normalizeFindRole(String? type) {
    if (type == null || type.isEmpty) return '';
    final lower = type.toLowerCase();
    final lastDot = lower.lastIndexOf('.');
    return lastDot >= 0 ? lower.substring(lastDot + 1) : lower;
  }

  /// Read a named attribute off the node addressed by [target]. [attr] is
  /// one of `text`, `label`, `value`, `identifier`, `type`, `role`, `rect`,
  /// `ref`. Unknown [attr] values throw `INVALID_ARGS`.
  Future<Object?> getAttr(String attr, InteractionTarget target) async {
    final snap = await snapshot();
    final node = await _resolveNode(target, snap);
    switch (attr) {
      case 'ref':
        return node.ref;
      case 'label':
        return node.label;
      case 'value':
        return node.value;
      case 'identifier':
        return node.identifier;
      case 'type':
        return node.type;
      case 'role':
        return node.role;
      case 'text':
        // Prefer label over value; many Android widgets carry the human
        // text on `label`.
        return node.label?.trim().isNotEmpty == true
            ? node.label
            : (node.value?.trim().isNotEmpty == true
                  ? node.value
                  : node.identifier);
      case 'rect':
        final r = node.rect;
        if (r == null) return null;
        return {'x': r.x, 'y': r.y, 'width': r.width, 'height': r.height};
    }
    throw AppError(
      AppErrorCodes.invalidArgs,
      'Unknown attribute "$attr". Expected one of: '
      'ref, label, value, identifier, type, role, text, rect.',
      details: {'attr': attr},
    );
  }

  /// Evaluate a predicate (e.g. `visible`, `hidden`, `editable`,
  /// `selected`, `exists`, `text=Submit`) against [target]. [predicate] is
  /// the bare name (e.g. `'visible'`) OR a `text=...` expression; pass the
  /// expected-text portion separately via [expectedText] for a stable
  /// programmatic API.
  ///
  /// Returns an [IsPredicateResult] whose `pass` field tells you whether
  /// the predicate held.
  Future<IsPredicateResult> isPredicate(
    String predicate,
    InteractionTarget target, {
    String? expectedText,
  }) async {
    if (!isSupportedPredicate(predicate)) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'Unsupported is-predicate: $predicate',
        details: {
          'predicate': predicate,
          'supported': const [
            'visible',
            'hidden',
            'exists',
            'editable',
            'selected',
            'text',
          ],
        },
      );
    }
    final snap = await snapshot();
    final nodes = _nodesOf(snap);
    SnapshotNode? node;
    try {
      node = await _resolveNode(target, snap);
    } on AppError catch (e) {
      // `exists` legitimately wants to observe "no match" → pass=false.
      // `hidden` for a ref/selector that doesn't exist on screen is also
      // a passing assertion.
      if (e.code == AppErrorCodes.commandFailed &&
          (predicate == 'exists' || predicate == 'hidden')) {
        return IsPredicateResult(
          pass: predicate == 'hidden',
          actualText: '',
          details: 'No node matched the target.',
        );
      }
      rethrow;
    }
    return evaluateIsPredicate(
      predicate: predicate,
      node: node,
      nodes: nodes,
      expectedText: expectedText,
      platform: backend.platform.name,
    );
  }

  /// Poll until [predicate] on [target] passes, with [timeout] and
  /// [pollInterval] knobs. Returns the final [IsPredicateResult]. Times
  /// out with `COMMAND_FAILED` when the condition doesn't hold before the
  /// deadline.
  Future<IsPredicateResult> wait(
    String predicate,
    InteractionTarget target, {
    Duration timeout = const Duration(seconds: 10),
    Duration pollInterval = const Duration(milliseconds: 400),
    String? expectedText,
  }) async {
    final deadline = clock.now() + timeout.inMilliseconds;
    IsPredicateResult last = const IsPredicateResult(
      pass: false,
      actualText: '',
      details: '',
    );
    while (true) {
      try {
        last = await isPredicate(predicate, target, expectedText: expectedText);
      } on AppError catch (e) {
        // Treat transient resolution failures as "not yet true" — polling.
        if (e.code != AppErrorCodes.commandFailed) rethrow;
        last = IsPredicateResult(
          pass: false,
          actualText: '',
          details: e.message,
        );
      }
      if (last.pass) return last;
      if (clock.now() >= deadline) {
        throw AppError(
          AppErrorCodes.commandFailed,
          'wait "$predicate" timed out after ${timeout.inMilliseconds}ms.',
          details: {
            'predicate': predicate,
            'timeoutMs': timeout.inMilliseconds,
            'lastActualText': last.actualText,
            'lastDetails': last.details,
          },
        );
      }
      await clock.sleep(pollInterval);
    }
  }

  /// Backend snapshot nodes are typed `List<Object?>?` at the contract
  /// boundary (the Backend type is intentionally loose). The real payload
  /// is always `List<SnapshotNode>` once `attachRefs` has run on the
  /// concrete backend. Narrow the cast here so every caller downstream
  /// sees a strong type.
  List<SnapshotNode> _nodesOf(BackendSnapshotResult snap) {
    final raw = snap.nodes;
    if (raw == null) return const [];
    if (raw is List<SnapshotNode>) return raw;
    return raw.whereType<SnapshotNode>().toList();
  }

  /// Internal: resolve [target] all the way to a [SnapshotNode] (rather
  /// than a [Point]). Shared by [getAttr], [isPredicate], and [wait].
  Future<SnapshotNode> _resolveNode(
    InteractionTarget target,
    BackendSnapshotResult snap,
  ) async {
    final nodes = _nodesOf(snap);
    if (nodes.isEmpty) {
      throw AppError(
        AppErrorCodes.commandFailed,
        'Cannot resolve $target: the snapshot is empty.',
      );
    }
    if (target is PointTarget) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'Point targets are not supported for find/get/is/wait — '
        'pass a @ref or selector.',
      );
    }
    if (target is RefTarget) {
      final node = findNodeByRef(nodes, target.ref);
      if (node == null) {
        throw AppError(
          AppErrorCodes.commandFailed,
          'Ref @${target.ref} not found in the current snapshot.',
          details: {'ref': target.ref},
        );
      }
      return node;
    }
    if (target is SelectorTarget) {
      final resolution = resolveSelectorChain(
        nodes,
        target.chain,
        platform: backend.platform.name,
        disambiguateAmbiguous: true,
      );
      if (resolution == null) {
        throw AppError(
          AppErrorCodes.commandFailed,
          'Selector did not match any node: ${target.source}',
          details: {'selector': target.source},
        );
      }
      return resolution.node;
    }
    throw StateError('unreachable');
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
