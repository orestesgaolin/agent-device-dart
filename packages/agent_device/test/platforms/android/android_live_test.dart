@TestOn('mac-os || linux')
@Tags(['android-live'])
library;

// ignore_for_file: avoid_print — this is a diagnostic test that prints
// progress against a real device.

import 'dart:io';

import 'package:agent_device/agent_device.dart';
import 'package:test/test.dart';

/// Phase 3 proof-of-life. Bypasses the (unported) runtime and drives
/// [AndroidBackend] directly against a real device or emulator.
///
/// Gated on AGENT_DEVICE_ANDROID_LIVE=1 so `dart test packages/agent_device`
/// stays clean without hardware. Run manually:
///
///     AGENT_DEVICE_ANDROID_LIVE=1 dart test packages/agent_device/test/platforms/android/android_live_test.dart
void main() {
  final gateValue = Platform.environment['AGENT_DEVICE_ANDROID_LIVE'];
  if (gateValue != '1') {
    test(
      'android live tests skipped',
      () {},
      skip: 'set AGENT_DEVICE_ANDROID_LIVE=1 to run',
    );
    return;
  }

  late BackendDeviceInfo device;

  setUpAll(() async {
    const backend = AndroidBackend();
    final devices = await backend.listDevices(const BackendCommandContext());
    if (devices.isEmpty) {
      fail(
        'No Android devices connected — attach a device or boot an emulator.',
      );
    }
    device = devices.first;
    print('[live] using device: id=${device.id} name=${device.name}');
  });

  test('listDevices returns at least one device', () async {
    const backend = AndroidBackend();
    final devices = await backend.listDevices(const BackendCommandContext());
    expect(devices, isNotEmpty);
  });

  test(
    'openApp("settings") + snapshot + listApps',
    () async {
      const backend = AndroidBackend();
      final ctx = BackendCommandContext(deviceSerial: device.id);

      // Open the Settings app via the "settings" intent alias.
      await backend.openApp(
        ctx,
        const BackendOpenTarget(app: 'settings'),
        null,
      );
      // Give Settings a moment to come to the foreground.
      await Future<void>.delayed(const Duration(seconds: 2));

      // Snapshot the current screen.
      final snap = await backend.captureSnapshot(ctx, null);
      print(
        '[live] captured ${(snap.nodes ?? const []).length} nodes '
        '(rawNodeCount=${snap.analysis?.rawNodeCount}, '
        'maxDepth=${snap.analysis?.maxDepth})',
      );
      expect(
        (snap.nodes ?? const []),
        isNotEmpty,
        reason: 'Expected non-empty snapshot — Settings app should show UI.',
      );
      expect(snap.analysis?.rawNodeCount ?? 0, greaterThan(0));

      // Current foreground app should be Settings (or a sub-activity of it).
      final state = await backend.getAppState(ctx, 'settings');
      print(
        '[live] foreground: package=${state.packageName} activity=${state.activity}',
      );
      expect(state.packageName, isNotNull);

      // List a handful of installed apps.
      final apps = await backend.listApps(ctx);
      print('[live] listApps: ${apps.length} packages');
      expect(apps, isNotEmpty);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test('screenshot writes a PNG file', () async {
    const backend = AndroidBackend();
    final ctx = BackendCommandContext(deviceSerial: device.id);
    final tmp = File(
      '${Directory.systemTemp.path}/agent-device-live-'
      '${DateTime.now().microsecondsSinceEpoch}.png',
    );
    addTearDown(() async {
      if (await tmp.exists()) await tmp.delete();
    });

    final result = await backend.captureScreenshot(ctx, tmp.path, null);
    expect(result, isNotNull);
    expect(await tmp.exists(), isTrue);
    final bytes = await tmp.readAsBytes();
    // PNG magic number.
    expect(bytes.take(4).toList(), equals([0x89, 0x50, 0x4E, 0x47]));
    print('[live] wrote ${bytes.length} bytes to ${tmp.path}');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test(
    'pressHome brings device to launcher',
    () async {
      const backend = AndroidBackend();
      final ctx = BackendCommandContext(deviceSerial: device.id);
      await backend.pressHome(ctx);
      await Future<void>.delayed(const Duration(seconds: 1));
      // Just confirm it didn't throw — can't easily assert launcher-ness.
      final snap = await backend.captureSnapshot(ctx, null);
      expect((snap.nodes ?? const []), isNotEmpty);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );
}
