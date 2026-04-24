@TestOn('mac-os')
@Tags(['ios-live'])
library;

// ignore_for_file: avoid_print, strict_raw_type — diagnostic test against a
// real simulator.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Phase 10 log streaming: `logs --stream` / `logs --stop` round-trip
/// against a booted simulator with Safari open.
void main() {
  final gate = Platform.environment['AGENT_DEVICE_IOS_LIVE'];
  if (gate != '1') {
    test(
      'iOS log-stream live tests skipped',
      () {},
      skip: 'set AGENT_DEVICE_IOS_LIVE=1 to run',
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

  late Directory stateDir;
  late String bootedUdid;

  Future<ProcessResult> cli(List<String> args) {
    return Process.run('dart', [
      'run',
      binPath,
      '--state-dir',
      stateDir.path,
      ...args,
      '--platform',
      'ios',
      '--serial',
      bootedUdid,
    ], workingDirectory: repoRoot);
  }

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
    for (final e in byRuntime.values) {
      if (e is! List) continue;
      for (final d in e) {
        if (d is Map && d['state'] == 'Booted') {
          udid = d['udid'] as String?;
          if (udid != null) break;
        }
      }
      if (udid != null) break;
    }
    if (udid == null) fail('No booted iOS simulator.');
    bootedUdid = udid;
    stateDir = await Directory.systemTemp.createTemp('ad-ios-logstream-');
    print('[live] simulator: $bootedUdid  state: ${stateDir.path}');
  });

  tearDownAll(() async {
    // Best-effort: nuke any stream record we might have left running.
    await cli(['logs', '--stop', '--json']);
    await Process.run('dart', [
      'run',
      binPath,
      '--state-dir',
      stateDir.path,
      'session',
      'clear',
      '--platform',
      'ios',
      '--serial',
      bootedUdid,
    ], workingDirectory: repoRoot);
    if (await stateDir.exists()) await stateDir.delete(recursive: true);
  });

  test(
    'logs --stream writes to disk, logs --stop finalizes it',
    () async {
      final openR = await cli(['open', 'com.apple.mobilesafari', '--json']);
      expect(openR.exitCode, 0, reason: openR.stderr.toString());

      final outPath = p.join(stateDir.path, 'safari-stream.log');
      final startR = await cli([
        'logs',
        '--stream',
        '--out',
        outPath,
        '--json',
      ]);
      expect(startR.exitCode, 0, reason: startR.stderr.toString());
      final startEnv =
          jsonDecode(startR.stdout.toString().trim().split('\n').first) as Map;
      expect(startEnv['success'], isTrue);
      final startData = startEnv['data'] as Map;
      expect(startData['backend'], 'ios-simulator-log-stream');
      expect(startData['outPath'], outPath);
      expect(startData['hostPid'], isA<int>());

      // Give the tail ~3s to pick up some Safari log output, then stop.
      await Future<void>.delayed(const Duration(seconds: 3));

      final stopR = await cli(['logs', '--stop', '--json']);
      expect(stopR.exitCode, 0, reason: stopR.stderr.toString());
      final stopEnv =
          jsonDecode(stopR.stdout.toString().trim().split('\n').first) as Map;
      expect(stopEnv['success'], isTrue);
      final stopData = stopEnv['data'] as Map;
      expect(stopData['outPath'], outPath);

      final out = File(outPath);
      expect(await out.exists(), isTrue);
      final bytes = await out.length();
      expect(
        bytes,
        greaterThan(0),
        reason: 'Expected some tail output during the 3s window.',
      );
      print('[live] streamed $bytes bytes of Safari log');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('logs --stop without an active stream reports COMMAND_FAILED', () async {
    final r = await cli(['logs', '--stop', '--json']);
    expect(r.exitCode, 1);
    final env = jsonDecode(r.stdout.toString().trim().split('\n').first) as Map;
    expect(env['success'], isFalse);
    expect((env['error'] as Map)['code'], 'COMMAND_FAILED');
  });

  test('logs --stream requires --out', () async {
    final openR = await cli(['open', 'com.apple.mobilesafari', '--json']);
    expect(openR.exitCode, 0);
    final r = await cli(['logs', '--stream', '--json']);
    expect(r.exitCode, 1);
    final env = jsonDecode(r.stdout.toString().trim().split('\n').first) as Map;
    expect((env['error'] as Map)['code'], 'INVALID_ARGS');
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
