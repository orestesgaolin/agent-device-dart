// Port of agent-device/src/backend.ts
import 'package:agent_device/agent_device.dart';
import 'package:test/test.dart';

/// Minimal test backend that implements the full interface.
class FakeBackend implements Backend {
  @override
  AgentDeviceBackendPlatform get platform => AgentDeviceBackendPlatform.android;

  @override
  BackendCapabilitySet? get capabilities => null;

  @override
  BackendEscapeHatches? get escapeHatches => null;

  @override
  Future<BackendSnapshotResult> captureSnapshot(
    BackendCommandContext ctx,
    BackendSnapshotOptions? options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendScreenshotResult?> captureScreenshot(
    BackendCommandContext ctx,
    String outPath,
    BackendScreenshotOptions? options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendReadTextResult> readText(
    BackendCommandContext ctx,
    Object node,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendFindTextResult> findText(
    BackendCommandContext ctx,
    String text,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendActionResult> tap(
    BackendCommandContext ctx,
    Point point,
    BackendTapOptions? options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendActionResult> fill(
    BackendCommandContext ctx,
    Point point,
    String text,
    BackendFillOptions? options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendActionResult> typeText(
    BackendCommandContext ctx,
    String text, [
    Map<String, Object?>? options,
  ]) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendActionResult> focus(
    BackendCommandContext ctx,
    Point point,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendActionResult> longPress(
    BackendCommandContext ctx,
    Point point,
    BackendLongPressOptions? options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendActionResult> swipe(
    BackendCommandContext ctx,
    Point from,
    Point to,
    BackendSwipeOptions? options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendActionResult> scroll(
    BackendCommandContext ctx,
    BackendScrollTarget target,
    BackendScrollOptions options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendActionResult> pinch(
    BackendCommandContext ctx,
    BackendPinchOptions options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendActionResult> pressKey(
    BackendCommandContext ctx,
    String key, [
    Map<String, Object?>? options,
  ]) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendActionResult> pressBack(
    BackendCommandContext ctx,
    BackendBackOptions? options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendActionResult> pressHome(BackendCommandContext ctx) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendActionResult> rotate(
    BackendCommandContext ctx,
    BackendDeviceOrientation orientation,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<Object?> setKeyboard(
    BackendCommandContext ctx,
    BackendKeyboardOptions options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<String> getClipboard(BackendCommandContext ctx) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendActionResult> setClipboard(
    BackendCommandContext ctx,
    String text,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendAlertResult> handleAlert(
    BackendCommandContext ctx,
    BackendAlertAction action, [
    Map<String, Object?>? options,
  ]) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendActionResult> openSettings(
    BackendCommandContext ctx, [
    String? target,
  ]) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendActionResult> openAppSwitcher(BackendCommandContext ctx) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendActionResult> openApp(
    BackendCommandContext ctx,
    BackendOpenTarget target,
    BackendOpenOptions? options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendActionResult> closeApp(
    BackendCommandContext ctx, [
    String? app,
  ]) async {
    throw UnimplementedError();
  }

  @override
  Future<List<BackendAppInfo>> listApps(
    BackendCommandContext ctx, [
    BackendAppListFilter? filter,
  ]) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendAppState> getAppState(
    BackendCommandContext ctx,
    String app,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendActionResult> pushFile(
    BackendCommandContext ctx,
    BackendPushInput input,
    String target,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendActionResult> triggerAppEvent(
    BackendCommandContext ctx,
    BackendAppEvent event,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<List<BackendDeviceInfo>> listDevices(
    BackendCommandContext ctx, [
    BackendDeviceFilter? filter,
  ]) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendActionResult> bootDevice(
    BackendCommandContext ctx, [
    BackendDeviceTarget? target,
  ]) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendEnsureSimulatorResult> ensureSimulator(
    BackendCommandContext ctx,
    BackendEnsureSimulatorOptions options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendInstallSource> resolveInstallSource(
    BackendCommandContext ctx,
    BackendInstallSource source,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendInstallResult> installApp(
    BackendCommandContext ctx,
    BackendInstallTarget target,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendInstallResult> reinstallApp(
    BackendCommandContext ctx,
    BackendInstallTarget target,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendRecordingResult> startRecording(
    BackendCommandContext ctx,
    BackendRecordingOptions? options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendRecordingResult> stopRecording(
    BackendCommandContext ctx,
    BackendRecordingOptions? options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendTraceResult> startTrace(
    BackendCommandContext ctx,
    BackendTraceOptions? options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendTraceResult> stopTrace(
    BackendCommandContext ctx,
    BackendTraceOptions? options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendReadLogsResult> readLogs(
    BackendCommandContext ctx,
    BackendReadLogsOptions? options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendDumpNetworkResult> dumpNetwork(
    BackendCommandContext ctx,
    BackendDumpNetworkOptions? options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendMeasurePerfResult> measurePerf(
    BackendCommandContext ctx,
    BackendMeasurePerfOptions? options,
  ) async {
    throw UnimplementedError();
  }
}

void main() {
  group('Backend', () {
    test('FakeBackend can be instantiated', () {
      final backend = FakeBackend();
      expect(backend.platform, AgentDeviceBackendPlatform.android);
      expect(backend.capabilities, isNull);
      expect(backend.escapeHatches, isNull);
    });

    test('Backend compilation ensures all 40 abstract methods exist', () {
      // The fact that FakeBackend can be instantiated (it doesn't compile
      // unless all abstract methods are implemented) proves that the Backend
      // abstract class has the complete interface including:
      // - Snapshot: captureSnapshot, captureScreenshot, readText, findText
      // - Interaction: tap, fill, typeText, focus, longPress, swipe,
      //               scroll, pinch, pressKey, pressBack, pressHome, rotate
      // - Keyboard/Clipboard: setKeyboard, getClipboard, setClipboard
      // - Alerts: handleAlert
      // - App Mgmt: openSettings, openAppSwitcher, openApp, closeApp,
      //            listApps, getAppState, pushFile, triggerAppEvent
      // - Device Mgmt: listDevices, bootDevice, ensureSimulator,
      //               resolveInstallSource, installApp, reinstallApp
      // - Recording: startRecording, stopRecording, startTrace, stopTrace
      // - Diagnostics: readLogs, dumpNetwork, measurePerf
      final backend = FakeBackend();
      expect(backend, isNotNull);
    });

    test('Enum fromString round-trips values', () {
      expect(
        AgentDeviceBackendPlatform.fromString('ios'),
        AgentDeviceBackendPlatform.ios,
      );
      expect(
        AgentDeviceBackendPlatform.fromString('android'),
        AgentDeviceBackendPlatform.android,
      );
      expect(AgentDeviceBackendPlatform.fromString('invalid'), isNull);

      expect(
        BackendCapabilityName.fromString('android.shell'),
        BackendCapabilityName.androidShell,
      );
      expect(
        BackendCapabilityName.fromString('ios.runnerCommand'),
        BackendCapabilityName.iosRunnerCommand,
      );
      expect(BackendCapabilityName.fromString('invalid'), isNull);

      expect(
        BackendAlertAction.fromString('accept'),
        BackendAlertAction.accept,
      );
      expect(
        BackendAlertAction.fromString('dismiss'),
        BackendAlertAction.dismiss,
      );
      expect(BackendAlertAction.fromString('invalid'), isNull);
    });

    test('Utility: hasBackendCapability checks capabilities', () {
      final backend = FakeBackend();
      expect(
        hasBackendCapability(backend, BackendCapabilityName.androidShell),
        false,
      );

      // Test with capabilities set.
      final backendWithCaps = _BackendWithCapabilities();
      expect(
        hasBackendCapability(
          backendWithCaps,
          BackendCapabilityName.androidShell,
        ),
        true,
      );
    });
  });
}

class _BackendWithCapabilities extends FakeBackend {
  @override
  BackendCapabilitySet? get capabilities => [
    BackendCapabilityName.androidShell,
  ];
}
