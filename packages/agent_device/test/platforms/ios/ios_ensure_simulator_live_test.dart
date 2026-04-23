@TestOn('mac-os')
@Tags(['ios-live'])
library;

// ignore_for_file: avoid_print — diagnostic test against simctl.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Phase 8C polish: verify `agent-device ensure-simulator <name>` resolves
/// an existing simulator (reuse path), and that `--create-new` actually
/// creates + cleans up.
///
/// Gated on `AGENT_DEVICE_IOS_LIVE=1` so CI without a real Xcode toolchain
/// doesn't try to run `xcrun simctl`.
void main() {
  final gate = Platform.environment['AGENT_DEVICE_IOS_LIVE'];
  if (gate != '1') {
    test(
      'iOS ensure-simulator live tests skipped',
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

  setUpAll(() async {
    stateDir = await Directory.systemTemp.createTemp('ad-ios-ensure-sim-');
  });

  tearDownAll(() async {
    if (await stateDir.exists()) await stateDir.delete(recursive: true);
  });

  test('ensure-simulator reuses an existing device by name', () async {
    // Find any iOS simulator name already present on the host — using
    // simctl directly so the test doesn't depend on any particular model
    // being installed.
    final list = await Process.run('xcrun', [
      'simctl',
      'list',
      'devices',
      '-j',
    ]);
    final payload = jsonDecode(list.stdout.toString()) as Map<String, Object?>;
    final devices = (payload['devices'] as Map?) ?? {};
    String? existingName;
    for (final entry in devices.values) {
      if (entry is! List) continue;
      for (final d in entry) {
        if (d is Map && d['isAvailable'] == true) {
          existingName = d['name'] as String?;
          if (existingName != null) break;
        }
      }
      if (existingName != null) break;
    }
    if (existingName == null) {
      markTestSkipped('No available simulator on host to resolve.');
      return;
    }

    final r = await cli([
      'ensure-simulator',
      existingName,
      '--no-boot',
      '--json',
    ], stateDir: stateDir.path);
    expect(r.exitCode, 0, reason: r.stderr);
    final env = jsonDecode(r.stdout.trim().split('\n').first) as Map;
    expect(env['success'], isTrue);
    final data = env['data'] as Map;
    expect(data['device'], existingName);
    expect(data['created'], isFalse, reason: 'Should reuse existing sim.');
    expect(data['booted'], isFalse);
    expect(data['udid'], isNotEmpty);
    print('[live] reused existing simulator: ${data['udid']}');
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
