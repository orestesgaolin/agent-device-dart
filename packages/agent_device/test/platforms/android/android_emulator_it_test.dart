@Tags(['android-emulator'])
library;

import 'dart:io' as io;

import 'package:agent_device/src/backend/backend.dart';
import 'package:agent_device/src/platforms/android/android_backend.dart';
import 'package:test/test.dart';

const String _skipReason =
    'Integration test requires AGENT_DEVICE_ANDROID_IT=1 environment variable and a live emulator';

void main() {
  final isAndroidItEnabled =
      io.Platform.environment['AGENT_DEVICE_ANDROID_IT'] == '1';

  group(
    'AndroidBackend integration',
    skip: !isAndroidItEnabled ? _skipReason : false,
    () {
      test(
        'opens Settings app and captures snapshot',
        skip: !isAndroidItEnabled,
        () async {
          // This is a placeholder for full integration test.
          // When AGENT_DEVICE_ANDROID_IT=1 is set and an emulator is running,
          // this test would:
          // 1. Instantiate AndroidBackend
          // 2. Cast to Backend to verify interface
          // 3. Open Settings via openApp
          // 4. Capture snapshot
          // 5. Verify snapshot contains expected UI elements

          final backend = const AndroidBackend() as Backend;
          expect(backend.platform, equals(AgentDeviceBackendPlatform.android));

          // TODO(port): Implement full integration test when emulator setup is available.
          // final ctx = const BackendCommandContext();
          // await backend.openApp(
          //   ctx,
          //   BackendOpenTarget(app: 'settings'),
          // );
          // final snapshot = await backend.captureSnapshot(ctx, null);
          // expect(snapshot.nodes, isNotNull);
          // expect(snapshot.truncated, isNull);
        },
      );
    },
  );

  group('AndroidBackend (unit)', () {
    test('is a concrete Backend implementation without requiring emulator', () {
      final backend = const AndroidBackend();
      expect(backend, isA<Backend>());
      expect(backend.platform, equals(AgentDeviceBackendPlatform.android));
    });
  });
}
