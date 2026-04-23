@TestOn('mac-os || linux')
@Tags(['android-live'])
library;

// ignore_for_file: avoid_print — this is a diagnostic test that prints
// progress against a real device.

import 'dart:io';

import 'package:agent_device/agent_device.dart';
import 'package:test/test.dart';

/// Phase 4 proof-of-life: drives the programmatic [AgentDevice] façade
/// end-to-end against a real device or emulator, exercising session
/// state + device resolution + backend dispatch.
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

  late AgentDevice device;

  setUpAll(() async {
    device = await AgentDevice.open(backend: const AndroidBackend());
    print(
      '[live] opened session on ${device.device.id} (${device.device.name})',
    );
  });

  tearDownAll(() async {
    await device.close();
  });

  test('session stores deviceSerial after open', () async {
    final record = await device.sessions.get(device.sessionName);
    expect(record?.deviceSerial, device.device.id);
  });

  test(
    'openApp("settings") + snapshot + getAppState + listApps',
    () async {
      await device.openApp('settings');
      await Future<void>.delayed(const Duration(seconds: 2));

      final snap = await device.snapshot();
      final nodes = snap.nodes ?? const [];
      print(
        '[live] snapshot: ${nodes.length} visible nodes, '
        'rawNodeCount=${snap.analysis?.rawNodeCount}, '
        'maxDepth=${snap.analysis?.maxDepth}',
      );
      expect(
        nodes,
        isNotEmpty,
        reason: 'Settings should show non-empty UI after open.',
      );

      final state = await device.getAppState();
      print(
        '[live] foreground: '
        'package=${state.packageName} activity=${state.activity}',
      );
      expect(state.packageName, isNotNull);

      // Session should remember the open app.
      final record = await device.sessions.get(device.sessionName);
      expect(record?.appId, 'settings');

      final apps = await device.listApps();
      print('[live] listApps: ${apps.length} packages');
      expect(apps, isNotEmpty);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test('screenshot writes a PNG file', () async {
    final tmp = File(
      '${Directory.systemTemp.path}/agent-device-live-'
      '${DateTime.now().microsecondsSinceEpoch}.png',
    );
    addTearDown(() async {
      if (await tmp.exists()) await tmp.delete();
    });

    final result = await device.screenshot(tmp.path);
    expect(result, isNotNull);
    expect(await tmp.exists(), isTrue);
    final bytes = await tmp.readAsBytes();
    expect(bytes.take(4).toList(), equals([0x89, 0x50, 0x4E, 0x47]));
    print('[live] wrote ${bytes.length} bytes to ${tmp.path}');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test(
    'pressHome brings device to launcher',
    () async {
      await device.pressHome();
      await Future<void>.delayed(const Duration(seconds: 1));
      final snap = await device.snapshot();
      expect(snap.nodes ?? const [], isNotEmpty);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('AgentDevice.listDevices works without opening a session', () async {
    final devices = await AgentDevice.listDevices(const AndroidBackend());
    expect(devices, isNotEmpty);
    expect(devices.first.id, isNotEmpty);
  });
}
