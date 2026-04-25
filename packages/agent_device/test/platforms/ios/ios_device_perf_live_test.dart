@TestOn('mac-os')
@Tags(['ios-device-live'])
library;

// ignore_for_file: avoid_print, strict_raw_type — diagnostic test against a
// paired iOS device. Gated on `AGENT_DEVICE_IOS_DEVICE_UDID=<udid>` plus
// `AGENT_DEVICE_IOS_LIVE=1` so CI without a device doesn't trigger it.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Phase 10 device perf: drives `agent-device perf` against a paired
/// iPhone with Safari open and asserts xctrace returns CPU% + resident
/// memory for the MobileSafari process. CPU% is derived from a delta
/// between two consecutive 1s xctrace captures.
void main() {
  final gate = Platform.environment['AGENT_DEVICE_IOS_LIVE'];
  final deviceUdid = Platform.environment['AGENT_DEVICE_IOS_DEVICE_UDID'];
  if (gate != '1' || deviceUdid == null || deviceUdid.isEmpty) {
    test(
      'iOS device perf live tests skipped',
      () {},
      skip:
          'set AGENT_DEVICE_IOS_LIVE=1 + AGENT_DEVICE_IOS_DEVICE_UDID=<udid> to run',
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
      deviceUdid,
    ], workingDirectory: repoRoot);
  }

  setUpAll(() async {
    stateDir = await Directory.systemTemp.createTemp('ad-ios-device-perf-');
    print('[live] device: $deviceUdid');
  });

  tearDownAll(() async {
    if (await stateDir.exists()) await stateDir.delete(recursive: true);
  });

  test(
    'perf on physical iPhone returns cpu (percent) + memory.resident',
    () async {
      final openR = await cli(['open', 'com.apple.mobilesafari', '--json']);
      expect(openR.exitCode, 0, reason: openR.stderr.toString());
      // Give Safari a beat to foreground.
      await Future<void>.delayed(const Duration(seconds: 2));

      final r = await cli(['perf', '--json']);
      expect(r.exitCode, 0, reason: r.stderr.toString());
      final env =
          jsonDecode(r.stdout.toString().trim().split('\n').first) as Map;
      expect(env['success'], isTrue, reason: r.stdout.toString());
      final data = env['data'] as Map;
      expect(data['backend'], 'ios-device-xctrace');
      final metrics = (data['metrics'] as List).cast<Map>();
      expect(metrics, hasLength(2));
      final byName = {for (final m in metrics) m['name']: m};
      expect(byName.containsKey('cpu'), isTrue);
      expect(byName.containsKey('memory.resident'), isTrue);
      expect(byName['cpu']!['unit'], 'percent');
      expect(byName['memory.resident']!['unit'], 'kB');
      expect(
        (byName['cpu']!['value'] as num),
        greaterThanOrEqualTo(0),
        reason: 'CPU% should be a non-negative percentage.',
      );
      expect(
        (byName['memory.resident']!['value'] as num),
        greaterThan(0),
        reason: 'MobileSafari should show a positive RSS on device.',
      );
      print(
        '[live] Safari device '
        'cpu=${byName['cpu']!['value']}% '
        'rss=${byName['memory.resident']!['value']}kB',
      );
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
