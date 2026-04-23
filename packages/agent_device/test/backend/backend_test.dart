// Port of agent-device/src/backend.ts
import 'package:agent_device/agent_device.dart';
import 'package:test/test.dart';

/// Minimal backend that declares only its platform; every other method
/// inherits the `unsupported` default from [Backend] and throws.
class _MinimalBackend extends Backend {
  const _MinimalBackend();

  @override
  AgentDeviceBackendPlatform get platform => AgentDeviceBackendPlatform.android;
}

class _BackendWithCapabilities extends _MinimalBackend {
  const _BackendWithCapabilities();

  @override
  BackendCapabilitySet? get capabilities => const [
    BackendCapabilityName.androidShell,
  ];
}

void main() {
  group('Backend', () {
    test('subclass can declare only platform', () {
      const backend = _MinimalBackend();
      expect(backend.platform, AgentDeviceBackendPlatform.android);
      expect(backend.capabilities, isNull);
      expect(backend.escapeHatches, isNull);
    });

    test('unoverridden methods throw UNSUPPORTED_OPERATION', () async {
      const backend = _MinimalBackend();
      const ctx = BackendCommandContext(session: 'test');

      await expectLater(
        backend.readText(ctx, 'anything'),
        throwsA(
          isA<AppError>()
              .having((e) => e.code, 'code', AppErrorCodes.unsupportedOperation)
              .having((e) => e.message, 'message', contains('readText'))
              .having((e) => e.message, 'message', contains('android')),
        ),
      );
      await expectLater(
        backend.pinch(ctx, const BackendPinchOptions(scale: 1.0)),
        throwsA(
          isA<AppError>().having(
            (e) => e.code,
            'code',
            AppErrorCodes.unsupportedOperation,
          ),
        ),
      );
    });

    test('enum fromString round-trips', () {
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

    test('hasBackendCapability honours declared capabilities', () {
      expect(
        hasBackendCapability(
          const _MinimalBackend(),
          BackendCapabilityName.androidShell,
        ),
        false,
      );
      expect(
        hasBackendCapability(
          const _BackendWithCapabilities(),
          BackendCapabilityName.androidShell,
        ),
        true,
      );
    });
  });
}
