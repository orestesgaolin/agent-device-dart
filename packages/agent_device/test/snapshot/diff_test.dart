import 'package:agent_device/src/snapshot/diff.dart';
import 'package:agent_device/src/snapshot/snapshot.dart';
import 'package:test/test.dart';

void main() {
  group('diff.dart', () {
    test('buildSnapshotDiff detects additions', () {
      final previous = [
        const SnapshotNode(index: 0, ref: 'e1', type: 'button', label: 'A'),
      ];

      final current = [
        const SnapshotNode(index: 0, ref: 'e1', type: 'button', label: 'A'),
        const SnapshotNode(index: 1, ref: 'e2', type: 'button', label: 'B'),
      ];

      final result = buildSnapshotDiff(previous, current);
      expect(result.summary.additions, greaterThan(0));
      expect(result.summary.removals, equals(0));
      expect(result.lines.isNotEmpty, isTrue);
    });

    test('buildSnapshotDiff detects removals', () {
      final previous = [
        const SnapshotNode(index: 0, ref: 'e1', type: 'button', label: 'A'),
        const SnapshotNode(index: 1, ref: 'e2', type: 'button', label: 'B'),
      ];

      final current = [
        const SnapshotNode(index: 0, ref: 'e1', type: 'button', label: 'A'),
      ];

      final result = buildSnapshotDiff(previous, current);
      expect(result.summary.removals, greaterThan(0));
      expect(result.summary.additions, equals(0));
    });

    test('buildSnapshotDiff handles unchanged', () {
      final nodes = [
        const SnapshotNode(index: 0, ref: 'e1', type: 'button', label: 'A'),
      ];

      final result = buildSnapshotDiff(nodes, nodes);
      expect(result.summary.unchanged, greaterThan(0));
      expect(result.summary.additions, equals(0));
      expect(result.summary.removals, equals(0));
    });

    test('SnapshotDiffLine toJson serializes', () {
      final line = const SnapshotDiffLine(
        kind: 'added',
        text: '@e1 [button] "Click"',
      );
      final json = line.toJson();
      expect(json['kind'], equals('added'));
      expect(json['text'], equals('@e1 [button] "Click"'));
    });

    test('SnapshotDiffSummary toJson serializes', () {
      final summary = const SnapshotDiffSummary(
        additions: 2,
        removals: 1,
        unchanged: 5,
      );
      final json = summary.toJson();
      expect(json['additions'], equals(2));
      expect(json['removals'], equals(1));
      expect(json['unchanged'], equals(5));
    });

    test('countSnapshotComparableLines counts lines', () {
      final nodes = [
        const SnapshotNode(index: 0, ref: 'e1', type: 'button', label: 'A'),
        const SnapshotNode(index: 1, ref: 'e2', type: 'text', label: 'B'),
      ];

      final count = countSnapshotComparableLines(nodes);
      expect(count, greaterThan(0));
    });
  });
}
