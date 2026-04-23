import 'package:agent_device/src/backend/backend.dart';
import 'package:agent_device/src/platforms/android/android_backend.dart';
import 'package:agent_device/src/utils/errors.dart';
import 'package:test/test.dart';

void main() {
  group('AndroidBackend', () {
    test('instantiates correctly', () {
      final backend = const AndroidBackend();
      expect(backend, isNotNull);
    });

    test('implements Backend interface', () {
      final backend = const AndroidBackend() as Backend;
      expect(backend, isA<Backend>());
    });

    test('reports correct platform', () {
      final backend = const AndroidBackend();
      expect(backend.platform, equals(AgentDeviceBackendPlatform.android));
    });

    test('has no capabilities by default', () {
      final backend = const AndroidBackend();
      expect(backend.capabilities, isNull);
    });

    test('has no escape hatches by default', () {
      final backend = const AndroidBackend();
      expect(backend.escapeHatches, isNull);
    });

    test('every abstract method has an implementation (not abstract)', () {
      // This is a compile-time check: if any abstract method is not
      // overridden, this test file will not compile.
      // At runtime, we verify that the backend is a concrete implementation.
      final backend = const AndroidBackend();
      expect(backend, isNotNull);

      // Verify all methods are defined and callable (some will throw
      // unsupported operation errors, but they exist).
      expect(backend.platform, isNotNull);
      expect(backend.capabilities, isNull); // null is valid
    });

    test(
      'unsupported methods throw AppError with unsupportedOperation code',
      () async {
        const backend = AndroidBackend();
        const ctx = BackendCommandContext(deviceSerial: 'emulator-5554');

        // pressKey is genuinely not wired (no Android equivalent in TS source).
        await expectLater(
          backend.pressKey(ctx, 'Return'),
          throwsA(
            isA<AppError>().having(
              (e) => e.code,
              'code',
              AppErrorCodes.unsupportedOperation,
            ),
          ),
        );
        // readText / pinch — also genuinely unsupported on Android.
        await expectLater(
          backend.readText(ctx, 'ignored'),
          throwsA(isA<AppError>()),
        );
        await expectLater(
          backend.pinch(ctx, const BackendPinchOptions(scale: 2.0)),
          throwsA(isA<AppError>()),
        );
      },
    );

    test('missing deviceSerial surfaces a clear error', () async {
      const backend = AndroidBackend();
      const ctx = BackendCommandContext(); // no deviceSerial
      await expectLater(
        backend.pressHome(ctx),
        throwsA(
          isA<AppError>()
              .having((e) => e.code, 'code', AppErrorCodes.unsupportedOperation)
              .having(
                (e) => e.message,
                'message',
                contains('ctx.deviceSerial'),
              ),
        ),
      );
    });
  });
}
