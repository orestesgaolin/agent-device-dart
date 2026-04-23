// Port of agent-device/src/utils/snapshot-processing.ts
library;

import 'snapshot.dart';

/// Helper to normalize a type string.
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

/// Check if a label is meaningful (not just a number or boolean).
bool _isMeaningfulLabel(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  if (RegExp(r'^(true|false)$', caseSensitive: false).hasMatch(trimmed)) {
    return false;
  }
  if (RegExp(r'^\d+$').hasMatch(trimmed)) {
    return false;
  }
  return true;
}

/// Find a node by label (case-insensitive substring match).
SnapshotNode? findNodeByLabel(List<SnapshotNode> nodes, String label) {
  final query = label.toLowerCase();
  try {
    return nodes.firstWhere((node) {
      final labelValue = (node.label ?? '').toLowerCase();
      final valueValue = (node.value ?? '').toLowerCase();
      final idValue = (node.identifier ?? '').toLowerCase();
      return labelValue.contains(query) ||
          valueValue.contains(query) ||
          idValue.contains(query);
    });
  } on StateError {
    return null;
  }
}

/// Resolve a reference label for a node, preferring meaningful labels.
String? resolveRefLabel(SnapshotNode node, List<SnapshotNode> nodes) {
  final candidates = [node.label, node.value, node.identifier]
      .map((v) => (v is String ? v.trim() : ''))
      .where((v) => v.isNotEmpty)
      .toList();

  final primary = candidates.isNotEmpty ? candidates.first : null;
  if (primary != null && _isMeaningfulLabel(primary)) return primary;

  final fallback = _findNearestMeaningfulLabel(node, nodes);
  return fallback ??
      (primary != null && _isMeaningfulLabel(primary) ? primary : null);
}

/// Find the nearest meaningful label to a node.
String? _findNearestMeaningfulLabel(
  SnapshotNode target,
  List<SnapshotNode> nodes,
) {
  if (target.rect == null) return null;

  final targetY = target.rect!.y + target.rect!.height / 2;
  ({String label, double distance})? best;

  for (final node in nodes) {
    if (node.rect == null) continue;

    final candidates = [node.label, node.value, node.identifier]
        .map((v) => (v is String ? v.trim() : ''))
        .where((v) => v.isNotEmpty)
        .toList();

    if (candidates.isEmpty) continue;
    final label = candidates.first;
    if (!_isMeaningfulLabel(label)) continue;

    final nodeY = node.rect!.y + node.rect!.height / 2;
    final distance = (nodeY - targetY).abs();

    if (best == null || distance < best.distance) {
      best = (label: label, distance: distance);
    }
  }

  return best?.label;
}

/// Prune group nodes without meaningful labels (to reduce clutter).
List<RawSnapshotNode> pruneGroupNodes(List<RawSnapshotNode> nodes) {
  final skippedDepths = <int>[];
  final result = <RawSnapshotNode>[];

  for (final node in nodes) {
    final depth = node.depth ?? 0;

    while (skippedDepths.isNotEmpty && depth <= skippedDepths.last) {
      skippedDepths.removeLast();
    }

    final type = _normalizeType(node.type ?? '');
    final labelCandidate = [node.label, node.value, node.identifier]
        .map((v) => (v is String ? v.trim() : ''))
        .where((v) => v.isNotEmpty)
        .toList();

    final hasMeaningfulLabel =
        labelCandidate.isNotEmpty && _isMeaningfulLabel(labelCandidate.first);

    if ((type == 'group' || type == 'ioscontentgroup') && !hasMeaningfulLabel) {
      skippedDepths.add(depth);
      continue;
    }

    final adjustedDepth = (depth - skippedDepths.length)
        .clamp(0, double.infinity)
        .toInt();
    result.add(
      RawSnapshotNode(
        index: node.index,
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
        depth: adjustedDepth,
        parentIndex: node.parentIndex,
        pid: node.pid,
        bundleId: node.bundleId,
        appName: node.appName,
        windowTitle: node.windowTitle,
        surface: node.surface,
        hiddenContentAbove: node.hiddenContentAbove,
        hiddenContentBelow: node.hiddenContentBelow,
      ),
    );
  }

  return result;
}

/// Check if a type is fillable (can accept text input) on a platform.
bool isFillableType(String type, String platform) {
  final normalized = _normalizeType(type);
  if (normalized.isEmpty) return true;

  if (platform == 'android') {
    return normalized.contains('edittext') ||
        normalized.contains('autocompletetextview');
  }

  return normalized.contains('textfield') ||
      normalized.contains('securetextfield') ||
      normalized.contains('searchfield') ||
      normalized.contains('textview') ||
      normalized.contains('textarea') ||
      normalized == 'search';
}

/// Find the nearest hittable ancestor of a node.
SnapshotNode? findNearestHittableAncestor(
  List<SnapshotNode> nodes,
  SnapshotNode node,
) {
  if (node.hittable == true) return node;

  var current = node;
  final visited = <String>{};

  while (current.parentIndex != null) {
    if (visited.contains(current.ref)) break;
    visited.add(current.ref);

    try {
      final parent = nodes.firstWhere((n) => n.index == current.parentIndex);
      if (parent.hittable == true) return parent;
      current = parent;
    } on StateError {
      break;
    }
  }

  return null;
}

/// Extract text from a node (label, value, or identifier).
String extractNodeText(SnapshotNode node) {
  final candidates = [node.label, node.value, node.identifier]
      .map((v) => (v is String ? v.trim() : ''))
      .where((v) => v.isNotEmpty)
      .toList();
  return candidates.isNotEmpty ? candidates.first : '';
}

/// Extract readable text from a node (same as extractNodeText).
String extractNodeReadText(SnapshotNode node) {
  // TODO(port): This may differ from extractNodeText once text-surface is fully ported.
  return extractNodeText(node);
}
