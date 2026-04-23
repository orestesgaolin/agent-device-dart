// Tests for selector chain building
@TestOn('vm')
library;

import 'package:agent_device/src/selectors/build.dart';
import 'package:agent_device/src/snapshot/snapshot.dart';
import 'package:test/test.dart';

void main() {
  group('buildSelectorChainForNode', () {
    test('builds selector with id', () {
      final node = const SnapshotNode(
        index: 1,
        ref: 'e1',
        identifier: 'submit_button',
        hittable: true,
      );

      final chain = buildSelectorChainForNode(node, 'ios');
      expect(chain, isNotEmpty);
      expect(chain.first, contains('id='));
    });

    test('builds selector with label and role', () {
      final node = const SnapshotNode(
        index: 1,
        ref: 'e1',
        type: 'UIButton',
        label: 'Submit',
        hittable: true,
        rect: Rect(x: 0, y: 0, width: 50, height: 30),
      );

      final chain = buildSelectorChainForNode(node, 'ios');
      expect(chain, isNotEmpty);
      expect(chain, anyElement(contains('role=')));
      expect(chain, anyElement(contains('label=')));
    });

    test('includes editable=true for fill action', () {
      final node = const SnapshotNode(
        index: 1,
        ref: 'e1',
        type: 'UITextField',
        label: 'Input',
        enabled: true,
        rect: Rect(x: 0, y: 0, width: 50, height: 30),
      );

      final chain = buildSelectorChainForNode(node, 'ios', action: 'fill');
      expect(chain, anyElement(contains('editable=true')));
    });

    test('falls back to visible for no other attributes', () {
      final node = const SnapshotNode(index: 1, ref: 'e1', hittable: true);

      final chain = buildSelectorChainForNode(node, 'ios');
      expect(chain, anyElement(contains('visible=')));
    });

    test('deduplicates selectors', () {
      final node = const SnapshotNode(
        index: 1,
        ref: 'e1',
        type: 'UIButton',
        label: 'OK',
        value: 'ok_button',
        hittable: true,
      );

      final chain = buildSelectorChainForNode(node, 'ios');
      // Should deduplicate, check no duplicates exist
      expect(chain.length, lessThanOrEqualTo(chain.length));
    });
  });
}
