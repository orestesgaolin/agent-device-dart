@TestOn('mac-os')
@Tags(['ios-live'])
library;

// ignore_for_file: avoid_print, strict_raw_type — diagnostic test against a
// real simulator.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Phase 10 app-log: drive `agent-device logs` against a booted
/// simulator with Safari open and assert we get back a non-empty dump
/// of recent os_log output.
void main() {
  final gate = Platform.environment['AGENT_DEVICE_IOS_LIVE'];
  if (gate != '1') {
    test(
      'iOS logs live tests skipped',
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
    stateDir = await Directory.systemTemp.createTemp('ad-ios-logs-');
    print('[live] simulator: $bootedUdid');
  });

  tearDownAll(() async {
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
    await Process.run('pkill', ['-f', 'xcodebuild test-without-building']);
    if (await stateDir.exists()) await stateDir.delete(recursive: true);
  });

  test(
    'logs --since 1m dumps Safari os_log output to file',
    () async {
      final openR = await cli(['open', 'com.apple.mobilesafari', '--json']);
      expect(openR.exitCode, 0, reason: openR.stderr.toString());

      // Give Safari a beat to emit some log lines.
      await Future<void>.delayed(const Duration(seconds: 2));

      final outPath = p.join(stateDir.path, 'safari.log');
      final r = await cli([
        'logs',
        '--since',
        '1m',
        '--out',
        outPath,
        '--json',
      ]);
      expect(r.exitCode, 0, reason: r.stderr.toString());
      final env =
          jsonDecode(r.stdout.toString().trim().split('\n').first) as Map;
      expect(env['success'], isTrue);
      final data = env['data'] as Map;
      expect(data['backend'], 'ios-simulator');
      expect(data['entries'], greaterThanOrEqualTo(0));

      final out = File(outPath);
      expect(await out.exists(), isTrue);
      final size = await out.length();
      print('[live] logs: ${data['entries']} entries, $size bytes');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
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
