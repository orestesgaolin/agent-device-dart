// Port of agent-device/src/utils/selector-node.ts
library;

import 'package:agent_device/src/snapshot/processing.dart';
import 'package:agent_device/src/snapshot/snapshot.dart';

/// Check if a node is visible (hittable or has a positive rect).
bool isNodeVisible(SnapshotNode node) {
  if (node.hittable == true) return true;
  if (node.rect == null) return false;
  return node.rect!.width > 0 && node.rect!.height > 0;
}

/// Check if a node is editable (fillable type and not disabled) on a given platform.
bool isNodeEditable(SnapshotNode node, String platform) {
  return isFillableType(node.type ?? '', platform) && node.enabled != false;
}
