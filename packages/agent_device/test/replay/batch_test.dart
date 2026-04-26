import 'dart:io';

import 'package:agent_device/src/backend/backend.dart';
import 'package:agent_device/src/replay/batch.dart';
import 'package:agent_device/src/runtime/agent_device.dart';
import 'package:agent_device/src/runtime/file_session_store.dart';
import 'package:agent_device/src/utils/errors.dart';
import 'package:test/test.dart';

void main() {
  group('validateAndNormalizeBatchSteps', () {
    test('accepts well-formed steps', () {
      final steps = validateAndNormalizeBatchSteps([
        {'command': 'home'},
        {'command': 'snapshot', 'positionals': ['-i']},
        {'command': 'tap', 'positionals': ['200', '300'], 'flags': {'force': true}},
      ], 100);
      expect(steps, hasLength(3));
      expect(steps[0].command, 'home');
      expect(steps[1].positionals, ['-i']);
      expect(steps[2].flags['force'], true);
    });

    test('rejects empty list', () {
      expect(
        () => validateAndNormalizeBatchSteps([], 100),
        throwsA(isA<AppError>()),
      );
    });

    test('rejects steps exceeding maxSteps', () {
      final large = List.generate(5, (_) => {'command': 'home'});
      expect(
        () => validateAndNormalizeBatchSteps(large, 3),
        throwsA(isA<AppError>().having(
          (e) => e.message,
          'message',
          contains('max allowed is 3'),
        )),
      );
    });

    test('rejects nested batch command', () {
      expect(
        () => validateAndNormalizeBatchSteps([
          {'command': 'batch'},
        ], 100),
        throwsA(isA<AppError>().having(
          (e) => e.message,
          'message',
          contains('cannot run batch'),
        )),
      );
    });

    test('rejects nested replay command', () {
      expect(
        () => validateAndNormalizeBatchSteps([
          {'command': 'replay'},
        ], 100),
        throwsA(isA<AppError>()),
      );
    });

    test('rejects unknown fields', () {
      expect(
        () => validateAndNormalizeBatchSteps([
          {'command': 'home', 'extra': 1},
        ], 100),
        throwsA(isA<AppError>().having(
          (e) => e.message,
          'message',
          contains('"extra"'),
        )),
      );
    });

    test('rejects missing command', () {
      expect(
        () => validateAndNormalizeBatchSteps([
          {'positionals': ['x']},
        ], 100),
        throwsA(isA<AppError>().having(
          (e) => e.message,
          'message',
          contains('requires command'),
        )),
      );
    });

    test('rejects non-string positionals', () {
      expect(
        () => validateAndNormalizeBatchSteps([
          {'command': 'tap', 'positionals': [1, 2]},
        ], 100),
        throwsA(isA<AppError>()),
      );
    });
  });

  group('parseBatchStepsJson', () {
    test('parses valid JSON array', () {
      final steps = parseBatchStepsJson(
        '[{"command":"home"},{"command":"back"}]',
      );
      expect(steps, hasLength(2));
      expect(steps[0].command, 'home');
    });

    test('rejects invalid JSON', () {
      expect(
        () => parseBatchStepsJson('not json'),
        throwsA(isA<AppError>()),
      );
    });

    test('rejects non-array JSON', () {
      expect(
        () => parseBatchStepsJson('{"command":"home"}'),
        throwsA(isA<AppError>()),
      );
    });
  });

  group('runBatch', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('ad-batch-');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    Future<AgentDevice> openDevice(Backend backend) async {
      return AgentDevice.open(
        backend: backend,
        selector: const DeviceSelector(serial: 'mock-serial'),
        sessionName: 'batch-test',
        sessions: FileSessionStore(tmp.path),
      );
    }

    test('executes all steps and returns ok result', () async {
      final backend = _RecordingBackend();
      final device = await openDevice(backend);
      final result = await runBatch(
        device: device,
        steps: const [
          BatchStep(command: 'home'),
          BatchStep(command: 'back'),
        ],
      );
      expect(result.ok, isTrue);
      expect(result.total, 2);
      expect(result.executed, 2);
      expect(result.results, hasLength(2));
      expect(result.results[0].command, 'home');
      expect(result.results[1].command, 'back');
      expect(backend.calls.map((c) => c.name), ['pressHome', 'pressBack']);
    });

    test('stops at first failure and returns failure context', () async {
      final backend = _RecordingBackend(failOn: 'pressBack');
      final device = await openDevice(backend);
      final result = await runBatch(
        device: device,
        steps: const [
          BatchStep(command: 'home'),
          BatchStep(command: 'back'),
          BatchStep(command: 'home'),
        ],
      );
      expect(result.ok, isFalse);
      expect(result.executed, 1);
      expect(result.total, 3);
      expect(result.failure, isNotNull);
      expect(result.failure!.step, 2);
      expect(result.failure!.command, 'back');
      expect(result.results, hasLength(1));
    });
  });
}

class _BackendCall {
  final String name;
  final Map<String, Object?> args;
  _BackendCall(this.name, this.args);
}

class _RecordingBackend extends Backend {
  final List<_BackendCall> calls = [];
  final String? failOn;

  _RecordingBackend({this.failOn});

  @override
  AgentDeviceBackendPlatform get platform => AgentDeviceBackendPlatform.android;

  void _record(String name) {
    calls.add(_BackendCall(name, const {}));
    if (failOn == name) {
      throw AppError(AppErrorCodes.commandFailed, 'injected failure on $name');
    }
  }

  @override
  Future<BackendActionResult> pressHome(BackendCommandContext ctx) async {
    _record('pressHome');
    return null;
  }

  @override
  Future<BackendActionResult> pressBack(
    BackendCommandContext ctx, [
    BackendBackOptions? options,
  ]) async {
    _record('pressBack');
    return null;
  }

  @override
  Future<List<BackendDeviceInfo>> listDevices(
    BackendCommandContext ctx, [
    BackendDeviceFilter? filter,
  ]) async =>
      [
        const BackendDeviceInfo(
          id: 'mock-serial',
          name: 'mock',
          platform: AgentDeviceBackendPlatform.android,
        ),
      ];
}
