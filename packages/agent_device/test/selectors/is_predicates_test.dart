import 'package:agent_device/src/selectors/is_predicates.dart';
import 'package:agent_device/src/snapshot/snapshot.dart';
import 'package:test/test.dart';

void main() {
  group('evaluateIsPredicate — visible/hidden', () {
    test('node inside window viewport is visible', () {
      final nodes = [
        SnapshotNode(
          index: 0,
          ref: 'e1',
          type: 'Window',
          depth: 0,
          rect: Rect(x: 0, y: 0, width: 390, height: 844),
        ),
        SnapshotNode(
          index: 1,
          ref: 'e2',
          type: 'Button',
          label: 'Visible',
          depth: 1,
          parentIndex: 0,
          rect: Rect(x: 20, y: 140, width: 160, height: 44),
          hittable: true,
        ),
      ];
      final result = evaluateIsPredicate(
        predicate: 'visible',
        node: nodes[1],
        nodes: nodes,
        platform: 'ios',
      );
      expect(result.pass, isTrue);
    });

    test('node below window viewport is hidden', () {
      final nodes = [
        SnapshotNode(
          index: 0,
          ref: 'e1',
          type: 'Window',
          depth: 0,
          rect: Rect(x: 0, y: 0, width: 390, height: 844),
        ),
        SnapshotNode(
          index: 1,
          ref: 'e2',
          type: 'Button',
          label: 'Far below',
          depth: 1,
          parentIndex: 0,
          rect: Rect(x: 20, y: 1100, width: 160, height: 44),
          hittable: true,
        ),
      ];
      final result = evaluateIsPredicate(
        predicate: 'visible',
        node: nodes[1],
        nodes: nodes,
        platform: 'ios',
      );
      expect(result.pass, isFalse);
    });

    test('hidden predicate is inverse of visible', () {
      final nodes = [
        SnapshotNode(
          index: 0,
          ref: 'e1',
          type: 'Window',
          depth: 0,
          rect: Rect(x: 0, y: 0, width: 390, height: 844),
        ),
        SnapshotNode(
          index: 1,
          ref: 'e2',
          type: 'Button',
          label: 'Far below',
          depth: 1,
          parentIndex: 0,
          rect: Rect(x: 20, y: 1100, width: 160, height: 44),
          hittable: true,
        ),
      ];
      final result = evaluateIsPredicate(
        predicate: 'hidden',
        node: nodes[1],
        nodes: nodes,
        platform: 'ios',
      );
      expect(result.pass, isTrue);
    });

    test(
      'scroll container clips children — inside visible, outside hidden',
      () {
        final nodes = [
          SnapshotNode(
            index: 0,
            ref: 'e1',
            type: 'Window',
            depth: 0,
            rect: Rect(x: 0, y: 0, width: 390, height: 844),
          ),
          SnapshotNode(
            index: 1,
            ref: 'e2',
            type: 'android.widget.ScrollView',
            depth: 1,
            parentIndex: 0,
            rect: Rect(x: 0, y: 120, width: 390, height: 500),
          ),
          SnapshotNode(
            index: 2,
            ref: 'e3',
            type: 'android.widget.TextView',
            label: 'Inside',
            depth: 2,
            parentIndex: 1,
            rect: Rect(x: 20, y: 200, width: 200, height: 30),
          ),
          SnapshotNode(
            index: 3,
            ref: 'e4',
            type: 'android.widget.TextView',
            label: 'Clipped',
            depth: 2,
            parentIndex: 1,
            rect: Rect(x: 20, y: 700, width: 200, height: 30),
          ),
        ];

        final insideResult = evaluateIsPredicate(
          predicate: 'visible',
          node: nodes[2],
          nodes: nodes,
          platform: 'android',
        );
        expect(insideResult.pass, isTrue);

        final clippedResult = evaluateIsPredicate(
          predicate: 'visible',
          node: nodes[3],
          nodes: nodes,
          platform: 'android',
        );
        expect(clippedResult.pass, isFalse);
      },
    );

    test('node at exact viewport boundary is visible (1px overlap)', () {
      final nodes = [
        SnapshotNode(
          index: 0,
          ref: 'e1',
          type: 'Window',
          depth: 0,
          rect: Rect(x: 0, y: 0, width: 390, height: 844),
        ),
        SnapshotNode(
          index: 1,
          ref: 'e2',
          type: 'Button',
          label: 'Edge',
          depth: 1,
          parentIndex: 0,
          rect: Rect(x: 20, y: -43, width: 160, height: 44),
          hittable: true,
        ),
      ];
      final result = evaluateIsPredicate(
        predicate: 'visible',
        node: nodes[1],
        nodes: nodes,
        platform: 'ios',
      );
      expect(result.pass, isTrue);
    });

    test('node just outside viewport boundary is hidden', () {
      final nodes = [
        SnapshotNode(
          index: 0,
          ref: 'e1',
          type: 'Window',
          depth: 0,
          rect: Rect(x: 0, y: 0, width: 390, height: 844),
        ),
        SnapshotNode(
          index: 1,
          ref: 'e2',
          type: 'Button',
          label: 'Outside',
          depth: 1,
          parentIndex: 0,
          rect: Rect(x: 20, y: -45, width: 160, height: 44),
          hittable: true,
        ),
      ];
      final result = evaluateIsPredicate(
        predicate: 'visible',
        node: nodes[1],
        nodes: nodes,
        platform: 'ios',
      );
      expect(result.pass, isFalse);
    });

    test('node with no rect is treated as visible', () {
      final nodes = [
        SnapshotNode(
          index: 0,
          ref: 'e1',
          type: 'Window',
          depth: 0,
          rect: Rect(x: 0, y: 0, width: 390, height: 844),
        ),
        SnapshotNode(
          index: 1,
          ref: 'e2',
          type: 'Other',
          depth: 1,
          parentIndex: 0,
        ),
      ];
      final result = evaluateIsPredicate(
        predicate: 'visible',
        node: nodes[1],
        nodes: nodes,
        platform: 'ios',
      );
      expect(result.pass, isTrue);
    });

    test('hittable node outside viewport is still hidden (geometry wins)', () {
      final nodes = [
        SnapshotNode(
          index: 0,
          ref: 'e1',
          type: 'Window',
          depth: 0,
          rect: Rect(x: 0, y: 0, width: 390, height: 844),
        ),
        SnapshotNode(
          index: 1,
          ref: 'e2',
          type: 'Button',
          depth: 1,
          parentIndex: 0,
          hittable: true,
          rect: Rect(x: 20, y: 2000, width: 160, height: 44),
        ),
      ];
      final result = evaluateIsPredicate(
        predicate: 'visible',
        node: nodes[1],
        nodes: nodes,
        platform: 'ios',
      );
      expect(result.pass, isFalse);
    });

    test('exists predicate passes for any resolved node', () {
      final node = SnapshotNode(index: 0, ref: 'e1', type: 'Button');
      final result = evaluateIsPredicate(
        predicate: 'exists',
        node: node,
        nodes: [node],
        platform: 'ios',
      );
      expect(result.pass, isTrue);
    });

    test('text predicate compares exact text', () {
      final node = SnapshotNode(
        index: 0,
        ref: 'e1',
        type: 'Button',
        label: 'Submit',
      );
      final pass = evaluateIsPredicate(
        predicate: 'text',
        node: node,
        nodes: [node],
        expectedText: 'Submit',
        platform: 'ios',
      );
      expect(pass.pass, isTrue);

      final fail = evaluateIsPredicate(
        predicate: 'text',
        node: node,
        nodes: [node],
        expectedText: 'Cancel',
        platform: 'ios',
      );
      expect(fail.pass, isFalse);
    });
  });
}
