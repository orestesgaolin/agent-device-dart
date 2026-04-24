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

    Future<AgentDevice> openDevice(Backend backend) async {
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

    test('appstate dispatches a read-only getAppState call', () async {
      final backend = _RecordingBackend();
      final device = await openDevice(backend);
      final script = File('${tmp.path}/appstate.ad');
      await script.writeAsString('appstate\n');
      final result = await runReplayScript(
        scriptPath: script.path,
        device: device,
      );
      expect(result.ok, isTrue);
      expect(backend.calls, hasLength(1));
      expect(backend.calls.first.name, 'getAppState');
    });

    test('scroll dispatches direction + amount', () async {
      final backend = _RecordingBackend();
      final device = await openDevice(backend);
      final script = File('${tmp.path}/scroll.ad');
      await script.writeAsString('scroll down\n');
      final result = await runReplayScript(
        scriptPath: script.path,
        device: device,
      );
      expect(result.ok, isTrue);
      expect(backend.calls.first.name, 'scroll');
      expect(
        (backend.calls.first.args['options'] as BackendScrollOptions?)
            ?.direction,
        'down',
      );
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

    test('replayUpdate heals a failing click + rewrites the script', () async {
      // Backend that fails the first click but returns a matching snapshot
      // so heal can rewrite to a fresh selector on retry.
      final backend = _HealBackend();
      final device = await openDevice(backend);
      final script = File('${tmp.path}/heal.ad');
      await script.writeAsString(
        'context platform=android\nclick id=stale-id\n',
      );

      final result = await runReplayScript(
        scriptPath: script.path,
        device: device,
        replayUpdate: true,
      );

      expect(result.ok, isTrue, reason: result.steps.toString());
      expect(result.healed, 1);
      expect(result.rewritten, isTrue);
      expect(result.steps.first.healed, isTrue);
      // Script file was rewritten with healed selector.
      final rewritten = await script.readAsString();
      expect(rewritten, contains('context platform=android'));
      expect(
        rewritten,
        isNot(contains('id=stale-id')),
        reason: 'Stale selector should be replaced after heal.',
      );
      expect(rewritten, contains('id='));
    });

    test('replayUpdate=false still fails fast', () async {
      final backend = _HealBackend();
      final device = await openDevice(backend);
      final script = File('${tmp.path}/fail-fast.ad');
      await script.writeAsString('click id=stale-id\n');
      final result = await runReplayScript(
        scriptPath: script.path,
        device: device,
      );
      expect(result.ok, isFalse);
      expect(result.healed, 0);
      expect(result.rewritten, isFalse);
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
  Future<BackendActionResult> scroll(
    BackendCommandContext ctx,
    BackendScrollTarget target,
    BackendScrollOptions options,
  ) async {
    _record('scroll', {'target': target, 'options': options});
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
  Future<BackendAppState> getAppState(
    BackendCommandContext ctx,
    String app,
  ) async {
    _record('getAppState', {'app': app});
    return const BackendAppState(state: 'foreground');
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

/// Backend that fails the first tap (the original click fails), returns a
/// snapshot containing the target element so heal can re-resolve, and
/// succeeds on the retry. Exercised by the replayUpdate unit test.
class _HealBackend extends Backend {
  int _tapCalls = 0;

  @override
  AgentDeviceBackendPlatform get platform => AgentDeviceBackendPlatform.android;

  @override
  Future<BackendActionResult> tap(
    BackendCommandContext ctx,
    Point point,
    BackendTapOptions? options,
  ) async {
    _tapCalls += 1;
    if (_tapCalls == 1) throw Exception('injected failure on initial tap');
    return null;
  }

  @override
  Future<BackendSnapshotResult> captureSnapshot(
    BackendCommandContext ctx,
    BackendSnapshotOptions? options,
  ) async {
    // One node whose id happens to be "stale-id" (matches the script's
    // selector). Heal will ask for a rebuild from this node and retry.
    final node = const SnapshotNode(
      index: 0,
      ref: '@e0',
      identifier: 'stale-id',
      label: 'Login',
      type: 'Button',
      role: 'Button',
      rect: Rect(x: 10, y: 10, width: 100, height: 40),
      hittable: true,
    );
    return BackendSnapshotResult(nodes: [node], truncated: false);
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
