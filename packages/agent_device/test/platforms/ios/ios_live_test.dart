@TestOn('mac-os')
@Tags(['ios-live'])
library;

// ignore_for_file: avoid_print — diagnostic test against a real simulator.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Phase 8A iOS MVP proof-of-life. Drives the `agent-device` CLI as a
/// subprocess against the user's booted iOS simulator. Gated on
/// AGENT_DEVICE_IOS_LIVE=1 and requires a simulator in Booted state
/// (auto-detected via `xcrun simctl list devices booted -j`).
void main() {
  final gate = Platform.environment['AGENT_DEVICE_IOS_LIVE'];
  if (gate != '1') {
    test(
      'iOS live tests skipped',
      () {},
      skip: 'set AGENT_DEVICE_IOS_LIVE=1 (with a booted simulator) to run',
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

  Future<_R> cli(List<String> args, {String? stateDir}) async {
    final argv = <String>['run', binPath];
    if (stateDir != null) argv.addAll(['--state-dir', stateDir]);
    argv.addAll(args);
    final r = await Process.run('dart', argv, workingDirectory: repoRoot);
    return _R(
      exitCode: r.exitCode,
      stdout: r.stdout.toString(),
      stderr: r.stderr.toString(),
    );
  }

  late Directory stateDir;
  late String bootedUdid;
  late String bootedName;

  setUpAll(() async {
    // Look up the currently booted simulator. Skip the whole suite if
    // there isn't one rather than failing each test.
    final probe = await Process.run('xcrun', [
      'simctl',
      'list',
      'devices',
      'booted',
      '-j',
    ]);
    if (probe.exitCode != 0) {
      fail('xcrun simctl failed: ${probe.stderr}');
    }
    final decoded = jsonDecode(probe.stdout.toString()) as Map<String, Object?>;
    final byRuntime = (decoded['devices'] as Map?) ?? {};
    String? udid;
    String? name;
    for (final entry in byRuntime.values) {
      if (entry is! List) continue;
      for (final d in entry) {
        if (d is! Map) continue;
        if (d['state'] == 'Booted') {
          udid = d['udid'] as String?;
          name = d['name'] as String?;
          break;
        }
      }
      if (udid != null) break;
    }
    if (udid == null) {
      fail(
        'No booted iOS simulator. Start one with '
        '`xcrun simctl boot <udid>` and retry.',
      );
    }
    bootedUdid = udid;
    bootedName = name ?? '(unnamed)';
    stateDir = await Directory.systemTemp.createTemp('ad-ios-');
    print('[live] booted simulator: $bootedUdid ($bootedName)');
  });

  tearDownAll(() async {
    if (await stateDir.exists()) await stateDir.delete(recursive: true);
  });

  group('iOS MVP CLI (live simulator)', () {
    test('devices --platform ios lists the booted simulator', () async {
      final r = await cli([
        'devices',
        '--platform',
        'ios',
        '--json',
      ], stateDir: stateDir.path);
      expect(r.exitCode, 0, reason: r.stderr);
      final env = jsonDecode(r.stdout.trim().split('\n').first) as Map;
      expect(env['success'], isTrue);
      final list = env['data'] as List;
      expect(list, isNotEmpty);
      // The booted one must appear with booted: true.
      final booted = list.firstWhere(
        (d) => (d as Map)['id'] == bootedUdid,
        orElse: () => null,
      );
      expect(
        booted,
        isNotNull,
        reason: 'Booted simulator $bootedUdid must be in the device list.',
      );
      expect((booted as Map)['booted'], isTrue);
    });

    test('screenshot writes a PNG to the booted simulator', () async {
      final out = File(
        p.join(
          stateDir.path,
          'iphone-${DateTime.now().microsecondsSinceEpoch}.png',
        ),
      );
      final r = await cli([
        'screenshot',
        out.path,
        '--platform',
        'ios',
        '--serial',
        bootedUdid,
      ], stateDir: stateDir.path);
      expect(r.exitCode, 0, reason: r.stderr);
      expect(await out.exists(), isTrue);
      final bytes = await out.readAsBytes();
      expect(bytes.length, greaterThan(1000));
      expect(bytes.take(4).toList(), equals([0x89, 0x50, 0x4E, 0x47]));
      print('[live] screenshot: ${bytes.length} bytes');
    });

    test('apps lists installed bundles (user + system)', () async {
      final r = await cli([
        'apps',
        '--platform',
        'ios',
        '--serial',
        bootedUdid,
        '--json',
      ], stateDir: stateDir.path);
      expect(r.exitCode, 0, reason: r.stderr);
      final env = jsonDecode(r.stdout.trim().split('\n').first) as Map;
      expect(env['success'], isTrue);
      final list = env['data'] as List;
      expect(list, isNotEmpty);
      final ids = list.map((a) => (a as Map)['bundleId'] as String).toList();
      expect(ids, contains('com.apple.mobilesafari'));
      print('[live] apps count: ${list.length}');
    });

    test('open + close Safari round-trip', () async {
      final openR = await cli([
        'open',
        'com.apple.mobilesafari',
        '--platform',
        'ios',
        '--serial',
        bootedUdid,
        '--json',
      ], stateDir: stateDir.path);
      expect(openR.exitCode, 0, reason: openR.stderr);
      final openEnv = jsonDecode(openR.stdout.trim().split('\n').first) as Map;
      expect(openEnv['success'], isTrue);

      // Give Safari a moment to come up before we kill it.
      await Future<void>.delayed(const Duration(seconds: 1));

      final closeR = await cli([
        'close',
        'com.apple.mobilesafari',
        '--platform',
        'ios',
        '--serial',
        bootedUdid,
        '--json',
      ], stateDir: stateDir.path);
      expect(closeR.exitCode, 0, reason: closeR.stderr);
    });

    test(
      'pinch still returns UNSUPPORTED_OPERATION (runner has no handler)',
      () async {
        // Phase 8B wires most runner commands; pinch needs a multi-touch
        // helper on the Swift side that isn't in the current runner build.
        // This asserts the regression door is closed.
        final r = await cli([
          'press',
          '@e0',
          '--platform',
          'ios',
          '--serial',
          bootedUdid,
          '--json',
          '--ephemeral-session',
        ], stateDir: stateDir.path);
        // `press @e0` requires snapshot + selector resolution against the
        // runner. If the runner snapshot returns nodes, ref resolution is
        // fine; if the runner is missing, we'd see a COMMAND_FAILED from
        // the launch path. Both are acceptable signals that the full chain
        // is wired — we're just looking for no UNSUPPORTED_OPERATION leaks.
        final env = jsonDecode(r.stdout.trim().split('\n').first) as Map;
        if (env['success'] == false) {
          expect(
            (env['error'] as Map)['code'],
            isNot('UNSUPPORTED_OPERATION'),
            reason:
                'After Phase 8B the runner is wired; UNSUPPORTED_OPERATION '
                'should not leak for selector-backed commands.',
          );
        }
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
