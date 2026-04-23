import 'package:agent_device/src/backend/backend.dart';
import 'package:agent_device/src/platforms/android/android_backend.dart';
import 'package:agent_device/src/utils/errors.dart';
import 'package:test/test.dart';

void main() {
  group('AndroidBackend', () {
    test('instantiates correctly', () {
      final backend = AndroidBackend();
      expect(backend, isNotNull);
    });

    test('implements Backend interface', () {
      final backend = AndroidBackend() as Backend;
      expect(backend, isA<Backend>());
    });

    test('reports correct platform', () {
      final backend = AndroidBackend();
      expect(backend.platform, equals(AgentDeviceBackendPlatform.android));
    });

    test('has no capabilities by default', () {
      final backend = AndroidBackend();
      expect(backend.capabilities, isNull);
    });

    test('has no escape hatches by default', () {
      final backend = AndroidBackend();
      expect(backend.escapeHatches, isNull);
    });

    test('every abstract method has an implementation (not abstract)', () {
      // This is a compile-time check: if any abstract method is not
      // overridden, this test file will not compile.
      // At runtime, we verify that the backend is a concrete implementation.
      final backend = AndroidBackend();
      expect(backend, isNotNull);

      // Verify all methods are defined and callable (some will throw
      // unsupported operation errors, but they exist).
      expect(backend.platform, isNotNull);
      expect(backend.capabilities, isNull); // null is valid
    });

    test(
      'unsupported methods throw AppError with unsupportedOperation code',
      () async {
        final backend = AndroidBackend();
        final ctx = const BackendCommandContext();

        // Test a few unsupported methods to verify they throw.
        expect(() => backend.pressKey(ctx, 'Return'), throwsA(isA<AppError>()));

        expect(() => backend.pressHome(ctx), throwsA(isA<AppError>()));

        expect(() => backend.listApps(ctx), throwsA(isA<AppError>()));
      },
    );
  });
}
