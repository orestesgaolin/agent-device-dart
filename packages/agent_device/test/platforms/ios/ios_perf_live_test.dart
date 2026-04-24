@TestOn('mac-os')
@Tags(['ios-live'])
library;

// ignore_for_file: avoid_print, strict_raw_type — diagnostic test against a
// real simulator.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Phase 10 perf: drive `agent-device perf` against Safari on a booted
/// simulator and assert sensible CPU + memory samples come back.
void main() {
  final gate = Platform.environment['AGENT_DEVICE_IOS_LIVE'];
  if (gate != '1') {
    test(
      'iOS perf live tests skipped',
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
    stateDir = await Directory.systemTemp.createTemp('ad-ios-perf-');
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
    if (await stateDir.exists()) await stateDir.delete(recursive: true);
  });

  test(
    'perf returns cpu + memory samples for Safari',
    () async {
      final openR = await cli(['open', 'com.apple.mobilesafari', '--json']);
      expect(openR.exitCode, 0, reason: openR.stderr.toString());
      // Give Safari a beat so ps sees it.
      await Future<void>.delayed(const Duration(seconds: 1));

      final r = await cli(['perf', '--json']);
      expect(r.exitCode, 0, reason: r.stderr.toString());
      final env =
          jsonDecode(r.stdout.toString().trim().split('\n').first) as Map;
      expect(env['success'], isTrue, reason: r.stdout.toString());
      final data = env['data'] as Map;
      expect(data['backend'], 'ios-simulator-ps');
      final metrics = (data['metrics'] as List).cast<Map>();
      expect(metrics, hasLength(2));
      final byName = {for (final m in metrics) m['name']: m};
      expect(byName.containsKey('cpu'), isTrue);
      expect(byName.containsKey('memory.resident'), isTrue);
      // Memory should be a positive number (bytes → kB).
      expect(byName['memory.resident']!['value'], isA<num>());
      expect((byName['memory.resident']!['value'] as num), greaterThan(0));
      expect(byName['cpu']!['unit'], 'percent');
      expect(byName['memory.resident']!['unit'], 'kB');
      print(
        '[live] Safari cpu=${byName['cpu']!['value']}% '
        'rss=${byName['memory.resident']!['value']}kB',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'perf --metric memory returns only the requested sample',
    () async {
      final openR = await cli(['open', 'com.apple.mobilesafari', '--json']);
      expect(openR.exitCode, 0);

      final r = await cli(['perf', '--metric', 'memory', '--json']);
      expect(r.exitCode, 0, reason: r.stderr.toString());
      final env =
          jsonDecode(r.stdout.toString().trim().split('\n').first) as Map;
      expect(env['success'], isTrue);
      final data = env['data'] as Map;
      final metrics = (data['metrics'] as List).cast<Map>();
      expect(metrics, hasLength(1));
      expect(metrics.first['name'], 'memory.resident');
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
