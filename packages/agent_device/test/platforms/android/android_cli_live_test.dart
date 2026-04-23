@TestOn('mac-os || linux')
@Tags(['android-live'])
library;

// ignore_for_file: avoid_print — this is a diagnostic test that prints
// progress against a real device.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Blackbox live test for the `agent-device` CLI against a real Android
/// emulator / device. Every command is invoked via `dart run
/// bin/agent_device.dart`, so this exercises the same code path end users
/// hit from the shell. JSON mode is used so we can assert on structured
/// output without fragile human-format matching.
///
/// Gated on AGENT_DEVICE_ANDROID_LIVE=1. Run manually:
///
///     AGENT_DEVICE_ANDROID_LIVE=1 dart test \
///       packages/agent_device/test/platforms/android/android_cli_live_test.dart
void main() {
  final gate = Platform.environment['AGENT_DEVICE_ANDROID_LIVE'];
  if (gate != '1') {
    test(
      'android CLI live tests skipped',
      () {},
      skip: 'set AGENT_DEVICE_ANDROID_LIVE=1 to run',
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

  Future<CliResult> runCli(List<String> args) async {
    final result = await Process.run('dart', [
      'run',
      binPath,
      ...args,
    ], workingDirectory: repoRoot);
    return CliResult(
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
  }

  /// Parse the first line of stdout as a JSON envelope. Returns a
  /// `(success, data | error)` pair.
  ({bool success, Object? data, Map<String, Object?>? error}) parseJson(
    String stdout,
  ) {
    final firstLine = stdout.trim().split('\n').first;
    final decoded = jsonDecode(firstLine) as Map<String, Object?>;
    return (
      success: decoded['success'] == true,
      data: decoded['data'],
      error: decoded['error'] as Map<String, Object?>?,
    );
  }

  group('agent-device CLI (live Android)', () {
    setUpAll(() async {
      // Sanity: emulator/device must be attached. If not, fail here rather
      // than inside every test.
      final result = await runCli([
        'devices',
        '--platform',
        'android',
        '--json',
      ]);
      expect(result.exitCode, 0, reason: 'devices failed: ${result.stderr}');
      final envelope = parseJson(result.stdout);
      expect(envelope.success, isTrue);
      final list = envelope.data as List;
      expect(list, isNotEmpty, reason: 'No Android devices attached.');
      print(
        '[live] using ${(list.first as Map)['id']} '
        '(${(list.first as Map)['name']})',
      );
    });

    tearDownAll(() async {
      // Land on the home screen so subsequent manual runs aren't stuck
      // mid-flow.
      await runCli(['home', '--platform', 'android', '--json']);
    });

    // ---- read-only commands -------------------------------------------------

    test('devices: human mode prints a table', () async {
      final r = await runCli(['devices', '--platform', 'android']);
      expect(r.exitCode, 0);
      expect(r.stdout, contains('android'));
      expect(r.stdout, isNot(contains('success')));
    });

    test('devices --json emits {success: true, data: [...]}', () async {
      final r = await runCli(['devices', '--platform', 'android', '--json']);
      expect(r.exitCode, 0);
      final env = parseJson(r.stdout);
      expect(env.success, isTrue);
      expect(env.data, isA<List<Object?>>());
      final first = (env.data as List).first as Map<String, Object?>;
      expect(first['id'], isA<String>());
      expect(first['platform'], 'android');
    });

    test('appstate reports the current foreground app', () async {
      final r = await runCli(['appstate', '--platform', 'android', '--json']);
      expect(r.exitCode, 0);
      final env = parseJson(r.stdout);
      expect(env.success, isTrue);
      final state = env.data as Map<String, Object?>;
      expect(state['state'], isNotNull);
    });

    test('apps lists installed packages', () async {
      final r = await runCli(['apps', '--platform', 'android', '--json']);
      expect(r.exitCode, 0);
      final env = parseJson(r.stdout);
      expect(env.success, isTrue);
      final apps = env.data as List;
      expect(apps, isNotEmpty);
      expect(apps.first, isA<Map<Object?, Object?>>());
      expect((apps.first as Map)['id'], isA<String>());
    });

    // ---- navigation ---------------------------------------------------------

    test('home + snapshot lands on launcher with nodes', () async {
      expect((await runCli(['home', '--platform', 'android'])).exitCode, 0);
      await Future<void>.delayed(const Duration(seconds: 1));
      final r = await runCli(['snapshot', '--platform', 'android', '--json']);
      expect(r.exitCode, 0);
      final env = parseJson(r.stdout);
      expect(env.success, isTrue);
      final data = env.data as Map<String, Object?>;
      expect(data['nodeCount'], isA<int>());
      expect(data['nodeCount'] as int, greaterThan(0));
    });

    test('back + app-switcher are callable', () async {
      expect((await runCli(['back', '--platform', 'android'])).exitCode, 0);
      expect(
        (await runCli(['app-switcher', '--platform', 'android'])).exitCode,
        0,
      );
      // Leave the device on home for the next test.
      await runCli(['home', '--platform', 'android']);
    });

    // ---- open / snapshot / close flow --------------------------------------

    test('open → snapshot → close(settings) round-trip', () async {
      final open = await runCli([
        'open',
        'settings',
        '--platform',
        'android',
        '--json',
      ]);
      expect(open.exitCode, 0, reason: open.stderr);
      expect(parseJson(open.stdout).success, isTrue);

      await Future<void>.delayed(const Duration(seconds: 2));

      final snap = await runCli([
        'snapshot',
        '--platform',
        'android',
        '--json',
      ]);
      expect(snap.exitCode, 0);
      final snapEnv = parseJson(snap.stdout);
      expect(snapEnv.success, isTrue);
      final data = snapEnv.data as Map<String, Object?>;
      expect(data['nodeCount'] as int, greaterThan(5));
      expect(data['rawNodeCount'], isA<int>());

      // getAppState should now report SOME foreground app — which
      // specific one depends on how the emulator's Android image resolves
      // the settings intent (on Pixel 9 Pro API 35 it redirects through
      // Google Play Services' multidevice flow). We only assert that we
      // got a real packageName, not a specific value.
      final state = await runCli([
        'appstate',
        '--platform',
        'android',
        '--json',
      ]);
      expect(state.exitCode, 0);
      final stateData = parseJson(state.stdout).data as Map<String, Object?>;
      expect(stateData['packageName'], isA<String>());
      expect((stateData['packageName'] as String).isNotEmpty, isTrue);
      print(
        '[live] after open settings, foreground=${stateData['packageName']}',
      );

      // Force-stop Settings so the next test starts from a clean slate.
      final close = await runCli([
        'close',
        'com.android.settings',
        '--platform',
        'android',
        '--json',
      ]);
      expect(close.exitCode, 0);
    });

    test('snapshot --interactive + --compact filter nodes', () async {
      await runCli(['open', 'settings', '--platform', 'android']);
      await Future<void>.delayed(const Duration(seconds: 2));

      final full =
          parseJson(
                (await runCli([
                  'snapshot',
                  '--platform',
                  'android',
                  '--json',
                ])).stdout,
              ).data
              as Map<String, Object?>;
      final interactive =
          parseJson(
                (await runCli([
                  'snapshot',
                  '-i',
                  '-c',
                  '--platform',
                  'android',
                  '--json',
                ])).stdout,
              ).data
              as Map<String, Object?>;

      final fullCount = full['nodeCount'] as int;
      final interactiveCount = interactive['nodeCount'] as int;
      print(
        '[live] snapshot full=$fullCount, interactive+compact=$interactiveCount',
      );
      // Interactive + compact should never exceed full.
      expect(interactiveCount, lessThanOrEqualTo(fullCount));
    });

    // ---- screenshot ---------------------------------------------------------

    test('screenshot writes a valid PNG file', () async {
      final tmp = File(
        p.join(
          Directory.systemTemp.path,
          'agent-device-cli-${DateTime.now().microsecondsSinceEpoch}.png',
        ),
      );
      addTearDown(() async {
        if (await tmp.exists()) await tmp.delete();
      });
      final r = await runCli([
        'screenshot',
        tmp.path,
        '--platform',
        'android',
        '--json',
      ]);
      expect(r.exitCode, 0, reason: r.stderr);
      expect(await tmp.exists(), isTrue);
      final bytes = await tmp.readAsBytes();
      // PNG magic number.
      expect(bytes.take(4).toList(), [0x89, 0x50, 0x4E, 0x47]);
      expect(bytes.length, greaterThan(1000));
    });

    // ---- clipboard ----------------------------------------------------------

    test(
      'clipboard --set round-trips or reports UNSUPPORTED_OPERATION',
      () async {
        // `cmd clipboard set-primary-clip` requires permissions that some
        // emulator images (notably google_apis_playstore on API 35) lock down.
        // Accept either a successful round-trip or a clean UNSUPPORTED_OPERATION
        // error — both are valid outcomes depending on the image.
        const text = 'agent-device-clipboard-probe-1234';
        final set = await runCli([
          'clipboard',
          '--set',
          text,
          '--platform',
          'android',
          '--json',
        ]);
        if (set.exitCode == 0) {
          // Write worked — confirm the read returns the same value.
          final get = await runCli([
            'clipboard',
            '--platform',
            'android',
            '--json',
          ]);
          expect(get.exitCode, 0);
          final data = parseJson(get.stdout).data as Map<String, Object?>;
          expect(data['clipboard'], text);
        } else {
          // Write rejected by device — must be the documented unsupported
          // operation error so we know it isn't a port bug.
          expect(set.exitCode, 1);
          final env = parseJson(set.stdout);
          expect(env.success, isFalse);
          expect(env.error!['code'], 'UNSUPPORTED_OPERATION');
          print(
            '[live] clipboard --set unsupported on this image: '
            '${env.error!['message']}',
          );
        }
      },
    );

    // ---- coordinate-based interactions --------------------------------------

    test('tap at a safe location runs without error', () async {
      // Tap the middle of the screen. Works on any app state — result may
      // have no visible effect, but the command should succeed.
      final r = await runCli([
        'tap',
        '540',
        '1200',
        '--platform',
        'android',
        '--json',
      ]);
      expect(r.exitCode, 0, reason: r.stderr);
      final data = parseJson(r.stdout).data as Map<String, Object?>;
      expect(data['tapped'], [540, 1200]);
    });

    test('swipe up runs without error', () async {
      final r = await runCli([
        'swipe',
        '540',
        '1800',
        '540',
        '600',
        '--duration-ms',
        '250',
        '--platform',
        'android',
        '--json',
      ]);
      expect(r.exitCode, 0, reason: r.stderr);
      final data = parseJson(r.stdout).data as Map<String, Object?>;
      expect(data['swiped'], [540, 1800, 540, 600]);
    });

    test('scroll down + up are callable', () async {
      final down = await runCli([
        'scroll',
        'down',
        '--platform',
        'android',
        '--json',
      ]);
      expect(down.exitCode, 0, reason: down.stderr);
      final up = await runCli([
        'scroll',
        'up',
        '--platform',
        'android',
        '--json',
      ]);
      expect(up.exitCode, 0, reason: up.stderr);
    });

    test('longpress at a safe location runs without error', () async {
      final r = await runCli([
        'longpress',
        '540',
        '1200',
        '--duration-ms',
        '500',
        '--platform',
        'android',
        '--json',
      ]);
      expect(r.exitCode, 0, reason: r.stderr);
    });

    // ---- focus / type / fill ------------------------------------------------

    test('type runs without error (may or may not land in a field)', () async {
      // The device might not be in a text-field context; the command itself
      // should still succeed — it just dispatches `input text` via adb.
      final r = await runCli([
        'type',
        'hello',
        '--platform',
        'android',
        '--json',
      ]);
      expect(r.exitCode, 0, reason: r.stderr);
    });

    test('focus at a safe location runs without error', () async {
      final r = await runCli([
        'focus',
        '540',
        '1200',
        '--platform',
        'android',
        '--json',
      ]);
      expect(r.exitCode, 0, reason: r.stderr);
    });

    // ---- error-path assertions ---------------------------------------------

    test('tap without coords exits 1 with normalized JSON error', () async {
      final r = await runCli(['tap', '--platform', 'android', '--json']);
      expect(r.exitCode, 1);
      final envelope = parseJson(r.stdout);
      expect(envelope.success, isFalse);
      expect(envelope.error, isNotNull);
      expect(envelope.error!['code'], 'INVALID_ARGS');
      expect(envelope.error!['message'], contains('tap'));
    });

    test('tap with non-integer coords exits 1', () async {
      final r = await runCli([
        'tap',
        'not-a-number',
        '100',
        '--platform',
        'android',
        '--json',
      ]);
      expect(r.exitCode, 1);
      final env = parseJson(r.stdout);
      expect(env.success, isFalse);
      expect(env.error!['code'], 'INVALID_ARGS');
    });

    test('open without a target exits 1', () async {
      final r = await runCli(['open', '--platform', 'android', '--json']);
      expect(r.exitCode, 1);
      expect(parseJson(r.stdout).success, isFalse);
    });

    test('open of a non-existent package exits 1', () async {
      final r = await runCli([
        'open',
        'com.definitely.not.a.real.package.xyz.1234',
        '--platform',
        'android',
        '--json',
      ]);
      expect(r.exitCode, 1);
      final env = parseJson(r.stdout);
      expect(env.success, isFalse);
      expect(env.error!['code'], anyOf('APP_NOT_INSTALLED', 'COMMAND_FAILED'));
    });

    test('unknown platform exits 64 (usage) or 1', () async {
      final r = await runCli(['devices', '--platform', 'not-a-platform']);
      expect(r.exitCode, anyOf(64, 1));
    });

    test('unknown command exits 64 (usage)', () async {
      final r = await runCli(['definitely-not-a-command']);
      expect(r.exitCode, 64);
    });

    // ---- final smoke --------------------------------------------------------

    test('home followed by snapshot still succeeds at the end', () async {
      expect((await runCli(['home', '--platform', 'android'])).exitCode, 0);
      await Future<void>.delayed(const Duration(seconds: 1));
      final r = await runCli(['snapshot', '--platform', 'android', '--json']);
      expect(r.exitCode, 0);
      expect(parseJson(r.stdout).success, isTrue);
    });
  });
}

class CliResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  const CliResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });
}

/// Walk up from the test file until we find the agent-device-dart repo
/// root (contains the top-level pubspec.yaml with `workspace:` entries).
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
  // Fallback: assume cwd is the repo root (common in CI).
  return Directory.current.path;
}
