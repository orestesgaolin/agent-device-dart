@TestOn('mac-os || linux')
@Tags(['android-live'])
library;

// ignore_for_file: avoid_print — this is a diagnostic test that prints
// progress against a real device.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Phase 6A proof-of-life: verify that session state survives between
/// separate CLI process invocations, so `agent-device open` in shell A
/// and `agent-device snapshot` in shell B land on the same device and
/// remember the previously opened app.
///
/// Gated on AGENT_DEVICE_ANDROID_LIVE=1. Uses a throwaway temp directory
/// as `--state-dir` so tests don't fight over the user's real
/// `~/.agent-device/`.
void main() {
  final gate = Platform.environment['AGENT_DEVICE_ANDROID_LIVE'];
  if (gate != '1') {
    test(
      'android cross-invocation tests skipped',
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

  late Directory stateDir;
  setUp(() async {
    stateDir = await Directory.systemTemp.createTemp('ad-xinv-');
  });
  tearDown(() async {
    if (await stateDir.exists()) await stateDir.delete(recursive: true);
  });

  Future<CliResult> cli(List<String> args) async {
    final r = await Process.run('dart', [
      'run',
      binPath,
      '--state-dir',
      stateDir.path,
      ...args,
    ], workingDirectory: repoRoot);
    return CliResult(
      exitCode: r.exitCode,
      stdout: r.stdout.toString(),
      stderr: r.stderr.toString(),
    );
  }

  Map<String, Object?> parseOk(CliResult r) {
    final line = r.stdout.trim().split('\n').first;
    final decoded = jsonDecode(line) as Map<String, Object?>;
    expect(decoded['success'], isTrue, reason: r.stdout);
    return decoded['data'] as Map<String, Object?>;
  }

  group('cross-invocation session sharing (live Android)', () {
    test('open in process A populates session read by process B', () async {
      final open = await cli([
        'open',
        'settings',
        '--platform',
        'android',
        '--json',
      ]);
      expect(open.exitCode, 0, reason: open.stderr);

      // Separate process B reads the same session dir.
      final show = await cli(['session', 'show', '--json']);
      expect(show.exitCode, 0);
      final record = parseOk(show);
      expect(record['deviceSerial'], 'emulator-5554');
      expect(record['appId'], 'settings');
    });

    test(
      'snapshot without --platform reuses the remembered deviceSerial',
      () async {
        // Process A: bind the session.
        expect(
          (await cli(['open', 'settings', '--platform', 'android'])).exitCode,
          0,
        );

        // Process B: no --platform flag at all — must resolve from session.
        final snap = await cli(['snapshot', '--json']);
        expect(snap.exitCode, 0, reason: snap.stderr);
        final data = parseOk(snap);
        expect(data['deviceSerial'], 'emulator-5554');
        expect(data['nodeCount'], isA<int>());
        expect(data['nodeCount'] as int, greaterThan(0));
      },
    );

    test(
      'open→snapshot preserves appId across invocations (merge, not clobber)',
      () async {
        await cli(['open', 'settings', '--platform', 'android']);
        await cli([
          'snapshot',
          '--json',
        ]); // would have clobbered appId before the merge fix
        final show = await cli(['session', 'show', '--json']);
        final record = parseOk(show);
        expect(
          record['appId'],
          'settings',
          reason: 'snapshot should merge into, not overwrite, the record',
        );
      },
    );

    test(
      'session clear removes the record so next CLI call is fresh',
      () async {
        await cli(['open', 'settings', '--platform', 'android']);
        expect((await cli(['session', 'clear'])).exitCode, 0);
        final show = await cli(['session', 'show']);
        expect(show.stdout, contains('not found'));
      },
    );

    test('--ephemeral-session writes nothing to disk', () async {
      final open = await cli([
        'open',
        'settings',
        '--platform',
        'android',
        '--ephemeral-session',
      ]);
      expect(open.exitCode, 0, reason: open.stderr);
      // The sessions/ dir should either not exist, or be empty.
      final dir = Directory(p.join(stateDir.path, 'sessions'));
      if (await dir.exists()) {
        final entries = await dir.list().toList();
        expect(
          entries,
          isEmpty,
          reason: '--ephemeral-session must not persist.',
        );
      }
    });

    test(
      'session list after two opens with distinct --session names',
      () async {
        await cli([
          'open',
          'settings',
          '--platform',
          'android',
          '--session',
          'a',
        ]);
        await cli([
          'open',
          'settings',
          '--platform',
          'android',
          '--session',
          'b',
        ]);
        final list = await cli(['session', 'list', '--json']);
        expect(list.exitCode, 0);
        final envelope =
            jsonDecode(list.stdout.trim().split('\n').first)
                as Map<String, Object?>;
        expect(envelope['success'], isTrue);
        final records = envelope['data'] as List;
        expect(records, hasLength(2));
        final names = records.map((r) => (r as Map)['name']).toList();
        expect(names, containsAll(['a', 'b']));
      },
    );
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
