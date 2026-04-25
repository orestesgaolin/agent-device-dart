// Port of agent-device/src/platforms/android/ui-hierarchy.ts

import '../../snapshot/snapshot.dart';
import '../../utils/scrollable.dart';

/// Analysis results from Android UI hierarchy parsing.
class AndroidSnapshotAnalysis {
  final int rawNodeCount;
  final int maxDepth;

  const AndroidSnapshotAnalysis({
    required this.rawNodeCount,
    required this.maxDepth,
  });
}

/// Android-specific node attributes extracted from UIAutomator XML.
class AndroidUiHierarchy {
  final String? type;
  final String? label;
  final String? value;
  final String? identifier;
  final Rect? rect;
  final bool? enabled;
  final bool? hittable;
  final int depth;
  final int? parentIndex;
  final bool? hiddenContentAbove;
  final bool? hiddenContentBelow;
  final List<AndroidUiHierarchy> children;

  const AndroidUiHierarchy({
    required this.type,
    required this.label,
    required this.value,
    required this.identifier,
    required this.rect,
    required this.enabled,
    required this.hittable,
    required this.depth,
    required this.parentIndex,
    required this.hiddenContentAbove,
    required this.hiddenContentBelow,
    required this.children,
  });
}

/// Built snapshot including both raw nodes and source hierarchy.
class AndroidBuiltSnapshot {
  final List<RawSnapshotNode> nodes;
  final List<AndroidUiHierarchy> sourceNodes;
  final bool? truncated;
  final AndroidSnapshotAnalysis analysis;

  const AndroidBuiltSnapshot({
    required this.nodes,
    required this.sourceNodes,
    required this.truncated,
    required this.analysis,
  });
}

/// Extract attributes for a text query from UIAutomator XML.
///
/// Returns the center coordinates of the first node matching the query,
/// or null if no match found.
({int x, int y})? findBounds(String xml, String query) {
  final q = query.toLowerCase();
  final nodeRegex = RegExp(r'<node[^>]+>');
  for (final match in nodeRegex.allMatches(xml)) {
    final node = match[0]!;
    final attrs = _parseXmlNodeAttributes(node);
    final textVal = (attrs['text'] ?? '').toLowerCase();
    final descVal = (attrs['content-desc'] ?? '').toLowerCase();
    if (textVal.contains(q) || descVal.contains(q)) {
      final rect = parseBounds(attrs['bounds']);
      if (rect != null) {
        return (
          x: (rect.x + rect.width / 2).floor(),
          y: (rect.y + rect.height / 2).floor(),
        );
      }
      return (x: 0, y: 0);
    }
  }
  return null;
}

/// Parse UIAutomator XML dump into snapshot tree and nodes.
///
/// Applies filtering rules based on [options] and returns raw nodes
/// with optional truncation indicator.
({
  List<RawSnapshotNode> nodes,
  bool? truncated,
  AndroidSnapshotAnalysis analysis,
})
parseUiHierarchy(String xml, int maxNodes, SnapshotOptions options) {
  final tree = parseUiHierarchyTree(xml);
  final built = buildUiHierarchySnapshot(tree, maxNodes, options);
  return (
    nodes: built.nodes,
    truncated: built.truncated,
    analysis: built.analysis,
  );
}

/// Build snapshot from parsed hierarchy tree.
///
/// Walks the tree applying filtering rules, memoizing interactive
/// descendant information, and respecting depth limits and node quotas.
AndroidBuiltSnapshot buildUiHierarchySnapshot(
  AndroidUiHierarchy tree,
  int maxNodes,
  SnapshotOptions options,
) {
  final analysis = _analyzeAndroidTree(tree);
  final nodes = <RawSnapshotNode>[];
  final sourceNodes = <AndroidUiHierarchy>[];
  var truncated = false;

  final maxDepth = options.depth ?? double.infinity;
  final scopedRoot = options.scope != null
      ? _findScopeNode(tree, options.scope!)
      : null;
  final roots = scopedRoot != null ? [scopedRoot] : tree.children;

  final interactiveDescendantMemo = <AndroidUiHierarchy, bool>{};
  bool hasInteractiveDescendant(AndroidUiHierarchy node) {
    if (interactiveDescendantMemo.containsKey(node)) {
      return interactiveDescendantMemo[node]!;
    }
    for (final child in node.children) {
      if (child.hittable ?? false) {
        interactiveDescendantMemo[node] = true;
        return true;
      }
      if (hasInteractiveDescendant(child)) {
        interactiveDescendantMemo[node] = true;
        return true;
      }
    }
    interactiveDescendantMemo[node] = false;
    return false;
  }

  void walk(
    AndroidUiHierarchy node,
    int depth,
    int? parentIndex, {
    bool ancestorHittable = false,
    bool ancestorCollection = false,
  }) {
    if (nodes.length >= maxNodes) {
      truncated = true;
      return;
    }
    if (depth > maxDepth) return;

    final include = (options.raw ?? false)
        ? true
        : _shouldIncludeAndroidNode(
            node,
            options,
            ancestorHittable,
            hasInteractiveDescendant(node),
            ancestorCollection,
          );

    var currentIndex = parentIndex;
    if (include) {
      currentIndex = nodes.length;
      sourceNodes.add(node);
      nodes.add(
        RawSnapshotNode(
          index: currentIndex,
          type: node.type,
          label: node.label,
          value: node.value,
          identifier: node.identifier,
          rect: node.rect,
          enabled: node.enabled,
          hittable: node.hittable,
          depth: depth,
          parentIndex: parentIndex,
          hiddenContentAbove: node.hiddenContentAbove,
          hiddenContentBelow: node.hiddenContentBelow,
        ),
      );
    }

    final nextAncestorHittable = ancestorHittable || (node.hittable ?? false);
    final nextAncestorCollection =
        ancestorCollection || _isCollectionContainerType(node.type);

    for (final child in node.children) {
      walk(
        child,
        depth + 1,
        currentIndex,
        ancestorHittable: nextAncestorHittable,
        ancestorCollection: nextAncestorCollection,
      );
      if (truncated) return;
    }
  }

  for (final root in roots) {
    walk(root, 0, null);
    if (truncated) break;
  }

  return AndroidBuiltSnapshot(
    nodes: nodes,
    sourceNodes: sourceNodes,
    truncated: truncated ? true : null,
    analysis: analysis,
  );
}

/// Extract node attributes from an XML node string.
///
/// Parses the opening tag and extracts common UIAutomator attributes,
/// converting string boolean values to Dart bools where applicable.
({
  String? text,
  String? desc,
  String? resourceId,
  String? className,
  String? bounds,
  bool? clickable,
  bool? enabled,
  bool? focusable,
  bool? focused,
})
readNodeAttributes(String node) {
  final attrs = _parseXmlNodeAttributes(node);
  String? getAttr(String name) => attrs[name];
  bool? boolAttr(String name) {
    final raw = getAttr(name);
    if (raw == null) return null;
    return raw == 'true';
  }

  return (
    text: getAttr('text'),
    desc: getAttr('content-desc'),
    resourceId: getAttr('resource-id'),
    className: getAttr('class'),
    bounds: getAttr('bounds'),
    clickable: boolAttr('clickable'),
    enabled: boolAttr('enabled'),
    focusable: boolAttr('focusable'),
    focused: boolAttr('focused'),
  );
}

/// Parse bounds string "[x1,y1][x2,y2]" into a Rect.
///
/// Returns null if bounds string is invalid or empty.
Rect? parseBounds(String? bounds) {
  if (bounds == null || bounds.isEmpty) return null;
  final match = RegExp(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]').firstMatch(bounds);
  if (match == null) return null;

  final x1 = double.parse(match.group(1)!);
  final y1 = double.parse(match.group(2)!);
  final x2 = double.parse(match.group(3)!);
  final y2 = double.parse(match.group(4)!);

  return Rect(
    x: x1,
    y: y1,
    width: (x2 - x1).clamp(0, double.infinity),
    height: (y2 - y1).clamp(0, double.infinity),
  );
}

/// Parse UIAutomator XML dump into a tree structure.
///
/// Uses a simple stack-based parser to handle nested `<node>` elements.
/// Self-closing nodes do not push onto the stack.
AndroidUiHierarchy parseUiHierarchyTree(String xml) {
  // Not const: `children` is mutated as we parse, so a const empty list
  // would throw at runtime on the first `add`.
  // ignore: prefer_const_constructors
  final root = AndroidUiHierarchy(
    type: null,
    label: null,
    value: null,
    identifier: null,
    depth: -1,
    parentIndex: null,
    enabled: null,
    hittable: null,
    rect: null,
    hiddenContentAbove: null,
    hiddenContentBelow: null,
    children: <AndroidUiHierarchy>[],
  );

  final stack = [root];
  final tokenRegex = RegExp(r'<node\b[^>]*>|</node>');

  for (final match in tokenRegex.allMatches(xml)) {
    final token = match[0]!;

    if (token.startsWith('</node')) {
      if (stack.length > 1) {
        stack.removeLast();
      }
      continue;
    }

    final attrs = readNodeAttributes(token);
    final rect = parseBounds(attrs.bounds);
    final parent = stack.last;
    final semanticText = _firstNonEmptyAndroidText(attrs.text, attrs.desc);

    final node = AndroidUiHierarchy(
      type: attrs.className,
      label: semanticText,
      value: semanticText,
      identifier: attrs.resourceId,
      rect: rect,
      enabled: attrs.enabled,
      hittable: attrs.clickable ?? attrs.focusable,
      depth: parent.depth + 1,
      parentIndex: null,
      hiddenContentAbove: null,
      hiddenContentBelow: null,
      children: [],
    );

    parent.children.add(node);

    if (!token.endsWith('/>')) {
      stack.add(node);
    }
  }

  return root;
}

/// Check if a node should be included in the snapshot.
///
/// Applies filtering based on snapshot options and node properties,
/// considering ancestry and descendant interactivity.
bool _shouldIncludeAndroidNode(
  AndroidUiHierarchy node,
  SnapshotOptions options,
  bool ancestorHittable,
  bool descendantHittable,
  bool ancestorCollection,
) {
  final type = _normalizeAndroidType(node.type);
  final hasText = (node.label?.trim().isNotEmpty) ?? false;
  final hasId = (node.identifier?.trim().isNotEmpty) ?? false;
  final hasMeaningfulText = hasText && !_isGenericAndroidId(node.label ?? '');
  final hasMeaningfulId = hasId && !_isGenericAndroidId(node.identifier ?? '');
  final isStructural = _isStructuralAndroidType(type);
  final isVisual = type == 'imageview' || type == 'imagebutton';

  if (options.interactiveOnly ?? false) {
    if (node.hittable ?? false) return true;
    if (isScrollableType(type) && descendantHittable) {
      return true;
    }
    final proxyCandidate = hasMeaningfulText || hasMeaningfulId;
    if (!proxyCandidate) return false;
    if (isVisual) return false;
    if (isStructural && !ancestorCollection) return false;
    return ancestorHittable || descendantHittable || ancestorCollection;
  }

  if (options.compact ?? false) {
    return hasMeaningfulText || hasMeaningfulId || (node.hittable ?? false);
  }

  if (isStructural || isVisual) {
    if (node.hittable ?? false) return true;
    if (hasMeaningfulText) return true;
    if (hasMeaningfulId) return true;
    return descendantHittable;
  }

  return true;
}

String? _firstNonEmptyAndroidText(String? text, String? desc) {
  final trimmedText = text?.trim();
  if (trimmedText != null && trimmedText.isNotEmpty) {
    return trimmedText;
  }
  final trimmedDesc = desc?.trim();
  if (trimmedDesc != null && trimmedDesc.isNotEmpty) {
    return trimmedDesc;
  }
  return null;
}

bool _isCollectionContainerType(String? type) {
  if (type == null) return false;
  final normalized = _normalizeAndroidType(type);
  return normalized.contains('recyclerview') ||
      normalized.contains('listview') ||
      normalized.contains('gridview');
}

String _normalizeAndroidType(String? type) {
  if (type == null) return '';
  return type.toLowerCase();
}

bool _isStructuralAndroidType(String type) {
  final short = type.split('.').last;
  return short.contains('layout') || short == 'viewgroup' || short == 'view';
}

bool _isGenericAndroidId(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return false;
  return RegExp(r'^[\w.]+:id/[\w.-]+$', caseSensitive: false).hasMatch(trimmed);
}

AndroidUiHierarchy? _findScopeNode(AndroidUiHierarchy root, String scope) {
  final query = scope.toLowerCase();
  final queue = [...root.children];
  var head = 0;

  while (head < queue.length) {
    final node = queue[head++];
    final label = (node.label ?? '').toLowerCase();
    final value = (node.value ?? '').toLowerCase();
    final identifier = (node.identifier ?? '').toLowerCase();

    if (label.contains(query) ||
        value.contains(query) ||
        identifier.contains(query)) {
      return node;
    }
    queue.addAll(node.children);
  }

  return null;
}

AndroidSnapshotAnalysis _analyzeAndroidTree(AndroidUiHierarchy root) {
  var rawNodeCount = 0;
  var maxDepth = 0;
  final stack = [...root.children];

  while (stack.isNotEmpty) {
    final node = stack.removeLast();
    rawNodeCount += 1;
    maxDepth = maxDepth > node.depth ? maxDepth : node.depth;
    stack.addAll(node.children);
  }

  return AndroidSnapshotAnalysis(
    rawNodeCount: rawNodeCount,
    maxDepth: maxDepth,
  );
}

/// Extract attributes from an XML opening tag using regex.
///
/// Handles quoted attribute values and whitespace. Returns a map
/// of attribute names to values.
Map<String, String> _parseXmlNodeAttributes(String node) {
  final attrs = <String, String>{};
  final start = node.indexOf(' ');
  final end = node.lastIndexOf('>');

  if (start < 0 || end <= start) return attrs;

  final attrRegex = RegExp(r'''([^\s=/>]+)\s*=\s*(["'])([\s\S]*?)\2''');
  var cursor = start;

  while (cursor < end) {
    // Skip whitespace
    while (cursor < end) {
      final char = node[cursor];
      if (char != ' ' && char != '\n' && char != '\r' && char != '\t') {
        break;
      }
      cursor += 1;
    }

    if (cursor >= end) break;

    final char = node[cursor];
    if (char == '/' || char == '>') break;

    final match = attrRegex.matchAsPrefix(node, cursor);
    if (match == null) break;

    attrs[match.group(1)!] = match.group(3)!;
    cursor = match.end;
  }

  return attrs;
}
