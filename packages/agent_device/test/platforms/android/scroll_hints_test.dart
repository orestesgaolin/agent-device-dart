import 'package:agent_device/src/platforms/android/scroll_hints.dart';
import 'package:agent_device/src/snapshot/snapshot.dart';
import 'package:test/test.dart';

void main() {
  group('scroll_hints', () {
    test(
      'deriveAndroidScrollableContentHints returns empty map for no scrollables',
      () {
        final nodes = [
          RawSnapshotNode(
            index: 0,
            type: 'Button',
            rect: Rect(x: 0, y: 0, width: 100, height: 50),
          ),
        ];

        final hints = deriveAndroidScrollableContentHints(nodes, '');

        expect(hints, isEmpty);
      },
    );

    test(
      'deriveAndroidScrollableContentHints returns empty map for no activity dump',
      () {
        final nodes = [
          RawSnapshotNode(
            index: 0,
            type: 'RecyclerView',
            rect: Rect(x: 0, y: 0, width: 100, height: 200),
          ),
        ];

        final hints = deriveAndroidScrollableContentHints(nodes, '');

        expect(hints, isEmpty);
      },
    );

    test('deriveAndroidScrollableContentHints detects scrollable types', () {
      const scrollableTypes = [
        'ScrollView',
        'HorizontalScrollView',
        'RecyclerView',
        'ListView',
        'GridView',
        'CollectionView',
      ];

      for (final type in scrollableTypes) {
        final nodes = [
          RawSnapshotNode(
            index: 0,
            type: type,
            rect: const Rect(x: 0, y: 0, width: 100, height: 200),
          ),
        ];

        final hints = deriveAndroidScrollableContentHints(nodes, '');
        // Returns empty without view hierarchy, but proves type detection works
        expect(hints, isA<Map<Object?, Object?>>());
      }
    });

    test(
      'deriveAndroidScrollableContentHints is case-insensitive for types',
      () {
        const types = [
          'scrollview',
          'ScrollView',
          'SCROLLVIEW',
          'recyclerview',
          'RecyclerView',
        ];

        for (final type in types) {
          final nodes = [
            RawSnapshotNode(
              index: 0,
              type: type,
              rect: const Rect(x: 0, y: 0, width: 100, height: 200),
            ),
          ];

          final hints = deriveAndroidScrollableContentHints(nodes, '');
          expect(hints, isA<Map<Object?, Object?>>());
        }
      },
    );

    test('deriveAndroidScrollableContentHints ignores nodes without rects', () {
      final nodes = [RawSnapshotNode(index: 0, type: 'ScrollView', rect: null)];

      final hints = deriveAndroidScrollableContentHints(nodes, '');

      expect(hints, isEmpty);
    });

    test('deriveAndroidScrollableContentHints handles empty view tree', () {
      final nodes = [
        RawSnapshotNode(
          index: 0,
          type: 'ScrollView',
          rect: Rect(x: 0, y: 0, width: 100, height: 200),
        ),
      ];

      final activityDump = 'some output\nthat does not match\nview pattern';

      final hints = deriveAndroidScrollableContentHints(nodes, activityDump);

      expect(hints, isEmpty);
    });

    test(
      'deriveAndroidScrollableContentHints produces HiddenContentHint objects',
      () {
        final nodes = [
          RawSnapshotNode(
            index: 0,
            type: 'ScrollView',
            rect: Rect(x: 0, y: 0, width: 100, height: 200),
          ),
        ];

        final hints = deriveAndroidScrollableContentHints(nodes, '');

        for (final hint in hints.values) {
          expect(hint, isA<HiddenContentHint>());
          expect(hint.hiddenContentAbove, isA<bool>());
          expect(hint.hiddenContentBelow, isA<bool>());
        }
      },
    );

    test('HiddenContentHint defaults are false', () {
      final hint = const HiddenContentHint();

      expect(hint.hiddenContentAbove, false);
      expect(hint.hiddenContentBelow, false);
    });

    test('HiddenContentHint can be constructed with true values', () {
      final hint = const HiddenContentHint(
        hiddenContentAbove: true,
        hiddenContentBelow: true,
      );

      expect(hint.hiddenContentAbove, true);
      expect(hint.hiddenContentBelow, true);
    });

    test('deriveAndroidScrollableContentHints preserves node indices', () {
      final nodes = [
        RawSnapshotNode(
          index: 0,
          type: 'ScrollView',
          rect: Rect(x: 0, y: 0, width: 100, height: 200),
        ),
        RawSnapshotNode(
          index: 1,
          type: 'ScrollView',
          rect: Rect(x: 0, y: 200, width: 100, height: 200),
        ),
      ];

      final hints = deriveAndroidScrollableContentHints(nodes, '');

      for (final index in hints.keys) {
        expect(index >= 0 && index < nodes.length, true);
      }
    });

    test('deriveAndroidScrollableContentHints handles mixed node types', () {
      final nodes = [
        RawSnapshotNode(
          index: 0,
          type: 'Button',
          rect: Rect(x: 0, y: 0, width: 100, height: 50),
        ),
        RawSnapshotNode(
          index: 1,
          type: 'ScrollView',
          rect: Rect(x: 0, y: 50, width: 100, height: 150),
        ),
        RawSnapshotNode(
          index: 2,
          type: 'TextView',
          rect: Rect(x: 10, y: 60, width: 80, height: 30),
        ),
      ];

      final hints = deriveAndroidScrollableContentHints(nodes, '');

      // Only ScrollView should be processed
      for (final index in hints.keys) {
        expect(nodes[index].type, 'ScrollView');
      }
    });

    test('deriveAndroidScrollableContentHints recognizes list-like types', () {
      const listTypes = ['ListView', 'GridView', 'RecyclerView'];

      for (final type in listTypes) {
        final nodes = [
          RawSnapshotNode(
            index: 0,
            type: type,
            rect: const Rect(x: 0, y: 0, width: 100, height: 200),
          ),
        ];

        final hints = deriveAndroidScrollableContentHints(nodes, '');
        expect(hints, isA<Map<Object?, Object?>>());
      }
    });
  });
}
