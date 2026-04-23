// Port of agent-device/src/platforms/android/scroll-hints.ts

import '../../snapshot/snapshot.dart';
import '../../utils/scrollable.dart';

/// Flow block within a scrollable container.
class _FlowBlock {
  final double start;
  final double size;
  final double crossSize;

  const _FlowBlock({
    required this.start,
    required this.size,
    required this.crossSize,
  });
}

/// Native Android scroll view in the view hierarchy.
class _NativeScrollView {
  final Rect rect;
  final double contentExtent;
  final List<_FlowBlock> contentBlocks;

  const _NativeScrollView({
    required this.rect,
    required this.contentExtent,
    required this.contentBlocks,
  });
}

/// View node from dumpsys activity top.
class _ViewNode {
  final String className;
  final Rect rect;
  final List<_ViewNode> children;

  const _ViewNode({
    required this.className,
    required this.rect,
    required this.children,
  });
}

/// Infer scroll position and hidden content hints.
///
/// Analyzes a scrollable node by matching visible child blocks to the native
/// Android view tree, estimating scroll offset from coverage gaps and block
/// positions, and returning whether there is hidden content above or below.
Map<int, HiddenContentHint> deriveAndroidScrollableContentHints(
  List<RawSnapshotNode> nodes,
  String activityTopDump,
) {
  final viewTree = _parseActivityTopViewTree(activityTopDump);
  if (viewTree == null) {
    return {};
  }

  final nativeScrollViews = _collectNativeScrollViews(viewTree);
  if (nativeScrollViews.isEmpty) {
    return {};
  }

  final hintsByIndex = <int, HiddenContentHint>{};

  for (final node in nodes) {
    final nodeRect = node.rect;
    if (nodeRect == null || !isScrollableType(node.type)) {
      continue;
    }

    final nativeScrollView = _matchNativeScrollView(
      nodeRect,
      nativeScrollViews,
    );
    if (nativeScrollView == null) {
      continue;
    }

    final visibleBlocks = _collectVisibleFlowBlocks(nodes, node);
    final hiddenContent = _inferHiddenScrollableContent(
      viewportRect: node.rect!,
      visibleBlocks: visibleBlocks,
      nativeScrollView: nativeScrollView,
    );

    if (hiddenContent == null) {
      continue;
    }

    final hint = HiddenContentHint(
      hiddenContentAbove: hiddenContent.above ?? false,
      hiddenContentBelow: hiddenContent.below ?? false,
    );

    hintsByIndex[node.index] = hint;
  }

  return hintsByIndex;
}

class _HiddenContentResult {
  final bool? above;
  final bool? below;

  const _HiddenContentResult({required this.above, required this.below});
}

/// Infer hidden content based on viewport, visible blocks, and native tree.
///
/// Uses a two-pronged approach: mounted coverage gaps (virtualized lists with
/// unmounted items) and scroll offset estimation (based on block matching).
_HiddenContentResult? _inferHiddenScrollableContent({
  required Rect viewportRect,
  required List<_FlowBlock> visibleBlocks,
  required _NativeScrollView nativeScrollView,
}) {
  if (visibleBlocks.isEmpty || nativeScrollView.contentBlocks.isEmpty) {
    return null;
  }

  final mountedCoverageHiddenContent = _inferMountedCoverageHiddenContent(
    nativeScrollView,
  );

  final offset =
      _estimateScrollOffset(nativeScrollView.contentBlocks, visibleBlocks) ??
      _estimateEdgeAlignedScrollOffset(
        nativeBlocks: nativeScrollView.contentBlocks,
        visibleBlocks: visibleBlocks,
        viewportExtent: viewportRect.height,
        contentExtent: nativeScrollView.contentExtent,
      );

  if (offset == null) {
    return mountedCoverageHiddenContent;
  }

  final viewportExtent = viewportRect.height;
  final hiddenBefore =
      (mountedCoverageHiddenContent?.above ?? false) || offset > 16;
  final hiddenAfter =
      (mountedCoverageHiddenContent?.below ?? false) ||
      offset + viewportExtent < nativeScrollView.contentExtent - 16;

  return _HiddenContentResult(above: hiddenBefore, below: hiddenAfter);
}

/// Infer hidden content from coverage gaps in the content tree.
///
/// Detects when the first/last native blocks don't align with the viewport
/// (indicating virtualized content that has been scrolled off-screen).
_HiddenContentResult? _inferMountedCoverageHiddenContent(
  _NativeScrollView nativeScrollView,
) {
  if (nativeScrollView.contentBlocks.isEmpty) {
    return null;
  }

  final firstBlock = nativeScrollView.contentBlocks.first;
  final lastBlock = nativeScrollView.contentBlocks.last;

  final blocks = nativeScrollView.contentBlocks;
  final medianBlockSize =
      _median(blocks.map((b) => b.size).toList()) ??
      nativeScrollView.rect.height;

  final hiddenAboveThreshold = (48 > (medianBlockSize * 0.5))
      ? 48
      : (medianBlockSize * 0.5).round();

  final hiddenBelowThreshold = (24 > (medianBlockSize * 0.25))
      ? 24
      : (medianBlockSize * 0.25).round();

  final hiddenBefore = firstBlock.start >= hiddenAboveThreshold.toDouble();
  final hiddenAfter =
      nativeScrollView.contentExtent - (lastBlock.start + lastBlock.size) >=
      hiddenBelowThreshold.toDouble();

  if (hiddenBefore || hiddenAfter) {
    return _HiddenContentResult(
      above: hiddenBefore ? true : null,
      below: hiddenAfter ? true : null,
    );
  }

  return null;
}

/// Estimate scroll offset by matching visible blocks to native blocks.
///
/// Accumulates offsets in buckets and returns the median from the bucket
/// with the most matches (indicating consensus on scroll position).
double? _estimateScrollOffset(
  List<_FlowBlock> nativeBlocks,
  List<_FlowBlock> visibleBlocks,
) {
  final offsetBuckets = <int, List<double>>{};

  for (final nativeBlock in nativeBlocks) {
    for (final visibleBlock in visibleBlocks) {
      if (!_areFlowBlocksComparable(nativeBlock, visibleBlock)) {
        continue;
      }

      final offset = nativeBlock.start - visibleBlock.start;
      final bucket = ((offset / 8).round() * 8).toInt();

      offsetBuckets.putIfAbsent(bucket, () => []).add(offset);
    }
  }

  List<double>? bestValues;
  for (final values in offsetBuckets.values) {
    if (bestValues == null || values.length > bestValues.length) {
      bestValues = values;
    }
  }

  if (bestValues == null || bestValues.length < 2) {
    return null;
  }

  final sorted = [...bestValues]..sort();
  return sorted[(sorted.length / 2).floor()];
}

/// Estimate scroll offset for edge-aligned positions.
///
/// Detects when scrolling is at the top (first block near y=0) or bottom
/// (content extent near viewport extent) and returns the offset.
double? _estimateEdgeAlignedScrollOffset({
  required List<_FlowBlock> nativeBlocks,
  required List<_FlowBlock> visibleBlocks,
  required double viewportExtent,
  required double contentExtent,
}) {
  final topAlignedOffsets = <double>[];
  final bottomAlignedOffsets = <double>[];

  for (final nativeBlock in nativeBlocks) {
    for (final visibleBlock in visibleBlocks) {
      if (!_areFlowBlocksComparable(nativeBlock, visibleBlock)) {
        continue;
      }

      final offset = nativeBlock.start - visibleBlock.start;

      if ((offset).abs() <= 16) {
        topAlignedOffsets.add(offset);
      }

      if ((offset + viewportExtent - contentExtent).abs() <= 16) {
        bottomAlignedOffsets.add(offset);
      }
    }
  }

  if (bottomAlignedOffsets.isNotEmpty) {
    return _median(bottomAlignedOffsets);
  }

  if (topAlignedOffsets.isNotEmpty) {
    return _median(topAlignedOffsets);
  }

  return null;
}

/// Calculate the median of a list of numbers.
double? _median(List<double> values) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  return sorted[(sorted.length / 2).floor()];
}

/// Check if two flow blocks are comparable (similar size/cross-section).
///
/// Allows for some tolerance when matching blocks from different sources.
bool _areFlowBlocksComparable(_FlowBlock nativeBlock, _FlowBlock visibleBlock) {
  final sizeTolerance =
      (24).toDouble().clamp(0, double.infinity) >
          ((nativeBlock.size.clamp(0, double.infinity) <
                          visibleBlock.size.clamp(0, double.infinity)
                      ? nativeBlock.size.clamp(0, double.infinity)
                      : visibleBlock.size.clamp(0, double.infinity)) *
                  0.2)
              .roundToDouble()
      ? (24).toDouble()
      : ((nativeBlock.size.clamp(0, double.infinity) <
                        visibleBlock.size.clamp(0, double.infinity)
                    ? nativeBlock.size.clamp(0, double.infinity)
                    : visibleBlock.size.clamp(0, double.infinity)) *
                0.2)
            .roundToDouble();

  final crossTolerance =
      (48).toDouble().clamp(0, double.infinity) >
          ((nativeBlock.crossSize.clamp(0, double.infinity) <
                          visibleBlock.crossSize.clamp(0, double.infinity)
                      ? nativeBlock.crossSize.clamp(0, double.infinity)
                      : visibleBlock.crossSize.clamp(0, double.infinity)) *
                  0.15)
              .roundToDouble()
      ? (48).toDouble()
      : ((nativeBlock.crossSize.clamp(0, double.infinity) <
                        visibleBlock.crossSize.clamp(0, double.infinity)
                    ? nativeBlock.crossSize.clamp(0, double.infinity)
                    : visibleBlock.crossSize.clamp(0, double.infinity)) *
                0.15)
            .roundToDouble();

  return (nativeBlock.size - visibleBlock.size).abs() <= sizeTolerance &&
      (nativeBlock.crossSize - visibleBlock.crossSize).abs() <= crossTolerance;
}

/// Collect visible flow blocks (child rectangles) under a scrollable node.
///
/// Unwraps intermediate container nodes and collects direct children,
/// filtering for positive vertical extent and sorting by y position.
List<_FlowBlock> _collectVisibleFlowBlocks(
  List<RawSnapshotNode> nodes,
  RawSnapshotNode scrollNode,
) {
  final contentRoot = _unwrapScrollableContentRoot(nodes, scrollNode);
  final children = nodes
      .where(
        (node) =>
            node.parentIndex == contentRoot.index &&
            node.rect != null &&
            _hasPositiveVerticalExtent(node.rect!),
      )
      .toList();

  children.sort((left, right) => (left.rect!.y).compareTo(right.rect!.y));

  return children
      .map((child) => _toFlowBlock(child.rect!, scrollNode.rect!))
      .toList();
}

/// Unwrap intermediate container nodes that wrap content.
///
/// If a scrollable node has a single child with the same rect as the
/// scrollable node itself, the child is likely a transparent wrapper
/// (content root). Unwinds down the chain to find the actual content root.
RawSnapshotNode _unwrapScrollableContentRoot(
  List<RawSnapshotNode> nodes,
  RawSnapshotNode scrollNode,
) {
  var current = scrollNode;
  final visited = <int>{};

  while (!visited.contains(current.index)) {
    visited.add(current.index);

    final children = nodes
        .where((node) => node.parentIndex == current.index && node.rect != null)
        .toList();

    if (children.length != 1) {
      return current;
    }

    final child = children.single;

    if (!_sameRect(child.rect!, scrollNode.rect!)) {
      return current;
    }

    current = child;
  }

  return scrollNode;
}

/// Collect all native scroll views from the view tree.
///
/// Traverses the tree and builds NativeScrollView objects for all
/// scrollable nodes found.
List<_NativeScrollView> _collectNativeScrollViews(_ViewNode root) {
  final results = <_NativeScrollView>[];
  final stack = [root];

  while (stack.isNotEmpty) {
    final node = stack.removeLast();

    if (isScrollableType(node.className)) {
      final nativeScrollView = _toNativeScrollView(node);
      if (nativeScrollView != null) {
        results.add(nativeScrollView);
      }
    }

    stack.addAll(node.children);
  }

  return results;
}

/// Convert a view node to a native scroll view.
///
/// Extracts content extent and flow blocks from the first child
/// (content root) of the scrollable node.
_NativeScrollView? _toNativeScrollView(_ViewNode node) {
  if (node.children.isEmpty) {
    return null;
  }

  final contentRoot = node.children.first;
  final childExtents = contentRoot.children
      .map((child) => child.rect.y + child.rect.height)
      .toList();
  final contentExtent = childExtents.isEmpty
      ? contentRoot.rect.height
      : (childExtents.fold<double>(
          contentRoot.rect.height,
          (max, val) => max > val ? max : val,
        ));

  final contentBlocks = contentRoot.children
      .where((child) => _hasPositiveVerticalExtent(child.rect))
      .map((child) => _toFlowBlock(child.rect, node.rect))
      .toList();

  contentBlocks.sort((left, right) => left.start.compareTo(right.start));

  if (contentBlocks.isEmpty) {
    return null;
  }

  return _NativeScrollView(
    rect: node.rect,
    contentExtent: contentExtent,
    contentBlocks: contentBlocks,
  );
}

/// Find the best matching native scroll view for a snapshot node.
///
/// Scores based on size and position differences, preferring exact matches.
/// Returns the match with the lowest composite score.
_NativeScrollView? _matchNativeScrollView(
  Rect rect,
  List<_NativeScrollView> nativeScrollViews,
) {
  _NativeScrollView? best;
  var bestScore = double.infinity;

  for (final nativeScrollView in nativeScrollViews) {
    final sizeScore =
        (nativeScrollView.rect.width - rect.width).abs() +
        (nativeScrollView.rect.height - rect.height).abs();

    if (sizeScore > 32) {
      continue;
    }

    final positionScore =
        (nativeScrollView.rect.x - rect.x).abs() +
        (nativeScrollView.rect.y - rect.y).abs();

    final score = sizeScore * 4 + positionScore;

    if (score < bestScore) {
      best = nativeScrollView;
      bestScore = score;
    }
  }

  return best;
}

/// Parse `dumpsys activity top` output into a view tree.
///
/// Extracts lines matching the view format (indentation + class name +
/// coordinates) and builds a tree using an indent-based stack.
_ViewNode? _parseActivityTopViewTree(String dump) {
  final root = const _ViewNode(
    className: 'root',
    rect: Rect(x: 0, y: 0, width: 0, height: 0),
    children: [],
  );

  final stack = [
    {'indent': -1, 'node': root},
  ];
  final lineRegex = RegExp(
    r'^(\s*)([\w.$]+)\{[^}]* (-?\d+),(-?\d+)-(-?\d+),(-?\d+) #',
  );

  for (final line in dump.split('\n')) {
    final match = lineRegex.firstMatch(line);
    if (match == null) {
      continue;
    }

    final indent = match.group(1)!.length;
    final x1 = double.parse(match.group(3)!);
    final y1 = double.parse(match.group(4)!);
    final x2 = double.parse(match.group(5)!);
    final y2 = double.parse(match.group(6)!);

    final node = _ViewNode(
      className: match.group(2)!,
      rect: Rect(
        x: x1,
        y: y1,
        width: (x2 - x1).clamp(0, double.infinity),
        height: (y2 - y1).clamp(0, double.infinity),
      ),
      children: [],
    );

    while (stack.length > 1 &&
        indent <= ((stack.last as Map)['indent'] as int)) {
      stack.removeLast();
    }

    ((stack.last as Map)['node'] as _ViewNode).children.add(node);
    stack.add({'indent': indent, 'node': node});
  }

  return root.children.isNotEmpty ? root : null;
}

/// Convert a rectangle to a flow block within a viewport.
///
/// The flow block's start is the y offset relative to the viewport,
/// size is the height, and crossSize is the width.
_FlowBlock _toFlowBlock(Rect rect, Rect viewportRect) {
  return _FlowBlock(
    start: rect.y - viewportRect.y,
    size: rect.height,
    crossSize: rect.width,
  );
}

bool _hasPositiveVerticalExtent(Rect rect) {
  return rect.height > 0;
}

bool _sameRect(Rect left, Rect right) {
  return left.x == right.x &&
      left.y == right.y &&
      left.width == right.width &&
      left.height == right.height;
}
