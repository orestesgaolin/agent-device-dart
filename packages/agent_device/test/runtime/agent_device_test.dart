import 'package:agent_device/agent_device.dart';
import 'package:test/test.dart';

/// Records every call made into it so tests can assert dispatch behavior
/// without touching a real device.
class _FakeBackend extends Backend {
  final List<BackendDeviceInfo> devicesToReturn;
  final List<String> callLog = [];
  BackendCommandContext? lastCtx;

  _FakeBackend({required this.devicesToReturn});

  @override
  AgentDeviceBackendPlatform get platform => AgentDeviceBackendPlatform.android;

  @override
  Future<List<BackendDeviceInfo>> listDevices(
    BackendCommandContext ctx, [
    BackendDeviceFilter? filter,
  ]) async {
    lastCtx = ctx;
    callLog.add('listDevices');
    return devicesToReturn;
  }

  @override
  Future<BackendSnapshotResult> captureSnapshot(
    BackendCommandContext ctx,
    BackendSnapshotOptions? options,
  ) async {
    lastCtx = ctx;
    callLog.add('captureSnapshot(serial=${ctx.deviceSerial})');
    return const BackendSnapshotResult(nodes: []);
  }

  @override
  Future<BackendActionResult> tap(
    BackendCommandContext ctx,
    Point point,
    BackendTapOptions? options,
  ) async {
    lastCtx = ctx;
    callLog.add('tap(${point.x.toInt()},${point.y.toInt()})');
    return null;
  }

  @override
  Future<BackendActionResult> openApp(
    BackendCommandContext ctx,
    BackendOpenTarget target,
    BackendOpenOptions? options,
  ) async {
    lastCtx = ctx;
    callLog.add('openApp(${target.app})');
    return null;
  }

  @override
  Future<BackendActionResult> closeApp(
    BackendCommandContext ctx, [
    String? app,
  ]) async {
    lastCtx = ctx;
    callLog.add('closeApp($app)');
    return null;
  }

  @override
  Future<BackendAppState> getAppState(
    BackendCommandContext ctx,
    String app,
  ) async {
    lastCtx = ctx;
    callLog.add('getAppState($app)');
    return const BackendAppState(state: 'foreground');
  }
}

void main() {
  const info = BackendDeviceInfo(
    id: 'emulator-5554',
    name: 'Pixel 9 Pro',
    platform: AgentDeviceBackendPlatform.android,
  );

  group('AgentDevice.open', () {
    test(
      'resolves first matching device and stores deviceSerial in session',
      () async {
        final backend = _FakeBackend(devicesToReturn: [info]);
        final device = await AgentDevice.open(backend: backend);
        expect(device.device.id, 'emulator-5554');
        expect(device.sessionName, 'default');
        expect(backend.callLog, contains('listDevices'));

        final record = await device.sessions.get('default');
        expect(record?.deviceSerial, 'emulator-5554');
      },
    );

    test('throws DEVICE_NOT_FOUND when nothing matches', () async {
      final backend = _FakeBackend(devicesToReturn: []);
      await expectLater(
        AgentDevice.open(backend: backend),
        throwsA(
          isA<AppError>().having(
            (e) => e.code,
            'code',
            AppErrorCodes.deviceNotFound,
          ),
        ),
      );
    });

    test('filters by serial when provided', () async {
      const other = BackendDeviceInfo(
        id: 'emulator-5556',
        name: 'Other',
        platform: AgentDeviceBackendPlatform.android,
      );
      final backend = _FakeBackend(devicesToReturn: [other, info]);
      final device = await AgentDevice.open(
        backend: backend,
        selector: const DeviceSelector(serial: 'emulator-5554'),
      );
      expect(device.device.id, 'emulator-5554');
    });

    test('throws when serial does not match any device', () async {
      final backend = _FakeBackend(devicesToReturn: [info]);
      await expectLater(
        AgentDevice.open(
          backend: backend,
          selector: const DeviceSelector(serial: 'emulator-9999'),
        ),
        throwsA(
          isA<AppError>()
              .having((e) => e.code, 'code', AppErrorCodes.deviceNotFound)
              .having(
                (e) => e.details?['serial'],
                'detail.serial',
                'emulator-9999',
              ),
        ),
      );
    });
  });

  group('AgentDevice methods pass deviceSerial from session state', () {
    test('snapshot includes ctx.deviceSerial', () async {
      final backend = _FakeBackend(devicesToReturn: [info]);
      final device = await AgentDevice.open(backend: backend);
      await device.snapshot();
      expect(backend.lastCtx?.deviceSerial, 'emulator-5554');
      expect(
        backend.callLog,
        contains('captureSnapshot(serial=emulator-5554)'),
      );
    });

    test('tap forwards rounded point', () async {
      final backend = _FakeBackend(devicesToReturn: [info]);
      final device = await AgentDevice.open(backend: backend);
      await device.tap(100.4, 250.9);
      expect(backend.callLog, contains('tap(100,250)'));
    });
  });

  group('AgentDevice session state mutations', () {
    test('openApp records appId in session', () async {
      final backend = _FakeBackend(devicesToReturn: [info]);
      final device = await AgentDevice.open(backend: backend);
      await device.openApp('com.android.settings');
      final record = await device.sessions.get('default');
      expect(record?.appId, 'com.android.settings');
    });

    test('closeApp uses session-stored appId when none passed', () async {
      final backend = _FakeBackend(devicesToReturn: [info]);
      final device = await AgentDevice.open(backend: backend);
      await device.openApp('com.android.settings');
      await device.closeApp();
      expect(backend.callLog, contains('closeApp(com.android.settings)'));
    });

    test('closeApp clears appId from session after success', () async {
      final backend = _FakeBackend(devicesToReturn: [info]);
      final device = await AgentDevice.open(backend: backend);
      await device.openApp('com.android.settings');
      expect(
        (await device.sessions.get('default'))?.appId,
        'com.android.settings',
      );
      await device.closeApp();
      expect((await device.sessions.get('default'))?.appId, isNull);
      // deviceSerial is preserved.
      expect(
        (await device.sessions.get('default'))?.deviceSerial,
        'emulator-5554',
      );
    });

    test('close() deletes session record', () async {
      final backend = _FakeBackend(devicesToReturn: [info]);
      final device = await AgentDevice.open(backend: backend);
      await device.close();
      expect(await device.sessions.get('default'), isNull);
    });
  });

  test('AgentDevice.listDevices is callable without open()', () async {
    final backend = _FakeBackend(devicesToReturn: [info]);
    final list = await AgentDevice.listDevices(backend);
    expect(list, hasLength(1));
    expect(list.first.id, 'emulator-5554');
  });
}
