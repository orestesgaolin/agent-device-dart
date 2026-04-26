// Port of agent-device/src/utils/snapshot.ts
library;

/// A point in 2D space.
class Point {
  final double x;
  final double y;

  const Point({required this.x, required this.y});

  /// Convert to a JSON map.
  Map<String, Object?> toJson() => {'x': x, 'y': y};
}

/// A rectangle defined by position and size.
class Rect {
  final double x;
  final double y;
  final double width;
  final double height;

  const Rect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  /// Convert to a JSON map.
  Map<String, Object?> toJson() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };
}

/// Options to control snapshot behavior.
class SnapshotOptions {
  final bool? interactiveOnly;
  final bool? compact;
  final int? depth;
  final String? scope;
  final bool? raw;

  const SnapshotOptions({
    this.interactiveOnly,
    this.compact,
    this.depth,
    this.scope,
    this.raw,
  });
}

/// Raw snapshot node data before ref attachment.
class RawSnapshotNode {
  final int index;
  final String? type;
  final String? role;
  final String? subrole;
  final String? label;
  final String? value;
  final String? identifier;
  final Rect? rect;
  final bool? enabled;
  final bool? selected;
  final bool? hittable;
  final int? depth;
  final int? parentIndex;
  final int? pid;
  final String? bundleId;
  final String? appName;
  final String? windowTitle;
  final String? surface;
  final bool? hiddenContentAbove;
  final bool? hiddenContentBelow;

  const RawSnapshotNode({
    required this.index,
    this.type,
    this.role,
    this.subrole,
    this.label,
    this.value,
    this.identifier,
    this.rect,
    this.enabled,
    this.selected,
    this.hittable,
    this.depth,
    this.parentIndex,
    this.pid,
    this.bundleId,
    this.appName,
    this.windowTitle,
    this.surface,
    this.hiddenContentAbove,
    this.hiddenContentBelow,
  });

  /// Convert to a JSON map.
  Map<String, Object?> toJson() => {
    'index': index,
    if (type != null) 'type': type,
    if (role != null) 'role': role,
    if (subrole != null) 'subrole': subrole,
    if (label != null) 'label': label,
    if (value != null) 'value': value,
    if (identifier != null) 'identifier': identifier,
    if (rect != null) 'rect': rect!.toJson(),
    if (enabled != null) 'enabled': enabled,
    if (selected != null) 'selected': selected,
    if (hittable != null) 'hittable': hittable,
    if (depth != null) 'depth': depth,
    if (parentIndex != null) 'parentIndex': parentIndex,
    if (pid != null) 'pid': pid,
    if (bundleId != null) 'bundleId': bundleId,
    if (appName != null) 'appName': appName,
    if (windowTitle != null) 'windowTitle': windowTitle,
    if (surface != null) 'surface': surface,
    if (hiddenContentAbove != null) 'hiddenContentAbove': hiddenContentAbove,
    if (hiddenContentBelow != null) 'hiddenContentBelow': hiddenContentBelow,
  };
}

/// Hint about hidden content in a snapshot node.
class HiddenContentHint {
  final bool hiddenContentAbove;
  final bool hiddenContentBelow;

  const HiddenContentHint({
    this.hiddenContentAbove = false,
    this.hiddenContentBelow = false,
  });
}

/// Snapshot node with an attached reference string.
class SnapshotNode extends RawSnapshotNode {
  final String ref;

  const SnapshotNode({
    required super.index,
    required this.ref,
    super.type,
    super.role,
    super.subrole,
    super.label,
    super.value,
    super.identifier,
    super.rect,
    super.enabled,
    super.selected,
    super.hittable,
    super.depth,
    super.parentIndex,
    super.pid,
    super.bundleId,
    super.appName,
    super.windowTitle,
    super.surface,
    super.hiddenContentAbove,
    super.hiddenContentBelow,
  });

  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'ref': ref};
}

/// Backend that produced the snapshot.
enum SnapshotBackend {
  xctest('xctest'),
  android('android'),
  macosHelper('macos-helper'),
  linuxAtspi('linux-atspi');

  final String value;
  const SnapshotBackend(this.value);

  factory SnapshotBackend.fromString(String value) {
    return SnapshotBackend.values.firstWhere(
      (b) => b.value == value,
      orElse: () => throw ArgumentError('Unknown backend: $value'),
    );
  }

  @override
  String toString() => value;
}

/// Full snapshot state including metadata.
class SnapshotState {
  final List<SnapshotNode> nodes;
  final int createdAt;
  final bool? truncated;
  final SnapshotBackend? backend;
  final bool? comparisonSafe;

  const SnapshotState({
    required this.nodes,
    required this.createdAt,
    this.truncated,
    this.backend,
    this.comparisonSafe,
  });

  /// Convert to a JSON map.
  Map<String, Object?> toJson() => {
    'nodes': nodes.map((n) => n.toJson()).toList(),
    'createdAt': createdAt,
    if (truncated != null) 'truncated': truncated,
    if (backend != null) 'backend': backend!.value,
    if (comparisonSafe != null) 'comparisonSafe': comparisonSafe,
  };
}

/// Reason why snapshot visibility is partial.
enum SnapshotVisibilityReason {
  offscreenNodes('offscreen-nodes'),
  scrollHiddenAbove('scroll-hidden-above'),
  scrollHiddenBelow('scroll-hidden-below');

  final String value;
  const SnapshotVisibilityReason(this.value);

  factory SnapshotVisibilityReason.fromString(String value) {
    return SnapshotVisibilityReason.values.firstWhere(
      (r) => r.value == value,
      orElse: () => throw ArgumentError('Unknown reason: $value'),
    );
  }

  @override
  String toString() => value;
}

/// Visibility status of a snapshot.
class SnapshotVisibility {
  final bool partial;
  final int visibleNodeCount;
  final int totalNodeCount;
  final List<SnapshotVisibilityReason> reasons;

  const SnapshotVisibility({
    required this.partial,
    required this.visibleNodeCount,
    required this.totalNodeCount,
    required this.reasons,
  });

  /// Convert to a JSON map.
  Map<String, Object?> toJson() => {
    'partial': partial,
    'visibleNodeCount': visibleNodeCount,
    'totalNodeCount': totalNodeCount,
    'reasons': reasons.map((r) => r.value).toList(),
  };
}

/// Attach reference strings to raw nodes.
List<SnapshotNode> attachRefs(List<RawSnapshotNode> nodes) {
  return nodes.asMap().entries.map((entry) {
    final idx = entry.key;
    final node = entry.value;
    return SnapshotNode(
      index: node.index,
      ref: 'e${idx + 1}',
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
      depth: node.depth,
      parentIndex: node.parentIndex,
      pid: node.pid,
      bundleId: node.bundleId,
      appName: node.appName,
      windowTitle: node.windowTitle,
      surface: node.surface,
      hiddenContentAbove: node.hiddenContentAbove,
      hiddenContentBelow: node.hiddenContentBelow,
    );
  }).toList();
}

/// Normalize a reference string (strip '@' prefix if present, validate format).
String? normalizeRef(String input) {
  final trimmed = input.trim();
  if (trimmed.startsWith('@')) {
    final ref = trimmed.substring(1);
    return ref.isNotEmpty ? ref : null;
  }
  if (trimmed.startsWith('e')) return trimmed;
  return null;
}

/// Find a node by its reference string.
SnapshotNode? findNodeByRef(List<SnapshotNode> nodes, String ref) {
  try {
    return nodes.firstWhere((node) => node.ref == ref);
  } on StateError {
    return null;
  }
}

/// Calculate the center point of a rectangle.
Point centerOfRect(Rect rect) {
  return Point(
    x: (rect.x + rect.width / 2).round().toDouble(),
    y: (rect.y + rect.height / 2).round().toDouble(),
  );
}
