// Port of agent-device/src/utils/snapshot-visibility.ts
library;

import 'snapshot.dart';

/// Determine if a backend is a desktop backend.
bool _isDesktopBackend(SnapshotBackend? backend) {
  return backend == SnapshotBackend.macosHelper ||
      backend == SnapshotBackend.linuxAtspi;
}

/// Build snapshot visibility information from node data and backend.
///
/// For desktop backends and raw snapshots, all nodes are visible.
/// For mobile backends, visibility is determined by viewport analysis.
SnapshotVisibility buildSnapshotVisibility({
  required List<SnapshotNode> nodes,
  SnapshotBackend? backend,
  bool snapshotRaw = false,
}) {
  if (snapshotRaw || _isDesktopBackend(backend)) {
    return SnapshotVisibility(
      partial: false,
      visibleNodeCount: nodes.length,
      totalNodeCount: nodes.length,
      reasons: const [],
    );
  }

  // TODO(port): mobile-snapshot-semantics not yet ported.
  // For now, report all nodes visible with no reasons.
  final reasons = <SnapshotVisibilityReason>[];

  return SnapshotVisibility(
    partial: reasons.isNotEmpty,
    visibleNodeCount: nodes.length,
    totalNodeCount: nodes.length,
    reasons: reasons,
  );
}
