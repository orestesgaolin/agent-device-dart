// Port of agent-device/src/utils/snapshot-diff.ts
library;

import 'lines.dart' as lines_lib;
import 'snapshot.dart';

/// A line in a diff result.
class SnapshotDiffLine {
  final String kind; // 'added', 'removed', or 'unchanged'
  final String text;

  const SnapshotDiffLine({required this.kind, required this.text});

  /// Convert to JSON.
  Map<String, Object?> toJson() => {'kind': kind, 'text': text};
}

/// Summary of a snapshot diff.
class SnapshotDiffSummary {
  final int additions;
  final int removals;
  final int unchanged;

  const SnapshotDiffSummary({
    required this.additions,
    required this.removals,
    required this.unchanged,
  });

  /// Convert to JSON.
  Map<String, Object?> toJson() => {
    'additions': additions,
    'removals': removals,
    'unchanged': unchanged,
  };
}

/// Result of a snapshot diff.
class SnapshotDiffResult {
  final SnapshotDiffSummary summary;
  final List<SnapshotDiffLine> lines;

  const SnapshotDiffResult({required this.summary, required this.lines});

  /// Convert to JSON.
  Map<String, Object?> toJson() => {
    'summary': summary.toJson(),
    'lines': lines.map((l) => l.toJson()).toList(),
  };
}

/// Options for building a diff.
class SnapshotDiffOptions {
  final bool flatten;

  const SnapshotDiffOptions({this.flatten = false});
}

/// Comparable line used for diff calculation.
class _SnapshotComparableLine {
  final String text;
  final String comparable;

  _SnapshotComparableLine({required this.text, required this.comparable});
}

/// Convert a snapshot node to a comparable line.
String _snapshotNodeToComparableLine(SnapshotNode node, int? depthOverride) {
  final role = lines_lib.formatRole(node.type ?? 'Element');
  final textPart = lines_lib.displayLabel(node, role);
  final enabledPart = node.enabled == false ? 'disabled' : 'enabled';
  final selectedPart = node.selected == true ? 'selected' : 'unselected';
  final hittablePart = node.hittable == true ? 'hittable' : 'not-hittable';
  final depthPart = (depthOverride ?? node.depth ?? 0).toString();
  return [
    depthPart,
    role,
    textPart,
    enabledPart,
    selectedPart,
    hittablePart,
  ].join('|');
}

/// Convert snapshot nodes to comparable lines.
List<_SnapshotComparableLine> _snapshotNodesToLines(
  List<SnapshotNode> nodes,
  SnapshotDiffOptions options,
) {
  if (options.flatten) {
    return nodes
        .map(
          (node) => _SnapshotComparableLine(
            text: lines_lib.formatSnapshotLine(
              node,
              0,
              false,
              null,
              const lines_lib.SnapshotLineFormatOptions(),
            ),
            comparable: _snapshotNodeToComparableLine(node, 0),
          ),
        )
        .toList();
  }

  return lines_lib
      .buildSnapshotDisplayLinesPublic(nodes)
      .map(
        (line) => _SnapshotComparableLine(
          text: line.text,
          comparable: _snapshotNodeToComparableLine(line.node, line.depth),
        ),
      )
      .toList();
}

/// Myers diff algorithm: compute edit distance and backtrack to produce diff.
List<SnapshotDiffLine> _diffComparableLinesMyers(
  List<_SnapshotComparableLine> previous,
  List<_SnapshotComparableLine> current,
) {
  final n = previous.length;
  final m = current.length;
  final max = n + m;
  final v = <int, int>{1: 0};
  final trace = <Map<int, int>>[];

  for (var d = 0; d <= max; d += 1) {
    trace.add(Map<int, int>.from(v));
    for (var k = -d; k <= d; k += 2) {
      final goDown = k == -d || (k != d && _getV(v, k - 1) < _getV(v, k + 1));
      var x = goDown ? _getV(v, k + 1) : _getV(v, k - 1) + 1;
      var y = x - k;

      while (x < n &&
          y < m &&
          previous[x].comparable == current[y].comparable) {
        x += 1;
        y += 1;
      }

      v[k] = x;

      if (x >= n && y >= m) {
        return _backtrackMyers(trace, previous, current, n, m);
      }
    }
  }

  return [];
}

/// Backtrack through the trace to produce the diff.
List<SnapshotDiffLine> _backtrackMyers(
  List<Map<int, int>> trace,
  List<_SnapshotComparableLine> previous,
  List<_SnapshotComparableLine> current,
  int n,
  int m,
) {
  final lines = <SnapshotDiffLine>[];
  var x = n;
  var y = m;

  for (var d = trace.length - 1; d >= 0; d -= 1) {
    final v = trace[d];
    final k = x - y;
    final goDown = k == -d || (k != d && _getV(v, k - 1) < _getV(v, k + 1));
    final prevK = goDown ? k + 1 : k - 1;
    final prevX = _getV(v, prevK);
    final prevY = prevX - prevK;

    while (x > prevX && y > prevY) {
      lines.add(SnapshotDiffLine(kind: 'unchanged', text: current[y - 1].text));
      x -= 1;
      y -= 1;
    }

    if (d == 0) break;

    if (x == prevX) {
      lines.add(SnapshotDiffLine(kind: 'added', text: current[prevY].text));
      y = prevY;
    } else {
      lines.add(SnapshotDiffLine(kind: 'removed', text: previous[prevX].text));
      x = prevX;
    }
  }

  return lines.reversed.toList();
}

/// Get a value from the v map (default 0 if not present).
int _getV(Map<int, int> v, int k) {
  return v[k] ?? 0;
}

/// Build a snapshot diff.
SnapshotDiffResult buildSnapshotDiff(
  List<SnapshotNode> previousNodes,
  List<SnapshotNode> currentNodes, [
  SnapshotDiffOptions? options,
]) {
  options ??= const SnapshotDiffOptions();

  final previous = _snapshotNodesToLines(previousNodes, options);
  final current = _snapshotNodesToLines(currentNodes, options);
  final diffLines = _diffComparableLinesMyers(previous, current);

  var additions = 0;
  var removals = 0;
  var unchanged = 0;

  for (final line in diffLines) {
    switch (line.kind) {
      case 'added':
        additions += 1;
      case 'removed':
        removals += 1;
      case 'unchanged':
        unchanged += 1;
    }
  }

  return SnapshotDiffResult(
    summary: SnapshotDiffSummary(
      additions: additions,
      removals: removals,
      unchanged: unchanged,
    ),
    lines: diffLines,
  );
}

/// Count the number of comparable lines (for metrics).
int countSnapshotComparableLines(
  List<SnapshotNode> nodes, [
  SnapshotDiffOptions? options,
]) {
  options ??= const SnapshotDiffOptions();
  return _snapshotNodesToLines(nodes, options).length;
}
