import 'package:agent_device/agent_device.dart';
import 'package:test/test.dart';

void main() {
  group('MemorySessionStore', () {
    test('roundtrips set / get', () async {
      final store = createMemorySessionStore();
      await store.set(
        const CommandSessionRecord(name: 'default', deviceSerial: 'x123'),
      );
      final r = await store.get('default');
      expect(r, isNotNull);
      expect(r!.deviceSerial, 'x123');
    });

    test('copyWith merges fields', () {
      const base = CommandSessionRecord(name: 'default', deviceSerial: 'x');
      final updated = base.copyWith(appId: 'com.example', deviceSerial: 'y');
      expect(updated.name, 'default');
      expect(updated.appId, 'com.example');
      expect(updated.deviceSerial, 'y');
    });

    test('copyWith(clearFields) clears nullable fields to null', () {
      const base = CommandSessionRecord(
        name: 'default',
        appId: 'com.example',
        deviceSerial: 'x',
      );
      final cleared = base.copyWith(clearFields: const {'appId'});
      expect(cleared.appId, isNull);
      expect(cleared.deviceSerial, 'x');
      expect(cleared.name, 'default');
    });

    test(
      'copyWith(clearFields) wins over a positive value for the same field',
      () {
        const base = CommandSessionRecord(
          name: 'default',
          appId: 'com.example',
        );
        final out = base.copyWith(
          appId: 'com.other',
          clearFields: const {'appId'},
        );
        expect(out.appId, isNull);
      },
    );

    test('delete removes record', () async {
      final store = createMemorySessionStore();
      await store.set(const CommandSessionRecord(name: 'default'));
      expect(await store.get('default'), isNotNull);
      await store.delete('default');
      expect(await store.get('default'), isNull);
    });

    test('list returns all records', () async {
      final store = createMemorySessionStore([
        const CommandSessionRecord(name: 'a'),
        const CommandSessionRecord(name: 'b'),
      ]);
      final items = await store.list();
      expect(items.map((r) => r.name), unorderedEquals(['a', 'b']));
    });

    test('get returns null for missing session', () async {
      final store = createMemorySessionStore();
      expect(await store.get('missing'), isNull);
    });
  });
}
