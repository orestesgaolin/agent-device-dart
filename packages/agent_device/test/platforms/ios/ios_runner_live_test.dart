@TestOn('mac-os')
@Tags(['ios-live'])
library;

// ignore_for_file: avoid_print — diagnostic test against a real simulator.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Phase 8B XCUITest-runner bridge: drive snapshot / tap / swipe / home /
/// app-switcher / rotate through the CLI on a real booted simulator.
///
/// Prerequisites:
///   - iOS simulator booted (`xcrun simctl boot <udid>`)
///   - Runner built once:
///     `xcodebuild build-for-testing -project ios-runner/AgentDeviceRunner/AgentDeviceRunner.xcodeproj \
///       -scheme AgentDeviceRunner -destination "generic/platform=iOS Simulator" \
///       -derivedDataPath ios-runner/build`
///   - `AGENT_DEVICE_IOS_LIVE=1` to enable
void main() {
  final gate = Platform.environment['AGENT_DEVICE_IOS_LIVE'];
  if (gate != '1') {
    test(
      'iOS runner live tests skipped',
      () {},
      skip:
          'set AGENT_DEVICE_IOS_LIVE=1 (with a booted simulator + built runner)',
    );
    return;
  }

  final repoRoot = _findRepoRoot();
  final binPath = p.join(
    repoRoot,
    'packages',
    'agent_device',
    'bin',
    'agent_device.dart',
  );

  /// Compose a CLI invocation. Root flags (--state-dir) come before the
  /// subcommand; --platform / --serial are command-level and must come
  /// AFTER it.
  Future<_R> cli(List<String> args, {String? stateDir, String? udid}) async {
    if (args.isEmpty) throw ArgumentError('empty args');
    final subcommand = args.first;
    final subArgs = args.sublist(1);
    final argv = <String>['run', binPath];
    if (stateDir != null) argv.addAll(['--state-dir', stateDir]);
    argv.add(subcommand);
    argv.addAll(['--platform', 'ios']);
    if (udid != null) argv.addAll(['--serial', udid]);
    argv.addAll(subArgs);
    final r = await Process.run('dart', argv, workingDirectory: repoRoot);
    return _R(
      exitCode: r.exitCode,
      stdout: r.stdout.toString(),
      stderr: r.stderr.toString(),
    );
  }

  Map<String, Object?> okData(_R r) {
    final line = r.stdout.trim().split('\n').first;
    final env = jsonDecode(line) as Map<String, Object?>;
    expect(env['success'], isTrue, reason: r.stdout);
    return env['data'] as Map<String, Object?>;
  }

  late Directory stateDir;
  late String bootedUdid;

  setUpAll(() async {
    final probe = await Process.run('xcrun', [
      'simctl',
      'list',
      'devices',
      'booted',
      '-j',
    ]);
    final decoded = jsonDecode(probe.stdout.toString()) as Map<String, Object?>;
    final byRuntime = (decoded['devices'] as Map?) ?? {};
    String? udid;
    for (final entries in byRuntime.values) {
      if (entries is! List) continue;
      for (final d in entries) {
        if (d is Map && d['state'] == 'Booted') {
          udid = d['udid'] as String?;
          break;
        }
      }
      if (udid != null) break;
    }
    if (udid == null) fail('No booted iOS simulator.');
    bootedUdid = udid;
    stateDir = await Directory.systemTemp.createTemp('ad-ios-runner-live-');
    print('[live] simulator: $bootedUdid');
  });

  tearDownAll(() async {
    // Tear down the detached runner we spun up so we don't leak
    // xcodebuild processes into the user's session.
    await cli(['session', 'clear'], stateDir: stateDir.path, udid: bootedUdid);
    // Module doesn't know about test tear-down, so kill any stray runner
    // directly.
    await Process.run('pkill', ['-f', 'xcodebuild test-without-building']);
    if (await stateDir.exists()) await stateDir.delete(recursive: true);
  });

  group('iOS runner-backed CLI (live)', () {
    test('snapshot: first call cold-starts the runner', () async {
      final sw = Stopwatch()..start();
      final r = await cli(
        ['snapshot', '--json'],
        stateDir: stateDir.path,
        udid: bootedUdid,
      );
      sw.stop();
      expect(r.exitCode, 0, reason: r.stderr);
      final data = okData(r);
      expect(data['deviceSerial'], bootedUdid);
      expect(data['nodeCount'], isA<int>());
      expect(data['nodeCount'] as int, greaterThan(0));
      print(
        '[live] first snapshot: ${data['nodeCount']} nodes '
        'in ${sw.elapsed.inSeconds}s',
      );
      // The cold start path spins up xcodebuild test-without-building; a
      // generous upper bound so this doesn't flake on slow machines but
      // still notices catastrophic regressions.
      expect(sw.elapsed.inSeconds, lessThan(90));
    });

    test(
      'snapshot: second call reuses the detached runner (fast path)',
      () async {
        final sw = Stopwatch()..start();
        final r = await cli(
          ['snapshot', '--json'],
          stateDir: stateDir.path,
          udid: bootedUdid,
        );
        sw.stop();
        expect(r.exitCode, 0, reason: r.stderr);
        print('[live] second snapshot in ${sw.elapsed.inSeconds}s (reused)');
        // Cold is ~10s on this machine, warm ~3s. Leave a wide margin but
        // assert we didn't pay the full cold-start cost.
        expect(sw.elapsed.inSeconds, lessThan(20));
      },
    );

    test('home / tap / app-switcher round-trip via runner', () async {
      final home = await cli(
        ['home', '--json'],
        stateDir: stateDir.path,
        udid: bootedUdid,
      );
      expect(home.exitCode, 0, reason: home.stderr);

      final tap = await cli(
        ['tap', '200', '400', '--json'],
        stateDir: stateDir.path,
        udid: bootedUdid,
      );
      expect(tap.exitCode, 0, reason: tap.stderr);

      final swi = await cli(
        ['app-switcher', '--json'],
        stateDir: stateDir.path,
        udid: bootedUdid,
      );
      expect(swi.exitCode, 0, reason: swi.stderr);
    });

    test('swipe sends drag with correct field names', () async {
      // Phase 8B regression: initial port sent fromX/fromY/toX/toY; the
      // runner expects x/y/x2/y2. Assert swipe now round-trips.
      final r = await cli(
        ['swipe', '200', '600', '200', '200', '--duration-ms', '150', '--json'],
        stateDir: stateDir.path,
        udid: bootedUdid,
      );
      expect(r.exitCode, 0, reason: r.stderr);
      final data = okData(r);
      expect(data['swiped'], [200, 600, 200, 200]);
    });

    test('rotate landscape + portrait round-trip', () async {
      final land = await cli(
        ['rotate', 'landscape-left', '--json'],
        stateDir: stateDir.path,
        udid: bootedUdid,
      );
      expect(land.exitCode, 0, reason: land.stderr);
      final port = await cli(
        ['rotate', 'portrait', '--json'],
        stateDir: stateDir.path,
        udid: bootedUdid,
      );
      expect(port.exitCode, 0, reason: port.stderr);
    });

    test('pinch zoom round-trips via runner', () async {
      // Phase 8C polish: runner has a pinch handler; Dart now calls it.
      // Any positive scale proves the wire format (command, scale, x?, y?)
      // round-trips without UNSUPPORTED_OPERATION.
      final r = await cli(
        ['pinch', '--scale', '1.5', '--json'],
        stateDir: stateDir.path,
        udid: bootedUdid,
      );
      expect(r.exitCode, 0, reason: r.stderr);
      final env = jsonDecode(r.stdout.trim().split('\n').first) as Map;
      expect(env['success'], isTrue, reason: r.stdout);
    });

    test('clipboard set + read round-trip (simctl)', () async {
      final marker = 'ad-live-${DateTime.now().microsecondsSinceEpoch}';
      final setR = await cli(
        ['clipboard', '--set', marker, '--json'],
        stateDir: stateDir.path,
        udid: bootedUdid,
      );
      expect(setR.exitCode, 0, reason: setR.stderr);

      final getR = await cli(
        ['clipboard', '--json'],
        stateDir: stateDir.path,
        udid: bootedUdid,
      );
      expect(getR.exitCode, 0, reason: getR.stderr);
      final env = jsonDecode(getR.stdout.trim().split('\n').first) as Map;
      expect(env['success'], isTrue);
      expect((env['data'] as Map)['clipboard'], marker);
    });

    test(
      'runner record is persisted at ~/.agent-device/ios-runners/<udid>.json',
      () async {
        final home = Platform.environment['HOME']!;
        final file = File(
          p.join(home, '.agent-device', 'ios-runners', '$bootedUdid.json'),
        );
        expect(
          await file.exists(),
          isTrue,
          reason: 'Expected runner record at ${file.path}',
        );
        final record = jsonDecode(await file.readAsString()) as Map;
        expect(record['udid'], bootedUdid);
        expect(record['port'], isA<int>());
        expect(record['xcodebuildPid'], isA<int>());
      },
    );
  });
}

class _R {
  final int exitCode;
  final String stdout;
  final String stderr;
  const _R({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });
}

String _findRepoRoot() {
  var dir = Directory(p.fromUri(Platform.script.resolve('.')));
  for (var i = 0; i < 10; i++) {
    final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    if (pubspec.existsSync()) {
      final content = pubspec.readAsStringSync();
      if (content.contains('workspace:') ||
          content.contains('agent_device_workspace')) {
        return dir.path;
      }
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return Directory.current.path;
}
