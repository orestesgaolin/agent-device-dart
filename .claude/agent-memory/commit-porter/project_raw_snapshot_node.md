---
name: RawSnapshotNode mutation pattern
description: RawSnapshotNode has non-final hiddenContentAbove/Below; const removal cascades to all test files
type: project
---

As of commit `0ca18ab` (port of upstream `77365ab7`):

`RawSnapshotNode` in `packages/agent_device/lib/src/snapshot/snapshot.dart` has:
- `hiddenContentAbove` and `hiddenContentBelow` are **non-final** (`bool?` not `final bool?`)
- The constructor is no longer `const` (non-final fields disallow it)
- `SnapshotNode` (extends `RawSnapshotNode`) is also no longer `const`

**Cascade effect:** Every test file that used `const RawSnapshotNode(...)` or `const SnapshotNode(...)`
must be updated to drop the `const` keyword. Files affected (as of this port):
- `test/snapshot/{diff,lines,processing,snapshot,tree,visibility}_test.dart`
- `test/platforms/android/scroll_hints_test.dart`
- `test/replay/replay_runtime_test.dart`
- `test/runtime/interaction_target_test.dart`
- `test/selectors/{build,is_predicates,match,resolve}_test.dart`

**Pattern for sed removal:**
```
sed -i '' 's/const RawSnapshotNode(/RawSnapshotNode(/g' <files...>
sed -i '' 's/const SnapshotNode(/SnapshotNode(/g' <files...>
```
Also check for `const BackendSnapshotResult(nodes: [SnapshotNode(...)])` — the list element
being non-const makes the outer const illegal too.

**Why:** TS mutates plain object properties directly; Dart achieves the same via non-final fields.
**How to apply:** If a future commit adds/modifies fields on RawSnapshotNode, check whether const
removal is needed again.
