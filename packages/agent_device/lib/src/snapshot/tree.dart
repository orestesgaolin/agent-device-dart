// Port of agent-device/src/utils/snapshot-tree.ts
library;

import 'snapshot.dart';

/// Normalize a snapshot tree: establish stable indices, repair parent links, infer missing depths.
List<RawSnapshotNode> normalizeSnapshotTree(List<RawSnapshotNode> nodes) {
  final originalToNormalizedIndex = <int, int>{};
  for (var i = 0; i < nodes.length; i++) {
    originalToNormalizedIndex[nodes[i].index] = i;
  }

  final normalized = <RawSnapshotNode>[];
  final ancestorStack = <({int depth, int index})>[];

  for (var position = 0; position < nodes.length; position++) {
    final node = nodes[position];
    final depth = (node.depth ?? 0).clamp(0, double.infinity).toInt();

    while (ancestorStack.isNotEmpty && depth <= ancestorStack.last.depth) {
      ancestorStack.removeLast();
    }

    final index = position;
    final explicitParentIndex = node.parentIndex != null
        ? originalToNormalizedIndex[node.parentIndex]
        : null;
    final parentIndex =
        (explicitParentIndex != null && explicitParentIndex < index)
        ? explicitParentIndex
        : (ancestorStack.isNotEmpty ? ancestorStack.last.index : null);

    normalized.add(
      RawSnapshotNode(
        index: index,
        type: node.type,
        role: node.role,
        subrole: node.subrole,
        label: node.label,
        value: node.value,
        identifier: node.identifier,
        rect: node.rect,
        enabled: node.enabled,
        selected: node.selected,
        hittable: node.hittable,
        depth: depth,
        parentIndex: parentIndex,
        pid: node.pid,
        bundleId: node.bundleId,
        appName: node.appName,
        windowTitle: node.windowTitle,
        surface: node.surface,
        hiddenContentAbove: node.hiddenContentAbove,
        hiddenContentBelow: node.hiddenContentBelow,
      ),
    );

    ancestorStack.add((depth: depth, index: index));
  }

  return normalized;
}

/// Build a map from node index to node for efficient lookup.
Map<int, T> buildSnapshotNodeMap<T extends RawSnapshotNode>(List<T> nodes) {
  return {for (var node in nodes) node.index: node};
}

/// Extract the display label from a snapshot node.
String displayNodeLabel(SnapshotNode node) {
  final label = node.label?.trim();
  if (label != null && label.isNotEmpty) return label;
  final value = node.value?.trim();
  if (value != null && value.isNotEmpty) return value;
  final identifier = node.identifier?.trim();
  if (identifier != null && identifier.isNotEmpty) return identifier;
  return '';
}
