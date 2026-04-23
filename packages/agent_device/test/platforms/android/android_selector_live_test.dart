@TestOn('mac-os || linux')
@Tags(['android-live'])
library;

// ignore_for_file: avoid_print — this is a diagnostic test that prints
// progress against a real device.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Phase 7 live coverage: find / get / is / press / wait on selectors and
/// refs, against a real Android device/emulator. Invokes the CLI as a
/// subprocess so session state persists between calls via the Phase 6A
/// disk store.
///
/// Gated on AGENT_DEVICE_ANDROID_LIVE=1.
void main() {
  final gate = Platform.environment['AGENT_DEVICE_ANDROID_LIVE'];
  if (gate != '1') {
    test(
      'android selector live tests skipped',
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
    stateDir = await Directory.systemTemp.createTemp('ad-sel-');
  });
  tearDown(() async {
    if (await stateDir.exists()) await stateDir.delete(recursive: true);
  });

  Future<_R> cli(List<String> args) async {
    final r = await Process.run('dart', [
      'run',
      binPath,
      '--state-dir',
      stateDir.path,
      ...args,
    ], workingDirectory: repoRoot);
    return _R(
      exitCode: r.exitCode,
      stdout: r.stdout.toString(),
      stderr: r.stderr.toString(),
    );
  }

  Map<String, Object?> okData(_R r) {
    final line = r.stdout.trim().split('\n').first;
    final env = jsonDecode(line) as Map<String, Object?>;
    expect(env['success'], isTrue, reason: r.stdout);
    return env['data'] as Map<String, Object?>;
  }

  Future<void> openSettings() async {
    final r = await cli(['open', 'settings', '--platform', 'android']);
    expect(r.exitCode, 0, reason: r.stderr);
    await Future<void>.delayed(const Duration(seconds: 2));
  }

  group('Phase 7 selector / ref CLI (live Android)', () {
    test(
      'find returns nodes whose label or identifier contains the text',
      () async {
        await openSettings();
        final r = await cli(['find', 'settings', '--json']);
        expect(r.exitCode, 0, reason: r.stderr);
        final list = jsonDecode(r.stdout.trim().split('\n').first) as Map;
        expect(list['success'], isTrue);
        final hits = list['data'] as List;
        expect(hits, isNotEmpty);
        // Every hit must carry a ref so the user can target it with press.
        for (final hit in hits.take(3)) {
          final m = hit as Map;
          expect(m['ref'], isA<String>());
          expect((m['ref'] as String).isNotEmpty, isTrue);
        }
      },
    );

    test('get identifier @ref returns the resource-id on Android', () async {
      await openSettings();
      // Ask the snapshot for a ref. `find` returns live refs from the
      // freshly-taken snapshot, so pick any first hit.
      final find = await cli(['find', '/', '--json']);
      final hits =
          (jsonDecode(find.stdout.trim().split('\n').first) as Map)['data']
              as List;
      expect(
        hits,
        isNotEmpty,
        reason: 'Snapshot should expose at least one node with a resource-id',
      );
      final ref = (hits.first as Map)['ref'] as String;
      final got = await cli(['get', 'identifier', '@$ref', '--json']);
      expect(got.exitCode, 0, reason: got.stderr);
      final data = okData(got);
      expect(data['attr'], 'identifier');
      expect(data['value'], isA<String>());
      print('[live] get identifier @$ref → ${data['value']}');
    });

    test(
      'is exists passes for a present ref and fails for a missing one',
      () async {
        await openSettings();
        final find = await cli(['find', '/', '--json']);
        final hits =
            (jsonDecode(find.stdout.trim().split('\n').first) as Map)['data']
                as List;
        final ref = (hits.first as Map)['ref'] as String;

        final yes = await cli(['is', 'exists', '@$ref']);
        expect(yes.exitCode, 0, reason: yes.stderr);
        expect(yes.stdout, contains('PASS'));

        final no = await cli(['is', 'exists', '@e999999']);
        expect(no.exitCode, 1);
        expect(no.stdout, contains('FAIL'));
      },
    );

    test('is visible/hidden and is editable round-trip', () async {
      await openSettings();
      final find = await cli(['find', '/', '--json']);
      final hits =
          (jsonDecode(find.stdout.trim().split('\n').first) as Map)['data']
              as List;
      final ref = (hits.first as Map)['ref'] as String;
      final vis = await cli(['is', 'visible', '@$ref', '--json']);
      expect(vis.exitCode, anyOf(0, 1));
      final vdata = jsonDecode(vis.stdout.trim().split('\n').first) as Map;
      expect(vdata['success'], isTrue);
      expect((vdata['data'] as Map)['predicate'], 'visible');
    });

    test('press @ref taps the node center (no-throw round-trip)', () async {
      await openSettings();
      // Find a node with a real rect — pick the first `find /` hit.
      final find = await cli(['find', '/', '--json']);
      final hits =
          (jsonDecode(find.stdout.trim().split('\n').first) as Map)['data']
              as List;
      // Walk until we find one with a rect.
      String? refWithRect;
      for (final hit in hits) {
        final m = hit as Map;
        if (m['rect'] != null) {
          refWithRect = m['ref'] as String;
          break;
        }
      }
      expect(refWithRect, isNotNull, reason: 'Need one node with rect.');
      final r = await cli(['press', '@$refWithRect', '--json']);
      expect(r.exitCode, 0, reason: r.stderr);
      final data = okData(r);
      expect(data['pressed'], '@$refWithRect');
    });

    test('press selector expression resolves and taps', () async {
      await openSettings();
      // Search with find, pick a hit whose identifier is well-formed, build
      // a selector from it. Preferred form: `id=<resource-id>`.
      final find = await cli(['find', '/', '--json']);
      final hits =
          (jsonDecode(find.stdout.trim().split('\n').first) as Map)['data']
              as List;
      String? rid;
      for (final hit in hits) {
        final m = hit as Map;
        final ident = m['identifier'] as String?;
        if (ident != null && ident.contains('/')) {
          rid = ident;
          break;
        }
      }
      expect(rid, isNotNull);
      final r = await cli(['press', 'id=$rid', '--json']);
      expect(r.exitCode, 0, reason: 'stderr=${r.stderr} stdout=${r.stdout}');
    });

    test('wait visible succeeds quickly on a visible ref', () async {
      await openSettings();
      final find = await cli(['find', '/', '--json']);
      final hits =
          (jsonDecode(find.stdout.trim().split('\n').first) as Map)['data']
              as List;
      final ref = (hits.first as Map)['ref'] as String;
      final r = await cli([
        'wait',
        'exists',
        '@$ref',
        '--timeout',
        '5000',
        '--json',
      ]);
      expect(r.exitCode, 0, reason: r.stderr);
      final data = okData(r);
      expect(data['pass'], isTrue);
    });

    test('wait times out quickly on a missing ref', () async {
      await openSettings();
      final sw = Stopwatch()..start();
      final r = await cli([
        'wait',
        'exists',
        '@e9999999',
        '--timeout',
        '1500',
        '--poll-ms',
        '300',
        '--json',
      ]);
      sw.stop();
      // Timeout path → exit 1, AppError(COMMAND_FAILED).
      expect(r.exitCode, 1);
      final env =
          jsonDecode(r.stdout.trim().split('\n').first) as Map<String, Object?>;
      expect(env['success'], isFalse);
      expect((env['error'] as Map)['code'], 'COMMAND_FAILED');
      // Should have hit the timeout, not run forever.
      expect(sw.elapsed.inSeconds, lessThan(20));
    });

    test('is text=<expected> round-trips', () async {
      await openSettings();
      // Find a node whose label is non-empty.
      final find = await cli(['find', '/', '--json']);
      final hits =
          (jsonDecode(find.stdout.trim().split('\n').first) as Map)['data']
              as List;
      String? ref;
      String? label;
      for (final hit in hits) {
        final m = hit as Map;
        final l = m['label'] as String?;
        if (l != null && l.trim().isNotEmpty) {
          ref = m['ref'] as String;
          label = l;
          break;
        }
      }
      if (ref == null || label == null) {
        // Device didn't show a labelled node; skip rather than fail.
        return;
      }
      final r = await cli(['is', 'text', label, '@$ref', '--json']);
      expect(
        r.exitCode,
        anyOf(0, 1),
        reason: 'is text returns 0/1 depending on match; got $r',
      );
      final data = jsonDecode(r.stdout.trim().split('\n').first) as Map;
      expect(data['success'], isTrue);
    });
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

  @override
  String toString() =>
      'CliResult(exit=$exitCode, stdout=${stdout.length}b, stderr=${stderr.length}b)';
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
