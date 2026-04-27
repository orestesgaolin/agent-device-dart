import 'package:agent_device/src/snapshot/snapshot.dart';
import 'package:agent_device/src/snapshot/visibility.dart';
import 'package:test/test.dart';

void main() {
  group('visibility.dart', () {
    test('buildSnapshotVisibility handles raw snapshots', () {
      final nodes = [
        SnapshotNode(index: 0, ref: 'e1', type: 'button'),
        SnapshotNode(index: 1, ref: 'e2', type: 'text'),
      ];

      final visibility = buildSnapshotVisibility(
        nodes: nodes,
        snapshotRaw: true,
      );

      expect(visibility.partial, isFalse);
      expect(visibility.visibleNodeCount, equals(2));
      expect(visibility.totalNodeCount, equals(2));
      expect(visibility.reasons, isEmpty);
    });

    test('buildSnapshotVisibility handles desktop backends', () {
      final nodes = [SnapshotNode(index: 0, ref: 'e1', type: 'button')];

      final visibility = buildSnapshotVisibility(
        nodes: nodes,
        backend: SnapshotBackend.macosHelper,
      );

      expect(visibility.partial, isFalse);
      expect(visibility.visibleNodeCount, equals(1));
      expect(visibility.totalNodeCount, equals(1));
    });

    test('buildSnapshotVisibility reports empty nodes', () {
      final visibility = buildSnapshotVisibility(nodes: []);

      expect(visibility.partial, isFalse);
      expect(visibility.visibleNodeCount, equals(0));
      expect(visibility.totalNodeCount, equals(0));
      expect(visibility.reasons, isEmpty);
    });

    test('SnapshotVisibility toJson serializes correctly', () {
      final visibility = const SnapshotVisibility(
        partial: true,
        visibleNodeCount: 5,
        totalNodeCount: 10,
        reasons: [SnapshotVisibilityReason.offscreenNodes],
      );

      final json = visibility.toJson();
      expect(json['partial'], isTrue);
      expect(json['visibleNodeCount'], equals(5));
      expect(json['totalNodeCount'], equals(10));
      expect(json['reasons'], equals(['offscreen-nodes']));
    });
  });
}
