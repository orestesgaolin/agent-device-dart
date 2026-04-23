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
bool _isAssertionVisible(SnapshotNode node, List<SnapshotNode> nodes) {
  if (node.hittable == true) return true;
  if (_hasPositiveRect(node.rect)) return _isRectVisibleInViewport(node, nodes);
  if (node.rect != null) return false;
  final anchor = _resolveVisibilityAnchor(node, nodes);
  if (anchor == null) return false;
  if (anchor.hittable == true) return true;
  if (!_hasPositiveRect(anchor.rect)) return false;
  return _isRectVisibleInViewport(anchor, nodes);
}

/// Check if a rect is visible in the effective viewport.
bool _isRectVisibleInViewport(SnapshotNode node, List<SnapshotNode> nodes) {
  // TODO(port): This delegates to isNodeVisibleInEffectiveViewport from
  // mobile-snapshot-semantics.ts, which is not yet ported. For now, we
  // check basic rect visibility.
  if (node.rect == null) return false;
  // Check if rect has positive dimensions
  return node.rect!.width > 0 && node.rect!.height > 0;
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

/// Check if a rect has positive dimensions.
bool _hasPositiveRect(Rect? rect) {
  return rect != null &&
      rect.x.isFinite &&
      rect.y.isFinite &&
      rect.width.isFinite &&
      rect.height.isFinite &&
      rect.width > 0 &&
      rect.height > 0;
}

/// Normalize a type string.
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

/// Simple JSON encoder (avoids import for now).
String _jsonEncode(Map<String, Object?> map) {
  final parts = <String>[];
  map.forEach((k, v) {
    parts.add('$k:$v');
  });
  return '{${parts.join(', ')}}';
}
