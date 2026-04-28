import 'package:agent_device/src/snapshot/processing.dart';
import 'package:agent_device/src/snapshot/snapshot.dart';
import 'package:test/test.dart';

void main() {
  group('processing.dart', () {
    test('findNodeByLabel performs case-insensitive substring match', () {
      final nodes = [
        SnapshotNode(index: 0, ref: 'e1', label: 'Login Button'),
        SnapshotNode(index: 1, ref: 'e2', label: 'Password Field'),
      ];

      expect(findNodeByLabel(nodes, 'login')?.ref, equals('e1'));
      expect(findNodeByLabel(nodes, 'password')?.ref, equals('e2'));
      expect(findNodeByLabel(nodes, 'notfound'), isNull);
    });

    test('resolveRefLabel prefers meaningful labels', () {
      final nodes = [
        SnapshotNode(index: 0, ref: 'e1', label: 'Submit'),
        SnapshotNode(index: 1, ref: 'e2'),
      ];

      expect(resolveRefLabel(nodes[0], nodes), equals('Submit'));
      expect(resolveRefLabel(nodes[1], nodes), isNull);
    });

    test('pruneGroupNodes removes empty group nodes', () {
      final nodes = [
        RawSnapshotNode(index: 0, type: 'window', depth: 0),
        RawSnapshotNode(index: 1, type: 'group', depth: 1),
        RawSnapshotNode(index: 2, type: 'button', label: 'Click', depth: 2),
      ];

      final pruned = pruneGroupNodes(nodes);
      expect(pruned.length, equals(2)); // empty group removed
      expect(pruned[0].type, equals('window'));
      expect(pruned[1].type, equals('button'));
    });

    test('isFillableType identifies editable fields', () {
      // Android edittext -> fillable
      expect(isFillableType('android.widget.EditText', 'android'), isTrue);
      // iOS textfield -> fillable
      expect(isFillableType('XCUIElementTypeTextField', 'ios'), isTrue);
      // iOS textview -> fillable
      expect(isFillableType('XCUIElementTypeTextView', 'ios'), isTrue);
      // iOS button -> not fillable
      expect(isFillableType('XCUIElementTypeButton', 'ios'), isFalse);
      // Android button -> not fillable
      expect(isFillableType('android.widget.Button', 'android'), isFalse);
    });

    test('findNearestHittableAncestor walks parent chain', () {
      final nodes = [
        SnapshotNode(index: 0, ref: 'e1', type: 'window', hittable: true),
        SnapshotNode(
          index: 1,
          ref: 'e2',
          type: 'button',
          parentIndex: 0,
          hittable: false,
        ),
        SnapshotNode(
          index: 2,
          ref: 'e3',
          type: 'text',
          parentIndex: 1,
          hittable: false,
        ),
      ];

      final result = findNearestHittableAncestor(nodes, nodes[2]);
      expect(result?.ref, equals('e1'));
    });

    test('extractNodeText gets first non-empty text field', () {
      final node = SnapshotNode(
        index: 0,
        ref: 'e1',
        label: 'Label',
        value: 'Value',
      );
      expect(extractNodeText(node), equals('Label'));

      final withoutLabel = SnapshotNode(index: 1, ref: 'e2', value: 'Value');
      expect(extractNodeText(withoutLabel), equals('Value'));

      final empty = SnapshotNode(index: 2, ref: 'e3');
      expect(extractNodeText(empty), equals(''));
    });
  });
}
