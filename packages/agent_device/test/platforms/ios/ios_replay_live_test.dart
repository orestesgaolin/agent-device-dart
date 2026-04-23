@TestOn('mac-os')
@Tags(['ios-live'])
library;

// ignore_for_file: avoid_print, strict_raw_type — diagnostic test against a
// real simulator; JSON decode returns dynamic maps.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Phase 10 MVP: exercise the replay runner end-to-end on an .ad script
/// driving a live simulator. Uses the same `home → snapshot` flow as the
/// iOS runner live suite but composes it as a replay script.
void main() {
  final gate = Platform.environment['AGENT_DEVICE_IOS_LIVE'];
  if (gate != '1') {
    test(
      'iOS replay live tests skipped',
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
  late File scriptFile;

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
    stateDir = await Directory.systemTemp.createTemp('ad-ios-replay-live-');
    scriptFile = File(p.join(stateDir.path, 'flow.ad'));
    await scriptFile.writeAsString('home\nsnapshot\n');
    print('[live] simulator: $bootedUdid');
  });

  tearDownAll(() async {
    // Kill any runner we spun up.
    final r = await Process.run('dart', [
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
    print('[live] cleanup exit ${r.exitCode}');
    await Process.run('pkill', ['-f', 'xcodebuild test-without-building']);
    if (await stateDir.exists()) await stateDir.delete(recursive: true);
  });

  test(
    'replay runs a two-step .ad script against simulator',
    () async {
      final argv = [
        'run',
        binPath,
        '--state-dir',
        stateDir.path,
        'replay',
        scriptFile.path,
        '--platform',
        'ios',
        '--serial',
        bootedUdid,
        '--json',
      ];
      final r = await Process.run('dart', argv, workingDirectory: repoRoot);
      expect(r.exitCode, 0, reason: r.stderr.toString());
      final env =
          jsonDecode(r.stdout.toString().trim().split('\n').first) as Map;
      expect(env['success'], isTrue, reason: r.stdout.toString());
      final data = env['data'] as Map;
      expect(data['ok'], isTrue);
      expect(data['passed'], 2);
      expect(data['failed'], 0);
      final steps = (data['steps'] as List).cast<Map>();
      expect(steps, hasLength(2));
      expect(steps[0]['command'], 'home');
      expect(steps[1]['command'], 'snapshot');
      expect(
        (steps[1]['artifactPaths'] as List?) ?? const [],
        isNotEmpty,
        reason: 'Snapshot step should produce a JSON artifact.',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'test command runs a script and reports pass count',
    () async {
      final argv = [
        'run',
        binPath,
        '--state-dir',
        stateDir.path,
        'test',
        scriptFile.path,
        '--platform',
        'ios',
        '--serial',
        bootedUdid,
        '--json',
      ];
      final r = await Process.run('dart', argv, workingDirectory: repoRoot);
      expect(r.exitCode, 0, reason: r.stderr.toString());
      final env =
          jsonDecode(r.stdout.toString().trim().split('\n').first) as Map;
      expect(env['success'], isTrue);
      final data = env['data'] as Map;
      expect(data['total'], 1);
      expect(data['passed'], 1);
      expect(data['failed'], 0);
    },
    timeout: const Timeout(Duration(minutes: 3)),
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
