@TestOn('mac-os')
@Tags(['ios-live'])
library;

// ignore_for_file: avoid_print, strict_raw_type — diagnostic test against a
// real simulator.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Phase 10 record-trace: drive the CLI's `record start` / `record stop`
/// commands against the booted iOS simulator with Safari open, then
/// assert a non-empty MP4 lands at the requested path.
void main() {
  final gate = Platform.environment['AGENT_DEVICE_IOS_LIVE'];
  if (gate != '1') {
    test(
      'iOS record live tests skipped',
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
  late String outPath;

  Future<ProcessResult> cli(List<String> args) {
    final argv = <String>[
      'run',
      binPath,
      '--state-dir',
      stateDir.path,
      ...args,
      '--platform',
      'ios',
      '--serial',
      bootedUdid,
    ];
    return Process.run('dart', argv, workingDirectory: repoRoot);
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
    stateDir = await Directory.systemTemp.createTemp('ad-ios-record-');
    outPath = p.join(stateDir.path, 'recording.mp4');
    print('[live] simulator: $bootedUdid  outPath: $outPath');
  });

  tearDownAll(() async {
    // Tear down any runner we spun up.
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
    'record start → home → record stop writes an mp4 on disk',
    () async {
      // Open Safari so the runner has an app to capture frames from.
      final openR = await cli(['open', 'com.apple.mobilesafari', '--json']);
      expect(openR.exitCode, 0, reason: openR.stderr.toString());

      // Start recording.
      final startR = await cli(['record', 'start', outPath, '--json']);
      expect(startR.exitCode, 0, reason: startR.stderr.toString());
      final startEnv =
          jsonDecode(startR.stdout.toString().trim().split('\n').first) as Map;
      expect(startEnv['success'], isTrue);

      // Do something while recording.
      await Future<void>.delayed(const Duration(seconds: 2));
      final homeR = await cli(['home', '--json']);
      expect(homeR.exitCode, 0, reason: homeR.stderr.toString());

      // Stop recording.
      final stopR = await cli(['record', 'stop', outPath, '--json']);
      expect(stopR.exitCode, 0, reason: stopR.stderr.toString());
      final stopEnv =
          jsonDecode(stopR.stdout.toString().trim().split('\n').first) as Map;
      expect(stopEnv['success'], isTrue, reason: stopR.stdout.toString());

      // File should exist on host FS with non-trivial size. Allow a warning
      // path too — the runner sometimes takes a beat to flush the file.
      final out = File(outPath);
      final exists = await out.exists();
      if (!exists) {
        // If the runner reported a warning, surface it as a skip rather
        // than a hard failure — this test is diagnostic.
        final data = stopEnv['data'] as Map?;
        final warning = data?['warning'] as String?;
        print('[live] recording warning: $warning');
      }
      expect(exists, isTrue, reason: 'Recording file should be on disk');
      final bytes = await out.length();
      expect(
        bytes,
        greaterThan(1000),
        reason: 'Recording should be larger than 1KB',
      );
      // MP4 magic: file starts with `ftyp` at offset 4.
      final head = await out.openRead(0, 12).toList();
      final flat = head.expand((e) => e).toList();
      final ftypMarker = utf8.decode(flat.sublist(4, 8));
      expect(ftypMarker, 'ftyp', reason: 'Expected MP4 ftyp header');
      print('[live] recording: $bytes bytes');
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
