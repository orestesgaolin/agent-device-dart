// Unit coverage for the Phase 10 replay runtime. Exercises the dispatch
// table against a recording Backend that captures every call so we can
// assert the script drives the backend correctly without needing a real
// device.

import 'dart:io';

import 'package:agent_device/src/backend/backend.dart';
import 'package:agent_device/src/replay/replay_runtime.dart';
import 'package:agent_device/src/runtime/agent_device.dart';
import 'package:agent_device/src/runtime/file_session_store.dart';
import 'package:agent_device/src/snapshot/snapshot.dart';
import 'package:test/test.dart';

void main() {
  group('runReplayScript', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('ad-replay-');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    Future<AgentDevice> openDevice(_RecordingBackend backend) async {
      return AgentDevice.open(
        backend: backend,
        selector: const DeviceSelector(serial: 'mock-serial'),
        sessionName: 'replay-test',
        sessions: FileSessionStore(tmp.path),
      );
    }

    test('open → home → snapshot runs through the dispatch table', () async {
      final backend = _RecordingBackend();
      final device = await openDevice(backend);
      final script = File('${tmp.path}/simple.ad');
      await script.writeAsString('open com.example.foo\nhome\nsnapshot\n');

      final result = await runReplayScript(
        scriptPath: script.path,
        device: device,
      );

      expect(result.ok, isTrue, reason: result.steps.toString());
      expect(result.steps, hasLength(3));
      expect(backend.calls.map((c) => c.name).toList(), [
        'openApp',
        'pressHome',
        'captureSnapshot',
      ]);
    });

    test('swipe parses four coords', () async {
      final backend = _RecordingBackend();
      final device = await openDevice(backend);
      final script = File('${tmp.path}/swipe.ad');
      await script.writeAsString('swipe 10 20 100 200\n');

      final result = await runReplayScript(
        scriptPath: script.path,
        device: device,
      );
      expect(result.ok, isTrue);
      expect(backend.calls, hasLength(1));
      expect(backend.calls.first.name, 'swipe');
      expect(backend.calls.first.args['from'], isA<Point>());
      final from = backend.calls.first.args['from'] as Point;
      expect(from.x, 10);
      expect(from.y, 20);
    });

    test('failing step stops execution and returns error', () async {
      final backend = _RecordingBackend(failOn: 'openApp');
      final device = await openDevice(backend);
      final script = File('${tmp.path}/fail.ad');
      await script.writeAsString('open com.example.foo\nhome\n');

      final result = await runReplayScript(
        scriptPath: script.path,
        device: device,
      );
      expect(result.ok, isFalse);
      expect(
        result.steps,
        hasLength(1),
        reason: 'Should stop at the first failing step.',
      );
      expect(result.steps.first.ok, isFalse);
      expect(result.steps.first.errorMessage, contains('injected'));
    });

    test('unknown command surfaces UNSUPPORTED_OPERATION', () async {
      final backend = _RecordingBackend();
      final device = await openDevice(backend);
      final script = File('${tmp.path}/unknown.ad');
      await script.writeAsString('totally-fake-command arg1\n');

      final result = await runReplayScript(
        scriptPath: script.path,
        device: device,
      );
      expect(result.ok, isFalse);
      expect(result.steps.first.errorCode, 'UNSUPPORTED_OPERATION');
    });

    test('surfaces context-header metadata on the result', () async {
      final backend = _RecordingBackend();
      final device = await openDevice(backend);
      final script = File('${tmp.path}/ctx.ad');
      await script.writeAsString(
        'context platform=ios timeout=5000 retries=2\nhome\n',
      );
      final result = await runReplayScript(
        scriptPath: script.path,
        device: device,
      );
      expect(result.ok, isTrue);
      expect(result.metadata, isNotNull);
      expect(result.metadata!.platform, 'ios');
      expect(result.metadata!.timeoutMs, 5000);
      expect(result.metadata!.retries, 2);
    });

    test('rejects JSON payloads', () async {
      final backend = _RecordingBackend();
      final device = await openDevice(backend);
      final script = File('${tmp.path}/json.ad');
      await script.writeAsString('{"not": "a replay"}\n');

      await expectLater(
        runReplayScript(scriptPath: script.path, device: device),
        throwsA(isA<Object>()),
      );
    });
  });
}

/// A [Backend] that records every method it's asked to perform. The
/// dispatch table under test in [runReplayScript] must funnel every
/// action through one of these methods.
class _RecordingBackend extends Backend {
  final List<_BackendCall> calls = [];
  final String? failOn;

  _RecordingBackend({this.failOn});

  @override
  AgentDeviceBackendPlatform get platform => AgentDeviceBackendPlatform.android;

  void _record(String name, Map<String, Object?> args) {
    calls.add(_BackendCall(name, args));
    if (failOn == name) {
      throw Exception('injected failure on $name');
    }
  }

  @override
  Future<BackendActionResult> openApp(
    BackendCommandContext ctx,
    BackendOpenTarget target,
    BackendOpenOptions? options,
  ) async {
    _record('openApp', {'target': target});
    return null;
  }

  @override
  Future<BackendActionResult> closeApp(
    BackendCommandContext ctx, [
    String? app,
  ]) async {
    _record('closeApp', {'app': app});
    return null;
  }

  @override
  Future<BackendActionResult> pressHome(BackendCommandContext ctx) async {
    _record('pressHome', const {});
    return null;
  }

  @override
  Future<BackendActionResult> pressBack(
    BackendCommandContext ctx,
    BackendBackOptions? options,
  ) async {
    _record('pressBack', const {});
    return null;
  }

  @override
  Future<BackendActionResult> openAppSwitcher(BackendCommandContext ctx) async {
    _record('openAppSwitcher', const {});
    return null;
  }

  @override
  Future<BackendActionResult> rotate(
    BackendCommandContext ctx,
    BackendDeviceOrientation orientation,
  ) async {
    _record('rotate', {'orientation': orientation});
    return null;
  }

  @override
  Future<BackendActionResult> typeText(
    BackendCommandContext ctx,
    String text, [
    Map<String, Object?>? options,
  ]) async {
    _record('typeText', {'text': text});
    return null;
  }

  @override
  Future<BackendActionResult> swipe(
    BackendCommandContext ctx,
    Point from,
    Point to,
    BackendSwipeOptions? options,
  ) async {
    _record('swipe', {'from': from, 'to': to});
    return null;
  }

  @override
  Future<BackendActionResult> tap(
    BackendCommandContext ctx,
    Point point,
    BackendTapOptions? options,
  ) async {
    _record('tap', {'point': point});
    return null;
  }

  @override
  Future<BackendSnapshotResult> captureSnapshot(
    BackendCommandContext ctx,
    BackendSnapshotOptions? options,
  ) async {
    _record('captureSnapshot', {'options': options});
    return const BackendSnapshotResult(nodes: [], truncated: false);
  }

  @override
  Future<List<BackendDeviceInfo>> listDevices(
    BackendCommandContext ctx, [
    BackendDeviceFilter? filter,
  ]) async => [
    const BackendDeviceInfo(
      id: 'mock-serial',
      name: 'mock',
      platform: AgentDeviceBackendPlatform.android,
    ),
  ];
}

class _BackendCall {
  final String name;
  final Map<String, Object?> args;
  _BackendCall(this.name, this.args);
  @override
  String toString() => '$name($args)';
}
