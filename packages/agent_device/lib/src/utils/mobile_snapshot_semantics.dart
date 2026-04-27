// Port of agent-device/src/utils/mobile-snapshot-semantics.ts
library;

import '../snapshot/snapshot.dart';
import '../snapshot/tree.dart';
import '../utils/scrollable.dart';

// ---------------------------------------------------------------------------
// Direction type (internal)
// ---------------------------------------------------------------------------

enum _Direction { above, below }

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Presentation of a mobile snapshot — visible nodes plus summary of hidden.
class MobileSnapshotPresentation {
  final List<SnapshotNode> nodes;
  final int hiddenCount;
  final List<String> summaryLines;

  const MobileSnapshotPresentation({
    required this.nodes,
    required this.hiddenCount,
    required this.summaryLines,
  });
}

// ---------------------------------------------------------------------------
// Public functions
// ---------------------------------------------------------------------------

/// Build the visible presentation of a mobile snapshot.
///
/// Filters offscreen nodes, annotates scrollable containers with hidden-content
/// hints, and produces human-readable summary lines for anything that was cut.
MobileSnapshotPresentation buildMobileSnapshotPresentation(
  List<SnapshotNode> nodes,
) {
  if (nodes.isEmpty) {
    return MobileSnapshotPresentation(
      nodes: nodes,
      hiddenCount: 0,
      summaryLines: const [],
    );
  }

  final analysis = _analyzeMobileSnapshotVisibility(nodes);
  final visibleNodeIndexes = analysis.visibleNodeIndexes;
  final offscreenNodes = analysis.offscreenNodes;
  final hintedContainers = analysis.hintedContainers;

  final presentedNodes = visibleNodeIndexes.isEmpty
      ? nodes
      : nodes.where((node) => visibleNodeIndexes.contains(node.index)).toList();

  final presentedNodesWithHints = presentedNodes
      .map(
        (node) => _applyDerivedHiddenContentHints(
          node,
          hintedContainers.directionsByContainer,
        ),
      )
      .toList();

  return MobileSnapshotPresentation(
    nodes: presentedNodesWithHints,
    hiddenCount: visibleNodeIndexes.isEmpty
        ? 0
        : nodes.length - presentedNodes.length,
    summaryLines: _buildOffscreenSummaryLines(
      offscreenNodes
          .where(
            (node) =>
                !hintedContainers.coveredNodeIndexes.contains(node.index) &&
                _isDiscoverableOffscreenNode(node),
          )
          .toList(),
      nodes,
      analysis.byIndex,
    ),
  );
}

/// Derive hidden-content hints for a mobile snapshot without filtering nodes.
///
/// Returns a map from node index to [HiddenContentHint] for any scrollable
/// containers that have content scrolled out of view.
Map<int, HiddenContentHint> deriveMobileSnapshotHiddenContentHints(
  List<SnapshotNode> nodes,
) {
  if (nodes.isEmpty) {
    return {};
  }

  final analysis = _analyzeMobileSnapshotVisibility(nodes);
  return _toHiddenContentHints(
    analysis.hintedContainers.directionsByContainer,
  );
}

/// Check if a node is visible in its effective viewport (nearest scrollable
/// ancestor, or the application/window rect as fallback).
bool isNodeVisibleInEffectiveViewport(
  SnapshotNode node,
  List<SnapshotNode> nodes,
  Map<int, SnapshotNode> byIndex,
) {
  if (node.rect == null) {
    return true;
  }
  final viewport = resolveEffectiveViewportRect(node, nodes, byIndex);
  if (viewport == null) {
    return true;
  }
  return _isRectVisibleInViewport(node.rect!, viewport);
}

/// Resolve the effective viewport rectangle for [node].
///
/// Uses the nearest scrollable ancestor's rect if one exists, otherwise falls
/// back to the Application/Window rect from the node list.
Rect? resolveEffectiveViewportRect(
  SnapshotNode node,
  List<SnapshotNode> nodes,
  Map<int, SnapshotNode> byIndex,
) {
  final clippingRect = _findNearestScrollableAncestorRect(node, byIndex);
  if (clippingRect != null) {
    return clippingRect;
  }
  return _resolveViewportRect(
    nodes,
    node.rect ?? const Rect(x: 0, y: 0, width: 0, height: 0),
  );
}

// ---------------------------------------------------------------------------
// Internal analysis
// ---------------------------------------------------------------------------

class _HintedContainers {
  final Map<int, Set<_Direction>> directionsByContainer;
  final Set<int> coveredNodeIndexes;

  const _HintedContainers({
    required this.directionsByContainer,
    required this.coveredNodeIndexes,
  });
}

class _VisibilityAnalysis {
  final Map<int, SnapshotNode> byIndex;
  final Set<int> visibleNodeIndexes;
  final List<SnapshotNode> offscreenNodes;
  final _HintedContainers hintedContainers;

  const _VisibilityAnalysis({
    required this.byIndex,
    required this.visibleNodeIndexes,
    required this.offscreenNodes,
    required this.hintedContainers,
  });
}

_VisibilityAnalysis _analyzeMobileSnapshotVisibility(List<SnapshotNode> nodes) {
  final byIndex = buildSnapshotNodeMap(nodes);
  final visibleNodeIndexes = <int>{};
  final offscreenNodes = <SnapshotNode>[];

  for (final node in nodes) {
    if (isNodeVisibleInEffectiveViewport(node, nodes, byIndex)) {
      _markNodeAndAncestorsVisible(node, visibleNodeIndexes, byIndex);
    } else {
      offscreenNodes.add(node);
    }
  }

  final hintedContainers = _deriveContainerHints(
    nodes,
    offscreenNodes,
    visibleNodeIndexes,
    byIndex,
  );

  return _VisibilityAnalysis(
    byIndex: byIndex,
    visibleNodeIndexes: visibleNodeIndexes,
    offscreenNodes: offscreenNodes,
    hintedContainers: hintedContainers,
  );
}

_HintedContainers _deriveContainerHints(
  List<SnapshotNode> allNodes,
  List<SnapshotNode> offscreenNodes,
  Set<int> visibleNodeIndexes,
  Map<int, SnapshotNode> byIndex,
) {
  final directionsByContainer = <int, Set<_Direction>>{};
  final coveredNodeIndexes = <int>{};

  for (final node in offscreenNodes) {
    if (node.rect == null) continue;
    final container = _findNearestVisibleScrollableAncestor(
      node,
      visibleNodeIndexes,
      byIndex,
    );
    if (container?.rect == null) continue;
    final direction = _classifyVerticalDirection(node.rect!, container!.rect!);
    if (direction == null) continue;

    directionsByContainer.putIfAbsent(container.index, () => {}).add(direction);
    coveredNodeIndexes.add(node.index);
  }

  _mergeScrollIndicatorDirections(
    allNodes,
    visibleNodeIndexes,
    byIndex,
    directionsByContainer,
  );

  return _HintedContainers(
    directionsByContainer: directionsByContainer,
    coveredNodeIndexes: coveredNodeIndexes,
  );
}

Map<int, HiddenContentHint> _toHiddenContentHints(
  Map<int, Set<_Direction>> directionsByContainer,
) {
  final hints = <int, HiddenContentHint>{};
  for (final entry in directionsByContainer.entries) {
    final index = entry.key;
    final directions = entry.value;
    final hint = HiddenContentHint(
      hiddenContentAbove: directions.contains(_Direction.above),
      hiddenContentBelow: directions.contains(_Direction.below),
    );
    if (hint.hiddenContentAbove || hint.hiddenContentBelow) {
      hints[index] = hint;
    }
  }
  return hints;
}

// ---------------------------------------------------------------------------
// Node application helpers
// ---------------------------------------------------------------------------

/// Return [node] with hidden-content hints applied from [directionsByContainer].
SnapshotNode _applyDerivedHiddenContentHints(
  SnapshotNode node,
  Map<int, Set<_Direction>> directionsByContainer,
) {
  final directions = directionsByContainer[node.index];
  if (directions == null || directions.isEmpty) {
    return node;
  }

  final hiddenAbove =
      node.hiddenContentAbove == true || directions.contains(_Direction.above);
  final hiddenBelow =
      node.hiddenContentBelow == true || directions.contains(_Direction.below);

  // Mutate in-place — RawSnapshotNode fields are non-final.
  node.hiddenContentAbove = hiddenAbove ? true : null;
  node.hiddenContentBelow = hiddenBelow ? true : null;
  return node;
}

// ---------------------------------------------------------------------------
// Offscreen summary
// ---------------------------------------------------------------------------

List<String> _buildOffscreenSummaryLines(
  List<SnapshotNode> nodes,
  List<SnapshotNode> snapshotNodes,
  Map<int, SnapshotNode> byIndex,
) {
  final groups = <_Direction, List<SnapshotNode>>{};

  for (final node in nodes) {
    final direction = _classifyNodeDirection(node, snapshotNodes, byIndex);
    if (direction == null) continue;
    groups.putIfAbsent(direction, () => []).add(node);
  }

  final lines = <String>[];
  for (final direction in [_Direction.above, _Direction.below]) {
    final group = groups[direction];
    if (group == null || group.isEmpty) continue;

    final labels = _uniqueLabels(group).take(3).map((l) => '"$l"').toList();
    final noun =
        group.length == 1 ? 'interactive item' : 'interactive items';
    final suffix = labels.isNotEmpty ? ': ${labels.join(', ')}' : '';
    final dirName = direction == _Direction.above ? 'above' : 'below';
    lines.add('[off-screen $dirName] ${group.length} $noun$suffix');
  }

  return lines;
}

_Direction? _classifyNodeDirection(
  SnapshotNode node,
  List<SnapshotNode> nodes,
  Map<int, SnapshotNode> byIndex,
) {
  if (node.rect == null) return null;
  final viewport = resolveEffectiveViewportRect(node, nodes, byIndex);
  if (viewport == null) return null;
  return _classifyVerticalDirection(node.rect!, viewport);
}

_Direction? _classifyVerticalDirection(Rect targetRect, Rect viewportRect) {
  if (targetRect.y + targetRect.height <= viewportRect.y) {
    return _Direction.above;
  }
  if (targetRect.y >= viewportRect.y + viewportRect.height) {
    return _Direction.below;
  }
  return null;
}

bool _isDiscoverableOffscreenNode(SnapshotNode node) {
  if (node.hittable == true) return true;
  final type = (node.type ?? '').toLowerCase();
  return type.contains('button') ||
      type.contains('link') ||
      type.contains('textfield') ||
      type.contains('edittext') ||
      type.contains('searchfield') ||
      type.contains('checkbox') ||
      type.contains('radio') ||
      type.contains('switch') ||
      type.contains('menuitem') ||
      displayNodeLabel(node).isNotEmpty;
}

List<String> _uniqueLabels(List<SnapshotNode> nodes) {
  final seen = <String>{};
  final labels = <String>[];
  for (final node in nodes) {
    final label = displayNodeLabel(node);
    if (label.isEmpty || seen.contains(label)) continue;
    seen.add(label);
    labels.add(label);
  }
  return labels;
}

// ---------------------------------------------------------------------------
// Ancestor traversal helpers
// ---------------------------------------------------------------------------

void _markNodeAndAncestorsVisible(
  SnapshotNode node,
  Set<int> visibleNodeIndexes,
  Map<int, SnapshotNode> byIndex,
) {
  SnapshotNode? current = node;
  final visited = <int>{};
  while (current != null && !visited.contains(current.index)) {
    visited.add(current.index);
    visibleNodeIndexes.add(current.index);
    final parentIndex = current.parentIndex;
    current = parentIndex != null ? byIndex[parentIndex] : null;
  }
}

SnapshotNode? _findNearestVisibleScrollableAncestor(
  SnapshotNode node,
  Set<int> visibleNodeIndexes,
  Map<int, SnapshotNode> byIndex,
) {
  final visited = <int>{};
  var parentIdx = node.parentIndex;
  while (parentIdx != null && !visited.contains(parentIdx)) {
    visited.add(parentIdx);
    final parent = byIndex[parentIdx];
    if (parent == null) break;
    if (visibleNodeIndexes.contains(parent.index) &&
        isScrollableNodeLike(
          type: parent.type,
          role: parent.role,
          subrole: parent.subrole,
        )) {
      return parent;
    }
    parentIdx = parent.parentIndex;
  }
  return null;
}

void _mergeScrollIndicatorDirections(
  List<SnapshotNode> nodes,
  Set<int> visibleNodeIndexes,
  Map<int, SnapshotNode> byIndex,
  Map<int, Set<_Direction>> directionsByContainer,
) {
  for (final node in nodes) {
    final inferredDirections = _inferDirectionsFromScrollIndicator(node);
    if (inferredDirections == null || inferredDirections.isEmpty) continue;

    final container = _findNearestVisibleScrollableAncestor(
      node,
      visibleNodeIndexes,
      byIndex,
    );
    if (container == null) continue;

    final directions =
        directionsByContainer.putIfAbsent(container.index, () => {});
    directions.addAll(inferredDirections);
  }
}

/// Port of `inferDirectionsFromScrollIndicator` from mobile-snapshot-semantics.ts.
///
/// Derives scroll directions from accessibility scroll indicator nodes.
/// Scroll-indicator.ts is not yet fully ported; this provides the minimal
/// subset needed for hidden-content hints.
Set<_Direction>? _inferDirectionsFromScrollIndicator(SnapshotNode node) {
  final inferred = _inferVerticalScrollIndicatorDirections(
    node.label,
    node.value,
  );
  if (inferred == null) return null;

  final directions = <_Direction>{};
  if (inferred.above) directions.add(_Direction.above);
  if (inferred.below) directions.add(_Direction.below);
  return directions.isNotEmpty ? directions : null;
}

/// Minimal port of `inferVerticalScrollIndicatorDirections` from scroll-indicator.ts.
({bool above, bool below})? _inferVerticalScrollIndicatorDirections(
  String? label,
  String? value,
) {
  final normalizedLabel = (label?.trim() ?? '').toLowerCase();
  if (!normalizedLabel.contains('vertical scroll bar')) {
    return null;
  }
  final scrollPercent = _parsePercentValue(value);
  if (scrollPercent == null) return null;

  // Treat <=1% as "at top", >=99% as "at bottom".
  if (scrollPercent <= 1) return (above: false, below: true);
  if (scrollPercent >= 99) return (above: true, below: false);
  return (above: true, below: true);
}

double? _parsePercentValue(String? value) {
  if (value == null || value.isEmpty) return null;
  final match = RegExp(r'^(\d{1,3})%$').firstMatch(value.trim());
  if (match == null) return null;
  return double.tryParse(match.group(1)!);
}

// ---------------------------------------------------------------------------
// Rect / viewport helpers
// ---------------------------------------------------------------------------

Rect? _findNearestScrollableAncestorRect(
  SnapshotNode node,
  Map<int, SnapshotNode> byIndex,
) {
  final visited = <int>{};
  var parentIdx = node.parentIndex;
  while (parentIdx != null && !visited.contains(parentIdx)) {
    visited.add(parentIdx);
    final parent = byIndex[parentIdx];
    if (parent == null) break;
    if (parent.rect != null &&
        isScrollableNodeLike(
          type: parent.type,
          role: parent.role,
          subrole: parent.subrole,
        )) {
      return parent.rect;
    }
    parentIdx = parent.parentIndex;
  }
  return null;
}

bool _isRectVisibleInViewport(Rect rect, Rect viewport) {
  // Overlap check (inclusive edges).
  final hOverlap =
      (rect.x <= viewport.x + viewport.width) &&
      (rect.x + rect.width >= viewport.x);
  final vOverlap =
      (rect.y <= viewport.y + viewport.height) &&
      (rect.y + rect.height >= viewport.y);
  return hOverlap && vOverlap;
}

Rect? _resolveViewportRect(List<SnapshotNode> nodes, Rect targetRect) {
  final cx = targetRect.x + targetRect.width / 2;
  final cy = targetRect.y + targetRect.height / 2;

  bool hasValidRect(Rect? r) =>
      r != null &&
      r.x.isFinite &&
      r.y.isFinite &&
      r.width.isFinite &&
      r.height.isFinite;

  bool containsPoint(Rect r, double x, double y) =>
      x >= r.x && x <= r.x + r.width && y >= r.y && y <= r.y + r.height;

  Rect? pickLargest(List<Rect> rects) {
    Rect? best;
    var bestArea = -1.0;
    for (final r in rects) {
      final area = r.width * r.height;
      if (area > bestArea) {
        best = r;
        bestArea = area;
      }
    }
    return best;
  }

  final rectNodes = nodes.where((n) => hasValidRect(n.rect)).toList();
  final viewportNodes = rectNodes.where((n) {
    final t = (n.type ?? '').toLowerCase();
    return t.contains('application') || t.contains('window');
  }).toList();

  final containingViewport = pickLargest(
    viewportNodes
        .map((n) => n.rect!)
        .where((r) => containsPoint(r, cx, cy))
        .toList(),
  );
  if (containingViewport != null) return containingViewport;

  final fallback = pickLargest(viewportNodes.map((n) => n.rect!).toList());
  if (fallback != null) return fallback;

  return pickLargest(
    rectNodes
        .map((n) => n.rect!)
        .where((r) => containsPoint(r, cx, cy))
        .toList(),
  );
}
