@TestOn('mac-os')
@Tags(['live'])
library;

// Runs the TS integration .ad replay scripts against live devices to verify
// the Dart port produces the same results. Each script is run via
// `dart run bin/agent_device.dart replay <script> --json` and asserted to
// exit 0 with `ok: true`.
//
// Gate: AGENT_DEVICE_IOS_LIVE=1 for iOS, AGENT_DEVICE_ANDROID_LIVE=1 for
// Android. Requires a booted simulator / connected device.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final iosLive = Platform.environment['AGENT_DEVICE_IOS_LIVE'] == '1';
  final androidLive = Platform.environment['AGENT_DEVICE_ANDROID_LIVE'] == '1';

  if (!iosLive && !androidLive) {
    test(
      'TS replay compat tests skipped',
      () {},
      skip: 'set AGENT_DEVICE_IOS_LIVE=1 and/or AGENT_DEVICE_ANDROID_LIVE=1',
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
  final tsReplaysDir = p.join(
    repoRoot,
    'agent-device',
    'test',
    'integration',
    'replays',
  );

  late Directory stateDir;
  late Directory screenshotDir;

  setUpAll(() async {
    stateDir = await Directory.systemTemp.createTemp('ad-ts-compat-');
    screenshotDir = await Directory.systemTemp.createTemp('ad-ts-compat-ss-');
  });

  tearDownAll(() async {
    if (await stateDir.exists()) await stateDir.delete(recursive: true);
    if (await screenshotDir.exists()) {
      await screenshotDir.delete(recursive: true);
    }
  });

  Future<void> runAdScript({
    required String scriptPath,
    required String platform,
    required String serial,
  }) async {
    final scriptName = p.basename(scriptPath);
    final argv = [
      'run',
      binPath,
      '--state-dir',
      stateDir.path,
      'replay',
      scriptPath,
      '--platform',
      platform,
      '--serial',
      serial,
      '--json',
    ];
    // ignore: avoid_print
    print('[compat] running $scriptName on $platform/$serial');
    final r = await Process.run(
      'dart',
      argv,
      workingDirectory: repoRoot,
      environment: {
        ...Platform.environment,
        'AD_SCREENSHOT_DIR': screenshotDir.path,
      },
    );
    final stdout = r.stdout.toString().trim();
    final firstLine = stdout.split('\n').first;
    Map<String, Object?>? envelope;
    try {
      envelope = jsonDecode(firstLine) as Map<String, Object?>;
    } catch (_) {
      fail(
        '$scriptName: could not parse JSON output.\n'
        'exit=${r.exitCode}\nstdout=$stdout\nstderr=${r.stderr}',
      );
    }
    final data = envelope['data'] as Map<String, Object?>?;
    expect(
      r.exitCode,
      0,
      reason: '$scriptName exit=${r.exitCode}\n'
          'stderr=${r.stderr}\nstdout=$stdout',
    );
    expect(
      data?['ok'],
      isTrue,
      reason: '$scriptName replay not ok.\n'
          'passed=${data?['passed']}  failed=${data?['failed']}\n'
          'steps=${jsonEncode(data?['steps'])}\n'
          'stderr=${r.stderr}',
    );
  }

  if (iosLive) {
    group('iOS simulator — TS replay scripts', () {
      late String udid;

      setUpAll(() async {
        udid = await _findBootedIosSimulator();
        // ignore: avoid_print
        print('[compat] iOS simulator: $udid');
      });

      final iosDir = Directory(p.join(tsReplaysDir, 'ios', 'simulator'));
      if (iosDir.existsSync()) {
        final scripts = iosDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.ad'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

        for (final script in scripts) {
          final name = p.basenameWithoutExtension(script.path);
          test(
            name,
            () => runAdScript(
              scriptPath: script.path,
              platform: 'ios',
              serial: udid,
            ),
            timeout: const Timeout(Duration(minutes: 3)),
          );
        }
      }
    });
  }

  if (androidLive) {
    group('Android — TS replay scripts', () {
      late String serial;

      setUpAll(() async {
        serial = await _findAndroidDevice();
        // ignore: avoid_print
        print('[compat] Android device: $serial');
      });

      final androidDir = Directory(p.join(tsReplaysDir, 'android'));
      if (androidDir.existsSync()) {
        final scripts = androidDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.ad'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

        for (final script in scripts) {
          final name = p.basenameWithoutExtension(script.path);
          test(
            name,
            () => runAdScript(
              scriptPath: script.path,
              platform: 'android',
              serial: serial,
            ),
            timeout: const Timeout(Duration(minutes: 3)),
          );
        }
      }
    });
  }
}

Future<String> _findBootedIosSimulator() async {
  final probe = await Process.run('xcrun', [
    'simctl',
    'list',
    'devices',
    'booted',
    '-j',
  ]);
  final decoded = jsonDecode(probe.stdout.toString()) as Map<String, Object?>;
  final byRuntime = (decoded['devices'] as Map?) ?? {};
  for (final e in byRuntime.values) {
    if (e is! List) continue;
    for (final d in e) {
      if (d is Map && d['state'] == 'Booted' && d['isAvailable'] == true) {
        final udid = d['udid'] as String?;
        if (udid != null) return udid;
      }
    }
  }
  throw StateError('No booted iOS simulator found.');
}

Future<String> _findAndroidDevice() async {
  final probe = await Process.run('adb', ['devices']);
  for (final line in probe.stdout.toString().split('\n')) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[1] == 'device' && parts[0].isNotEmpty) {
      return parts[0];
    }
  }
  throw StateError('No connected Android device found.');
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
