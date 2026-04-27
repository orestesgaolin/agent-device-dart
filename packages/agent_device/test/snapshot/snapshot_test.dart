import 'package:agent_device/src/snapshot/snapshot.dart';
import 'package:test/test.dart';

void main() {
  group('snapshot.dart', () {
    test('Point and Rect toJson', () {
      final point = const Point(x: 10.5, y: 20.5);
      expect(point.toJson(), equals({'x': 10.5, 'y': 20.5}));

      final rect = const Rect(x: 0, y: 0, width: 100, height: 200);
      expect(
        rect.toJson(),
        equals({'x': 0, 'y': 0, 'width': 100, 'height': 200}),
      );
    });

    test('attachRefs assigns sequential ref strings', () {
      final nodes = [
        RawSnapshotNode(index: 0, type: 'button', label: 'OK'),
        RawSnapshotNode(index: 1, type: 'text', label: 'Title'),
      ];

      final withRefs = attachRefs(nodes);
      expect(withRefs.length, equals(2));
      expect(withRefs[0].ref, equals('e1'));
      expect(withRefs[1].ref, equals('e2'));
    });

    test('normalizeRef handles @ prefix', () {
      expect(normalizeRef('@e1'), equals('e1'));
      expect(normalizeRef('e1'), equals('e1'));
      expect(normalizeRef('@'), isNull);
      expect(normalizeRef('not-a-ref'), isNull);
    });

    test('findNodeByRef returns node by reference', () {
      final nodes = [
        SnapshotNode(index: 0, ref: 'e1', label: 'First'),
        SnapshotNode(index: 1, ref: 'e2', label: 'Second'),
      ];

      expect(findNodeByRef(nodes, 'e1')?.label, equals('First'));
      expect(findNodeByRef(nodes, 'e2')?.label, equals('Second'));
      expect(findNodeByRef(nodes, 'e3'), isNull);
    });

    test('centerOfRect calculates center point correctly', () {
      final rect = const Rect(x: 0, y: 0, width: 100, height: 100);
      final center = centerOfRect(rect);
      expect(center.x, equals(50));
      expect(center.y, equals(50));
    });
  });
}
