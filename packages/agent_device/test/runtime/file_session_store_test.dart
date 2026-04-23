import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:agent_device/agent_device.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('FileSessionStore', () {
    late Directory tmp;
    late FileSessionStore store;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('ad-fs-store-');
      store = FileSessionStore(p.join(tmp.path, 'sessions'));
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('get returns null when no file exists', () async {
      expect(await store.get('missing'), isNull);
    });

    test('set then get round-trips every stable field', () async {
      await store.set(
        const CommandSessionRecord(
          name: 'default',
          appId: 'com.example',
          appBundleId: 'com.example.bundle',
          appName: 'Example',
          backendSessionId: 'bs-1',
          deviceSerial: 'emu-1',
          metadata: {'foo': 'bar', 'n': 42},
        ),
      );
      final r = await store.get('default');
      expect(r, isNotNull);
      expect(r!.appId, 'com.example');
      expect(r.appBundleId, 'com.example.bundle');
      expect(r.appName, 'Example');
      expect(r.backendSessionId, 'bs-1');
      expect(r.deviceSerial, 'emu-1');
      expect(r.metadata, {'foo': 'bar', 'n': 42});
    });

    test('set writes the file under sessionsDir with safe name', () async {
      await store.set(const CommandSessionRecord(name: 'my/nasty:name!'));
      final file = File(p.join(store.sessionsDir, 'my_nasty_name_.json'));
      expect(await file.exists(), isTrue);
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      expect(json['name'], 'my/nasty:name!');
    });

    test(
      'set is atomic: no .tmp.* left behind after successful write',
      () async {
        await store.set(const CommandSessionRecord(name: 'default'));
        final dir = Directory(store.sessionsDir);
        final contents = await dir.list().toList();
        final names = contents.map((e) => p.basename(e.path)).toList();
        expect(names, contains('default.json'));
        expect(names.where((n) => n.contains('.tmp')), isEmpty);
      },
    );

    test('delete removes the file', () async {
      await store.set(const CommandSessionRecord(name: 'default'));
      expect(await store.get('default'), isNotNull);
      await store.delete('default');
      expect(await store.get('default'), isNull);
      final file = File(p.join(store.sessionsDir, 'default.json'));
      expect(await file.exists(), isFalse);
    });

    test('delete is safe on a missing session', () async {
      await store.delete('never-existed');
      expect(await store.get('never-existed'), isNull);
    });

    test('list returns every stored session, alphabetised', () async {
      await store.set(const CommandSessionRecord(name: 'b'));
      await store.set(const CommandSessionRecord(name: 'a'));
      await store.set(const CommandSessionRecord(name: 'c'));
      final items = await store.list();
      expect(items.map((r) => r.name), ['a', 'b', 'c']);
    });

    test('list ignores corrupt files', () async {
      await store.set(const CommandSessionRecord(name: 'good'));
      await Directory(store.sessionsDir).create(recursive: true);
      await File(
        p.join(store.sessionsDir, 'corrupt.json'),
      ).writeAsString('{this is not json');
      final items = await store.list();
      expect(items.map((r) => r.name), ['good']);
    });

    test('get returns null for corrupt file rather than throwing', () async {
      await Directory(store.sessionsDir).create(recursive: true);
      await File(
        p.join(store.sessionsDir, 'corrupt.json'),
      ).writeAsString('not json');
      expect(await store.get('corrupt'), isNull);
    });

    test('snapshot field is intentionally not persisted', () async {
      // Round-trip a record with null snapshot (Phase 6A: we never persist
      // SnapshotState to disk — the toJson comment documents this).
      await store.set(
        const CommandSessionRecord(name: 'default', appId: 'com.example'),
      );
      final raw = await File(
        p.join(store.sessionsDir, 'default.json'),
      ).readAsString();
      expect(raw, isNot(contains('"snapshot"')));
    });

    test('concurrent writes from isolates do not corrupt the file', () async {
      // Spawn 8 isolates all writing distinct records under the same name;
      // the last writer wins but the file must always be decodable.
      const name = 'default';
      const n = 8;
      final futures = <Future<void>>[];
      for (var i = 0; i < n; i++) {
        futures.add(
          Isolate.run(() async {
            final s = FileSessionStore(store.sessionsDir);
            await s.set(
              CommandSessionRecord(
                name: name,
                appId: 'com.example.$i',
                metadata: {'i': i},
              ),
            );
          }),
        );
      }
      await Future.wait(futures);

      // Final state must be readable and valid JSON with a populated appId.
      final r = await store.get(name);
      expect(r, isNotNull);
      expect(r!.name, name);
      expect(r.appId, matches(RegExp(r'^com\.example\.[0-7]$')));
    });
  });
}
