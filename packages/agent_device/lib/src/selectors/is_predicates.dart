// Port of agent-device/src/utils/selector-is-predicates.ts
library;

import 'package:agent_device/src/snapshot/processing.dart';
import 'package:agent_device/src/snapshot/snapshot.dart';

import 'selector_node.dart';

/// Supported predicates for 'is' assertions.
typedef IsPredicate = String;

/// Check if a predicate is supported.
bool isSupportedPredicate(String input) {
  return [
    'visible',
    'hidden',
    'exists',
    'editable',
    'selected',
    'text',
  ].contains(input);
}

/// Result of evaluating an 'is' predicate.
class IsPredicateResult {
  final bool pass;
  final String actualText;
  final String details;

  const IsPredicateResult({
    required this.pass,
    required this.actualText,
    required this.details,
  });
}

/// Evaluate an 'is' predicate against a node.
IsPredicateResult evaluateIsPredicate({
  required String predicate,
  required SnapshotNode node,
  required List<SnapshotNode> nodes,
  String? expectedText,
  required String platform,
}) {
  final actualText = extractNodeText(node);
  final editable = isNodeEditable(node, platform);
  final selected = node.selected == true;
  final visible = predicate == 'text'
      ? isNodeVisible(node)
      : _isAssertionVisible(node, nodes);

  var pass = false;
  switch (predicate) {
    case 'visible':
      pass = visible;
      break;
    case 'hidden':
      pass = !visible;
      break;
    case 'exists':
      // If we got a node at all, the selector/ref matched — exists is
      // true. Callers that want to observe "no match" must guard against
      // the resolution throwing before this function is invoked.
      pass = true;
      break;
    case 'editable':
      pass = editable;
      break;
    case 'selected':
      pass = selected;
      break;
    case 'text':
      pass = actualText == (expectedText ?? '');
      break;
  }

  final details = predicate == 'text'
      ? 'expected="${expectedText ?? ''}" actual="$actualText"'
      : 'actual=${_jsonEncode({'visible': visible, 'editable': editable, 'selected': selected})}';

  return IsPredicateResult(
    pass: pass,
    actualText: actualText,
    details: details,
  );
}

/// Check if a node is visible in an assertion context.
///
/// Priority: viewport geometry first. `hittable` is only used as a
/// last-resort fallback when no rect is available at all. This matches
/// the TS `isNodeVisibleInEffectiveViewport` behaviour — a node can be
/// `hittable` according to the accessibility system yet scrolled out of
/// the viewport.
bool _isAssertionVisible(SnapshotNode node, List<SnapshotNode> nodes) {
  if (_hasPositiveRect(node.rect)) return _isRectVisibleInViewport(node, nodes);
  if (node.rect != null) return false;
  // No rect at all — try to resolve a parent anchor with geometry.
  final anchor = _resolveVisibilityAnchor(node, nodes);
  if (anchor != null && _hasPositiveRect(anchor.rect)) {
    return _isRectVisibleInViewport(anchor, nodes);
  }
  // No geometry available — assume visible (conservative, matches TS).
  return true;
}

/// Port of `isNodeVisibleInEffectiveViewport` from
/// mobile-snapshot-semantics.ts — checks whether [node]'s rect overlaps
/// the effective viewport (nearest scrollable ancestor, or the
/// Application/Window rect as fallback).
bool _isRectVisibleInViewport(SnapshotNode node, List<SnapshotNode> nodes) {
  if (node.rect == null) return true;
  final viewport = _resolveEffectiveViewportRect(node, nodes);
  if (viewport == null) return true;
  return _rectsOverlap(node.rect!, viewport);
}

/// Find a useful visibility anchor node by traversing parents.
SnapshotNode? _resolveVisibilityAnchor(
  SnapshotNode node,
  List<SnapshotNode> nodes,
) {
  final nodesByIndex = <int, SnapshotNode>{};
  for (final n in nodes) {
    nodesByIndex[n.index] = n;
  }

  var current = node;
  final visited = <int>{};

  while (current.parentIndex != null && !visited.contains(current.index)) {
    visited.add(current.index);
    final parent = nodesByIndex[current.parentIndex];
    if (parent == null) break;
    if (_isUsefulVisibilityAnchor(parent)) return parent;
    current = parent;
  }

  return null;
}

/// Check if a node is a useful visibility anchor.
bool _isUsefulVisibilityAnchor(SnapshotNode node) {
  final type = _normalizeType(node.type ?? '');
  // These containers often report the full content frame, not the clipped on-screen geometry.
  if (type.contains('application') ||
      type.contains('window') ||
      type.contains('scrollview') ||
      type.contains('tableview') ||
      type.contains('collectionview') ||
      type == 'table' ||
      type == 'list' ||
      type == 'listview') {
    return false;
  }
  return node.hittable == true || _hasPositiveRect(node.rect);
}

// =========================================================================
// Viewport visibility — port of rect-visibility.ts +
// mobile-snapshot-semantics.ts § isNodeVisibleInEffectiveViewport
// =========================================================================

/// Resolve the effective viewport for [node]: the nearest scrollable
/// ancestor's rect, or the Application/Window rect as fallback.
Rect? _resolveEffectiveViewportRect(
  SnapshotNode node,
  List<SnapshotNode> nodes,
) {
  final byIndex = _buildIndexMap(nodes);
  final scrollableRect = _findNearestScrollableAncestorRect(node, byIndex);
  if (scrollableRect != null) return scrollableRect;
  return _resolveViewportRect(nodes, node.rect!);
}

/// Walk up the parent chain to find the nearest scrollable ancestor with
/// a valid rect. Returns that ancestor's rect (the clipping region).
Rect? _findNearestScrollableAncestorRect(
  SnapshotNode node,
  Map<int, SnapshotNode> byIndex,
) {
  var parentIdx = node.parentIndex;
  final visited = <int>{};
  while (parentIdx != null && !visited.contains(parentIdx)) {
    visited.add(parentIdx);
    final parent = byIndex[parentIdx];
    if (parent == null) break;
    if (parent.rect != null && _isScrollableNodeLike(parent)) {
      return parent.rect;
    }
    parentIdx = parent.parentIndex;
  }
  return null;
}

/// Fallback viewport resolution: find the largest Application/Window rect
/// that contains the target center, or just the largest such rect overall.
Rect? _resolveViewportRect(List<SnapshotNode> nodes, Rect targetRect) {
  final cx = targetRect.x + targetRect.width / 2;
  final cy = targetRect.y + targetRect.height / 2;

  final rectNodes = nodes.where((n) => _hasValidRect(n.rect)).toList();
  final viewportNodes = rectNodes.where((n) {
    final t = (n.type ?? '').toLowerCase();
    return t.contains('application') || t.contains('window');
  }).toList();

  final containingViewport = _pickLargestRect(
    viewportNodes
        .map((n) => n.rect!)
        .where((r) => _containsPoint(r, cx, cy))
        .toList(),
  );
  if (containingViewport != null) return containingViewport;

  final fallback = _pickLargestRect(
    viewportNodes.map((n) => n.rect!).toList(),
  );
  if (fallback != null) return fallback;

  return _pickLargestRect(
    rectNodes
        .map((n) => n.rect!)
        .where((r) => _containsPoint(r, cx, cy))
        .toList(),
  );
}

/// True when [a] and [b] have any overlap (inclusive edges).
bool _rectsOverlap(Rect a, Rect b) {
  final hOverlap = (a.x <= b.x + b.width) && (a.x + a.width >= b.x);
  final vOverlap = (a.y <= b.y + b.height) && (a.y + a.height >= b.y);
  return hOverlap && vOverlap;
}

bool _isScrollableNodeLike(SnapshotNode node) {
  final type = (node.type ?? '').toLowerCase();
  if (type.contains('scroll') ||
      type.contains('recyclerview') ||
      type.contains('listview') ||
      type.contains('gridview') ||
      type.contains('collectionview') ||
      type == 'table') {
    return true;
  }
  final role = '${node.role ?? ''} ${node.subrole ?? ''}'.toLowerCase();
  return role.contains('scroll');
}

Map<int, SnapshotNode> _buildIndexMap(List<SnapshotNode> nodes) {
  return {for (final n in nodes) n.index: n};
}

bool _containsPoint(Rect r, double x, double y) {
  return x >= r.x && x <= r.x + r.width && y >= r.y && y <= r.y + r.height;
}

Rect? _pickLargestRect(List<Rect> rects) {
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

// =========================================================================
// Shared helpers
// =========================================================================

bool _hasValidRect(Rect? rect) {
  return rect != null &&
      rect.x.isFinite &&
      rect.y.isFinite &&
      rect.width.isFinite &&
      rect.height.isFinite;
}

bool _hasPositiveRect(Rect? rect) {
  return _hasValidRect(rect) && rect!.width > 0 && rect.height > 0;
}

String _normalizeType(String type) {
  var normalized = type.toLowerCase();
  if (normalized.contains('.')) {
    final lastDot = normalized.lastIndexOf('.');
    if (lastDot != -1) {
      normalized = normalized.substring(lastDot + 1);
    }
  }
  return normalized;
}

String _jsonEncode(Map<String, Object?> map) {
  final parts = <String>[];
  map.forEach((k, v) {
    parts.add('$k:$v');
  });
  return '{${parts.join(', ')}}';
}
