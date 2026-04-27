import 'package:agent_device/src/snapshot/snapshot.dart';
import 'package:agent_device/src/snapshot/tree.dart';
import 'package:test/test.dart';

void main() {
  group('tree.dart', () {
    test('normalizeSnapshotTree repairs parent indices', () {
      final nodes = [
        RawSnapshotNode(index: 10, type: 'window', depth: 0),
        RawSnapshotNode(
          index: 20,
          type: 'button',
          depth: 1,
          parentIndex: 10,
        ),
        RawSnapshotNode(
          index: 30,
          type: 'text',
          depth: 2,
          parentIndex: 20,
        ),
      ];

      final normalized = normalizeSnapshotTree(nodes);
      expect(normalized.length, equals(3));
      expect(normalized[0].index, equals(0));
      expect(normalized[1].index, equals(1));
      expect(normalized[2].index, equals(2));
      expect(normalized[1].parentIndex, equals(0));
      expect(normalized[2].parentIndex, equals(1));
    });

    test('buildSnapshotNodeMap creates lookup map', () {
      final nodes = [
        SnapshotNode(index: 5, ref: 'e1', type: 'button'),
        SnapshotNode(index: 10, ref: 'e2', type: 'text'),
      ];

      final map = buildSnapshotNodeMap(nodes);
      expect(map[5]?.ref, equals('e1'));
      expect(map[10]?.ref, equals('e2'));
      expect(map[99], isNull);
    });

    test('displayNodeLabel extracts meaningful text', () {
      final withLabel = SnapshotNode(
        index: 0,
        ref: 'e1',
        label: 'Click me',
      );
      expect(displayNodeLabel(withLabel), equals('Click me'));

      final withValue = SnapshotNode(
        index: 1,
        ref: 'e2',
        value: 'Input text',
      );
      expect(displayNodeLabel(withValue), equals('Input text'));

      final withIdentifier = SnapshotNode(
        index: 2,
        ref: 'e3',
        identifier: 'com.example:id/button',
      );
      expect(displayNodeLabel(withIdentifier), equals('com.example:id/button'));

      final empty = SnapshotNode(index: 3, ref: 'e4');
      expect(displayNodeLabel(empty), equals(''));
    });
  });
}
